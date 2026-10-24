-- "Pretending to be someone else": a report category for impersonation.
--
-- Verification proves a mailbox, not a person, so impersonation is
-- handled by reporting rather than by gatekeeping. This category is put
-- at the front of the queue (priority 2) but does NOT auto-hide on the
-- first report: a single unproven accusation must not be able to take
-- someone's post down. Owner can promote it to priority_categories in
-- Settings if a first-report takedown is ever wanted.
--
-- Everything here is re-runnable.

-- ------------------------------------------------------- settings
alter table public.moderation_settings
  add column if not exists review_first_categories text[] not null default '{impersonation}';

comment on column public.moderation_settings.review_first_categories is
  'Categories shown at the top of the queue (priority 2) without the automatic hide that priority_categories causes.';

-- ------------------------------------------------------- reports
alter table public.reports drop constraint if exists reports_category_valid;
alter table public.reports add constraint reports_category_valid
  check (category in ('spam','scam','harassment','impersonation',
                      'inappropriate','minor_safety','misinformation','other'));

-- Reason text → category. The stored reason stays English.
create or replace function public.mod_category_from_reason(p_reason text)
returns text
language sql immutable
as $$
  select case
    when p_reason ilike '%minor%' or p_reason ilike '%child%'      then 'minor_safety'
    when p_reason ilike '%impersonat%' or p_reason ilike '%pretend%' then 'impersonation'
    when p_reason ilike 'scam%'   or p_reason ilike '%fraud%'      then 'scam'
    when p_reason ilike '%spam%'                                   then 'spam'
    when p_reason ilike '%hate%'  or p_reason ilike '%harass%'     then 'harassment'
    when p_reason ilike '%inappropriate%' or p_reason ilike '%sexual%' then 'inappropriate'
    when p_reason ilike '%misinfo%'                                then 'misinformation'
    else 'other'
  end;
$$;

-- Human label used in notifications ("It was reported as …").
create or replace function public.mod_category_label(p_category text)
returns text
language sql immutable
as $$
  select case p_category
    when 'spam'           then 'spam'
    when 'scam'           then 'a scam or fraud'
    when 'harassment'     then 'hate speech or harassment'
    when 'impersonation'  then 'pretending to be someone else'
    when 'inappropriate'  then 'inappropriate content'
    when 'minor_safety'   then 'content endangering minors'
    when 'misinformation' then 'misinformation'
    else 'breaking the community rules' end;
$$;

-- ------------------------------------------------------- report insert
-- Only the allowed-category list changes here.
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
  if new.category not in ('spam','scam','harassment','impersonation',
                          'inappropriate','minor_safety','misinformation','other') then
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

-- ------------------------------------------------------- auto-hide
-- Same as 004300, plus: a review-first category raises priority without
-- hiding. priority_categories still hide on the first report.
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
  v_review     boolean;
  v_counted    int;
  v_total      int;
  v_restored   boolean;
begin
  select * into c from public.moderation_cases where id = new.case_id for update;
  if not found then return null; end if;

  v_priority := new.category = any (s.priority_categories);
  v_review   := new.category = any (s.review_first_categories);

  select count(distinct reporter_id) filter (where counts_toward_auto_hide),
         count(*)
  into v_counted, v_total
  from public.reports where case_id = c.id;

  update public.moderation_cases
  set last_reported_at = now(),
      priority = greatest(priority,
                          case when v_priority or v_review then 2
                               when v_counted >= s.auto_hide_report_count then 1
                               else 0 end)
  where id = c.id;

  t := public.mod_log_target(c);
  perform public.mod_log(
    case when v_total = 1 then 'case_opened' else 'report_consolidated' end,
    t[1], t[2], null,
    jsonb_build_object('case_id', c.id, 'category', new.category,
                       'reports', v_total, 'trusted_reporters', v_counted,
                       'counted', new.counts_toward_auto_hide,
                       'review_first', v_review),
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

revoke execute on function public.mod_report_before_insert() from public, anon, authenticated;
revoke execute on function public.mod_report_after_insert()  from public, anon, authenticated;
