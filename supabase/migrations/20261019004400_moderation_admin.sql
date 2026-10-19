-- Moderation, part 4: human decisions, admin views, and the user side
-- (status page + appeals).
--
-- Human-only (each an RPC that checks is_admin(), requires a reason and
-- logs): resolve a case (dismiss / restore / remove / warn), restrict a
-- user (any scope, timed or permanent), lift / reinstate a restriction,
-- bulk-resolve spam, unmask an anonymous author, approve or reject a
-- club, decide an appeal. Role changes stay owner-only (guard trigger in
-- 20260801000200) and are logged by trg_mod_profile_audit.
--
-- Anonymity: admin views blank the owner of anonymous targets. Acting on
-- the author (strike, restriction) goes through the case id, so admins
-- can enforce without learning who it is. Only admin_unmask() reveals
-- the author, and it requires a typed reason that is logged.
--
-- Errors are raised as 'MOD:<code>' for the app to translate.

create or replace function public.mod_require_admin()
returns void
language plpgsql stable security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'MOD:not_admin' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.mod_require_reason(p_reason text, p_min int default 3)
returns text
language plpgsql immutable
as $$
begin
  if p_reason is null or length(btrim(p_reason)) < p_min then
    raise exception 'MOD:reason_required' using errcode = 'P0001',
      detail = jsonb_build_object('min', p_min)::text;
  end if;
  return btrim(p_reason);
end;
$$;

-- Marks the transaction so trg_mod_profile_audit doesn't double-log.
create or replace function public.mod_rpc_begin()
returns void
language sql
as $$ select set_config('mykerawang.mod_rpc', '1', true); $$;

revoke execute on function public.mod_require_admin()          from public, anon, authenticated;
revoke execute on function public.mod_require_reason(text, int) from public, anon, authenticated;
revoke execute on function public.mod_rpc_begin()              from public, anon, authenticated;

-- ====================================================== views
-- These run as their owner and so bypass RLS; `where is_admin()` is the
-- gate. Never expose target_owner_id of anonymous targets here.

drop view if exists public.moderation_queue;
create view public.moderation_queue as
select
  c.id, c.target_type, c.target_id, c.status, c.priority,
  c.auto_hidden, c.hidden_at, c.decision, c.decision_reason, c.decided_at,
  c.first_reported_at, c.last_reported_at, c.target_anonymous,
  case when c.target_anonymous then null else c.target_owner_id end as target_owner_id,
  case when c.target_anonymous or pr.id is null then null
       else jsonb_build_object('id', pr.id, 'username', pr.username,
              'display_name', pr.display_name, 'avatar_url', pr.avatar_url,
              'role', pr.role)
  end as owner,
  case when c.target_anonymous then null else (
    select count(*)::int from public.moderation_cases s
    where s.target_owner_id = c.target_owner_id and s.strike
      and s.decided_at > now() - make_interval(days => (public.mod_settings()).strike_window_days)
  ) end as owner_strikes,
  agg.report_count, agg.trusted_reporters, agg.categories, agg.reasons,
  public.mod_preview(c.target_type, c.target_id) as preview,
  (select a.status from public.appeals a where a.case_id = c.id) as appeal_status
from public.moderation_cases c
left join public.profiles pr on pr.id = c.target_owner_id
left join lateral (
  select count(*)::int as report_count,
         count(distinct r.reporter_id) filter (where r.counts_toward_auto_hide)::int as trusted_reporters,
         coalesce(array_agg(distinct r.category) filter (where r.category is not null), '{}') as categories,
         coalesce(array_agg(distinct r.reason)   filter (where r.reason   is not null), '{}') as reasons
  from public.reports r where r.case_id = c.id
) agg on true
where public.is_admin();

