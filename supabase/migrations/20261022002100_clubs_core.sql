-- Clubs, part 1: data model.
--
-- A club is a page run by student officers (no shared logins). Admins
-- approve new clubs. Posts, events and listings can be published "as" a
-- club by its officers (club_id), and admins/club officers can mark a post
-- as an announcement.
--
--   clubs            the page (handle is case-insensitive and unique)
--   club_private     registration proof + decision reason (admins/officers)
--   club_members     president / officer / member
--   club_followers   who follows a club
--   posts/events/listings.club_id, posts.is_announcement(+category)
--   posts_public     gains club, club_id, is_announcement, announcement_category
--
-- Then 002200 (RPCs) and 002300 (migrating role='club' accounts).
-- Every statement is re-runnable.

create schema if not exists extensions;
create extension if not exists citext with schema extensions;

-- ====================================================== clubs
create table if not exists public.clubs (
  id            uuid primary key default gen_random_uuid(),
  handle        extensions.citext not null,
  name          text not null,
  description   text,
  logo_url      text,
  cover_url     text,
  category      text,
  faculty       text,
  contact_email text,
  socials       jsonb not null default '{}',
  is_verified   boolean not null default false,
  status        text not null default 'pending',
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'clubs_handle_key') then
    alter table public.clubs add constraint clubs_handle_key unique (handle);
  end if;
end $$;

alter table public.clubs drop constraint if exists clubs_status_valid;
alter table public.clubs add constraint clubs_status_valid
  check (status in ('pending','active','rejected','suspended'));

-- Letters, digits, underscore; 3–30. Used in /c/:handle.
alter table public.clubs drop constraint if exists clubs_handle_format;
alter table public.clubs add constraint clubs_handle_format
  check (handle::text ~ '^[A-Za-z0-9_]{3,30}$');

alter table public.clubs drop constraint if exists clubs_name_length;
alter table public.clubs add constraint clubs_name_length
  check (length(btrim(name)) between 2 and 80);

alter table public.clubs drop constraint if exists clubs_description_length;
alter table public.clubs add constraint clubs_description_length
  check (description is null or length(description) <= 2000);

create index if not exists clubs_status_idx on public.clubs (status, name);

-- Not on clubs: anyone can read clubs rows, and RLS can't hide columns.
create table if not exists public.club_private (
  club_id         uuid primary key references public.clubs(id) on delete cascade,
  proof_note      text,
  decision_reason text,
  decided_by      uuid references public.profiles(id) on delete set null,
  decided_at      timestamptz
);

