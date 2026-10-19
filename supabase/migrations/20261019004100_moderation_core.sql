-- Moderation, part 1: data model.
--
--   moderation_settings  one row, owner-editable thresholds (nothing hardcoded)
--   reports              + status, category, case_id, handled_*, one per reporter+target
--   moderation_cases     one active case per reported target; reports attach to it
--   user_restrictions    scoped, optionally time-limited write bans
--   moderation_log       append-only audit trail (admins read, nobody edits)
--   appeals              one per decision (case or restriction)
--   comments/events/listings.is_hidden, so every reportable type can be hidden
--
-- Later files: 004200 enforcement, 004300 automation, 004400 admin RPCs,
-- 004500 pins. Apply in order. Every statement is re-runnable.
--
-- Internal helpers are prefixed mod_ and are not executable by clients.

-- ====================================================== settings
create table if not exists public.moderation_settings (
  id boolean primary key default true check (id),
  -- Distinct (trusted) reporters before content is hidden automatically.
  auto_hide_report_count        int     not null default 3,
  -- Categories hidden on the first report.
  priority_categories           text[]  not null default '{scam,minor_safety}',
  strike_window_days            int     not null default 30,
  strikes_for_auto_restriction  int     not null default 3,
  auto_restriction_days         int     not null default 7,
  -- Accounts younger than this get the per-hour limits below.
  new_account_hours             int     not null default 24,
  new_account_posts_per_hour    int     not null default 3,
  new_account_comments_per_hour int     not null default 10,
  new_account_listings_per_hour int     not null default 3,
  new_account_events_per_hour   int     not null default 2,
  -- Reporter quality: once a reporter has this many resolved reports and
  -- more than this share were dismissed, their reports stop counting
  -- toward auto-hide (they still reach the queue).
  reporter_min_resolved         int     not null default 5,
  reporter_max_dismissed_ratio  numeric not null default 0.7,
  max_active_pins_per_club      int     not null default 1,
  pin_duration_days             int     not null default 7,
  updated_at                    timestamptz not null default now(),
  updated_by                    uuid
);

alter table public.moderation_settings
  drop constraint if exists moderation_settings_sane;
alter table public.moderation_settings
  add constraint moderation_settings_sane check (
        auto_hide_report_count >= 1
    and strike_window_days >= 1
    and strikes_for_auto_restriction >= 1
    and auto_restriction_days >= 1
    and new_account_hours >= 0
    and new_account_posts_per_hour >= 1
    and new_account_comments_per_hour >= 1
    and new_account_listings_per_hour >= 1
    and new_account_events_per_hour >= 1
    and reporter_min_resolved >= 1
    and reporter_max_dismissed_ratio between 0 and 1
    and max_active_pins_per_club >= 0
    and pin_duration_days >= 1);

insert into public.moderation_settings (id) values (true) on conflict do nothing;

alter table public.moderation_settings enable row level security;

drop policy if exists "moderation_settings_select" on public.moderation_settings;
create policy "moderation_settings_select" on public.moderation_settings
for select to authenticated using (true);

drop policy if exists "moderation_settings_update_owner" on public.moderation_settings;
create policy "moderation_settings_update_owner" on public.moderation_settings
for update to authenticated
using (public.is_owner()) with check (public.is_owner());

revoke all on public.moderation_settings from anon;
grant select, update on public.moderation_settings to authenticated;

create or replace function public.mod_settings()
returns public.moderation_settings
language sql security definer stable
set search_path = public
as $$
  select * from public.moderation_settings where id;
$$;

-- ====================================================== audit log
-- actor_id has no FK: deleting a profile must not rewrite history.
create table if not exists public.moderation_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid,
  actor       text not null check (actor in ('system','owner','admin','user')),
  action      text not null,
  target_type text,
  target_id   text,
  reason      text,
  metadata    jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

create index if not exists moderation_log_created_idx on public.moderation_log (created_at desc);
create index if not exists moderation_log_action_idx  on public.moderation_log (action);

alter table public.moderation_log enable row level security;

drop policy if exists "moderation_log_select_admin" on public.moderation_log;
create policy "moderation_log_select_admin" on public.moderation_log
for select to authenticated using (public.is_admin());

revoke all on public.moderation_log from anon, authenticated;
grant select on public.moderation_log to authenticated;