drop view if exists public.moderation_restrictions;
create view public.moderation_restrictions as
select
  r.id, r.scope, r.until, r.reason, r.case_id, r.created_at,
  r.lifted_at, r.lift_reason,
  (r.lifted_at is null and (r.until is null or r.until > now())) as active,
  (r.created_by is null) as automatic,
  coalesce(c.target_anonymous, false) as anonymous_source,
  case when coalesce(c.target_anonymous, false) then null else r.user_id end as user_id,
  case when coalesce(c.target_anonymous, false) or pr.id is null then null
       else jsonb_build_object('id', pr.id, 'username', pr.username,
              'display_name', pr.display_name, 'avatar_url', pr.avatar_url)
  end as profile,
  cb.display_name as created_by_name,
  lb.display_name as lifted_by_name
from public.user_restrictions r
left join public.moderation_cases c on c.id = r.case_id
left join public.profiles pr on pr.id = r.user_id
left join public.profiles cb on cb.id = r.created_by
left join public.profiles lb on lb.id = r.lifted_by
where public.is_admin();

drop view if exists public.moderation_appeals;
create view public.moderation_appeals as
select
  a.id, a.message, a.status, a.created_at, a.handled_at, a.resolution_note,
  a.case_id, a.restriction_id,
  coalesce(c.target_anonymous, rc.target_anonymous, false) as anonymous_source,
  case when coalesce(c.target_anonymous, rc.target_anonymous, false) then null
       else jsonb_build_object('id', pr.id, 'username', pr.username,
              'display_name', pr.display_name, 'avatar_url', pr.avatar_url)
  end as profile,
  case when c.id is null then null else jsonb_build_object(
    'target_type', c.target_type, 'target_id', c.target_id, 'status', c.status,
    'decision', c.decision, 'decision_reason', c.decision_reason,
    'preview', public.mod_preview(c.target_type, c.target_id)) end as case_info,
  case when r.id is null then null else jsonb_build_object(
    'scope', r.scope, 'until', r.until, 'reason', r.reason,
    'active', r.lifted_at is null and (r.until is null or r.until > now())) end as restriction_info
from public.appeals a
left join public.moderation_cases  c  on c.id = a.case_id
left join public.user_restrictions r  on r.id = a.restriction_id
left join public.moderation_cases  rc on rc.id = r.case_id
left join public.profiles pr on pr.id = a.user_id
where public.is_admin();

revoke all on public.moderation_queue, public.moderation_restrictions, public.moderation_appeals from anon;
grant select on public.moderation_queue, public.moderation_restrictions, public.moderation_appeals to authenticated;

