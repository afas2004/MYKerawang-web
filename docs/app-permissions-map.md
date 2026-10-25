# How the app is put together — actors, flows, and where permissions bite

Written for the October security review, because a table-by-table audit cannot
tell you whether a permission change breaks a screen. Everything below is read
from the code (`lib/router.dart`, the screens, the services) and, where marked,
from the live API. Nothing here is applied.

## 1. Actors

Two independent ladders, easy to confuse:

| Ladder | Stored | Values | Meanıng |
|---|---|---|---|
| Account role | `profiles.role` | `student`, `club_pending`, `club`, `admin`, `owner` | platform-wide: who may moderate, who may claim a club, legacy "club account" |
| Club role | `club_members.role` | `president`, `officer`, `member` | per-club: who may act *as the club* (`can_act_as_club` → president/officer of an **active** club) |

Plus three switches that are not roles: `is_verified` / `student_verifications`
(gates `event_join`, `event_create`, `sell`, `club_join`, `form_submit` while
`access_settings.verification_enabled` is on — it is **off** today),
`is_banned` (blocks writes via the `mod_guard_write` triggers), and
`user_restrictions` (per-scope: post/comment/event/listing/account).

Guests are not an actor in the database — they are the `anon` PostgREST role
with whatever `grant … to anon` + anon policies allow.

## 2. Routes and who can open them

`isGuestPath()` (`router.dart:81-89`) is the guest list; everything else
redirects to `/login?from=…`.

| Route | Guest | Student | Club officer | Admin | What it reads | What it writes |
|---|---|---|---|---|---|---|
| `/home`, `/announcements` | yes | yes | yes | yes | `posts_public`, `profiles_public`, `events`, `listings`, `event_participant_counts`, `follow_counts`, `content_categories` | — |
| `/market`, `/search` | yes | yes | yes | yes | `listings`, `profiles_public`, `clubs`, `posts_public` | — |
| `/events` | yes | yes | yes | yes | `events` (+ `profiles_public`) | — |
| `/item/:id` | yes | yes | yes | yes | `listings`, `profiles_public`; contact via `get_listing_contact` RPC | (contact reveal is RPC + rate-limited) |
| `/event/:id` | yes | yes | yes | yes | `events`; organiser from `profiles_public` **for guests** (`event_detail_screen.dart:133`); participants count from `event_participant_counts` **for guests** (`:140-152`) | join/leave `event_participants` (signed-in only, `:520-527`) |
| `/post/:id` | yes | yes | yes | yes | `posts_public`, `comments_public` | comment insert |
| `/u/:id` | yes → `GuestProfileScreen` | → `ProfileScreen` (`router.dart:322-324`) | same | same | guest: `profiles_public`, `follow_counts`, `posts_public`, `events`, `listings` (`guest_views.dart:110-116`) | follow/unfollow (signed-in) |
| `/u/:id/followers` \| `/following` | **no** (two segments, not a guest path) | yes | yes | yes | `followers` + embedded `profiles` | — |
| `/event/:id/form` | yes (shows a sign-in bar) | yes | yes | yes | `form_public` RPC | — |
| `/tag/:tag` | yes | yes | yes | yes | `posts_public` | — |
| `/event/:id/checkin`, `/event/:id/form/responses`, `/event/:id/form/edit` | no | joined/manager | manager | manager | check-in tokens / `form_response_list` / `form_analysis` | check-in, form answers, form edits |
| `/create/*`, `/profile/edit`, `/settings`, `/notifications` | no | yes | yes | yes | own rows | own rows |
| `/create/announcement` | no | no | officer of an active club | + admin | `can_post_announcement` | `posts` insert |
| Admin/moderation tabs | no | no | no | yes | admin RPCs only | admin RPCs |
| `/settings/privacy` | yes | yes | yes | yes | static text | — |

## 3. The design rule the code follows

Every guest-facing screen reads a **view** or a **count view**, never a base
table that holds other people's rows. The code says so where it matters:

