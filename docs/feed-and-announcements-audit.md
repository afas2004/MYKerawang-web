# Audit: home feed, announcements, pins and refresh

Status: **findings only — nothing in here has been fixed.** Written 2026-10-30 against
commit `88c8578` on `main` (clean tree).

## How to use this document

This is a handoff. Every claim below was read out of the files cited, and every citation is
`path:line` so you can verify it rather than trust it. Where something is inferred rather
than read, it says so.

Companion document: [cancelled-content-fix-plan.md](cancelled-content-fix-plan.md) — the
proposed fix for §3, which the user has **not** approved.

### Decisions the user already made — do not re-open these

1. **Fix visibility rules in app code, not by adding an `events_public` Postgres view.**
   Reason: reversible, and production has partially-applied old migrations, so schema
   changes carry real risk.
2. **On promotional surfaces a cancelled event disappears entirely.** Not "shown greyed".
3. **On browse surfaces it stays visible, marked and sorted last.** This is existing
   deliberate design, promised in the cancel dialog's own copy
   ([access_strings.dart:262](../lib/l10n/access_strings.dart:262)).
4. **The Events screen must not change.** It is already correct.

### Open questions

- Whether the "bump" feature (§7) belongs in the fix plan or its own. Recommendation given:
  its own, so the bug fix does not wait on feature decisions. Unanswered.
- Whether to fix §6A/§6C now. Unanswered.

### Project conventions worth knowing before you touch anything

- **Never run plain `flutter build web`.** Use `./deploy_web.bat`: it stamps `BUILD_ID`,
  passes `--wasm` (plain web builds leave iOS WebKit on a white screen),
  `--pwa-strategy=none`, and swaps in `sw_reset.js`. See the comments in that file.
- Migrations are named `YYYYMMDD00NN00_snake_case.sql`, must be **re-runnable**, and
  same-day sequences start at `001100`.
- `create or replace view` in Postgres matches columns **by position** and only allows
  appending at the end. `posts_public` has been redefined six times for this reason — see
  the comment at
  [20261026003100:369](../supabase/migrations/20261026003100_event_contacts_attendance.sql:369).
- `add column if not exists ... not null` **silently skips** if the column already exists
  nullable. Given the partial-migration state of production, prefer `coalesce(col, false)`
  over `not col` in any new SQL.
- The user applies migrations themselves. `apply_migrations.sh` exists but is **stale** (it
  lists only the first 17 migrations) and uses the Management API rather than a password.

---

## 1. How announcements actually work

An announcement is **not a separate table.** It is a row in `posts` with
`is_announcement = true` plus the columns added by
[20261023001100_create_matrix.sql](../supabase/migrations/20261023001100_create_matrix.sql).

| Column | Purpose |
|---|---|
| `announcement_category` | `kolej` · `jpk` · `club` · `event` · `general`. Also decides **who may post it** |
| `cover_url`, `cover_aspect` | Banner image; `16:9` (default) or `1:1` |
| `action_links` (jsonb) | Up to 2 CTA buttons, each `https://…` or an in-app `/path` |
| `linked_event_id` | Optional event attached to the notice |
| `publish_at` | Scheduling. A future value hides the row from everyone but the author |
| `feature_until` | Puts it in the hub's hero carousel while in the future. **Not a pin** |
| `comments_enabled`, `show_in_feed` | Author switches |
| `pinned_until`, `club_pinned_until` | Pins — see §5. Writable only via RPC |

**Permission** comes from one RPC, `can_post_announcement()`
([create_matrix.sql:204](../supabase/migrations/20261023001100_create_matrix.sql:204)):
admins get all five categories; a president or officer of an *active* club gets
`club`/`event`/`general`. `kolej` and `jpk` are additionally enforced server-side by the
`post_create_rules` trigger
([:86](../supabase/migrations/20261023001100_create_matrix.sql:86)), so a crafted insert
cannot fake a college notice.

Validation is mirrored in three places that agree, which is good layering: Dart rules in
[announcement_rules.dart](../lib/utils/announcement_rules.dart), a Postgres check
constraint, and the trigger.

