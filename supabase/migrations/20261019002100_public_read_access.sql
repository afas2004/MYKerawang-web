-- Shared links (/event/:id, /item/:id, /post/:id, /u/:id) open read-only
-- for visitors who aren't logged in, so the `anon` role needs to read
-- exactly what those pages show — and nothing private.
--
-- Not granted to anon:
--   * profiles (base table): it holds phone_number and payment_qr_url.
--     Anonymous readers get profiles_public instead.
--   * event_participants: who joined is not public; anon gets a count.
--   * comments / posts base tables: anonymity is enforced by the
--     *_public views (see 20260801000100_post_anonymity.sql).

-- ---------------------------------------------------------- events
-- Only public events. Logged-in reads keep whatever policy exists today.
grant select on public.events to anon;

drop policy if exists "events_select_anon" on public.events;
create policy "events_select_anon" on public.events
for select to anon
using (coalesce(is_public, true));

-- ---------------------------------------------------------- listings
grant select on public.listings to anon;

drop policy if exists "listings_select_anon" on public.listings;
create policy "listings_select_anon" on public.listings
for select to anon
using (true);

-- ---------------------------------------------------------- profiles
-- Column-safe projection. Runs as the view owner (bypasses RLS), so it
-- must only ever list columns that are fine for anyone to see. Never add
-- phone_number, payment_qr_url, full_name, email or moderation fields.
drop view if exists public.profiles_public;
create view public.profiles_public as
select
  p.id, p.username, p.display_name, p.avatar_url, p.bio,
  p.role, p.is_verified
from public.profiles p;

grant select on public.profiles_public to anon, authenticated;

-- ---------------------------------------------------------- counts
-- Attendance and follower numbers without exposing who.
drop view if exists public.event_participant_counts;
create view public.event_participant_counts as
select e.id as event_id, count(ep.user_id)::int as participant_count
from public.events e
left join public.event_participants ep on ep.event_id = e.id
where coalesce(e.is_public, true)
group by e.id;

grant select on public.event_participant_counts to anon, authenticated;

drop view if exists public.follow_counts;
create view public.follow_counts as
select
  p.id as user_id,
  (select count(*) from public.followers f where f.following_id = p.id)::int as followers,
  (select count(*) from public.followers f where f.follower_id  = p.id)::int as following
from public.profiles p;

grant select on public.follow_counts to anon, authenticated;

-- ---------------------------------------------------------- posts/comments
-- Already granted in 20260801000100; repeated so this file alone is
-- enough to make guest pages work on a fresh project.
grant select on public.posts_public    to anon;
grant select on public.comments_public to anon;
