-- Moderation, part 3: what runs without an admin. Every rule logs to
-- moderation_log as actor 'system'.
--
--   * reports on the same target consolidate into one case
--   * auto-hide at N distinct trusted reporters, or on the first report
--     in a priority category; the author is told why and how to appeal
--   * reporters whose reports are mostly dismissed stop counting toward
--     auto-hide (their reports still reach the queue)
--   * a target an admin already restored is not auto-hidden again by the
--     ordinary threshold (priority categories still are)
--   * reports on a target its author deletes are closed
--   * upheld cases are strikes; enough strikes in the window create a
--     temporary restriction (mod_apply_strike, called from 004400)
--   * restriction start/end notices; ends are swept lazily, no cron
--
-- Human-only decisions live in 004400.

-- ------------------------------------------------------- labels
-- English copy for notifications (the DB keeps one language).
create or replace function public.mod_type_label(p_type text)
returns text
language sql immutable
as $$
  select case p_type
    when 'post' then 'post' when 'comment' then 'comment'
    when 'event' then 'event' when 'listing' then 'listing'
    else 'profile' end;
$$;

create or replace function public.mod_category_label(p_category text)
returns text
language sql immutable
as $$
  select case p_category
    when 'spam'           then 'spam'
    when 'scam'           then 'a scam or fraud'
    when 'harassment'     then 'hate speech or harassment'
    when 'inappropriate'  then 'inappropriate content'
    when 'minor_safety'   then 'content endangering minors'
    when 'misinformation' then 'misinformation'
    else 'breaking the community rules' end;
$$;

create or replace function public.mod_scope_label(p_scope text)
returns text
language sql immutable
as $$
  select case p_scope
    when 'post'    then 'creating or editing posts'
    when 'comment' then 'commenting'
    when 'market'  then 'selling in the Market'
    when 'events'  then 'creating or joining events'
    else 'using your account to post, comment, sell, join, follow or report' end;
$$;

create or replace function public.mod_scope_for(p_type text)
returns text
language sql immutable
as $$
  select case p_type
    when 'post' then 'post' when 'comment' then 'comment'
    when 'listing' then 'market' when 'event' then 'events'
    else null end;
$$;

-- The log must not de-anonymise: anonymous targets are logged as their case.
create or replace function public.mod_log_target(c public.moderation_cases)
returns text[]
language sql immutable
as $$
  select case when c.target_anonymous
    then array['case', c.id::text]
    else array[c.target_type, c.target_id] end;
$$;