-- ====================================================== cases
create or replace function public.admin_resolve_case(
  p_case_id  uuid,
  p_decision text,   -- dismiss | restore | remove | warn
  p_reason   text
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c          public.moderation_cases;
  t          text[];
  v_reason   text;
  v_decision text;
  v_status   text;
  v_label    text;
  v_hidden   boolean;
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();
  v_reason := public.mod_require_reason(p_reason);

  select * into c from public.moderation_cases where id = p_case_id for update;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  if c.status not in ('open','hidden') then
    raise exception 'MOD:already_resolved' using errcode = 'P0001';
  end if;

  v_label  := public.mod_type_label(c.target_type);
  v_hidden := c.status = 'hidden';

  if p_decision in ('dismiss','restore') then
    if v_hidden then
      perform public.mod_set_hidden(c.target_type, c.target_id, false);
    end if;
    v_decision := case when v_hidden then 'restored' else 'dismissed' end;
    v_status   := 'dismissed';
  elsif p_decision = 'remove' then
    if not public.mod_is_hideable(c.target_type) then
      raise exception 'MOD:not_hideable' using errcode = 'P0001';
    end if;
    perform public.mod_set_hidden(c.target_type, c.target_id, true);
    v_decision := 'removed';
    v_status   := 'actioned';
  elsif p_decision = 'warn' then
    v_decision := 'warned';
    v_status   := 'actioned';
  else
    raise exception 'MOD:bad_decision' using errcode = 'P0001';
  end if;

  update public.moderation_cases
  set status = v_status, decision = v_decision, decision_reason = v_reason,
      decided_by = auth.uid(), decided_at = now()
  where id = c.id;

  update public.reports
  set status = case when v_status = 'actioned' then 'actioned' else 'dismissed' end,
      handled_by = auth.uid(), handled_at = now(), resolution_note = v_reason
  where case_id = c.id and status = 'open';

  if v_status = 'actioned' then
    perform public.mod_apply_strike(c.id);
  end if;

  t := public.mod_log_target(c);
  perform public.mod_log('case_' || v_decision, t[1], t[2], v_reason,
    jsonb_build_object('case_id', c.id, 'previous_status', c.status));

  perform public.mod_notify_reporters(c.id,
    case when v_status = 'actioned' then 'actioned' else 'dismissed' end);

  if v_decision = 'restored' then
    perform public.mod_notify(c.target_owner_id,
      'Your ' || v_label || ' is visible again',
      'An admin reviewed your ' || v_label || ' and restored it. Thanks for your patience.',
      jsonb_build_object('kind', 'content_restored', 'case_id', c.id,
                         'target_type', c.target_type, 'target_id', c.target_id));
  elsif v_decision = 'removed' then
    perform public.mod_notify(c.target_owner_id,
      'Your ' || v_label || ' was removed',
      'An admin removed your ' || v_label || '. Reason: ' || v_reason
        || '. If you think this is a mistake, open Account status to appeal.',
      jsonb_build_object('kind', 'content_removed', 'case_id', c.id,
                         'target_type', c.target_type, 'target_id', c.target_id));
  elsif v_decision = 'warned' then
    perform public.mod_notify(c.target_owner_id,
      'A warning about your ' || v_label,
      'An admin reviewed a report about your ' || v_label || '. Reason: ' || v_reason
        || '. Repeated warnings can lead to restrictions. Open Account status to appeal.',
      jsonb_build_object('kind', 'warned', 'case_id', c.id,
                         'target_type', c.target_type, 'target_id', c.target_id));
  end if;

  return jsonb_build_object('case_id', c.id, 'decision', v_decision,
                            'previous_status', c.status,
                            'undoable', v_status = 'dismissed');
end;
$$;

-- Undo for dismiss / restore (the snackbar action). Removals and
-- warnings are confirmed up front instead, since they notify and strike.
create or replace function public.admin_undo_case(p_case_id uuid)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  c public.moderation_cases;
  t text[];
begin
  perform public.mod_require_admin();
  select * into c from public.moderation_cases where id = p_case_id for update;
  if not found or c.status <> 'dismissed' or c.decided_at < now() - interval '15 minutes' then
    raise exception 'MOD:cannot_undo' using errcode = 'P0001';
  end if;

  begin
    update public.moderation_cases
    set status = case when c.decision = 'restored' then 'hidden' else 'open' end,
        decision = null, decision_reason = null, decided_by = null, decided_at = null
    where id = c.id;
  exception when unique_violation then
    raise exception 'MOD:cannot_undo' using errcode = 'P0001';
  end;

  if c.decision = 'restored' then
    perform public.mod_set_hidden(c.target_type, c.target_id, true);
  end if;

  update public.reports
  set status = 'open', handled_by = null, handled_at = null, resolution_note = null
  where case_id = c.id and status = 'dismissed';

  t := public.mod_log_target(c);
  perform public.mod_log('case_reopened', t[1], t[2], 'undo',
    jsonb_build_object('case_id', c.id, 'undid', c.decision));
  return jsonb_build_object('case_id', c.id);
end;
$$;

-- Bulk actions are for spam waves only: every report on every case must
-- be categorised spam.
create or replace function public.admin_bulk_resolve(
  p_case_ids uuid[],
  p_decision text,   -- dismiss | remove
  p_reason   text
)
returns int
language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid;
  n    int := 0;
begin
  perform public.mod_require_admin();
  perform public.mod_require_reason(p_reason);
  if p_decision not in ('dismiss','remove') then
    raise exception 'MOD:bad_decision' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.reports
    where case_id = any (p_case_ids) and category is distinct from 'spam'
  ) then
    raise exception 'MOD:bulk_spam_only' using errcode = 'P0001';
  end if;

  foreach v_id in array p_case_ids loop
    perform public.admin_resolve_case(v_id, p_decision, p_reason);
    n := n + 1;
  end loop;

  perform public.mod_log('bulk_' || p_decision, 'cases', null, p_reason,
    jsonb_build_object('count', n, 'case_ids', to_jsonb(p_case_ids)));
  return n;