**Reads** all go through the `posts_public` view (latest definition:
[20261026003100:339](../supabase/migrations/20261026003100_event_contacts_attendance.sql:339)),
which blanks anonymous authors, joins club/profile/event/listing, computes `is_pinned`, and
applies `post_visible_now()` for scheduling. Guests can read it.

**Writes split oddly.** Creating is a plain `insert` into `posts`
([announcement_service.dart:183](../lib/services/announcement_service.dart:183)); editing
goes through the `update_my_announcement` RPC, because `posts` deliberately has no author
UPDATE policy.

### Bugs found in this area

**1a. A scheduled announcement arrives buried.** The serious one.
[home_screen.dart:175](../lib/screens/home_screen.dart:175) orders by `is_pinned`, then
**`created_at`** — but the entire point of `publish_at` is to decouple those. Write a notice
Monday, schedule it for Friday 9am: on Friday the row becomes visible and sorts to its
*Monday* position, below everything posted Tue–Thu. The feature works in the sense that
nothing leaks early, and fails in the sense that nobody sees it. One-line fix: order by
`publish_at`.

**1b. `cover_aspect` cannot be edited.** The column was added in phase 5
([20261026003100:332](../supabase/migrations/20261026003100_event_contacts_attendance.sql:332))
and wired into the composer and the view, but
[update_my_announcement](../supabase/migrations/20261023003100_update_my_announcement.sql:29)
predates it and its field whitelist was never extended. `toRow()`
([announcement_service.dart:122](../lib/services/announcement_service.dart:122)) sends
`cover_aspect` on every edit; the RPC silently drops it. Switching 16:9 → 1:1 on an existing
announcement appears to save and does nothing.

**1c. `feature_until` does nothing on Home.** It only drives the hub hero. Home has no
concept of an important notice; the only lever there is a pin, which costs an admin action.
The priority signal is already stored and ignored.

---

## 2. Home feed layout and ordering

Order as rendered ([home_screen.dart:303](../lib/screens/home_screen.dart:303)): app bar →
composer prompt → *(narrow widths only)* "Happening soon" events strip → "Fresh finds"
listings strip → the post list, with an event/listing embed after every 6th post → paging
footer.

The ≤680px column and the `railBreakpoint` switch are clean, and `buildFeedItems`
([:29](../lib/screens/home_screen.dart:29)) being pure and deterministic is the right call —
it is unit-testable without Supabase.

Three layout problems:

- **Mobile buries the feed.** Two 196px carousels sit between the composer and the first
  post. A returning user scrolls ~400px past content they have seen to reach what is new.
- **The same events appear twice.** The "Happening soon" strip and the every-6th-post embeds
  draw from the same arrays, so on a short feed an event shows in the strip and again as an
  embed a few cards later.
- **Desktop fetches discovery twice and throws it away.** Home pulls 20 events + 20
  listings then calls `.take(8)` — and only uses them on narrow layouts, so on desktop all
  40 rows are fetched for nothing. Meanwhile
  [right_rail.dart:47](../lib/widgets/right_rail.dart:47) independently fetches 3 events + 4
  listings. The rail should take the data as a parameter.

---

## 3. The cancelled-content bug (the one that started this)

**Symptom:** after an organiser cancels an event it still appears in Home's "Happening soon"
carousel, looking live, with no indication.

**Root cause.** Cancelling writes **one timestamp**, `events.cancelled_at`
([20261019002200_event_soft_cancel.sql](../supabase/migrations/20261019002200_event_soft_cancel.sql)).
There is no `cancel_reason` column, no RPC — `event_detail_screen.dart:292` does a plain
client `UPDATE`, and passing `null` un-cancels. **No RLS policy, no view and no trigger
hides a cancelled event from reads.** Hiding it is entirely the client's job.

Of the **12** event list queries in the app, exactly **one** does it.

