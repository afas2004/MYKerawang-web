# Plan: cancelled events and reserved listings shown as live

Status: **draft, not approved.** Written 2026-10-30 against commit `88c8578`.

Findings, root cause and all citations: [feed-and-announcements-audit.md](feed-and-announcements-audit.md) §3.
Read that first — this document is only the proposed fix.

## What this fixes

After an organiser cancels an event it still appears in Home's "Happening soon" carousel
looking live. The cause is that cancelling writes only `events.cancelled_at` and nothing in
the database hides it, so each of 12 event list queries has to remember — and only one does.
Separately, most compact cards cannot render a "closed" state at all, so even where an item
legitimately stays visible it looks live.

## Decisions this plan is built on

- The rule lives in **app code**, not a new `events_public` view (reversible; production has
  partial old migrations).
- **Promotional surfaces** drop cancelled/hidden entirely: Home "Happening soon", the right
  rail (upcoming *and* past fallback), the announcement event-picker.
- **Browse surfaces** keep showing them, marked and sorted last. Existing deliberate design.
- **The Events screen does not change.** It is already correct.

## Group 1 — extract the shared rule (no behaviour change)

Create `lib/utils/event_status.dart`, mirroring
[lib/utils/listing_status.dart](../lib/utils/listing_status.dart) — same directory, same
`badge(AppStrings)` contract, importing nothing but l10n:

- `enum EventStatus { upcoming, ended, cancelled }`
- `EventStatus.of(Map, {DateTime? now})` — precedence **cancelled > ended > upcoming**. The
  injectable clock is the one divergence from `ListingStatus.of` (which reads a stored
  column); without it the tests are flaky.
- `badge(AppStrings s)` → `null` / `s.ended` / `s.cancelled`. **No new strings needed** —
  both already exist in all three languages.
- `isEventPromotable(Map)` → `!isEventCancelled(e) && e['is_hidden'] != true`. Deliberately
  ignores "but I am the organiser", which is what stops a moderator-hidden event appearing in
  its own organiser's Happening soon.
- `compareForBrowse(a, b)` — lifted verbatim from the comparator at
  [events_cubit.dart:248-255](../lib/screens/events_cubit.dart:248), so "upcoming soonest
  first, then closed most-recent first" has exactly one definition.
- Move `isEventEnded`, `isEventCancelled`, `isEventClosed` here from
  [events_cubit.dart:57-72](../lib/screens/events_cubit.dart:57).

**Import churn is two lines.** `events_cubit.dart` is imported by exactly two files:
[events_screen.dart](../lib/screens/events_screen.dart) (one new import; its five call sites
compile unchanged) and [test/guest_events_test.dart](../test/guest_events_test.dart) (uses
only `EventsCubit` — zero change). Do **not** re-export from the cubit: `lib/widgets/*` must
not depend on a screen file, or they pick up `flutter_bloc`, `database_helper.dart` and a
`widgets/ → screens/ → widgets/` cycle.

Create `lib/utils/event_queries.dart` — the only new file importing `supabase_flutter`:

```dart
extension EventQueryFilters<T> on PostgrestFilterBuilder<T> {
  PostgrestFilterBuilder<T> notCancelled() => isFilter('cancelled_at', null);
  PostgrestFilterBuilder<T> notHidden()    => eq('is_hidden', false);
  PostgrestFilterBuilder<T> endsAfter(DateTime now) =>
      gt('end_datetime', now.toUtc().toIso8601String());
  PostgrestFilterBuilder<T> promotableOnly() => notCancelled().notHidden();
}
```

- Must be **generic in `T`** — the narrowed-`select()` call sites yield different type
  arguments, and a non-generic extension would not apply to them.
- Apply **before** `.order()`/`.limit()`; those return a `PostgrestTransformBuilder`, which
  has no filter methods.
- `promotableOnly()` deliberately excludes `endsAfter`, because the rail's past-events
  fallback needs the former without the latter.
- Never write `.eq('cancelled_at', null)` — PostgREST renders that as `cancelled_at=eq.null`,
  which matches nothing.
- Known fragility: an extension on a third-party generic type. A `supabase_flutter` major
  bump can break this one 15-line file. Accepted.