end;
$$;

-- ====================================================== restrictions
-- p_user_id or p_case_id (enforce against an anonymous author without
-- learning who it is). With a case, an open case is upheld too.
create or replace function public.admin_restrict_user(
  p_user_id uuid,
  p_case_id uuid,
  p_scopes  text[],
  p_until   timestamptz,  -- null = permanent
  p_reason  text
)
returns uuid[]
language plpgsql security definer
set search_path = public
as $$
declare
  c        public.moderation_cases;
  v_user   uuid := p_user_id;
  v_reason text;
  v_scope  text;
  v_ids    uuid[] := '{}';
  v_id     uuid;
  v_role   text;
  t        text[];
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();
  v_reason := public.mod_require_reason(p_reason);

  if p_case_id is not null then
    select * into c from public.moderation_cases where id = p_case_id;
    if not found then
      raise exception 'MOD:not_found' using errcode = 'P0001';
    end if;
    v_user := coalesce(v_user, c.target_owner_id);
  end if;

  if v_user is null then
    raise exception 'MOD:no_user' using errcode = 'P0001';
  end if;
  if v_user = auth.uid() then
    raise exception 'MOD:self' using errcode = 'P0001';
  end if;
  select role into v_role from public.profiles where id = v_user;
  if v_role in ('admin','owner') and not public.is_owner() then
    raise exception 'MOD:protected_user' using errcode = 'P0001';
  end if;
  if coalesce(array_length(p_scopes, 1), 0) = 0 then
    raise exception 'MOD:no_scope' using errcode = 'P0001';
  end if;
  if p_until is not null and p_until <= now() then
    raise exception 'MOD:bad_until' using errcode = 'P0001';
  end if;

  -- Restrictions first, so the strike from upholding the case doesn't
  -- add a duplicate automatic one on the same scope.
  foreach v_scope in array p_scopes loop
    insert into public.user_restrictions (user_id, scope, until, reason, case_id, created_by)
    values (v_user, v_scope, p_until, v_reason, p_case_id, auth.uid())
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;

  if p_case_id is not null then
    t := public.mod_log_target(c);
  else
    t := array['user', v_user::text];
  end if;
  perform public.mod_log('restrict', t[1], t[2], v_reason,
    jsonb_build_object('scopes', to_jsonb(p_scopes), 'until', p_until,
                       'permanent', p_until is null, 'restriction_ids', to_jsonb(v_ids),
                       'case_id', p_case_id));

  if p_case_id is not null and c.status in ('open','hidden') then
    perform public.admin_resolve_case(p_case_id,
      case when public.mod_is_hideable(c.target_type) then 'remove' else 'warn' end,
      v_reason);
  end if;

  return v_ids;
end;
$$;

