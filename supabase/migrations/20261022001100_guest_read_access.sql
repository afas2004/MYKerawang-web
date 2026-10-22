-- v1.3 guest mode: logged-out visitors browse Home, Announcements, Market,
-- Events, Search, detail pages and public profiles read-only.
-- Idempotent: re-asserts the grants from 20261019002100 (prod may lack
-- it) and tightens anon to non-hidden rows now that moderation exists.
--
-- Never granted to anon: profiles (contacts), event_participants,
-- followers, notifications, saved_items, reports or any moderation table.

grant select on public.events   to anon;
drop policy if exists "events_select_anon" on public.events;
create policy "events_select_anon" on public.events
for select to anon
using (coalesce(is_public, true) and not coalesce(is_hidden, false));

grant select on public.listings to anon;
drop policy if exists "listings_select_anon" on public.listings;
create policy "listings_select_anon" on public.listings
for select to anon
using (not coalesce(is_hidden, false));

-- Views (already anonymity / moderation safe).
grant select on public.posts_public             to anon;
grant select on public.comments_public          to anon;
grant select on public.profiles_public          to anon;
grant select on public.event_participant_counts to anon;
grant select on public.follow_counts            to anon;