Also add two comments so nobody "fixes" correct code later: at
[events_cubit.dart:146](../lib/screens/events_cubit.dart:146) (why the stream is
deliberately unfiltered) and at
[account_data.dart:69](../lib/services/account_data.dart:69) (the data export must include
cancelled and hidden rows).

## Group 2 — the reported bug: promo filters

- [home_screen.dart:121](../lib/screens/home_screen.dart:121) →
  `.promotableOnly().endsAfter(DateTime.now())`. **This alone fixes the reported symptom.**
- [right_rail.dart:49](../lib/widgets/right_rail.dart:49) → same
- [right_rail.dart:66](../lib/widgets/right_rail.dart:66) (past fallback) →
  `.promotableOnly()` **only**, no `endsAfter`
- [announcement_service.dart:196](../lib/services/announcement_service.dart:196)
  `linkableEvents` → `.promotableOnly()`; you cannot promote a cancelled or hidden event
- [announcements_repository.dart:315](../lib/screens/announcements/announcements_repository.dart:315)
  → rewrite to use the extension, preserving behaviour. Otherwise the one correct query is
  the one place the rule is duplicated, and it will drift.

## Group 3 — reserved listings

Switch from the legacy `is_sold` to `status` at
[home_screen.dart:126](../lib/screens/home_screen.dart:126),
[right_rail.dart:55](../lib/widgets/right_rail.dart:55) and
[search_screen.dart:195](../lib/screens/search_screen.dart:195), mirroring
[marketplace_cubit.dart:181](../lib/screens/marketplace_cubit.dart:181).

**Run this against production first:**

```sql
select count(*) from public.listings where status is null;
```

If it is not 0, `.eq('status','available')` would **hide legitimate listings** (rows
untouched since the
[20261019002500](../supabase/migrations/20261019002500_listing_status.sql) backfill, which
deliberately skipped `reserved`). Use
`.or('status.eq.available,and(status.is.null,is_sold.eq.false)')` in that case.

Search also needs its `select()` widened at
[search_screen.dart:196](../lib/screens/search_screen.dart:196) — it currently fetches no
`status` column.

## Group 4 — the render layer

Reuse [StatusBadge](../lib/widgets/status_badge.dart) (the compact constructor; its doc
comment already lists "Cancelled"), copying placement and the desaturation treatment from
[marketplace_screen.dart:340-351](../lib/screens/marketplace_screen.dart:340) rather than
inventing a new one.

- [universal_card.dart](../lib/widgets/universal_card.dart) — Home's carousels **and** the
  club page's events tab
  ([club_page_screen.dart:526](../lib/screens/clubs/club_page_screen.dart:526)), so that
  surface is fixed for free. Branch on the existing `containsKey('start_datetime')`
  inference at [:26](../lib/widgets/universal_card.dart:26); its photo is **not** in a
  `Stack` ([:91](../lib/widgets/universal_card.dart:91)), so add a wrapper.
- [embed_card.dart](../lib/widgets/embed_card.dart) — **two** classes: `EmbedCard` (~:127)
  and `SharedItemHero` ([:168](../lib/widgets/embed_card.dart:168)), which is what
  [post_card.dart:289](../lib/widgets/post_card.dart:289) renders for a shared event.
  `SharedItemHero` already has `isEvent` as a field. Also covers
  [announcement_view.dart:327](../lib/widgets/announcement_view.dart:327) and
  `guest_views.dart`. Beware [embed_card.dart:187](../lib/widgets/embed_card.dart:187)
  reaching into `EmbedCard(...)._meta()`.
- [right_rail.dart](../lib/widgets/right_rail.dart) `_EventRow` (~:188) and `_ItemGrid`
  (~:235). The rail is filtered by Group 2, but its past-events fallback still shows ended
  events with a `primary`-coloured left border that reads as live — mute it.
- [search_screen.dart:610,676](../lib/screens/search_screen.dart:610) — hardcodes `s.ended`,
  so a cancelled event says "Ended". Use `badge()`, and widen the event `select()` at
  [:180](../lib/screens/search_screen.dart:180) to include `cancelled_at`. Prefer replacing
  `_hasEnded` ([:102](../lib/screens/search_screen.dart:102)) with `compareForBrowse` at
  `:184` and deleting it.
