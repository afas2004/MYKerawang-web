-- Beta cleanup: retire the development content without losing it.
--
-- ONE-OFF — already applied on 2026-10-24, before the beta seed. Kept for
-- the record; it is not part of `migrations/`.
--
-- Nothing is deleted except the three obvious test accounts, their own
-- content, and rows that are pure by-products of the old content
-- (notifications, reports, contact reveals). Everything else is only
-- flagged is_hidden, so it can be restored from the JSON backup
-- (`.deepseek/backups/2026-10-24-beta-reset/`) or by flipping the flag.
--
-- The `created_at` guard means a later re-run cannot hide newly seeded
-- content, and the seed itself refuses to run twice.

begin;

-- 1. By-products first: these reference users without ON DELETE CASCADE.
delete from public.notifications;
delete from public.contact_reveals;
delete from public.reports;
delete from public.moderation_cases;

-- 2. Anything else that would block removing a test account.
with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.followers
where follower_id in (select id from doomed) or following_id in (select id from doomed);

with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.saved_items where user_id in (select id from doomed);

with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.event_participants where user_id in (select id from doomed);

with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.club_members where user_id in (select id from doomed);

-- 3. Content authored by those accounts (their FKs are RESTRICT, so it
--    has to go before the profile).
with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.events where organizer_id in (select id from doomed);

with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.listings where seller_id in (select id from doomed);

with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.comments where user_id in (select id from doomed);

with doomed as (
  select id from auth.users
  where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com')
)
delete from public.posts where user_id in (select id from doomed);

-- 4. The accounts themselves. Profiles cascade to what is left.
delete from public.profiles
where id in (select id from auth.users
             where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com'));

delete from auth.users
where email in ('test@test.com', 'admin@uitm.edu.my', 'user@gmail.com');

-- 5. Everything else that was created during development.
update public.posts    set is_hidden = true
  where is_hidden = false and created_at < timestamptz '2026-10-24 22:40+08';
update public.events   set is_hidden = true
  where is_hidden = false and created_at < timestamptz '2026-10-24 22:40+08';
update public.listings set is_hidden = true
  where is_hidden = false and created_at < timestamptz '2026-10-24 22:40+08';

-- 6. Your own and the admin account's hidden rows would still show up for
--    you two (hidden content stays visible to its author) — and those are
--    the accounts used for the demo. Deleted, and in the backup.
delete from public.events
where is_hidden and organizer_id in (select id from public.profiles where role in ('owner','admin'));
delete from public.listings
where is_hidden and seller_id in (select id from public.profiles where role in ('owner','admin'));
delete from public.posts
where is_hidden and user_id in (select id from public.profiles where role in ('owner','admin'));

commit;

select
  (select count(*) from public.posts    where not is_hidden)::int as visible_posts,
  (select count(*) from public.events   where not is_hidden)::int as visible_events,
  (select count(*) from public.listings where not is_hidden)::int as visible_listings,
  (select count(*) from auth.users)::int as accounts;