create or replace function public.admin_lift_restriction(p_id uuid, p_reason text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  r        public.user_restrictions;
  v_reason text;
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();
  v_reason := public.mod_require_reason(p_reason);

  update public.user_restrictions
  set lifted_at = now(), lifted_by = auth.uid(), lift_reason = v_reason
  where id = p_id and lifted_at is null
  returning * into r;
  if not found then
    raise exception 'MOD:already_resolved' using errcode = 'P0001';
  end if;

  perform public.mod_log('restriction_lifted', 'restriction', r.id::text, v_reason,
    jsonb_build_object('scope', r.scope));
  return jsonb_build_object('id', r.id, 'undoable', true);
end;
$$;

-- Undo for a lift (snackbar), within 15 minutes.
create or replace function public.admin_reinstate_restriction(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r public.user_restrictions;
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();

  update public.user_restrictions
  set lifted_at = null, lifted_by = null, lift_reason = null
  where id = p_id and lifted_at > now() - interval '15 minutes'
  returning * into r;
  if not found then
    raise exception 'MOD:cannot_undo' using errcode = 'P0001';
  end if;

  perform public.mod_log('restriction_reinstated', 'restriction', r.id::text, 'undo',
    jsonb_build_object('scope', r.scope));
end;
$$;

-- ====================================================== unmask
-- Replaces direct use of admin_unmask_post(), which can't log.
create or replace function public.admin_unmask(p_target_type text, p_target_id uuid, p_reason text)
returns table (author_id uuid, display_name text, username text)
language plpgsql security definer
set search_path = public
as $$
declare
  v_reason text;
begin
  perform public.mod_require_admin();
  v_reason := public.mod_require_reason(p_reason, 10);
  if p_target_type not in ('post','comment') then
    raise exception 'MOD:bad_target' using errcode = 'P0001';
  end if;

  -- Logged without the revealed identity: every admin can read the log.
  perform public.mod_log('unmask', p_target_type, p_target_id::text, v_reason, '{}');

  if p_target_type = 'post' then
    return query
      select p.user_id, pr.display_name::text, pr.username::text
      from public.posts p left join public.profiles pr on pr.id = p.user_id
      where p.id = p_target_id;
  else
    return query
      select c.user_id, pr.display_name::text, pr.username::text
      from public.comments c left join public.profiles pr on pr.id = c.user_id
      where c.id = p_target_id;
  end if;
end;
$$;

-- The old function stays for the SQL editor only.
do $$
begin
  if to_regprocedure('public.admin_unmask_post(uuid)') is not null then
    revoke execute on function public.admin_unmask_post(uuid) from public, anon, authenticated;
  end if;
end $$;

-- ====================================================== clubs
create or replace function public.admin_club_requests()
returns table (id uuid, username text, display_name text, avatar_url text, bio text)
language sql security definer stable
set search_path = public
as $$
  select p.id, p.username::text, p.display_name::text, p.avatar_url::text, p.bio::text
  from public.profiles p
  where p.role = 'club_pending' and public.is_admin()
  order by p.display_name;
$$;

create or replace function public.admin_decide_club(p_user_id uuid, p_approve boolean, p_reason text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_role   text;
  v_reason text;
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();
  v_reason := case when p_approve then nullif(btrim(coalesce(p_reason, '')), '')
                   else public.mod_require_reason(p_reason) end;

  select role into v_role from public.profiles where id = p_user_id for update;
  if v_role is distinct from 'club_pending' then
    raise exception 'MOD:not_pending' using errcode = 'P0001';
  end if;

  if p_approve then
    update public.profiles set role = 'club', is_verified = true where id = p_user_id;
    perform public.mod_notify(p_user_id, 'Your club account is approved',
      'Your account is now a verified club. You can pin one announcement at a time to the top of the feed.',
      jsonb_build_object('kind', 'club_approved'));
  else
    update public.profiles set role = 'student' where id = p_user_id;
    perform public.mod_notify(p_user_id, 'Your club request wasn''t approved',
      'Reason: ' || v_reason || '. You can update your profile and request again.',
      jsonb_build_object('kind', 'club_rejected'));
  end if;

  perform public.mod_log(case when p_approve then 'club_approved' else 'club_rejected' end,
    'user', p_user_id::text, v_reason,
    jsonb_build_object('from', 'club_pending', 'to', case when p_approve then 'club' else 'student' end));
end;
$$;

-- ====================================================== appeals
create or replace function public.admin_handle_appeal(p_appeal_id uuid, p_accept boolean, p_note text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  a      public.appeals;
  c      public.moderation_cases;
  v_note text;
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();
  v_note := public.mod_require_reason(p_note);

  select * into a from public.appeals where id = p_appeal_id for update;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'pending' then
    raise exception 'MOD:already_resolved' using errcode = 'P0001';
  end if;

  if p_accept then
    if a.case_id is not null then
      select * into c from public.moderation_cases where id = a.case_id for update;
      if c.status = 'hidden' or c.decision = 'removed' then
        perform public.mod_set_hidden(c.target_type, c.target_id, false);
      end if;
      update public.moderation_cases
      set status = 'dismissed', decision = 'restored', strike = false,
          decision_reason = 'Appeal accepted: ' || v_note,
          decided_by = auth.uid(), decided_at = now()
      where id = c.id;
      update public.reports
      set status = 'dismissed', handled_by = auth.uid(), handled_at = now(),
          resolution_note = 'Appeal accepted: ' || v_note
      where case_id = c.id and status in ('open','actioned');
    else
      update public.user_restrictions
      set lifted_at = now(), lifted_by = auth.uid(), lift_reason = 'Appeal accepted: ' || v_note
      where id = a.restriction_id and lifted_at is null;
    end if;
  end if;

  update public.appeals
  set status = case when p_accept then 'accepted' else 'rejected' end,
      handled_by = auth.uid(), handled_at = now(), resolution_note = v_note
  where id = a.id;

  perform public.mod_notify(a.user_id,
    case when p_accept then 'Your appeal was accepted' else 'Your appeal wasn''t accepted' end,
    case when p_accept
      then 'An admin reviewed your appeal and reversed the decision. Note: ' || v_note
      else 'An admin reviewed your appeal and kept the decision. Note: ' || v_note end,
    jsonb_build_object('kind', 'appeal_' || case when p_accept then 'accepted' else 'rejected' end,
                       'appeal_id', a.id));

  perform public.mod_log(case when p_accept then 'appeal_accepted' else 'appeal_rejected' end,
    'appeal', a.id::text, v_note,
    jsonb_build_object('case_id', a.case_id, 'restriction_id', a.restriction_id));
end;
$$;

-- ====================================================== admin summary
-- One call for the queue header; also sends overdue "restriction ended"
-- notices (mod_sweep_expired).
create or replace function public.admin_queue_summary()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  perform public.mod_require_admin();
  perform public.mod_sweep_expired(null);
  select jsonb_build_object(
    'open_cases',      (select count(*) from public.moderation_cases where status in ('open','hidden')),
    'hidden_cases',    (select count(*) from public.moderation_cases where status = 'hidden'),
    'oldest_open_at',  (select min(first_reported_at) from public.moderation_cases where status in ('open','hidden')),
    'pending_appeals', (select count(*) from public.appeals where status = 'pending'),
    'club_requests',   (select count(*) from public.profiles where role = 'club_pending'),
    'active_restrictions', (select count(*) from public.user_restrictions
                            where lifted_at is null and (until is null or until > now())))
  into v;
  return v;
end;
$$;

-- ====================================================== user side
-- Everything the account-status page shows: active restrictions, recent
-- decisions on the caller's own content, appeal states.
create or replace function public.my_moderation_status()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v     jsonb;
begin
  if v_uid is null then
    raise exception 'MOD:not_signed_in' using errcode = '42501';
  end if;
  perform public.mod_sweep_expired(v_uid);

  select jsonb_build_object(
    'restrictions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'scope', x.scope, 'until', x.until, 'reason', x.reason,
               'created_at', x.created_at, 'automatic', x.created_by is null,
               'appeal_status', (select a.status from public.appeals a where a.restriction_id = x.id))
             order by x.created_at desc)
      from public.user_restrictions x
      where x.user_id = v_uid and x.lifted_at is null
        and (x.until is null or x.until > now())), '[]'::jsonb),
    'banned', coalesce((select is_banned from public.profiles where id = v_uid), false),
    'cases', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'target_type', c.target_type, 'target_id', c.target_id,
               'status', c.status, 'decision', c.decision,
               'reason', case when c.status = 'hidden' then null else c.decision_reason end,
               'categories', (select coalesce(array_agg(distinct r.category), '{}')
                              from public.reports r where r.case_id = c.id),
               'hidden_at', c.hidden_at, 'decided_at', c.decided_at,
               'preview', public.mod_preview_raw(c.target_type, c.target_id),
               'appeal_status', (select a.status from public.appeals a where a.case_id = c.id))
             order by coalesce(c.decided_at, c.hidden_at) desc)
      from public.moderation_cases c
      where c.target_owner_id = v_uid
        and (c.status = 'hidden' or c.decision in ('removed','warned','restored'))
        and coalesce(c.decided_at, c.hidden_at, c.created_at) > now() - interval '90 days'), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