| Site | Role | `cancelled_at` | `is_hidden` |
|---|---|---|---|
| [announcements_repository.dart:315](../lib/screens/announcements/announcements_repository.dart:315) | hub events strip | **yes** | **yes** |
| [home_screen.dart:121](../lib/screens/home_screen.dart:121) | **the reported bug** | no | no |
| [right_rail.dart:49](../lib/widgets/right_rail.dart:49) | rail upcoming | no | no |
| [right_rail.dart:66](../lib/widgets/right_rail.dart:66) | rail past fallback | no | no |
| [announcement_service.dart:196](../lib/services/announcement_service.dart:196) | event picker | no | no |
| [events_cubit.dart:134](../lib/screens/events_cubit.dart:134) | Events, guest read | no — **correct** | no |
| [events_cubit.dart:151](../lib/screens/events_cubit.dart:151) | Events, realtime stream | no — **correct** | no |
| [search_screen.dart:179](../lib/screens/search_screen.dart:179) | search | no | no |
| [profile_screen.dart:95](../lib/screens/profile_screen.dart:95) | profile tab | no | no |
| [profile_cubit.dart:100](../lib/screens/profile_cubit.dart:100) | own profile | no | no |
| [guest_views.dart:114](../lib/screens/guest_views.dart:114) | guest profile | no | no |
| [club_service.dart:459](../lib/services/club_service.dart:459) | club page | no | no |

**This is not a permissions problem**, which was the initial hypothesis. Admins have no
table-level pass on events — [20261026004100](../supabase/migrations/20261026004100_hidden_content_visibility.sql)
deliberately removed it, and its header says admins read hidden content through the
security-definer moderation RPCs instead. Only the *organiser* sees their own `is_hidden`
event. Cancelled events are visible to everyone because nothing tries to hide them.

### The correct split

Applying the user's decisions, the real shape is **4 queries missing a filter and 7 places
missing a badge** — not 12 broken queries:

- **Promotional** (filter needed): `home_screen.dart:121`, `right_rail.dart:49`,
  `right_rail.dart:66`, `announcement_service.dart:196`
- **Browse** (badge + sort only): search, profile ×2, guest profile, club page
- **Already fully correct**: the hub strip, and the Events screen

The Events screen already sorts closed events last
([events_cubit.dart:248](../lib/screens/events_cubit.dart:248)) and renders a Cancelled pill
([events_screen.dart:357](../lib/screens/events_screen.dart:357)).

That matters for a second reason: `events_cubit.dart:151` is a realtime `.stream()`, and
Supabase streams support only single-column `eq/neq/gt/gte/lt/lte/inFilter` with **no `is
null`** — so `cancelled_at is null` cannot be expressed there at all. Because that surface
must not filter, **the hardest part of this problem does not need solving.** Note also that
`.eq('cancelled_at', null)` renders as `cancelled_at=eq.null` and matches nothing.

### Second half: the render layer cannot express "closed"

These widgets never read `cancelled_at`, `is_sold` or `status`:

- [universal_card.dart](../lib/widgets/universal_card.dart) — Home's **both** carousels and
  the club page's events tab ([club_page_screen.dart:526](../lib/screens/clubs/club_page_screen.dart:526)).
  Two traps: it infers kind by key-sniffing (`containsKey('start_datetime')` at
  [:26](../lib/widgets/universal_card.dart:26)), and its photo is **not** inside a `Stack`
  ([:91](../lib/widgets/universal_card.dart:91)), so a badge needs a wrapper.
- [embed_card.dart](../lib/widgets/embed_card.dart) — **two** classes: `EmbedCard` (in-feed
  embed) and `SharedItemHero` ([:168](../lib/widgets/embed_card.dart:168)), which is what
  [post_card.dart:289](../lib/widgets/post_card.dart:289) actually renders for a shared
  event. Note `embed_card.dart:187` reaches into `EmbedCard(...)._meta()`, a private-member
  hack, so constructor changes ripple.
- [right_rail.dart](../lib/widgets/right_rail.dart) `_EventRow` (~:188), `_ItemGrid` (~:235)

Meanwhile `StatusBadge` ([status_badge.dart](../lib/widgets/status_badge.dart)) already
exists for exactly this, its doc comment already lists "Cancelled" as an intended label, and
it is already used this way at
[marketplace_screen.dart:351](../lib/screens/marketplace_screen.dart:351).

### Adjacent bugs of the same shape

**3a. Reserved listings look available.** `is_sold` is trigger-maintained as *exactly*
`status == 'sold'`
([20261019002500:40](../supabase/migrations/20261019002500_listing_status.sql:40)), so a
`reserved` listing passes `.eq('is_sold', false)` and renders with no badge. Affects
[home_screen.dart:126](../lib/screens/home_screen.dart:126),
[right_rail.dart:55](../lib/widgets/right_rail.dart:55),
[search_screen.dart:195](../lib/screens/search_screen.dart:195).
[marketplace_cubit.dart:181](../lib/screens/marketplace_cubit.dart:181) is the correct
contrast — it filters on `status`.