- [profile_screen.dart:764-766](../lib/screens/profile_screen.dart:764) — already has the
  badge plumbing but computes the label by hand and gets **both** branches wrong. Replace
  with `EventStatus.of(item).badge(s)` / `ListingStatus.of(item).badge(s)` and drop the
  hand-rolled `ended` at [:758](../lib/screens/profile_screen.dart:758).

While here, consider adding "Happening now" to `UniversalCard` and `EmbedCard` — it needs the
same status lookup in the same place, and today a running event looks identical to one next
week on Home. See audit §7.

Finally apply `compareForBrowse` to the four browse lists
([profile_screen.dart:95](../lib/screens/profile_screen.dart:95),
[profile_cubit.dart:100](../lib/screens/profile_cubit.dart:100),
[guest_views.dart:114](../lib/screens/guest_views.dart:114),
[club_service.dart:459](../lib/services/club_service.dart:459)). Pre-existing limitation to
note, not fix: they order server-side by `start_datetime desc` with a page limit, so a
client-side re-sort only reorders the fetched page.

## Group 5 — the mobile offline cache

Without this, badges are blank offline on phones regardless of Groups 1–4 (audit §3d).

- Add `cancelled_at` + `end_datetime` to the cached `events` table and `status` to
  `listings`, and persist them in `cacheEvents` / `cacheListings`
  ([database_helper.dart:60-96](../lib/database_helper.dart:60))
- **Bump `version: 1` → `2` at
  [database_helper.dart:28](../lib/database_helper.dart:28) and add an `onUpgrade`.** There
  is none today, so without it existing installs keep the old schema and inserts fail.
- Web is unaffected — `_webWrite` stores whole rows as JSON
- Any future client-side filtering in `_onRows` must run **after** the `cacheEvents` write at
  [events_cubit.dart:164](../lib/screens/events_cubit.dart:164), or the offline cache slowly
  loses legitimately-visible history

## Group 6 — one migration: attendee counts leak

New file `supabase/migrations/20261030001100_count_view_respects_hidden.sql`:
`drop view if exists` + `create view` with `and not coalesce(e.is_hidden, false)` added, then
re-`grant select to anon, authenticated`. The original
([20261019002100:44](../supabase/migrations/20261019002100_public_read_access.sql:44))
already drops before creating, so the "append new columns last" rule does not bind, and the
view has only two columns.

**Do not use `security_invoker = true`** — it breaks guests. Audit §3e explains why.

Use `coalesce(e.is_hidden, false)`, not `not e.is_hidden`, because
`add column if not exists ... not null` silently skips on a database where the column
pre-existed nullable.

Cancelled events should still be counted — cancellation is public, and the organiser and the
people who joined both want to know how many were affected. Only `hidden` is a moderation
secret.

Before shipping, confirm
[event_detail_screen.dart:100-110](../lib/screens/event_detail_screen.dart:100) guards a
missing count the way [events_screen.dart:362](../lib/screens/events_screen.dart:362)
already does — a hidden event now returns no row at all.

## Verification

### New tests

**`test/event_status_test.dart`** (pure unit). The case most likely to regress: a row with
**both** `cancelled_at` set and a past `end_datetime` must return `cancelled`, not `ended`.
Plus an injected clock either side of `end_datetime`; `end_datetime: null` falling back to
`start_datetime`; neither present → `upcoming`; `badge()` in all three languages;
`isEventPromotable` true for an `is_hidden: null` row. Lock `compareForBrowse` against a
fixed 5-row fixture **during Group 1, before the extraction**, to prove the move was
behaviour-preserving.

**`test/event_query_filters_test.dart`** — closes the "zero `.from('events')` tests" gap.
Assert on the generated request URI (build the chain against a client with a dummy url/key;
nothing hits the network until `await`) and check it contains `cancelled_at=is.null` and
`is_hidden=eq.false`. This catches the `.eq('cancelled_at', null)` mistake that grepping
never would. If brittle across SDK versions, fall back to a guard-rail test asserting the
four promo files mention `promotableOnly()`.