create or replace function public.submit_appeal(p_case_id uuid, p_restriction_id uuid, p_message text)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_msg text := btrim(coalesce(p_message, ''));
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'MOD:not_signed_in' using errcode = '42501';
  end if;
  if length(v_msg) < 10 or length(v_msg) > 2000 then
    raise exception 'MOD:message_length' using errcode = 'P0001';
  end if;
  if num_nonnulls(p_case_id, p_restriction_id) <> 1 then
    raise exception 'MOD:bad_target' using errcode = 'P0001';
  end if;

  if p_case_id is not null and not exists (
    select 1 from public.moderation_cases
    where id = p_case_id and target_owner_id = v_uid
      and (status = 'hidden' or decision in ('removed','warned'))
  ) then
    raise exception 'MOD:not_appealable' using errcode = 'P0001';
  end if;

  if p_restriction_id is not null and not exists (
    select 1 from public.user_restrictions
    where id = p_restriction_id and user_id = v_uid
      and lifted_at is null and (until is null or until > now())
  ) then
    raise exception 'MOD:not_appealable' using errcode = 'P0001';
  end if;

  begin
    insert into public.appeals (user_id, case_id, restriction_id, message)
    values (v_uid, p_case_id, p_restriction_id, v_msg)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'MOD:already_appealed' using errcode = 'P0001';
  end;

  perform public.mod_log('appeal_submitted', 'appeal', v_id::text, null,
    jsonb_build_object('case_id', p_case_id, 'restriction_id', p_restriction_id));
  return v_id;
