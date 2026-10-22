-- v1.4 create pages: who may create what, and the new post/listing fields.
--
--   Post          students (anonymous ok) · clubs as club (never anonymous)
--                 · admins
--   Announcement  club officers as their club (club / event / general)
--                 · admins (all, incl. kolej / jpk)
--   Listing       students · clubs (club contact) · admins
--                 + condition, meetup, quantity
--   Event         students · clubs (official) · admins   (club_id, 002100)
--
-- posts gain cover_url, action_links, linked_event_id, publish_at,
-- feature_until, comments_enabled, show_in_feed; posts_public exposes
-- them and hides scheduled posts (publish_at in the future) from everyone
-- but the author, the club's officers and admins.
--
-- Errors for the app: 'POST:category_admin_only', 'POST:comments_disabled',
-- 'POST:action_links' (+ CLUB:announcement / CLUB:not_officer from 002100).
-- Re-runnable.

-- ====================================================== posts columns
alter table public.posts
  add column if not exists cover_url        text,
  add column if not exists action_links     jsonb not null default '[]',
  add column if not exists linked_event_id  uuid,
  add column if not exists feature_until    timestamptz,
  add column if not exists comments_enabled boolean not null default true,
  add column if not exists show_in_feed     boolean not null default true;

-- publish_at: existing posts were published when they were created.
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'posts' and column_name = 'publish_at') then
    alter table public.posts add column publish_at timestamptz default now();
    update public.posts set publish_at = coalesce(created_at, now());
    alter table public.posts alter column publish_at set not null;
  end if;
end $$;
alter table public.posts alter column publish_at set default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'posts_linked_event_fk') then
    alter table public.posts add constraint posts_linked_event_fk
      foreign key (linked_event_id) references public.events(id) on delete set null;
  end if;
end $$;

create index if not exists posts_publish_at_idx on public.posts (publish_at);

