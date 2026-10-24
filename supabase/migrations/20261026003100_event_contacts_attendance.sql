-- Event fields, contact channels, attendance and the 1:1 announcement cover.
--
-- Phase 2: registration deadline, capacity, audience, fee, merit and the
-- UiTM activity reference. Merit is gated to club officers and admins:
-- if anyone could tick it, "merit" becomes bait.
--
-- Phase 3: contact channels live in their own table, because `events` is
-- readable by guests — a number there would be public to the internet.
--
-- Phase 4: rotating check-in codes. The organiser's device asks for a
-- token every 10 s; a token stays valid for 20 s, so one slow scan does
-- not fail while a screenshot shared later still dies. The QR encodes a
-- URL, which is what lets a phone camera open the web check-in page.
--
-- Phase 5: posts.cover_aspect (16:9 default, 1:1 optional).
--
-- Re-runnable.

-- ====================================================== phase 2: fields
alter table public.events
  add column if not exists join_deadline      timestamptz,
  add column if not exists capacity           int,
  add column if not exists audience           text,
  add column if not exists fee                numeric(10,2),
  add column if not exists merit_offered      boolean not null default false,
  add column if not exists merit_note         text,
  add column if not exists activity_ref       text,
  add column if not exists co_organiser       text,
  add column if not exists attendance_enabled boolean not null default false;

alter table public.events drop constraint if exists events_capacity_positive;
alter table public.events add constraint events_capacity_positive
  check (capacity is null or capacity > 0);

alter table public.events drop constraint if exists events_fee_non_negative;
alter table public.events add constraint events_fee_non_negative
  check (fee is null or fee >= 0);

alter table public.events drop constraint if exists events_audience_valid;
alter table public.events add constraint events_audience_valid
  check (audience is null or audience in ('uitm','kolej','klab','awam'));

-- Merit may only be claimed by a club officer publishing as the club, or
-- by staff. Re-checked only when the flag is switched on, so an edit by a
-- former officer does not fail.
create or replace function public.event_guard_merit()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.merit_offered
     and (tg_op = 'INSERT' or not coalesce(old.merit_offered, false))
     and not public.is_admin()
     and not (new.club_id is not null and public.can_act_as_club(new.club_id)) then
    raise exception 'EVENT:merit_not_allowed' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_event_guard_merit on public.events;
create trigger trg_event_guard_merit
before insert or update of merit_offered on public.events
for each row execute function public.event_guard_merit();

-- Joining: respect the deadline and the capacity. The event row is locked
-- so two simultaneous joins cannot both take the last place.
create or replace function public.event_join_guard()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  e public.events;
  n int;
begin
  if auth.uid() is null then
    return new;  -- system / SQL editor
  end if;

  select * into e from public.events where id = new.event_id for update;
  if not found then
    raise exception 'EVENT:not_found' using errcode = 'P0001';
  end if;
  if e.cancelled_at is not null then
    raise exception 'EVENT:cancelled' using errcode = 'P0001';
  end if;
  if e.join_deadline is not null and now() > e.join_deadline then
    raise exception 'EVENT:closed' using errcode = 'P0001';
  end if;
  if e.capacity is not null then
    select count(*) into n
    from public.event_participants p
    where p.event_id = new.event_id and p.user_id <> new.user_id;
    if n >= e.capacity then
      raise exception 'EVENT:full' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_event_join_guard on public.event_participants;
create trigger trg_event_join_guard
before insert on public.event_participants
for each row execute function public.event_join_guard();

-- ====================================================== phase 3: contacts
create table if not exists public.event_contacts (
  event_id   uuid primary key references public.events(id) on delete cascade,
  whatsapp   text,
  telegram   text,
  instagram  text,
  email      text,
  link       text,
  updated_at timestamptz not null default now()
);

alter table public.event_contacts enable row level security;