end;
$$;

-- ====================================================== grants
revoke execute on function public.admin_resolve_case(uuid, text, text)                       from public, anon;
revoke execute on function public.admin_undo_case(uuid)                                      from public, anon;
revoke execute on function public.admin_bulk_resolve(uuid[], text, text)                     from public, anon;
revoke execute on function public.admin_restrict_user(uuid, uuid, text[], timestamptz, text) from public, anon;
revoke execute on function public.admin_lift_restriction(uuid, text)                         from public, anon;
revoke execute on function public.admin_reinstate_restriction(uuid)                          from public, anon;
revoke execute on function public.admin_unmask(text, uuid, text)                             from public, anon;
revoke execute on function public.admin_club_requests()                                      from public, anon;
revoke execute on function public.admin_decide_club(uuid, boolean, text)                     from public, anon;
revoke execute on function public.admin_handle_appeal(uuid, boolean, text)                   from public, anon;
revoke execute on function public.admin_queue_summary()                                      from public, anon;
revoke execute on function public.my_moderation_status()                                     from public, anon;
revoke execute on function public.submit_appeal(uuid, uuid, text)                            from public, anon;

grant execute on function public.admin_resolve_case(uuid, text, text)                       to authenticated;
grant execute on function public.admin_undo_case(uuid)                                      to authenticated;
grant execute on function public.admin_bulk_resolve(uuid[], text, text)                     to authenticated;
grant execute on function public.admin_restrict_user(uuid, uuid, text[], timestamptz, text) to authenticated;
grant execute on function public.admin_lift_restriction(uuid, text)                         to authenticated;
grant execute on function public.admin_reinstate_restriction(uuid)                          to authenticated;
grant execute on function public.admin_unmask(text, uuid, text)                             to authenticated;
grant execute on function public.admin_club_requests()                                      to authenticated;
grant execute on function public.admin_decide_club(uuid, boolean, text)                     to authenticated;
grant execute on function public.admin_handle_appeal(uuid, boolean, text)                   to authenticated;
grant execute on function public.admin_queue_summary()                                      to authenticated;
grant execute on function public.my_moderation_status()                                     to authenticated;
grant execute on function public.submit_appeal(uuid, uuid, text)                            to authenticated;