* `event_detail_screen.dart:130-133` — "Guests can't read the profiles table (it
  holds phone numbers), so they go through the safe view."
* `event_detail_screen.dart:138-152` — guests get `event_participant_counts`;
  only a session counts `event_participants`.
* `guest_views.dart:110-116` — guest profile is `profiles_public` +
  `follow_counts` only.
* `post_detail_screen.dart:186,206` — comments come from `comments_public`, which
  nulls the author on anonymous rows and filters `is_hidden`.

Writes follow the same shape: the UI hides them, and the database enforces them
on the **row owner** (`auth.uid()`), not on a client-sent column. Writes that
need a rule go through a security-definer RPC (`submit_form_response`,
`pin_post`/`club_pin_post`, `apply_to_club`, `register_club`, the moderation
admin RPCs). The client never builds SQL; `.or()` strings pass `filterSafe`.

## 4. What that means for the review's findings

| Finding | Flow it touches | Verified against the flow? |
|---|---|---|
| **C1** images bucket anon write | every image upload path | Yes — the app uploads only as a signed-in user, with a generated name, and never lists. Removing anon write breaks no designed flow. **The one to smoke-test after applying is a real upload** |
| **H2** anon reads `profiles`/`followers`/`event_participants` | guest home, event, post, profile | **Yes, and it corrected my first draft.** Guests never touch those tables: the guest branches in `event_detail_screen.dart:133,146-151`, `guest_views.dart:110-116` and the `/u/:id` route split (`router.dart:322-324`) all use views. The repo comment ("never granted to anon") is the intended contract; the live grants are drift |
| **H3** notification insert | follow, mention, event invite | Yes for follow/mention (real edges exist); **`create_event_screen.dart:408` needs reading before that policy is applied** — if it sends a type outside follow/mention, the tightened policy would make that insert throw |
| **M5/M6** upload gate | all pickers | Only by unit tests + the picker code path; a real photo picker was not run |
| **M1** hidden-event counts | guest event page + feed | Yes — guests use this view, and the added `is_hidden` filter is what the event page already expects (`events` policy hides the row) |
| **M3/M2** domain rules | sign-up, admin verification | Yes for sign-up (mode is `open`, so inert); admin verification is a deliberate behaviour change |
| **M4** form caps | form editor → publish → answer | Yes for the editor (client caps already match); the risk is only for a *legacy* form over the cap, hence the preflight |
| **M12** `event_contact` | event page contact buttons | Yes — the button is shown to any signed-in user by design; the finding is about volume, not a broken flow |

### Correction to the first draft

I originally wrote "guests use the views, so revoking anon is safe" as an
**inference** from the repo comments. It is now checked against the actual guest
branches, and it holds. The same check found one thing the table audit missed:

**New — M25: the follower list over-fetches the whole profile row.**
`follow_list_screen.dart:41-47` selects `profiles!follower_id(*)` and
`profiles!following_id(*)`. Any signed-in user can therefore pull every
column granted to `authenticated` for every follower of any account — not just
the name and avatar the UI renders. Today that includes `full_name`,
`device_id`, `is_banned`, `ban_reason`, `last_active_at`; if `phone_number` /
`payment_qr_url` are still granted on `profiles`, they ride along too.
Fix: name the columns in both selects (`id, username, display_name,
avatar_url, is_verified`), and/or column-restrict `profiles` for
`authenticated`. One-line each, no flow change.

## 5. What I have not run

I have not used the app signed in. The flows above are read from code, and the
guest ones were rendered in headless Edge against the live build (home, feed,
events, market). Not exercised:

1. Google sign-in round-trip (redirect allowlist + code exchange).
2. Upload from a real picker → bucket → render (the storage policy change).
3. Club logo / payment QR upload (the path that had no gate).
4. Submit a form answer, then read it as the organiser (matrices + CSV).
5. Follow a user → the mention/follow notification appears.
6. Delete a post → its images are removed with the new owner-scoped delete.

Six clicks, one account. If you give me a throwaway account I will run them and
report exactly which one, if any, regresses; otherwise the checklist is yours.
