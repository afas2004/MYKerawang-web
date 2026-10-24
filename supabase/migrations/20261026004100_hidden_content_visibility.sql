-- `is_hidden` becomes real for signed-in readers too.
--
-- Moderation hides content by setting is_hidden; the *_public views and the
-- anon policies already respected it, but a signed-in list query did not.
-- These restrictive policies AND with whatever permissive select policy
-- exists, so hidden rows vanish from every list.
--
-- The author still sees their own hidden row (so an edit or an appeal is
-- possible). Admins do NOT get a table-level pass: they would see the
-- hidden backlog mixed into the feed. The console reads hidden content
-- through the security-definer moderation RPCs anyway.

drop policy if exists "events_hide_select" on public.events;
create policy "events_hide_select" on public.events
as restrictive for select to authenticated
using (
  not coalesce(is_hidden, false)
  or organizer_id = auth.uid()
);

drop policy if exists "listings_hide_select" on public.listings;
create policy "listings_hide_select" on public.listings
as restrictive for select to authenticated
using (
  not coalesce(is_hidden, false)
  or seller_id = auth.uid()
);