**3b. Four hand-rolled copies of "is this still live?"** — the strongest argument for one
shared definition. [profile_screen.dart:764](../lib/screens/profile_screen.dart:764) has the
badge plumbing but computes the label by hand and gets **both** branches wrong:

```dart
final badge = isEvent
    ? (ended ? s.ended : null)                      // never checks cancelled_at
    : (item['is_sold'] == true ? s.sold : null);    // never checks status → reserved blank
```

[search_screen.dart:676](../lib/screens/search_screen.dart:676) hardcodes `s.ended`, so a
cancelled event there says "Ended". The two newest copies are the two that are wrong.

**3c. Narrowed `select()` lists block the badge fix.**
[search_screen.dart:180](../lib/screens/search_screen.dart:180) selects
`'id, title, start_datetime, end_datetime, image_url'` — no `cancelled_at`. Line
[:196](../lib/screens/search_screen.dart:196) selects `'id, title, price, image_url,
is_sold'` — no `status`. Both must be widened before a badge can render there.

**3d. The mobile offline cache cannot represent cancellation at all.**
[database_helper.dart:48](../lib/database_helper.dart:48) lists explicit columns and includes
neither `cancelled_at` nor `end_datetime`; cached `listings` carry `is_sold` but not
`status`. So offline on a phone, a cancelled event reads back as live and a reserved listing
as available, **no matter what the queries do**. Anticipated by the comment at
[listing_status.dart:10](../lib/utils/listing_status.dart:10). Also:
`openDatabase(..., version: 1, onCreate: ...)` at
[database_helper.dart:28](../lib/database_helper.dart:28) has **no `onUpgrade` handler**, so
adding columns requires a version bump plus a migration path or existing installs break.
Web is unaffected — `_webWrite` stores whole rows as JSON.

**3e. Attendee counts leak from hidden events.** `public.event_participant_counts`
([20261019002100:44](../supabase/migrations/20261019002100_public_read_access.sql:44)) is a
plain view, so it runs as its owner and **bypasses RLS**, and it filters only
`coalesce(e.is_public, true)`. It reports counts for events the reader cannot see.

