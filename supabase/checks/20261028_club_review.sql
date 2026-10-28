-- Verification for 20261028120000_club_review_fixes.sql
--
-- Run after the migration, either:
--   npx supabase db query --file supabase/checks/20261028_club_review.sql --db-url "<pooler uri>"
-- or paste into the dashboard SQL editor:
--   https://supabase.com/dashboard/project/zxjuqpqzyzmegdjttzyz/sql/new
--
-- Queries 1 and 3 must return **no rows**. Query 2 is informational.

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