drop policy if exists "event_contacts_owner" on public.event_contacts;
create policy "event_contacts_owner" on public.event_contacts
for all to authenticated
using (
  public.is_admin()
  or exists (select 1 from public.events e
             where e.id = event_id and e.organizer_id = auth.uid()))
with check (
  public.is_admin()
  or exists (select 1 from public.events e
             where e.id = event_id and e.organizer_id = auth.uid()));

revoke all on public.event_contacts from anon, authenticated;
grant select, insert, update on public.event_contacts to authenticated;

-- Signed-in reveal. Same shape as get_listing_contact(), without the log:
-- the organiser chose to publish these.
create or replace function public.event_contact(p_event_id uuid)
returns table (whatsapp text, telegram text, instagram text, email text, link text)
language plpgsql security definer stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'EVENT:login_required' using errcode = '42501';
  end if;
  return query
  select c.whatsapp, c.telegram, c.instagram, c.email, c.link
  from public.event_contacts c
  where c.event_id = p_event_id;
end;
$$;

revoke execute on function public.event_contact(uuid) from public, anon;
grant  execute on function public.event_contact(uuid) to authenticated;

-- ====================================================== phase 4: attendance
create table if not exists public.event_checkin_tokens (
  token      text primary key,
  event_id   uuid not null references public.events(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists event_checkin_tokens_event_idx
  on public.event_checkin_tokens (event_id, expires_at);

alter table public.event_checkin_tokens enable row level security;
revoke all on public.event_checkin_tokens from anon, authenticated;

create table if not exists public.event_attendance (
  event_id      uuid not null references public.events(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  method        text not null default 'qr',
  primary key (event_id, user_id)
);

alter table public.event_attendance enable row level security;

drop policy if exists "event_attendance_select" on public.event_attendance;
create policy "event_attendance_select" on public.event_attendance
for select to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
  or exists (select 1 from public.events e
             where e.id = event_id and e.organizer_id = auth.uid()));

revoke all on public.event_attendance from anon, authenticated;
grant select on public.event_attendance to authenticated;

-- Organiser asks for a code; the next one replaces nothing (old codes
-- keep working until they expire, which is the two-window grace).
create or replace function public.event_checkin_token(p_event_id uuid)
returns table (token text, expires_at timestamptz)
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events e
                 where e.id = p_event_id
                   and (e.organizer_id = v_uid or public.is_admin())) then
    raise exception 'CHECKIN:not_organizer' using errcode = 'P0001';
  end if;

  delete from public.event_checkin_tokens
  where event_id = p_event_id and expires_at < now() - interval '5 minutes';

  insert into public.event_checkin_tokens (token, event_id, expires_at)
  values (gen_random_uuid()::text, p_event_id, now() + interval '20 seconds')
  returning event_checkin_tokens.token, event_checkin_tokens.expires_at
  into token, expires_at;

  return next;
end;
$$;

revoke execute on function public.event_checkin_token(uuid) from public, anon;
grant  execute on function public.event_checkin_token(uuid) to authenticated;

create or replace function public.checkin_with_token(p_token text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  t       public.event_checkin_tokens;
  e       public.events;
  v_new   boolean;
begin
  if v_uid is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;

  select * into t from public.event_checkin_tokens where token = p_token;
  if not found then
    raise exception 'CHECKIN:invalid' using errcode = 'P0001';
  end if;
  if t.expires_at < now() then
    raise exception 'CHECKIN:expired' using errcode = 'P0001';
  end if;

  select * into e from public.events where id = t.event_id;
  if e.cancelled_at is not null then
    raise exception 'CHECKIN:cancelled' using errcode = 'P0001';
  end if;

  -- Merit only means something for verified students, so require it only
  -- while verification is switched on.
  if public.verification_required('event_join')
     and not public.is_verified_student(v_uid) then
    raise exception 'CHECKIN:verify' using errcode = 'P0001';
  end if;

  insert into public.event_attendance (event_id, user_id, method)
  values (t.event_id, v_uid, 'qr')
  on conflict (event_id, user_id) do nothing;
  v_new := found;

  -- Attending implies going, unless the event is full (then the join
  -- guard would refuse; attendance still stands).
  begin
    insert into public.event_participants (event_id, user_id)
    values (t.event_id, v_uid)
    on conflict do nothing;
  exception when others then
    null;
  end;

  return case when v_new then 'ok' else 'already' end;
end;
$$;

revoke execute on function public.checkin_with_token(text) from public, anon;
grant  execute on function public.checkin_with_token(text) to authenticated;

-- Organiser export: full name, student id (the local part of the verified
-- address), when they checked in.
create or replace function public.event_attendance_list(p_event_id uuid)
returns table (
  user_id       uuid,
  username      text,
  display_name  text,
  student_id    text,
  verified      boolean,
  checked_in_at timestamptz,
  method        text
)
language plpgsql security definer stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events e
                 where e.id = p_event_id
                   and (e.organizer_id = auth.uid() or public.is_admin())) then
    raise exception 'CHECKIN:not_organizer' using errcode = 'P0001';
  end if;

  return query
  select a.user_id,
         p.username,
         p.display_name,
         split_part(v.email::text, '@', 1),
         coalesce(v.status = 'verified', false),
         a.checked_in_at,
         a.method
  from public.event_attendance a
  left join public.profiles p on p.id = a.user_id
  left join public.student_verifications v on v.user_id = a.user_id
  where a.event_id = p_event_id
  order by a.checked_in_at;
end;
$$;

revoke execute on function public.event_attendance_list(uuid) from public, anon;
grant  execute on function public.event_attendance_list(uuid) to authenticated;

-- ====================================================== phase 5: cover aspect
alter table public.posts add column if not exists cover_aspect text not null default '16:9';
alter table public.posts drop constraint if exists posts_cover_aspect_valid;
alter table public.posts add constraint posts_cover_aspect_valid
  check (cover_aspect in ('16:9','1:1'));

-- posts_public is the client's read model for announcements; the new
-- column has to ride along or the composer's choice is invisible.
create or replace view public.posts_public as
select
  p.id, p.title, p.body, p.image_url, p.gallery_urls, p.tags,
  p.upvotes, p.comment_count, p.is_anonymous,
  p.shared_event_id, p.shared_listing_id, p.created_at,
  case when p.is_anonymous then null else p.user_id end as user_id,
  case
    when p.is_anonymous or pr.id is null then null
    else jsonb_build_object(
      'id', pr.id, 'username', pr.username, 'display_name', pr.display_name,
      'avatar_url', pr.avatar_url, 'is_verified', pr.is_verified)
  end as profiles,
  case when ev.id is null or ev.is_hidden then null else to_jsonb(ev) end as events,
  case when li.id is null or li.is_hidden then null else to_jsonb(li) end as listings,
  case when p.pinned_until > now() then p.pinned_until end as pinned_until,
  coalesce(p.pinned_until > now(), false) as is_pinned,
  case when cl.id is null or cl.status <> 'active' then null
       else jsonb_build_object('id', cl.id, 'handle', cl.handle::text, 'name', cl.name,
                               'logo_url', cl.logo_url, 'is_verified', cl.is_verified)
  end as club,
  case when cl.status = 'active' then p.club_id end as club_id,
  p.is_announcement,
  p.announcement_category,
  p.cover_url,
  p.action_links,
  p.linked_event_id,
  p.publish_at,
  p.feature_until,
  p.comments_enabled,
  p.show_in_feed,
  case when p.club_pinned_until > now() then p.club_pinned_until end as club_pinned_until,
  coalesce(p.club_pinned_until > now(), false) as is_club_pinned,
  -- Appended last: `create or replace view` matches columns by position,
  -- so a new column may only be added at the end.
  p.cover_aspect
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
left join public.clubs    cl on cl.id = p.club_id
where p.is_hidden = false
  and public.post_visible_now(p.publish_at, p.user_id, p.club_id);

grant select on public.posts_public to authenticated, anon;