**`test/cancelled_event_render_test.dart`** — following
[test/v14_home_feed_test.dart](../test/v14_home_feed_test.dart). `FeedView` takes `events`
/ `listings` as plain parameters, so no Supabase is needed. A cancelled event in the strip
shows "Cancelled" at `kCompact` and `kExpanded` with `takeException()` null (the new `Stack`
must not overflow the fixed 196px `HoverCarousel`); a reserved listing shows "Reserved"; a
plain upcoming event shows **neither** badge; `SharedItemHero` with a cancelled event shows
"Cancelled" (extend [test/v13_repost_hero_test.dart](../test/v13_repost_hero_test.dart)
rather than duplicating its scaffolding).

**Extend [test/helpers/feed_fixtures.dart](../test/helpers/feed_fixtures.dart)** —
`sampleEvent(id, {cancelledAt, isHidden, startsIn})` and `sampleListing(id, {status})`,
keeping the positional `id` so existing callers compile. `sampleListing` must emit **both**
`status` and `is_sold: status == 'sold'`, matching the trigger, or the `ListingStatus.of`
fallback path is never honestly exercised. `sampleEvent` should always emit the
`cancelled_at` and `is_hidden` keys (null / false by default) — "key absent" vs "key null" is
a real distinction given the key-sniffing in `universal_card.dart`.

### Regression suite to watch

The new `Stack` wrappers move pixels: `feed_layout_test.dart`, `ui_layout_test.dart:96`
(already pumps an event card with `cancelled_at` set), `screens_responsive_test.dart`,
`profile_page_test.dart`, `clubs_test.dart`, `v13_repost_hero_test.dart:34` (asserts
`SharedItemHero`'s `getTopLeft().dy`). Run the full suite after Group 4 specifically.

```bash
flutter analyze
```

```bash
flutter test
```

### By hand, as an organiser, on one event

1. **The reported bug.** Create an event starting tomorrow → confirm it is in Home
   "Happening soon" and the desktop right rail → cancel it → refresh Home. Gone from both,
   **still** on the Events tab in the collapsed "Ended & cancelled" section with a Cancelled
   pill. Then hit **Restore** and confirm it returns to the carousel.
2. **Hidden events.** Have a moderator hide one of your own events. On *your* account it must
   vanish from Home and the rail, but stay on the Events tab (you need to find it to appeal)
   and on your own profile. On another account, invisible everywhere.
3. **Reserved.** Mark a listing reserved → "Reserved" badge on its market tile, and absent
   from Home "Fresh finds" and the rail grid.
4. **Shared event.** Share a cancelled event in a post → the hero shows a Cancelled stamp and
   still links through to the event, which shows its cancelled banner.
5. **Counts leak.** Signed out, open the public link for a hidden event's id. In the browser
   network tab the `event_participant_counts` request must return `[]`, not a row with `0`.
   Counts must still be correct on a *cancelled* event.
6. **Rail fallback.** With no upcoming events at all, the rail falls back to recent ones — no
   cancelled event there, and the ended ones no longer carry a live-looking border.
7. **Picker.** Compose an announcement → "link an event": cancelled and hidden must not be
   offered.
8. **Search.** Search the cancelled event's title: present, greyed, badged **Cancelled** (not
   Ended), sorted after upcoming matches.

### Deploy

Never a plain `flutter build web` — the script sets `BUILD_ID`, `--wasm`,
`--pwa-strategy=none` and the `sw_reset` worker:

```bash
./deploy_web.bat
```

Push Group 6's migration before deploying the web build:

```bash
npx supabase db push --linked
```

## Sequencing

Group 1 must land before 2/3/4 (they import it). Groups 2–4 are the fix for what was reported
and need no database change. Group 5 affects mobile builds only. Group 6 is independent of
the visible symptom — a data-leak tidy-up — and can go first or last.

## Not in this plan

Separate work, documented in the audit:

- The refresh bugs (audit §6) — pinning fires no refresh at all, Undo updates no state,
  offset paging silently skips posts, pull-to-refresh races with auto-paging, one content
  change refetches every tab, and `publish_at` going live triggers nothing.
- The scheduled-announcement ordering bug and `cover_aspect` being unsaveable on edit
  (audit §1a, §1b).
- The hub hero treating featured and pinned as mutually exclusive (audit §4a).
- The dead `role = 'club'` branch in `pin_post` (audit §5).
- The "bump" feature (audit §8).