-- Append-only for everyone, service_role and definer functions included.
create or replace function public.mod_log_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'moderation_log is append-only' using errcode = '42501';
end;
$$;

drop trigger if exists trg_moderation_log_immutable on public.moderation_log;
create trigger trg_moderation_log_immutable
before update or delete on public.moderation_log
for each row execute function public.mod_log_immutable();

drop trigger if exists trg_moderation_log_no_truncate on public.moderation_log;
create trigger trg_moderation_log_no_truncate
before truncate on public.moderation_log
for each statement execute function public.mod_log_immutable();

-- p_system: the action was taken by an automatic rule, even if a user's
-- request (e.g. inserting a report) happened to run it.
create or replace function public.mod_log(
  p_action      text,
  p_target_type text,
  p_target_id   text,
  p_reason      text  default null,
  p_metadata    jsonb default '{}',
  p_system      boolean default false
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_role text;
begin
  if p_system or v_uid is null then
    insert into public.moderation_log (actor_id, actor, action, target_type, target_id, reason, metadata)
    values (null, 'system', p_action, p_target_type, p_target_id, p_reason, coalesce(p_metadata, '{}'));
    return;
  end if;

  select role into v_role from public.profiles where id = v_uid;
  insert into public.moderation_log (actor_id, actor, action, target_type, target_id, reason, metadata)
  values (
    v_uid,
    case when v_role in ('owner','admin') then v_role else 'user' end,
    p_action, p_target_type, p_target_id, p_reason, coalesce(p_metadata, '{}'));
end;
$$;

-- ====================================================== notifications
-- System notices have no actor. The DB keeps one language (English, as
-- for mentions); data.kind lets the app localise later.
alter table public.notifications alter column actor_id drop not null;

create or replace function public.mod_notify(
  p_user  uuid,
  p_title text,
  p_body  text,
  p_data  jsonb default '{}'
)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if p_user is null then return; end if;
  begin
    insert into public.notifications (user_id, actor_id, type, title, body, data)
    values (p_user, null, 'moderation', p_title, p_body,
            coalesce(p_data, '{}') || jsonb_build_object('route', '/standing'));
  exception when others then
    -- A failed notice must never undo the moderation action itself
    -- (e.g. if notifications.type has a check constraint).
    perform public.mod_log('notify_failed', 'user', p_user::text, sqlerrm,
                           jsonb_build_object('title', p_title), true);
  end;
end;
$$;

-- ====================================================== cases
create table if not exists public.moderation_cases (
  id                uuid primary key default gen_random_uuid(),
  target_type       text not null check (target_type in ('post','comment','event','listing','user')),
  target_id         text not null,
  -- Server-side only. Admin views blank it when target_anonymous.
  target_owner_id   uuid references public.profiles(id) on delete set null,
  target_anonymous  boolean not null default false,
  -- open      reported, visible, waiting
  -- hidden    auto-hidden, waiting for a human
  -- actioned  upheld (removed / warned)
  -- dismissed no violation (content restored if it was hidden)
  -- closed    target deleted by its author
  status            text not null default 'open'
                    check (status in ('open','hidden','actioned','dismissed','closed')),
  -- 2 priority category, 1 threshold reached / auto-hidden, 0 normal
  priority          smallint not null default 0,
  auto_hidden       boolean not null default false,
  hidden_at         timestamptz,
  decision          text check (decision in ('dismissed','restored','removed','warned','target_deleted')),
  decision_reason   text,
  decided_by        uuid references public.profiles(id) on delete set null,
  decided_at        timestamptz,
  -- Upheld against the owner; counted for automatic restrictions.
  strike            boolean not null default false,
  first_reported_at timestamptz not null default now(),
  last_reported_at  timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

create unique index if not exists moderation_cases_one_active
  on public.moderation_cases (target_type, target_id)
  where status in ('open','hidden');
create index if not exists moderation_cases_queue_idx
  on public.moderation_cases (status, priority desc, first_reported_at);
create index if not exists moderation_cases_strikes_idx
  on public.moderation_cases (target_owner_id, decided_at) where strike;

-- No policies: admins read through moderation_queue, owners through
-- my_moderation_status(). The table itself would leak anonymous authors.
alter table public.moderation_cases enable row level security;
revoke all on public.moderation_cases from anon, authenticated;

-- ====================================================== reports
alter table public.reports
  add column if not exists status          text not null default 'open',
  add column if not exists category        text,
  add column if not exists case_id         uuid,
  add column if not exists handled_by      uuid,
  add column if not exists handled_at      timestamptz,
  add column if not exists resolution_note text,
  add column if not exists counts_toward_auto_hide boolean not null default true,
  add column if not exists created_at      timestamptz not null default now();

-- Older projects already had a free-text reports.status (and possibly
-- category). Map legacy values onto the new set before constraining.
update public.reports set status = case
    when lower(trim(status)) in ('open','actioned','dismissed','closed') then lower(trim(status))
    when lower(trim(status)) in ('resolved','reviewed','done','handled','removed','approved','action_taken','actioned_on')
      then 'actioned'
    when lower(trim(status)) in ('rejected','ignored','invalid','declined','no_action')
      then 'dismissed'
    else 'open'
  end
where status is null
   or status not in ('open','actioned','dismissed','closed');
alter table public.reports alter column status set default 'open';
alter table public.reports alter column status set not null;

alter table public.reports drop constraint if exists reports_status_valid;
alter table public.reports add constraint reports_status_valid
  check (status in ('open','actioned','dismissed','closed'));

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reports_case_fk') then
    alter table public.reports add constraint reports_case_fk
      foreign key (case_id) references public.moderation_cases(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'reports_handled_by_fk') then
    alter table public.reports add constraint reports_handled_by_fk
      foreign key (handled_by) references public.profiles(id) on delete set null;
  end if;
end $$;

create index if not exists reports_case_idx     on public.reports (case_id);
create index if not exists reports_reporter_idx on public.reports (reporter_id, status);

-- The stored reason stays English (report_helper.dart); category is the
-- machine value the thresholds use.
create or replace function public.mod_category_from_reason(p_reason text)
returns text
language sql immutable
as $$
  select case
    when p_reason ilike '%minor%' or p_reason ilike '%child%'      then 'minor_safety'
    when p_reason ilike 'scam%'   or p_reason ilike '%fraud%'      then 'scam'
    when p_reason ilike '%spam%'                                   then 'spam'
    when p_reason ilike '%hate%'  or p_reason ilike '%harass%'     then 'harassment'
    when p_reason ilike '%inappropriate%' or p_reason ilike '%sexual%' then 'inappropriate'
    when p_reason ilike '%misinfo%'                                then 'misinformation'
    else 'other'
  end;
$$;

update public.reports set category = public.mod_category_from_reason(reason)
where category is null
   or category not in ('spam','scam','harassment','inappropriate','minor_safety','misinformation','other');

alter table public.reports drop constraint if exists reports_category_valid;
alter table public.reports add constraint reports_category_valid
  check (category in ('spam','scam','harassment','inappropriate','minor_safety','misinformation','other'));

-- One report per reporter per target. Older duplicates are dropped
-- (earliest kept) so the constraint can be added.
delete from public.reports r
using public.reports keep
where keep.reporter_id = r.reporter_id
  and keep.target_type = r.target_type
  and keep.target_id   = r.target_id
  and keep.ctid < r.ctid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reports_one_per_reporter') then
    alter table public.reports add constraint reports_one_per_reporter
      unique (reporter_id, target_type, target_id);
  end if;
end $$;

-- Who reported what is private. Enabling RLS here is safe whatever the
-- previous state: the client only inserts its own reports.
alter table public.reports enable row level security;

drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own" on public.reports
for insert to authenticated with check (reporter_id = auth.uid());

drop policy if exists "reports_select_own" on public.reports;
create policy "reports_select_own" on public.reports
for select to authenticated using (reporter_id = auth.uid() or public.is_admin());

revoke update, delete on public.reports from anon, authenticated;

-- ====================================================== restrictions
create table if not exists public.user_restrictions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  -- account blocks every write
  scope           text not null check (scope in ('post','comment','market','events','account')),
  -- null = permanent
  until           timestamptz,
  reason          text not null,
  case_id         uuid references public.moderation_cases(id) on delete set null,
  -- null = created by an automatic rule
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  lifted_at       timestamptz,
  lifted_by       uuid references public.profiles(id) on delete set null,
  lift_reason     text,
  -- Set once the "restriction ended" notice went out (see mod_sweep_expired).
  end_notified_at timestamptz
);

create index if not exists user_restrictions_active_idx
  on public.user_restrictions (user_id, scope) where lifted_at is null;

alter table public.user_restrictions enable row level security;

drop policy if exists "user_restrictions_select_own" on public.user_restrictions;
create policy "user_restrictions_select_own" on public.user_restrictions
for select to authenticated using (user_id = auth.uid());

revoke all on public.user_restrictions from anon, authenticated;
grant select on public.user_restrictions to authenticated;

-- ====================================================== appeals
create table if not exists public.appeals (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  case_id         uuid references public.moderation_cases(id) on delete cascade,
  restriction_id  uuid references public.user_restrictions(id) on delete cascade,
  message         text not null,
  status          text not null default 'pending' check (status in ('pending','accepted','rejected')),
  handled_by      uuid references public.profiles(id) on delete set null,
  handled_at      timestamptz,
  resolution_note text,
  created_at      timestamptz not null default now(),
  check (num_nonnulls(case_id, restriction_id) = 1),
  check (length(btrim(message)) between 10 and 2000)
);

create unique index if not exists appeals_one_per_case
  on public.appeals (case_id) where case_id is not null;
create unique index if not exists appeals_one_per_restriction
  on public.appeals (restriction_id) where restriction_id is not null;

alter table public.appeals enable row level security;

drop policy if exists "appeals_select_own" on public.appeals;
create policy "appeals_select_own" on public.appeals
for select to authenticated using (user_id = auth.uid());

revoke all on public.appeals from anon, authenticated;
grant select on public.appeals to authenticated;

-- ====================================================== hideable content
-- posts.is_hidden already exists (20260801000100).
alter table public.comments add column if not exists is_hidden boolean not null default false;
alter table public.events   add column if not exists is_hidden boolean not null default false;
alter table public.listings add column if not exists is_hidden boolean not null default false;

-- Restrictive policies AND with whatever permissive ones exist, so this
-- works without knowing them. Owners and admins still see the row.
-- anon gets its own policy because is_admin() isn't granted to anon.
drop policy if exists "comments_hide_moderated" on public.comments;
create policy "comments_hide_moderated" on public.comments
as restrictive for select to authenticated
using (not is_hidden or user_id = auth.uid() or public.is_admin());

drop policy if exists "comments_hide_moderated_anon" on public.comments;
create policy "comments_hide_moderated_anon" on public.comments
as restrictive for select to anon using (not is_hidden);

drop policy if exists "events_hide_moderated" on public.events;
create policy "events_hide_moderated" on public.events
as restrictive for select to authenticated
using (not is_hidden or organizer_id = auth.uid() or public.is_admin());

drop policy if exists "events_hide_moderated_anon" on public.events;
create policy "events_hide_moderated_anon" on public.events
as restrictive for select to anon using (not is_hidden);

drop policy if exists "listings_hide_moderated" on public.listings;
create policy "listings_hide_moderated" on public.listings
as restrictive for select to authenticated
using (not is_hidden or seller_id = auth.uid() or public.is_admin());

drop policy if exists "listings_hide_moderated_anon" on public.listings;
create policy "listings_hide_moderated_anon" on public.listings
as restrictive for select to anon using (not is_hidden);

-- comments_public runs as its owner (bypasses RLS), so filter it here.
-- Same columns as 20260801000100, only the where clause is new.
create or replace view public.comments_public as
select
  c.id, c.post_id, c.event_id, c.body, c.is_anonymous, c.created_at,
  case when c.is_anonymous then null else c.user_id end as user_id,
  case
    when c.is_anonymous or pr.id is null then null
    else jsonb_build_object(
      'id', pr.id, 'username', pr.username,
      'display_name', pr.display_name, 'avatar_url', pr.avatar_url)
  end as profiles
from public.comments c
left join public.profiles pr on pr.id = c.user_id
where not c.is_hidden;

grant select on public.comments_public to authenticated, anon;

-- ====================================================== target helpers
create or replace function public.mod_is_hideable(p_type text)
returns boolean
language sql immutable
as $$ select p_type in ('post','comment','event','listing'); $$;

-- Owner + anonymity of a reportable target. No row = target missing.
create or replace function public.mod_target_owner(p_type text, p_id text)
returns table (owner_id uuid, anonymous boolean)
language plpgsql security definer stable
set search_path = public
as $$
begin
  case p_type
    when 'post' then
      return query select p.user_id, coalesce(p.is_anonymous, false)
                   from public.posts p where p.id = p_id::uuid;
    when 'comment' then
      return query select c.user_id, coalesce(c.is_anonymous, false)
                   from public.comments c where c.id = p_id::uuid;
    when 'event' then
      return query select e.organizer_id, false from public.events e where e.id = p_id::uuid;
    when 'listing' then
      return query select l.seller_id, false from public.listings l where l.id = p_id::uuid;
    when 'user' then
      return query select pr.id, false from public.profiles pr where pr.id = p_id::uuid;
    else
      return;
  end case;
exception when invalid_text_representation then
  return;
end;
$$;

create or replace function public.mod_set_hidden(p_type text, p_id text, p_hidden boolean)
returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
  case p_type
    when 'post'    then update public.posts    set is_hidden = p_hidden where id = p_id::uuid;
    when 'comment' then update public.comments set is_hidden = p_hidden where id = p_id::uuid;
    when 'event'   then update public.events   set is_hidden = p_hidden where id = p_id::uuid;
    when 'listing' then update public.listings set is_hidden = p_hidden where id = p_id::uuid;
    else return false;
  end case;
  return found;
end;
$$;

-- Short content summary for queue previews and owners' own status page.
create or replace function public.mod_preview_raw(p_type text, p_id text)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
declare
  v jsonb;
begin
  case p_type
    when 'post' then
      select jsonb_build_object('title', p.title, 'body', left(p.body, 600),
               'image_url', p.image_url, 'anonymous', coalesce(p.is_anonymous, false),
               'hidden', p.is_hidden, 'created_at', p.created_at)
      into v from public.posts p where p.id = p_id::uuid;
    when 'comment' then
      select jsonb_build_object('body', left(c.body, 600), 'post_id', c.post_id,
               'event_id', c.event_id, 'anonymous', coalesce(c.is_anonymous, false),
               'hidden', c.is_hidden, 'created_at', c.created_at)
      into v from public.comments c where c.id = p_id::uuid;
    when 'event' then
      select jsonb_build_object('title', e.title, 'body', left(e.description, 600),
               'image_url', e.image_url, 'hidden', e.is_hidden, 'starts_at', e.start_datetime)
      into v from public.events e where e.id = p_id::uuid;
    when 'listing' then
      select jsonb_build_object('title', l.title, 'body', left(l.description, 600),
               'image_url', l.image_url, 'price', l.price, 'hidden', l.is_hidden)
      into v from public.listings l where l.id = p_id::uuid;
    when 'user' then
      select jsonb_build_object('title', coalesce(pr.display_name, pr.username),
               'username', pr.username, 'body', left(pr.bio, 600),
               'image_url', pr.avatar_url, 'role', pr.role, 'banned', coalesce(pr.is_banned, false))
      into v from public.profiles pr where pr.id = p_id::uuid;
    else
      v := null;
  end case;
  return v;
exception when invalid_text_representation then
  return null;
end;
$$;

-- Views call this as the requesting user, so it is granted but answers
-- admins only.
create or replace function public.mod_preview(p_type text, p_id text)
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select case when public.is_admin() then public.mod_preview_raw(p_type, p_id) end;
$$;

-- ====================================================== grants
revoke execute on function public.mod_settings()                         from public, anon;
revoke execute on function public.mod_log(text, text, text, text, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.mod_notify(uuid, text, text, jsonb)    from public, anon, authenticated;
revoke execute on function public.mod_target_owner(text, text)           from public, anon, authenticated;
revoke execute on function public.mod_set_hidden(text, text, boolean)    from public, anon, authenticated;
revoke execute on function public.mod_preview_raw(text, text)            from public, anon, authenticated;
revoke execute on function public.mod_preview(text, text)                from public, anon;
grant  execute on function public.mod_preview(text, text)                to authenticated;
grant  execute on function public.mod_settings()                         to authenticated;