-- ------------------------------------------------------- reporter quality
create or replace function public.mod_reporter_trusted(p_reporter uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select case
    when x.resolved < s.reporter_min_resolved then true
    else (x.dismissed::numeric / x.resolved) <= s.reporter_max_dismissed_ratio
  end
  from public.mod_settings() s,
       lateral (
         select count(*) filter (where status in ('actioned','dismissed')) as resolved,
                count(*) filter (where status = 'dismissed')               as dismissed
         from public.reports where reporter_id = p_reporter
       ) x;
$$;

-- ------------------------------------------------------- notify reporters
create or replace function public.mod_notify_reporters(p_case_id uuid, p_outcome text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  v_title text;
  v_body  text;
begin
  -- Outcome only, never anything about the other person.
  case p_outcome
    when 'actioned' then
      v_title := 'Thanks — we took action';
      v_body  := 'We reviewed something you reported and took action under the community rules.';
    when 'dismissed' then
      v_title := 'Your report was reviewed';
      v_body  := 'We reviewed something you reported. It didn''t break the community rules, so it stays up.';
    else
      v_title := 'Your report was closed';
      v_body  := 'Something you reported is no longer available, so your report was closed.';
  end case;

  for r in select distinct reporter_id from public.reports where case_id = p_case_id loop
    perform public.mod_notify(r.reporter_id, v_title, v_body,
      jsonb_build_object('kind', 'report_' || p_outcome, 'case_id', p_case_id));
  end loop;
end;
$$;

-- ------------------------------------------------------- auto-hide
create or replace function public.mod_auto_hide(p_case_id uuid, p_rule text, p_category text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  c   public.moderation_cases;
  t   text[];
  v_why text;
begin
  select * into c from public.moderation_cases where id = p_case_id;
  if not found or c.status <> 'open' then return; end if;

  perform public.mod_set_hidden(c.target_type, c.target_id, true);

  update public.moderation_cases
  set status = 'hidden', auto_hidden = true, hidden_at = now(),
      priority = greatest(priority, 1)
  where id = c.id;

  t := public.mod_log_target(c);
  perform public.mod_log('auto_hide', t[1], t[2], p_rule,
    jsonb_build_object('case_id', c.id, 'category', p_category), true);

  v_why := case when p_rule = 'priority_category'
    then 'It was reported as ' || public.mod_category_label(p_category) || '.'
    else 'It received several reports.' end;

  perform public.mod_notify(c.target_owner_id,
    'Your ' || public.mod_type_label(c.target_type) || ' is hidden pending review',
    v_why || ' It''s hidden while an admin reviews it. If you think this is a mistake, '
          || 'open Account status to appeal.',
    jsonb_build_object('kind', 'content_hidden', 'case_id', c.id,
                       'target_type', c.target_type, 'target_id', c.target_id));
end;
$$;

-- ------------------------------------------------------- reports
create or replace function public.mod_report_before_insert()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_anon  boolean;
  v_case  uuid;
begin
  if auth.uid() is not null then
    new.reporter_id := auth.uid();
  end if;

  new.target_type     := lower(new.target_type);
  new.status          := 'open';
  new.handled_by      := null;
  new.handled_at      := null;
  new.resolution_note := null;
  new.category := coalesce(nullif(new.category, ''), public.mod_category_from_reason(new.reason));
  if new.category not in ('spam','scam','harassment','inappropriate','minor_safety','misinformation','other') then
    new.category := 'other';
  end if;

  select o.owner_id, o.anonymous into v_owner, v_anon
  from public.mod_target_owner(new.target_type, new.target_id::text) o;
  if not found then
    raise exception 'MOD:target_missing' using errcode = 'P0001';
  end if;
  if v_owner = new.reporter_id then
    raise exception 'MOD:self_report' using errcode = 'P0001';
  end if;

  new.counts_toward_auto_hide := public.mod_reporter_trusted(new.reporter_id);

  -- Consolidate: attach to the target's active case, or open one.
  insert into public.moderation_cases (target_type, target_id, target_owner_id, target_anonymous)
  values (new.target_type, new.target_id::text, v_owner, coalesce(v_anon, false))
  on conflict (target_type, target_id) where status in ('open','hidden') do nothing
  returning id into v_case;

  if v_case is null then
    select id into v_case from public.moderation_cases
    where target_type = new.target_type and target_id = new.target_id::text
      and status in ('open','hidden');
  end if;

  new.case_id := v_case;
  return new;
end;
$$;

create or replace function public.mod_report_after_insert()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  s            public.moderation_settings := public.mod_settings();
  c            public.moderation_cases;
  t            text[];
  v_priority   boolean;
  v_counted    int;
  v_total      int;
  v_restored   boolean;
begin
  select * into c from public.moderation_cases where id = new.case_id for update;
  if not found then return null; end if;

  v_priority := new.category = any (s.priority_categories);

  select count(distinct reporter_id) filter (where counts_toward_auto_hide),
         count(*)
  into v_counted, v_total
  from public.reports where case_id = c.id;

  update public.moderation_cases
  set last_reported_at = now(),
      priority = greatest(priority,
                          case when v_priority then 2
                               when v_counted >= s.auto_hide_report_count then 1
                               else 0 end)
  where id = c.id;

  t := public.mod_log_target(c);
  perform public.mod_log(
    case when v_total = 1 then 'case_opened' else 'report_consolidated' end,
    t[1], t[2], null,
    jsonb_build_object('case_id', c.id, 'category', new.category,
                       'reports', v_total, 'trusted_reporters', v_counted,
                       'counted', new.counts_toward_auto_hide),
    true);

  if c.status = 'open' and public.mod_is_hideable(c.target_type) then
    v_restored := exists (
      select 1 from public.moderation_cases o
      where o.target_type = c.target_type and o.target_id = c.target_id
        and o.id <> c.id and o.decision in ('dismissed','restored'));

    if v_priority then
      perform public.mod_auto_hide(c.id, 'priority_category', new.category);
    elsif v_counted >= s.auto_hide_report_count and not v_restored then
      perform public.mod_auto_hide(c.id, 'report_threshold', new.category);
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_mod_report_before on public.reports;
create trigger trg_mod_report_before
before insert on public.reports
for each row execute function public.mod_report_before_insert();

drop trigger if exists trg_mod_report_after on public.reports;
create trigger trg_mod_report_after
after insert on public.reports
for each row execute function public.mod_report_after_insert();

-- Existing reports: group into cases (no auto-hide for the backlog).
do $$
declare
  r record;
  v_case uuid;
begin
  for r in
    select target_type, target_id::text as target_id,
           min(created_at) as first_at, max(created_at) as last_at
    from public.reports
    where case_id is null and status = 'open'
    group by target_type, target_id::text
  loop
    select id into v_case from public.moderation_cases
    where target_type = lower(r.target_type) and target_id = r.target_id
      and status in ('open','hidden');

    if v_case is null then
      begin
        insert into public.moderation_cases
          (target_type, target_id, target_owner_id, target_anonymous,
           first_reported_at, last_reported_at)
        select lower(r.target_type), r.target_id, o.owner_id, coalesce(o.anonymous, false),
               r.first_at, r.last_at
        from (select 1) one
        left join lateral public.mod_target_owner(lower(r.target_type), r.target_id) o on true
        returning id into v_case;
      exception when check_violation then
        continue; -- unknown target_type in old data
      end;
    end if;

    update public.reports set case_id = v_case
    where case_id is null and status = 'open'
      and target_type = r.target_type and target_id::text = r.target_id;
  end loop;
end $$;

-- ------------------------------------------------------- deleted targets
create or replace function public.mod_target_deleted()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_type text := tg_argv[0];
  c      public.moderation_cases;
  t      text[];
begin
  for c in
    select * from public.moderation_cases
    where target_type = v_type and target_id = old.id::text and status in ('open','hidden')
  loop
    update public.moderation_cases
    set status = 'closed', decision = 'target_deleted', decided_at = now()
    where id = c.id;

    update public.reports
    set status = 'closed', handled_at = now(), resolution_note = 'target_deleted'
    where case_id = c.id and status = 'open';

    t := public.mod_log_target(c);
    perform public.mod_log('auto_close_target_deleted', t[1], t[2], null,
      jsonb_build_object('case_id', c.id), true);
    perform public.mod_notify_reporters(c.id, 'closed');
  end loop;
  return old;
end;
$$;

do $$
declare
  spec record;
begin
  for spec in
    select * from (values ('posts','post'), ('comments','comment'),
                          ('events','event'), ('listings','listing'),
                          ('profiles','user')) as t(tbl, typ)
  loop
    execute format('drop trigger if exists trg_mod_target_deleted on public.%I', spec.tbl);
    execute format(
      'create trigger trg_mod_target_deleted after delete on public.%I '
      'for each row execute function public.mod_target_deleted(%L)',
      spec.tbl, spec.typ);
  end loop;
end $$;

-- ------------------------------------------------------- strikes
-- Called when a human upholds a case (removed / warned).
create or replace function public.mod_apply_strike(p_case_id uuid)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  s       public.moderation_settings := public.mod_settings();
  c       public.moderation_cases;
  v_scope text;
  v_count int;
  v_id    uuid;
  t       text[];
begin
  update public.moderation_cases set strike = true
  where id = p_case_id
  returning * into c;
  if not found or c.target_owner_id is null then return null; end if;

  select count(*) into v_count
  from public.moderation_cases
  where target_owner_id = c.target_owner_id and strike
    and decided_at > now() - make_interval(days => s.strike_window_days);

  v_scope := public.mod_scope_for(c.target_type);
  if v_scope is null
     or v_count < s.strikes_for_auto_restriction
     or public.is_restricted_user(c.target_owner_id, v_scope) then
    return null;
  end if;

  insert into public.user_restrictions (user_id, scope, until, reason, case_id, created_by)
  values (c.target_owner_id, v_scope,
          now() + make_interval(days => s.auto_restriction_days),
          format('Automatic: %s upheld reports in %s days', v_count, s.strike_window_days),
          c.id, null)
  returning id into v_id;

  t := public.mod_log_target(c);
  perform public.mod_log('auto_restrict', t[1], t[2], null,
    jsonb_build_object('case_id', c.id, 'restriction_id', v_id, 'scope', v_scope,
                       'strikes', v_count, 'days', s.auto_restriction_days),
    true);
  return v_id;
end;
$$;

-- ------------------------------------------------------- restriction notices
create or replace function public.mod_restriction_changed()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_until text;
begin
  if tg_op = 'INSERT' then
    v_until := case when new.until is null then 'permanently'
      else 'until ' || to_char(new.until at time zone 'Asia/Kuala_Lumpur', 'DD Mon YYYY HH24:MI') || ' (MYT)' end;
    perform public.mod_notify(new.user_id,
      'Your account has a restriction',
      'You can''t use ' || public.mod_scope_label(new.scope) || ' ' || v_until
        || '. Reason: ' || new.reason || '. Open Account status for details or to appeal.',
      jsonb_build_object('kind', 'restricted', 'restriction_id', new.id,
                         'scope', new.scope, 'until', new.until));

    if new.scope = 'account' and new.until is null then
      update public.profiles set is_banned = true, ban_reason = new.reason
      where id = new.user_id;
    end if;

  elsif old.lifted_at is null and new.lifted_at is not null then
    perform public.mod_notify(new.user_id,
      'A restriction was lifted',
      'You can use ' || public.mod_scope_label(new.scope) || ' again.'
        || coalesce(' Note: ' || nullif(new.lift_reason, ''), ''),
      jsonb_build_object('kind', 'restriction_lifted', 'restriction_id', new.id, 'scope', new.scope));

  elsif old.lifted_at is not null and new.lifted_at is null then
    perform public.mod_notify(new.user_id,
      'A restriction is back in place',
      'An admin undid the earlier lift. You can''t use ' || public.mod_scope_label(new.scope)
        || ' for now. Open Account status for details.',
      jsonb_build_object('kind', 'restricted', 'restriction_id', new.id, 'scope', new.scope));
  end if;

  -- profiles.is_banned mirrors "has an active permanent account ban".
  if new.scope = 'account' and new.until is null and tg_op = 'UPDATE' then
    update public.profiles
    set is_banned = exists (
          select 1 from public.user_restrictions r
          where r.user_id = new.user_id and r.scope = 'account'
            and r.until is null and r.lifted_at is null),
        ban_reason = case when new.lifted_at is null then new.reason else null end
    where id = new.user_id;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_mod_restriction_changed on public.user_restrictions;
create trigger trg_mod_restriction_changed
after insert or update of lifted_at on public.user_restrictions
for each row execute function public.mod_restriction_changed();

-- Restrictions end by themselves (until <= now()). This only sends the
-- "it ended" notice, once, whenever someone next looks: the user's own
-- status call or the admin queue. To send them on time instead, schedule
-- `select public.mod_sweep_expired(null);` with pg_cron (optional).
create or replace function public.mod_sweep_expired(p_user uuid default null)
returns int
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    update public.user_restrictions
    set end_notified_at = now()
    where lifted_at is null and until is not null and until <= now()
      and end_notified_at is null
      and (p_user is null or user_id = p_user)
    returning id, user_id, scope
  loop
    perform public.mod_notify(r.user_id,
      'A restriction has ended',
      'You can use ' || public.mod_scope_label(r.scope) || ' again. Please keep to the community rules.',
      jsonb_build_object('kind', 'restriction_ended', 'restriction_id', r.id, 'scope', r.scope));
    perform public.mod_log('restriction_expired', 'restriction', r.id::text, null,
      jsonb_build_object('scope', r.scope), true);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ------------------------------------------------------- profile audit
-- Role / verification / ban changes are logged however they happen.
-- Moderation RPCs set mykerawang.mod_rpc and log their own richer entry.
create or replace function public.mod_profile_audit()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('mykerawang.mod_rpc', true), '') = '1' then
    return null;
  end if;
  if new.role is distinct from old.role then
    perform public.mod_log('role_change', 'user', new.id::text, null,
      jsonb_build_object('from', old.role, 'to', new.role));
  end if;
  if new.is_verified is distinct from old.is_verified then
    perform public.mod_log('verified_change', 'user', new.id::text, null,
      jsonb_build_object('from', old.is_verified, 'to', new.is_verified));
  end if;
  if new.is_banned is distinct from old.is_banned then
    perform public.mod_log('ban_flag_change', 'user', new.id::text, new.ban_reason,
      jsonb_build_object('from', old.is_banned, 'to', new.is_banned));
  end if;
  return null;
end;
$$;

drop trigger if exists trg_mod_profile_audit on public.profiles;
create trigger trg_mod_profile_audit
after update of role, is_verified, is_banned on public.profiles
for each row execute function public.mod_profile_audit();

-- Settings edits are logged with the before/after values.
create or replace function public.mod_settings_audit()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and tg_when = 'BEFORE' then
    new.updated_at := now();
    new.updated_by := auth.uid();
    return new;
  end if;
  perform public.mod_log('settings_change', 'settings', 'moderation', null,
    jsonb_build_object('before', to_jsonb(old) - 'updated_at' - 'updated_by',
                       'after',  to_jsonb(new) - 'updated_at' - 'updated_by'));
  return null;
end;
$$;

drop trigger if exists trg_mod_settings_stamp on public.moderation_settings;
create trigger trg_mod_settings_stamp
before update on public.moderation_settings
for each row execute function public.mod_settings_audit();

drop trigger if exists trg_mod_settings_audit on public.moderation_settings;
create trigger trg_mod_settings_audit
after update on public.moderation_settings
for each row execute function public.mod_settings_audit();

-- ------------------------------------------------------- grants
revoke execute on function public.mod_reporter_trusted(uuid)        from public, anon, authenticated;
revoke execute on function public.mod_notify_reporters(uuid, text)  from public, anon, authenticated;
revoke execute on function public.mod_auto_hide(uuid, text, text)   from public, anon, authenticated;
revoke execute on function public.mod_report_before_insert()        from public, anon, authenticated;
revoke execute on function public.mod_report_after_insert()         from public, anon, authenticated;
revoke execute on function public.mod_target_deleted()              from public, anon, authenticated;
revoke execute on function public.mod_apply_strike(uuid)            from public, anon, authenticated;
revoke execute on function public.mod_restriction_changed()         from public, anon, authenticated;
revoke execute on function public.mod_sweep_expired(uuid)           from public, anon, authenticated;
revoke execute on function public.mod_profile_audit()               from public, anon, authenticated;
revoke execute on function public.mod_settings_audit()              from public, anon, authenticated;
