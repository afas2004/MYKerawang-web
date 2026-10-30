-- Verification for 20261028120000_club_review_fixes.sql
--
-- Paste the whole file into the dashboard SQL editor (it accepts many statements):
--   https://supabase.com/dashboard/project/zxjuqpqzyzmegdjttzyz/sql/new
--
-- Or run the statements one at a time on the CLI — `db query --file` only accepts
-- a single statement:
--   npx supabase db query --db-url "<pooler uri>" "select count(*) from ..."
--
-- Queries 1 and 3 must return **no rows**. Query 2 is informational.
--
-- Result on 2026-10-28, after applying the migration: 0, 0, 0.

-- ---------------------------------------------------------------- 1. registry
-- A rejected request must no longer hold its registry entry. Before the fix,
-- these rows kept `registry_id` and blocked the entry for every other club.
select r.code, r.name, c.handle, c.status
from clubs c
join club_registry r on r.id = c.registry_id
where c.status = 'rejected';

-- ---------------------------------------------------------------- 2. big clubs
-- Informational: clubs with more than 30 posts were the ones whose pinned post
-- could fall outside the club page's window. The page fetches pins separately
-- now, so this is a list to eyeball, not a problem to fix.
select club_id, count(*) as posts
from posts
where club_id is not null and not is_hidden
group by club_id
having count(*) > 30
order by posts desc;

-- ---------------------------------------------------------------- 3. club pins
-- A club pin that was not set through club_pin_post: no author, or an expiry
-- beyond the configured duration. Must be empty — the guard now resets these
-- columns on any raw insert or update.
select id, club_id, club_pinned_until, club_pinned_by
from posts
where club_pinned_until is not null
  and (club_pinned_by is null
       or club_pinned_until > now() + make_interval(days => (
            select pin_duration_days from moderation_settings where id)));