-- At most 2 links, each {label ≤ 24 chars, url https://… or /internal}.
create or replace function public.post_action_links_valid(p jsonb)
returns boolean
language sql immutable
as $$
  select p is null or (
    jsonb_typeof(p) = 'array'
    and jsonb_array_length(p) <= 2
    and not exists (
      select 1 from jsonb_array_elements(p) e
      where jsonb_typeof(e) <> 'object'
         or jsonb_typeof(e -> 'label') is distinct from 'string'
         or jsonb_typeof(e -> 'url') is distinct from 'string'
         or length(btrim(e ->> 'label')) not between 1 and 24
         or not ((e ->> 'url') ~ '^https://[^\s]+$' or (e ->> 'url') ~ '^/[^\s]*$')));
$$;

alter table public.posts drop constraint if exists posts_action_links_valid;
alter table public.posts add constraint posts_action_links_valid
  check (public.post_action_links_valid(action_links));

-- ====================================================== post rules
-- 002100's club_guard_write already enforces: announcements need an
-- officer of the post's active club or an admin; club posts are never
-- anonymous. This adds the admin-only categories and a readable error for
-- bad links (the check constraint would otherwise say only "violates").
create or replace function public.post_create_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.announcement_category in ('kolej','jpk') and not public.is_admin() then
    raise exception 'POST:category_admin_only' using errcode = 'P0001';
  end if;
  if not public.post_action_links_valid(new.action_links) then
    raise exception 'POST:action_links' using errcode = 'P0001';
  end if;
  if new.club_id is not null then
    new.is_anonymous := false;
  end if;
  return new;
end;
$$;

revoke execute on function public.post_create_rules() from public, anon, authenticated;

drop trigger if exists trg_post_create_rules on public.posts;
create trigger trg_post_create_rules
before insert or update of announcement_category, action_links, club_id, is_anonymous on public.posts
for each row execute function public.post_create_rules();

-- ====================================================== comments on/off
create or replace function public.post_accepts_comments(p_post_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select p_post_id is null
      or coalesce((select comments_enabled from public.posts where id = p_post_id), true);
$$;

revoke execute on function public.post_accepts_comments(uuid) from public;
grant  execute on function public.post_accepts_comments(uuid) to anon, authenticated;

drop policy if exists "comments_require_enabled" on public.comments;
create policy "comments_require_enabled" on public.comments
as restrictive for insert to authenticated
with check (public.post_accepts_comments(post_id));

create or replace function public.comment_guard_enabled()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.post_accepts_comments(new.post_id) then
    raise exception 'POST:comments_disabled' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.comment_guard_enabled() from public, anon, authenticated;

drop trigger if exists trg_comment_guard_enabled on public.comments;
create trigger trg_comment_guard_enabled
before insert on public.comments
for each row execute function public.comment_guard_enabled();

-- ====================================================== scheduled posts
-- Called by posts_public as the viewer (anon included), hence definer +
-- granted to anon; is_admin() itself isn't granted to anon.
create or replace function public.post_visible_now(p_publish_at timestamptz, p_user_id uuid, p_club_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select p_publish_at is null or p_publish_at <= now()
      or (auth.uid() is not null and (
            p_user_id = auth.uid()
            or (p_club_id is not null and public.is_club_officer(p_club_id))
            or public.is_admin()));
$$;

revoke execute on function public.post_visible_now(timestamptz, uuid, uuid) from public;
grant  execute on function public.post_visible_now(timestamptz, uuid, uuid) to anon, authenticated;

-- Latest definition (20261022002100) with the new columns appended.
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
  p.show_in_feed
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
left join public.clubs    cl on cl.id = p.club_id
where p.is_hidden = false
  and public.post_visible_now(p.publish_at, p.user_id, p.club_id);

grant select on public.posts_public to authenticated, anon;

-- ====================================================== what can I announce
create or replace function public.can_post_announcement()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  with mine as (
    select c.id, c.name, c.handle::text as handle, c.logo_url
    from public.club_members m
    join public.clubs c on c.id = m.club_id
    where m.user_id = auth.uid() and m.role in ('president','officer') and c.status = 'active'
    order by c.name
  )
  select jsonb_build_object(
    'allowed', auth.uid() is not null and (public.is_admin() or exists (select 1 from mine)),
    'categories', to_jsonb(case
      when auth.uid() is not null and public.is_admin() then array['kolej','jpk','club','event','general']
      when exists (select 1 from mine) then array['club','event','general']
      else array[]::text[] end),
    'clubs', coalesce((select jsonb_agg(jsonb_build_object(
               'id', id, 'name', name, 'handle', handle, 'logo_url', logo_url)) from mine), '[]'::jsonb));
$$;

revoke execute on function public.can_post_announcement() from public, anon;
grant  execute on function public.can_post_announcement() to authenticated;

-- ====================================================== listings
alter table public.listings
  add column if not exists condition text,
  add column if not exists meetup    text,
  add column if not exists quantity  int;

-- The live table already had a free-text `condition` (and possibly
-- quantity/meetup) from earlier versions. Map legacy values onto the new
-- set before constraining; anything unrecognised becomes null (the
-- listing's description still carries the seller's own words).
update public.listings set condition = case
    when lower(btrim(condition)) in ('new','brand new','brand-new','baru','sealed','bnib','bnwt') then 'new'
    when lower(btrim(condition)) in ('like_new','like new','like-new','almost new','mint','excellent','very good','macam baru','seperti baru') then 'like_new'
    when lower(btrim(condition)) in ('used','good','fair','ok','okay','second hand','second-hand','secondhand','preloved','pre-loved','pre loved','terpakai','poor','worn') then 'used'
    else null
  end
where condition is not null
  and condition not in ('new','like_new','used');
update public.listings set quantity = null where quantity is not null and quantity <= 0;
update public.listings set meetup = left(meetup, 200) where meetup is not null and length(meetup) > 200;

alter table public.listings drop constraint if exists listings_condition_valid;
alter table public.listings add constraint listings_condition_valid
  check (condition is null or condition in ('new','like_new','used'));

alter table public.listings drop constraint if exists listings_quantity_positive;
alter table public.listings add constraint listings_quantity_positive
  check (quantity is null or quantity > 0);

alter table public.listings drop constraint if exists listings_meetup_length;
alter table public.listings add constraint listings_meetup_length
  check (meetup is null or length(meetup) <= 200);

-- ====================================================== club contact
-- A club's private phone / payment QR, used for club listings instead of
-- the officer's personal contact.
alter table public.club_private
  add column if not exists contact_phone  text,
  add column if not exists payment_qr_url text;

create or replace function public.set_club_contact(p_club_id uuid, p_phone text, p_payment_qr_url text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_club_officer(p_club_id) then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  insert into public.club_private (club_id, contact_phone, payment_qr_url)
  values (p_club_id, nullif(btrim(coalesce(p_phone, '')), ''), nullif(btrim(coalesce(p_payment_qr_url, '')), ''))
  on conflict (club_id) do update
  set contact_phone = excluded.contact_phone, payment_qr_url = excluded.payment_qr_url;
end;
$$;

revoke execute on function public.set_club_contact(uuid, text, text) from public, anon;
grant  execute on function public.set_club_contact(uuid, text, text) to authenticated;

-- get_listing_contact (20261019002600) with club listings answered by the
-- club: phone / QR from club_private, the club's handle and name, and its
-- public contact email. Same limits and logging. Columns appended, so the
-- old ones keep their names.
drop function if exists public.get_listing_contact(uuid);
create function public.get_listing_contact(p_listing_id uuid)
returns table (
  phone_number   text,
  payment_qr_url text,
  username       text,
  display_name   text,
  contact_email  text,
  is_club        boolean
)
language plpgsql security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_status text;
  v_club   uuid;
  v_recent int;
begin
  if auth.uid() is null then
    raise exception 'Login required' using errcode = '42501';
  end if;

  select l.seller_id, l.status, l.club_id into v_seller, v_status, v_club
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    return;
  end if;

  if v_seller <> auth.uid() then
    if v_status = 'sold' then
      raise exception 'listing_sold: this listing has been sold'
        using errcode = 'P0001';
    end if;

    perform pg_advisory_xact_lock(hashtext('contact_reveal:' || auth.uid()::text));

    select count(distinct r.seller_id) into v_recent
    from public.contact_reveals r
    where r.viewer_id = auth.uid()
      and r.revealed_at > now() - interval '1 hour'
      and r.seller_id <> v_seller;

    if v_recent >= 20 then
      raise exception 'rate_limited: too many contact requests, try again later'
        using errcode = 'P0001';
    end if;

    insert into public.contact_reveals (listing_id, seller_id, viewer_id)
    values (p_listing_id, v_seller, auth.uid());
  end if;

  if v_club is not null then
    return query
    select cp.contact_phone, cp.payment_qr_url, c.handle::text, c.name, c.contact_email, true
    from public.clubs c
    left join public.club_private cp on cp.club_id = c.id
    where c.id = v_club;
    return;
  end if;

  return query
  select c.phone_number, c.payment_qr_url, p.username::text, p.display_name::text, null::text, false
  from public.profiles p
  left join public.profile_contacts c on c.user_id = p.id
  where p.id = v_seller;
end;
$$;

revoke execute on function public.get_listing_contact(uuid) from public, anon;
grant  execute on function public.get_listing_contact(uuid) to authenticated;