-- ====================================================== members
create table if not exists public.club_members (
  club_id   uuid not null references public.clubs(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

alter table public.club_members drop constraint if exists club_members_role_valid;
alter table public.club_members add constraint club_members_role_valid
  check (role in ('president','officer','member'));

-- Exactly one president per club.
create unique index if not exists club_members_one_president
  on public.club_members (club_id) where role = 'president';
create index if not exists club_members_user_idx on public.club_members (user_id);

create table if not exists public.club_followers (
  club_id    uuid not null references public.clubs(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (club_id, user_id)
);
create index if not exists club_followers_user_idx on public.club_followers (user_id);

-- ====================================================== helpers
-- The caller's role in a club (null when none).
create or replace function public.club_role(p_club_id uuid)
returns text
language sql security definer stable
set search_path = public
as $$
  select role from public.club_members
  where club_id = p_club_id and user_id = auth.uid();
$$;

-- Officers (incl. the president) of an ACTIVE club may publish as it.
-- Used by RLS on posts/events/listings inserts with club_id.
create or replace function public.can_act_as_club(p_club_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.club_members m
    join public.clubs c on c.id = m.club_id
    where m.club_id = p_club_id
      and m.user_id = auth.uid()
      and m.role in ('president','officer')
      and c.status = 'active');
$$;

-- Officers may see/manage their club in any status (e.g. while pending).
create or replace function public.is_club_officer(p_club_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce(public.club_role(p_club_id) in ('president','officer'), false);
$$;

revoke execute on function public.club_role(uuid)       from public;
revoke execute on function public.can_act_as_club(uuid) from public;
revoke execute on function public.is_club_officer(uuid) from public;
grant  execute on function public.club_role(uuid)       to anon, authenticated;
grant  execute on function public.can_act_as_club(uuid) to anon, authenticated;
grant  execute on function public.is_club_officer(uuid) to anon, authenticated;

-- ====================================================== RLS
alter table public.clubs          enable row level security;
alter table public.club_private   enable row level security;
alter table public.club_members   enable row level security;
alter table public.club_followers enable row level security;

-- Active clubs are public (incl. guests). Officers see their own club in
-- any state; admins see everything. Writes go through RPCs.
drop policy if exists "clubs_select_active" on public.clubs;
create policy "clubs_select_active" on public.clubs
for select to anon using (status = 'active');

drop policy if exists "clubs_select" on public.clubs;
create policy "clubs_select" on public.clubs
for select to authenticated
using (status = 'active' or public.is_club_officer(id) or public.is_admin());

drop policy if exists "club_private_select" on public.club_private;
create policy "club_private_select" on public.club_private
for select to authenticated
using (public.is_club_officer(club_id) or public.is_admin());

drop policy if exists "club_members_select_anon" on public.club_members;
create policy "club_members_select_anon" on public.club_members
for select to anon
using (exists (select 1 from public.clubs c where c.id = club_id and c.status = 'active'));

drop policy if exists "club_members_select" on public.club_members;
create policy "club_members_select" on public.club_members
for select to authenticated
using (
  exists (select 1 from public.clubs c where c.id = club_id and c.status = 'active')
  or user_id = auth.uid()
  or public.is_club_officer(club_id)
  or public.is_admin());

-- Following: anyone signed in follows/unfollows themselves.
drop policy if exists "club_followers_select" on public.club_followers;
create policy "club_followers_select" on public.club_followers
for select to authenticated using (user_id = auth.uid() or public.is_club_officer(club_id));

drop policy if exists "club_followers_insert" on public.club_followers;
create policy "club_followers_insert" on public.club_followers
for insert to authenticated
with check (user_id = auth.uid()
  and exists (select 1 from public.clubs c where c.id = club_id and c.status = 'active'));

drop policy if exists "club_followers_delete" on public.club_followers;
create policy "club_followers_delete" on public.club_followers
for delete to authenticated using (user_id = auth.uid());

revoke all on public.clubs, public.club_private, public.club_members, public.club_followers from anon;
revoke insert, update, delete on public.clubs, public.club_private, public.club_members from authenticated;
grant select on public.clubs, public.club_members to anon, authenticated;
grant select on public.club_private to authenticated;
grant select, insert, delete on public.club_followers to authenticated;

-- Follower counts without exposing who follows.
create or replace view public.club_follower_counts as
select c.id as club_id, count(f.user_id)::int as followers
from public.clubs c
left join public.club_followers f on f.club_id = c.id
where c.status = 'active'
group by c.id;

grant select on public.club_follower_counts to anon, authenticated;

-- ====================================================== content columns
alter table public.posts    add column if not exists club_id uuid;
alter table public.events   add column if not exists club_id uuid;
alter table public.listings add column if not exists club_id uuid;

alter table public.posts add column if not exists is_announcement boolean not null default false;
alter table public.posts add column if not exists announcement_category text;

alter table public.posts drop constraint if exists posts_announcement_category_valid;
alter table public.posts add constraint posts_announcement_category_valid
  check (announcement_category is null
         or announcement_category in ('kolej','jpk','club','event','general'));

do $$
declare
  t text;
begin
  foreach t in array array['posts','events','listings'] loop
    if not exists (select 1 from pg_constraint where conname = t || '_club_fk') then
      execute format(
        'alter table public.%I add constraint %I foreign key (club_id) '
        'references public.clubs(id) on delete set null', t, t || '_club_fk');
    end if;
    execute format('create index if not exists %I on public.%I (club_id) where club_id is not null',
                   t || '_club_idx', t);
  end loop;
end $$;

-- Publishing as a club needs an officer of an active club. Restrictive,
-- so it ANDs with every existing insert policy. Admins may also post
-- announcements without a club (kolej / JPK notices).
drop policy if exists "posts_club_insert" on public.posts;
create policy "posts_club_insert" on public.posts
as restrictive for insert to authenticated
with check (
  (club_id is null or public.can_act_as_club(club_id))
  and (not is_announcement or public.is_admin()
       or (club_id is not null and public.can_act_as_club(club_id))));

drop policy if exists "events_club_insert" on public.events;
create policy "events_club_insert" on public.events
as restrictive for insert to authenticated
with check (club_id is null or public.can_act_as_club(club_id));

drop policy if exists "listings_club_insert" on public.listings;
create policy "listings_club_insert" on public.listings
as restrictive for insert to authenticated
with check (club_id is null or public.can_act_as_club(club_id));

-- Same rule as a trigger: covers security-definer paths and gives the
-- app a readable error ('CLUB:not_officer' / 'CLUB:announcement').
-- Club posts are never anonymous (the club is the speaker).
create or replace function public.club_guard_write()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_is_post boolean := tg_table_name = 'posts';
  v_ann     boolean := false;
begin
  if auth.uid() is null then
    return new;  -- SQL editor, service role, migrations
  end if;

  if tg_op = 'UPDATE' and new.club_id is not distinct from old.club_id
     and (not v_is_post or (to_jsonb(new) ->> 'is_announcement') is not distinct from (to_jsonb(old) ->> 'is_announcement')) then
    return new;
  end if;

  if new.club_id is not null and not public.can_act_as_club(new.club_id) and not public.is_admin() then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;

  if v_is_post then
    v_ann := coalesce((to_jsonb(new) ->> 'is_announcement')::boolean, false);
    if v_ann and not public.is_admin()
       and (new.club_id is null or not public.can_act_as_club(new.club_id)) then
      raise exception 'CLUB:announcement' using errcode = 'P0001';
    end if;
    if new.club_id is not null then
      new := jsonb_populate_record(new, jsonb_build_object('is_anonymous', false));
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.club_guard_write() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['posts','events','listings'] loop
    execute format('drop trigger if exists trg_club_guard on public.%I', t);
    execute format(
      'create trigger trg_club_guard before insert or update of club_id%s on public.%I '
      'for each row execute function public.club_guard_write()',
      case when t = 'posts' then ', is_announcement' else '' end, t);
  end loop;
end $$;

-- ====================================================== posts_public
-- Latest definition (20261019004500) with club columns appended.
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
  p.announcement_category
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
left join public.clubs    cl on cl.id = p.club_id
where p.is_hidden = false;

grant select on public.posts_public to authenticated, anon;