> **Do not "fix" this with `security_invoker = true`.** It looks elegant and it breaks
> guests: `event_participants` is deliberately never granted to `anon`
> ([20261019002100:8](../supabase/migrations/20261019002100_public_read_access.sql:8),
> [20261022001100:6](../supabase/migrations/20261022001100_guest_read_access.sql:6) — "who
> joined is not public; anon gets a count"), so under `security_invoker` the left join
> returns nothing and every signed-out visitor sees zero attendees everywhere. Owner-run
> with an explicit `WHERE` is correct.

**3f. Shared cancelled events look live in posts — but need no migration.** `posts_public`
embeds the shared event as `to_jsonb(ev)`
([20261026003100:351](../supabase/migrations/20261026003100_event_contacts_attendance.sql:351)),
which already carries `cancelled_at`. The client has the data and ignores it, so this is a
render fix. **Nulling the embed out in SQL was considered and rejected**: it would leave a
post whose entire content is "come to our event" pointing at nothing — less informative than
one marked Cancelled — and would mean redefining a 29-column position-sensitive view for a
seventh time against a partially-migrated production database.

---

## 4. The News page is the Announcements hub

One screen, two names, which is itself a source of confusion. "News" is only the nav label
([hub_strings.dart:83](../lib/screens/announcements/hub_strings.dart:83)); the route, the
files and the code all say announcements (`/announcements`,
[announcements_screen.dart](../lib/screens/announcements/announcements_screen.dart)).

Structure top to bottom: hero carousel → channel chips (who is posting) → category tabs →
upcoming-events strip → the list. Same `posts` table as Home, filtered to
`is_announcement = true`. There is a legacy fallback
([announcements_repository.dart:279](../lib/screens/announcements/announcements_repository.dart:279))
showing official authors' recent posts so the hub is not empty on a fresh upgrade.

Two real bugs:

**4a. The hero treats "featured" and "pinned" as mutually exclusive.**
[announcements_repository.dart:193](../lib/screens/announcements/announcements_repository.dart:193)
is `featured, else pinned, else newest 3`. So if any club has a featured announcement
running, an admin pinning an urgent `kolej` notice gets **no hero slot at all**. These should
merge, with pinned and `kolej`/`jpk` ranking first.

**4b. It fetches the 80 newest by `created_at`, then re-sorts by `publish_at` in Dart**
([:256](../lib/screens/announcements/announcements_repository.dart:256) vs
[:216](../lib/screens/announcements/announcements_repository.dart:216)). A scheduled
announcement written long ago can fall outside that 80 and never appear.

---

## 5. Pins — three systems and one dead leftover

| | Column | Who | Scope |
|---|---|---|---|
| Global pin | `pinned_until` | Admins, in practice | Home feed **and** News hub |
| Club pin | `club_pinned_until` | Club president/officer | That club's own page only |
| Comment pin | — | — | Within one post's comments |

The split is deliberate and documented:
[20261024004100_club_pins.sql:3-10](../supabase/migrations/20261024004100_club_pins.sql:3)
says the club pin exists *so that* "a club's internal pin no longer promotes its post in the
global hub/home".

**The confusing leftover:** `pin_post` still contains a branch letting a user pin their own
post if `profiles.role == 'club'`
([20261019004500_post_pins.sql:81](../supabase/migrations/20261019004500_post_pins.sql:81)).
That is the pre-clubs "club account" model. The club_pins migration header states those pins
"stop working… those accounts are club presidents now" — but the code was never deleted, so
it reads like a live feature nobody can reach. **No account has `role = 'club'` any more**,
making the global pin effectively admin-only. Worth deleting.

**Shared settings, two meanings:** `max_active_pins_per_club` (default 1) and
`pin_duration_days` (default 7), from
[moderation_core.sql:37](../supabase/migrations/20261019004100_moderation_core.sql:37), are
used by **both** pin systems.

`feature_until` is **not** a pin despite behaving like one; it affects only the hub hero.

The Home feed orders on `is_pinned` only — it ignores `is_club_pinned`, which is correct per
the design above.

---

## 6. Refresh: how updates propagate, and where it breaks

The mechanism is one global counter.
[app_nav.dart:388](../lib/utils/app_nav.dart:388) declares
`ValueNotifier<int> contentChanges`; `notifyContentChanged()` increments it; the
`RefreshOnContentChange` mixin ([:419](../lib/utils/app_nav.dart:419)) makes a `State`
refetch on every increment. `completePublish` and `completeEdit` call it.

**6A. Pinning has no refresh path at all.** [pin_controls.dart](../lib/widgets/pin_controls.dart)
**never calls `notifyContentChanged()`** — the function appears nowhere in the file. And
`_togglePin` ([post_card.dart:164](../lib/widgets/post_card.dart:164)) only patches the
card's own local copy:

```dart
setState(() => _post = {..._post, 'is_pinned': now});
```

So the card flips to "Pinned" where it sits and **the feed is never re-sorted or refetched**.
The post jumps to the top only later, on a pull-to-refresh, a reload, or an unrelated content
change — which reads as the app acting randomly a minute after you pinned.

The club pin, written later, got the wiring the global pin did not: `_toggleClubPin`
([:172](../lib/widgets/post_card.dart:172)) does the same optimistic patch **plus**
`widget.onClubPinChanged?.call()`, which
[club_page_screen.dart:232](../lib/screens/clubs/club_page_screen.dart:232) uses to refetch.
Same feature, two ages, two behaviours.

**Undo is worse.** The snackbar's Undo calls `ModerationService.pin/unpin` directly
([pin_controls.dart:54](../lib/widgets/pin_controls.dart:54),
[:95](../lib/widgets/pin_controls.dart:95)) with *no state update whatsoever*. Tap Undo and
the card keeps showing the state you just undid until something else refreshes it.

Smallest fix: `notifyContentChanged()` after a successful pin, unpin, and in both Undo
callbacks — four lines. Caveat: that triggers 6D's refetch storm on every pin.

**6B. Pinning silently skips posts from the feed.** `_postsPage`
([home_screen.dart:175](../lib/screens/home_screen.dart:175)) orders `is_pinned` then
`created_at` and pages by **offset** (`_posts.length`). Changing a pin reorders the list
underneath that offset:

- Pinning moves a post **up** → rows shift down → the next window overlaps. Harmless;
  `_postIds` dedupes.
- **Unpinning**, or a pin **expiring after 7 days**, moves a post **down** → rows shift up →
  the offset skips one → **a post that is never shown.** No error, no gap marker. Pin expiry
  is automatic, so this happens with nobody touching anything.

There is also a reachable infinite loop. The footer self-drives paging
([home_screen.dart:430](../lib/screens/home_screen.dart:430)):

```dart
if (!loadingMore) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
}
```

If a page ever returns 20 rows that are *all* already known, `_posts` does not grow, so
`_hasMore` stays `true` and the same offset is requested forever. It needs roughly 20
simultaneous pin changes to trigger, so it is unlikely — but nothing prevents it.

No patch makes offset paging safe over a mutable sort. The fix is structural: fetch pins as
one short separate query rendered above a chronologically-paged feed.

**6C. Pull-to-refresh races with auto-paging.** `_loadMore`
([home_screen.dart:184](../lib/screens/home_screen.dart:184)) guards with
`if (_loadingMore || !_hasMore || _isLoading) return;` — but `_fetchFeedData`
([:114](../lib/screens/home_screen.dart:114)) **never sets `_isLoading = true`**; it only
ever sets it `false`, at the end. So on every refresh after the first load that guard is
open. Pull to refresh while the footer is paging and: the refresh clears `_posts` and inserts
a fresh 20, then the in-flight `_loadMore` appends the window it computed from the *old*
offset. Page 1 followed by page 3. Dedupe prevents duplicates, not the wrong order.

Fix: set `_isLoading = true` at the top of `_fetchFeedData`.

**6D. One content change refetches every tab simultaneously.**
[router.dart:162](../lib/router.dart:162) is `StatefulShellRoute.indexedStack` — "state
preserved per branch", so Home, Events, Market and Profile all stay mounted. Every one mixes
in `RefreshOnContentChange`, all listening to the same notifier, with no debounce and no
visibility check. Publishing one post fires Home's three parallel queries *plus* Events
*plus* Marketplace *plus* any open detail page at once.

It also fires on non-events: [router.dart:417](../lib/router.dart:417) bumps the counter on
**exiting the edit-profile screen unconditionally**, saved or not.

The eventual shape is probably for `contentChanges` to carry *what* changed so listeners can
decide whether they care, instead of every screen blindly refetching everything.

**6E. "Go live" has no refresh path at all.** There is **no realtime subscription on
`posts`** anywhere — realtime covers notifications
([main.dart:236](../lib/main.dart:236),
[unread_notifications.dart:28](../lib/services/unread_notifications.dart:28)), events
([events_cubit.dart:152](../lib/screens/events_cubit.dart:152)) and post comments
([post_detail_screen.dart:76](../lib/screens/post_detail_screen.dart:76)) only. And
`contentChanges` fires only from actions in your own session. So when a scheduled
announcement's `publish_at` passes, **nothing happens**: no timer, no subscription. It
surfaces on the next manual refresh or reload — and then lands at its `created_at` position
rather than the top (§1a).

---

## 7. "Happening now"

Computed, not stored: [events_screen.dart:25-36](../lib/screens/events_screen.dart:25)
returns "Happening now" once the start time has passed while the event is neither ended nor
cancelled; below a week out it says Today / Tomorrow / In N days instead.

It is rendered in only **two** places — the Events screen cards
([:333](../lib/screens/events_screen.dart:333)) and the event detail page
([event_detail_screen.dart:825](../lib/screens/event_detail_screen.dart:825)). It is **not**
in `UniversalCard` or `EmbedCard`, so on Home's strip and in-feed embeds an event running
right now looks identical to one next Friday. Same widget gap as the Cancelled badge, and the
same one-line fix once a shared status helper exists.

A running event is correctly *not* "ended" (that is `end_datetime`-based), so it legitimately
stays in Home's strip — the label "Happening soon" is just slightly wrong for it.

---

## 8. Proposed: "bump" / auto-up a listing (not built)

User's request: let a seller push an old listing back to the top instead of deleting and
reposting, with an optional automatic version. Three findings before anyone builds it:

**It works for listings.** Every "newest first" list orders by `created_at`, so: add
`bumped_at`, default it to `created_at`, and switch those queries to order by it — Home
"Fresh finds", the right rail, marketplace (all three sort modes), profile, club page,
search.

**It does nothing for events.** Every event list sorts by `start_datetime` — *when it
happens*, not when it was posted; Home's strip is soonest-first. A bump changes nothing unless
"soonest first" is abandoned, which is not wanted. Events already have `feature_until` (hero
placement) and admin pins. If the real need is "remind people", that is a notification, not a
bump.

**Without a cooldown it breaks on day one.** If everyone can bump freely, bumping means
nothing and the market becomes whoever tapped most recently. Needs a hard limit, e.g. one
bump per listing per 24h.

Two existing patterns to copy rather than reinvent:

- **Rate limiting:** `get_listing_contact`
  ([create_matrix.sql:329](../supabase/migrations/20261023001100_create_matrix.sql:329))
  takes an advisory lock, counts rows in a time window from a log table, and raises
  `rate_limited`. A `bump_listing(id)` RPC wants the same shape.
- **Column protection:** `mod_guard_pin_columns`
  ([post_pins.sql:28](../supabase/migrations/20261019004500_post_pins.sql:28)) is a trigger
  that silently reverts direct writes to the pin columns so they change only via RPC.
  `bumped_at` needs the same guard — `listings` currently has no such protection, so a seller
  could simply write it.

The "auto" part needs an opt-in flag plus a `pg_cron` job, and has the same failure mode but
worse: everyone opts in once, and then nobody's bump helps.

---

## 9. Out of scope / deliberately not changing

- **The Events screen, its realtime stream, and the GDPR data export**
  ([account_data.dart:69](../lib/services/account_data.dart:69)) — all three are correct as
  they stand. Add a comment to the export so nobody "fixes" it.
- **The dead `is_admin()` clause** in the older of the two overlapping `is_hidden` policies
  ([moderation_core.sql:419](../supabase/migrations/20261019004100_moderation_core.sql:419)).
  Two restrictive policies AND together, so the narrower
  [20261026004100:14](../supabase/migrations/20261026004100_hidden_content_visibility.sql:14)
  wins and the admin pass is dead. Its header says that is deliberate. Misleading but
  harmless — **note that any future change to hidden-event visibility must edit both
  policies or appear to do nothing.**
- **The missing events UPDATE policy.** There is none in version control, so un-cancelling is
  an unguarded client write. The baseline schema predates this repo's `supabase/` directory.

## 10. Testing situation

43 test files. Relevant seams:

- [test/helpers/feed_fixtures.dart](../test/helpers/feed_fixtures.dart) — `sampleEvent(id)`,
  `sampleListing(id)`, `pumpAt`, `kCompact`/`kMedium`/`kExpanded`, `installFeedHooks()`.
  `sampleEvent` emits **no** `cancelled_at`/`is_hidden`; `sampleListing` emits no
  `status`/`is_sold`. Both need optional params before any of this can be tested.
- `FeedView` ([home_screen.dart:265](../lib/screens/home_screen.dart:265)) takes
  `posts`/`events`/`listings` as plain parameters — widget-testable with no Supabase.
  [test/v14_home_feed_test.dart](../test/v14_home_feed_test.dart) is the model to follow.
- `EventsCubit.debugFetchOnce` / `debugStream`
  ([test/guest_events_test.dart](../test/guest_events_test.dart)) inject rows without
  Supabase.
- [test/ui_layout_test.dart:96](../test/ui_layout_test.dart:96) already pumps an event card
  with `cancelled_at` set — a pre-existing partial test of this feature.

**There are zero query-level tests**: no test anywhere calls `.from('events')`, so none of
the filter behaviour is covered. Adding `Stack` wrappers for badges will perturb
`feed_layout_test.dart`, `ui_layout_test.dart`, `screens_responsive_test.dart`,
`profile_page_test.dart`, `clubs_test.dart` and `v13_repost_hero_test.dart:34`.

Checks: `flutter analyze` and `flutter test`.
