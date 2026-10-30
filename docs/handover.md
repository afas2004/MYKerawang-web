# Handover — MYKerawang web

Updated 2026-10-25 at the end of an evening session, for the next one to start
cold. Everything below was checked against the repo, the live site and the
database.

## Where things stand

| | |
|---|---|
| Repo | `C:\src\project\Flutter\MYKerawang-web` |
| Worktree to reopen | `.deepseek/worktrees/clubs-admin` |
| Branch | `deepseek/clubs-admin` — clean, pushed |
| Live | https://kerawang.my — build `202610282014`, version **1.9.2** (+27) |
| Tests | **563** Flutter tests green; analyzer 16 info/warnings, **no errors** |
| Migrations | **all applied**, and the remote history table now matches. `db push` works through `db_push.ps1`; see the CLI notes below |
| Supabase | project `zxjuqpqzyzmegdjttzyz` |

## Do this first: deploy

**Done on 2026-10-28.** Production is now 1.9.2+27 / build `202610282014`
(verified from `https://kerawang.my/build.json`, `version.json` and the string in
`main.dart.js`; `mykerawang-app.web.app` serves the same build). To redeploy:

```powershell
# pubspec.yaml           version: 1.9.2+27
# lib/services/update_service.dart   appVersion = '1.9.2'
cd C:\src\project\Flutter\MYKerawang-web\.deepseek\worktrees\clubs-admin
.\deploy_web.bat          # builds, stamps build.json/index/bootstrap, deploys
```

Then verify **from the site**, not the log: `https://kerawang.my/build.json`,
`version.json`, and the id inside `main.dart.js`. Note that headless Edge
cannot render the wasm build (it stalls on the splash for a local copy too), so
a visual check needs a real browser.

## The eight unmanaged objects — adopted 2026-10-29

An audit compared every live function, trigger and policy against every
`supabase/**/*.sql` (and `git log --all -S`, which found nothing). Eight objects
had been created by hand in the dashboard and existed **only** in the database:

| Object | Attached to | Now |
|---|---|---|
| `handle_new_user()` | `on_auth_user_created` on **auth.users** | adopted, `search_path` added, `on conflict (id) do nothing` |
| `update_comment_count()` | `on_comment_change` on **comments** | adopted; count can no longer go below zero |
| `notify_new_event()` | `on_event_created` on **events** | adopted; `search_path` added |
| `events_insert_own` | INSERT policy on **events** | adopted — `authenticated`, `organizer_id = auth.uid()` |
| `listings_insert_own` | INSERT policy on **listings** | adopted — `authenticated`, `seller_id = auth.uid()` |
| `ensure_profile_exists(uuid)` | callable, **anon had EXECUTE** | **dropped** — no caller in `lib/` or `test/`, and it inserted a hard-coded name and avatar |

Why it mattered: without these, a database built from `migrations/` alone would
sign people up with **no profile row**, lose comment counts, lose new-event
notifications, and lose the ability to insert an event or listing.

Two things to know about the file:

- The `auth.users` trigger is created **only when `auth.users.raw_user_meta_data`
  exists** — i.e. on a real Supabase project. The PGlite stub models `auth.users`
  with four columns and every test creates its own profile row, so attaching the
  trigger there would collide with 13 helper inserts rather than test anything.
  Verified after applying: the trigger **is** live on `auth.users`.
- The migration also adds `set search_path = public` to the three definer
  functions. `handle_new_user` and friends had none, which is the classic
  definer-escalation shape.

The harness got two fidelity fixes so the other three objects are exercised:
`profiles.notify_new_events` and `notifications.message` exist in the stub now,
and `notifications.actor_id` is nullable (as it is in production).

**Three suites fail for reasons that predate this work** — verified by stashing
the migration and re-running: `create/announce_edit_test.mjs` and
`create/create_test.mjs` die on `invalid input syntax for type uuid:
"Debate Society"`, and `posts_v13/posts_v13_test.mjs` needs the `citext`
extension it does not load.

## The 2026-10-28 club review

Four findings; three fixed here, one left to the owner.

| # | Finding | Fix |
|---|---|---|
| 1 | A **rejected** club request kept `registry_id`, and every later check treats a non-null id as claimed — so one bogus application could burn a registry entry for ever, while the rejection notice promised "you can register again". | `admin_decide_club_request` nulls `registry_id` on reject, plus a one-time release of rows already stuck. **Migration — owner runs `db push`.** |
| 2 | The club page's pinned post could be missing: `ClubService.posts` ordered by `is_pinned` (the *global* admin pin, ascending) and limited to 30, so a club pin older than the 30 newest fell outside the window. | Pinned rows are now fetched **separately** (`is_club_pinned` true), then the rest by date — inclusion no longer depends on the limit. Split rule extracted to `lib/utils/club_posts.dart` with tests. |
| 4 | `club_pinned_until` / `club_pinned_by` were not in `mod_guard_pin_columns`, so an officer's own session could insert a permanent club pin past the cap, and pin as anyone. | Guard redefined for all four pin columns; trigger recreates with the club columns in its `update of` list. **Same migration.** |
| — | Smaller: `/admin/clubs/registry` ignored the admin PIN lock; roster notice credited officers; the handle preview fell back to a name-derived handle the server never assigns; two unused imports. | Registry screen now asks for the PIN and resets on the idle timer; notice says **the president**; `registryHandlePreview` mirrors `register_club` (`club` + code when short); imports removed. |

**Still open, needs a product decision:** `add_club_member` puts someone on a
club's **public** roster without asking them — they only get a notification. Keep
it (president-managed roster) or switch to an invitation the person accepts?

Verified 2026-10-28 with
[`supabase/checks/20261028_club_review.sql`](checks/20261028_club_review.sql):

| Check | Result |
|---|---|
| Rejected clubs still holding a registry entry | **0** |
| Clubs with more than 30 posts (the ones the page bug could bite) | **0** — nobody was affected yet |
| Club pins not set through `club_pin_post` | **0** |
| `trg_mod_guard_pin_columns` definition | `BEFORE INSERT OR UPDATE OF pinned_until, pinned_by, club_pinned_until, club_pinned_by` |
| Reject path in the live function | releases the entry (`registry_id = case when p_approve …`) |

## What tonight's six commits do

| Commit | What |
|---|---|
| `cfe6580` | **Navigation**: the answer page and analyses had no `onExit`, so an in-app back was reported as a *new* history entry and the browser's back reopened the page just closed. Also: cold-opened form screens now go up to their event, `?f=` is carried on every form link (edit ↔ answer ↔ responses), and editor → analyses → Edit no longer pushes a second editor. |
| `5a2b6d2` | **Form text**: caps enforced while typing (label 200, title 120, intro 500, help 300, choice 60, answers 200/2000) via `lib/utils/text_rules.dart`; choices can be renamed again (the rewrite had made them add/delete only); **CSV formula injection** neutralised in the response CSV, attendance CSV and copied S1/S2/S3 tables (`csvSafe`). |
| `e0e6fd6` | **Links and filters**: `launchableUri` allows only http/https/mailto/tel, so an event's `javascript:` registration link or a contact "handle" cannot reach `launchUrl`; the composer refuses non-https registration links. `filterSafe` strips PostgREST filter syntax from the clubs directory and mention autocomplete. Hosting headers: nosniff, SAMEORIGIN, referrer policy. |
| `35d2f1d` | **Domain**: `og:image`/`twitter:image` and the native share fallback now say `kerawang.my`. |
| `ca7f9c9` | **Storage**: review of every upload path; removed an unused `uploadAvatar` that named objects with the picked file's extension. New migration sets the bucket MIME allowlist and 5 MB cap. |
| `6b2cbeb` | **Upload checks**: `lib/utils/photo_rules.dart` — signature sniffing (PNG/JPEG/GIF/WebP), 5 MB byte cap and a 40 MP decompression-bomb guard, refused at pick time with a message. |

Two earlier commits from the same evening are already in production:
`7aa7c6c` (the form editor + answer sheet redesign, version 1.9.0) and
`0ae5322` (deploy cache).

## The custom domain

`kerawang.my` is live with a Firebase-managed certificate; `http` redirects to
https and Firebase sends HSTS (one year).

- **`www.kerawang.my` has no matching certificate** — every visit is a browser
  security warning. Fix: add it as a second custom domain in Firebase Hosting.
- The old `mykerawang-app.web.app` still serves the app. Two origins, two
  separate sessions (browser storage is per-origin).
- Supabase Auth URL configuration was updated by the owner for the new domain.
  Note: `/auth/v1/authorize` **accepts any `redirect_to`** at that stage — the
  allowlist is applied at the callback, so that endpoint is not a way to test
  the setting. Don't "verify" it that way.

## Migrations, in order (all applied)

| Migration | What it does |
|---|---|
| `20261026007100_event_forms.sql` | The KI report survey: templates, forms, responses, `form_analysis` (S1/S2/S3), `event_open_form`, `event_form_summary`, `create_blank_form` |
| `20261026008100_event_links_pic.sql` | `events.action_links` (max 2 buttons, guarded by a trigger) and `events.pic` |
| `20261026009100_fix_checkin_token.sql` | **The attendance fix.** `event_checkin_token()` had a `returns table (…, expires_at)` output column and a bare `expires_at` in its cleanup `DELETE` → `42702 ambiguous`, so the rotating code never worked at all |
| `20261026010100_form_after_checkin.sql` | `set_form_after_checkin(form, bool)` — the "ask the KI form after check-in" switch |
| `20261026011100_checkin_does_not_join.sql` | A check-in no longer inserts into `event_participants` |
| `20261026014100_storage_image_limits.sql` | `images` and `avatars` buckets: `allowed_mime_types` (jpeg/png/webp/gif) and a 5 MB `file_size_limit`. Applied 2026-10-25. |
| `20261026015100_security_review_fixes.sql` | Form text caps, hidden-event counts, exact signup domain, verification-domain trigger, execute grants, and the `images` bucket write policies. **Applied 2026-10-28.** Verified: an anonymous PNG upload to `images` now fails with `new row violates row-level security policy` (it returned 200 before). |
| `20261028120000_club_review_fixes.sql` | The club-review fixes: a **rejected** request releases its registry entry, the **pin guard covers the club columns**, and the roster notice credits **the president**. **Applied 2026-10-28**, history recorded |
| `20261029230000_formalise_unmanaged_objects.sql` | **Applied 2026-10-29.** Adopts the eight objects that only ever existed in the dashboard — `handle_new_user` (trigger on `auth.users`), `update_comment_count` (comments), `notify_new_event` (events), the `events_insert_own` / `listings_insert_own` policies — and **drops `ensure_profile_exists`**, which was anon-executable and inserted a hard-coded identity. Adds `set search_path = public` to the three security-definer functions. See "The eight unmanaged objects" below. |

Seeded data: `supabase/seed/2026-10-25_ki_test_event.sql` created **Malam Ujian
KI** — the event to test the whole report loop on. Re-runnable.

## What exists now

**Forms / KI report** — read `docs/ki-event-reports.md` first (design, grounded
in the club's real documents), then `docs/mockups/` for the redesign.

- The app owns the **survey and its analysis**, not the HEP report PDF.
- The **editor** (`/event/:id/form/edit`) is a ledger: every setting a question
  has is on its row (type, counted-as, KI element, scale, required, options).
  Sections are heading rows that tint a lane: purple = KI before, gold = KI
  after, teal = feedback. Reorder by dragging the handle at the card's edge or
  with the arrows. A wide window shows a coverage rail (KI1–7 before/after, S1
  pairs, publish checks); a phone collapses it to one line.
- The **answer sheet** (`/event/:id/form`) groups questions into the form's own
  sections with the same tinting, five-segment ratings, one progress line and a
  sticky submit bar.
- **Analyses** (`/event/:id/form/responses`): S1/S2/S3 with their `n`, copy
  buttons for the Word report, a CSV of all responses.
- Answers are validated server-side (`submit_form_response`) and mirrored in
  `lib/utils/form_rules.dart`; field definitions in `form_check_field`.

**Attendance** (`lib/screens/events/attendance_live_screen.dart`) — rotating
code (20 s token), live count, last person in, End attendance, then an animated
summary with the attendance CSV and/or KI CSV.

**Event page / composer** — the event page leads with the door for its owner;
everything else is behind **Manage event**. Contact channels are buttons.
Check-in opens 15 min before the start (`lib/utils/event_live.dart`).

## Security posture (what is done, so it is not redone)

- Client holds the **publishable** key only; the leaked `service_role` is dead.
- No SQL string building: PostgREST/RPC parameters only. `filterSafe` for the
  `.or()` strings.
- No HTML surface (Flutter canvas, no `HtmlElementView`, no webview), so no
  stored XSS in the app itself.
- Links: scheme allowlist before `launchUrl`; action links https-only at
  creation and in a DB trigger; `safeReturnPath` blocks open redirects.
- CSV/TSV: formula prefixes neutralised.
- Uploads: generated object names, sniffed content type, 5 MB + 40 MP caps,
  bucket MIME allowlist. **Every** pick path now checks the bytes, including the
  club logo/cover/QR pickers (they did not before), and `uploadPhotos` refuses
  unchecked bytes itself. Lossless-WebP bombs are caught.
- **Not done:** a Content-Security-Policy (tested and ready in
  `docs/security-review.md` §6 — do not ship it without reading that), and
  storage **write policies** — see below.

## The October security review (read this before touching storage or RLS)

`docs/security-review.md` has the full findings table, evidence and fixes. The
short version:

1. **`images` bucket was world-writable** — anonymous create, overwrite, delete
   and list, measured with only the publishable key. Anyone could have wiped or
   replaced every photo. The fix is in
   `supabase/migrations/20261026015100_security_review_fixes.sql`; **it is not
   applied yet** (no DB access from the review session). Apply it, then re-run
   the curl check in the review doc.
2. Two RLS changes **need an owner decision** and are deliberately kept out
   of `supabase/migrations` in
   `supabase/pending/20261026015200_security_signoff.sql`: anon reads of
   `profiles`/`followers`/`event_participants` (the repo says anon should not
   have them), and the notification insert policy (any user can notify any
   user). The third block — report categories hiding on the first priority
   report — is **accepted as the intended design** and needs nothing.
3. Everything else is listed by severity, with the dashboard instructions in
   review doc §11. `docs/app-permissions-map.md` maps the actors, routes and
   guest/authenticated branches, so a future RLS change can be checked against
   a screen instead of guessed.
4. The one thing that is destructive today is the `images` bucket (anonymous
   delete/overwrite, measured). Nothing else lets an outsider destroy data.

**The SQL test harness was red** and is fixed: the shared stub had no
`storage.buckets`, so every suite stopped at the storage-limits migration. The
`moderation` suite still has its two known assertion failures and then crashes at
`pin_post` (admin-only since `20261024004100_club_pins.sql`; the test was never
updated). `create/*` and `posts_v13/*` were already broken and are not in the
list above.

New suite: `node supabase/tests/security/security_test.mjs .` — 22 assertions.

## Open work

1. **Deploy** (see above).
2. **`www.kerawang.my` certificate** — Firebase Hosting, add the domain.
3. **Photo quality** — the picker caps at 1600 px / q80, so uploads are
   200–600 KB. Discussed but not changed: 2048 / q85 would be ~1 MB and still
   far under the cap. Two related fixes are still open: the native path
   **compresses twice** (picker q80, then `ImageCompressor` q75 with no size
   gain), and feed cards decode at full resolution (no `memCacheWidth` in
   `post_card`/`universal_card`).
4. `/event/:id/checkin` still has no `onExit: historyAwareExit` — same latent
   fault the form pages had, harmless while it is only opened cold.
5. Announcement categories are still a fixed set of five.
6. "Check-in is open" is missing from the feed/announcement cards.
7. Launch ops (`docs/launch-checklist.md`): rotate the DB password; one real
   attendance dry run; captcha (needs an hCaptcha/Turnstile site key from the
   owner; touches the OAuth launch); a manual backup before inviting clubs.

## How to work

```powershell
cd C:\src\project\Flutter\MYKerawang-web\.deepseek\worktrees\clubs-admin
flutter analyze --no-pub
flutter test

# migration suites (PGlite), install once:
cd supabase/tests/moderation; npm i --no-save @electric-sql/pglite@0.2.17
node moderation_test.mjs ../../../          # applies every migration twice
cd supabase/tests
node clubs/clubs_test.mjs ../..             # 87 assertions
node verification/verification_test.mjs ../..
node forms/forms_test.mjs ../..             # 62
node events/events_links_test.mjs ../..     # 10
node events/attendance_flow_test.mjs ../..  # 15

# deploy
.\deploy_web.bat

# apply pending migrations (asks for the DB password, masked)
.\db_push.ps1              # dry run, then confirm
.\db_push.ps1 -Repair      # first time only: record pasted migrations as applied
```

### The migrations route on this machine

- The Supabase CLI is **not on PATH**; run it as `npx --no-install supabase` (v2.122.0 is
  in the npx cache) or through `db_push.ps1`.
- **`--linked` is broken** for this project: the CLI creates a temporary
  `cli_login_postgres` role and a leftover one makes it fail with
  `permission denied to alter role … only roles with CREATEROLE and ADMIN option`.
  `--dry-run` fails the same way. A direct connection string avoids the whole path.
- **Connection string** (project is in **South Asia / Mumbai**):
  `postgresql://postgres.zxjuqpqzyzmegdjttzyz:<password>@aws-1-ap-south-1.pooler.supabase.com:5432/postgres`
  `aws-1` is the right host — `aws-0` answers `tenant/user … not found`. The direct
  `db.<ref>.supabase.co` has no A record (IPv6 only).
- **The history trap — now resolved.** Everything before `20261025001100` had been
  pushed, and the 16 migrations after it had not been recorded (they were pasted
  into the dashboard). On 2026-10-28 those 16 were proved live object by object
  ([`supabase/checks/20261028_history_preflight.sql`](checks/20261028_history_preflight.sql))
  and then recorded with `migration repair --status applied`. The remote history
  now matches the repo, so `db push` on a future migration applies **only** that
  migration — no `-Repair` needed any more.
- **`db query --file` runs one statement.** A file with several `select`s fails with
  `cannot insert multiple commands into a prepared statement`. Run each query on
  its own (`--db-url "<sql>"`), or paste the file into the dashboard, which is happy
  with many.

Two moderation assertions fail **without** the new migrations too ("two
reports → one open case", "priority category hidden on first report") —
pre-existing, not yours.

## Code map

| Area | Files |
|---|---|
| Events | `lib/screens/event_detail_screen.dart`, `events_screen.dart`, `create_event_screen.dart` |
| Attendance | `events/attendance_live_screen.dart`, `events/checkin_screens.dart`, `lib/utils/attendance_rules.dart`, `lib/utils/event_live.dart` |
| Forms / KI | `lib/services/form_service.dart`, `events/form_editor_screen.dart`, `events/event_form_screen.dart`, `events/form_responses_screen.dart`, `lib/utils/form_rules.dart`, `lib/utils/text_rules.dart`, `lib/utils/form_csv.dart`, `lib/widgets/form_style.dart`, `lib/l10n/form_strings.dart` |
| Uploads | `lib/utils/local_image.dart`, `lib/utils/photo_rules.dart`, `lib/utils/image_compressor.dart`, `lib/widgets/media_picker_grid.dart` |
| Security helpers | `lib/utils/url_rules.dart` (link schemes), `lib/utils/filter_rules.dart` (PostgREST), `lib/utils/text_rules.dart` (`csvSafe`) |
| Navigation | `lib/router.dart`, `lib/utils/app_nav.dart`, `browser_history_{web,stub}.dart` |
| Mentions | `lib/widgets/mention_input.dart` (`suggestClubs`) |
| Docs | `docs/ki-event-reports.md`, `docs/mobile-ui-rules.md`, `docs/mockups/`, `docs/launch-checklist.md` |

## Gotchas that cost real time

- **Do not rewrite text files with PowerShell** (`Get-Content -Raw` →
  `Set-Content`, or `-replace`). It double-encoded em-dashes, arrows and middle
  dots in `handover.md` and twice in Dart. Use the edit/write tools.
- **Commit messages through PowerShell**: parentheses and quotes in a
  double-quoted `-m "…"` break the parse. Write the message to a temp file and
  use `git commit -F`.
- `flutter test` uses a test font where every glyph is a square: long strings
  are several times wider than in production, so a 375 px test overflows where
  the app is fine. Use `Flexible`/ellipsis and `quietCounter` rather than
  chasing the overflow in the app.
- Headless Edge reports a viewport **wider than `--window-size`** (430 → 492),
  so screenshots are cropped at the right edge. Not a layout bug. **Correction
  (Oct 2026):** `--headless=new` with `--enable-unsafe-swiftshader
  --use-angle=swiftshader` *does* boot the wasm build — the CSP tests in
  `.deepseek/csp/` drive it over CDP. The old "cannot boot the wasm build at
  all" note applied to the legacy headless mode.
- `app_strings.save` is `"SAVE"` (uppercase) and `cancel` is `"Cancel"`.
  Widget tests that tap a dialog button must match the case exactly.
- `DropdownButtonFormField` needs `isExpanded: true` in a narrow dialog; a bare
  `DropdownButton` needs a bounded width, or it overflows at 375 px.
- **`returns table (a, b, …)` makes those names PL/pgSQL variables.** An
  unqualified column with the same name raises `42702 … ambiguous` at run time.
- `supabase_flutter` hardcodes `webOnlyWindowName: '_self'` for OAuth, so it
  always pushes a history entry; hence the custom launch.
- The **owner account cannot delete itself** (`owner_cannot_delete`). The
  `demo@mykerawang.local` account has no password and cannot be logged into.
- Hidden content stays visible to its author; admins do not get a feed pass.
- Generated plugin registrants (`linux/`, `macos/`, `windows/`) get touched by
  builds — `git checkout --` them before committing.
- Student data supplied for design work (`BORANG KI…xlsx`, `LAPORAN…pdf`) is
  git-ignored by name and must never be committed.
- Storage **write policies were not in the repo** — they lived only in the
  Supabase dashboard, and the `images` ones granted anonymous write (see the
  October review). `20261026015100_security_review_fixes.sql` now owns them for
  `images`; `avatars` is still dashboard-only. Do not assume a bucket is safe
  because a migration says nothing.

## Suggested next session

The owner asked for a **full security check**. A prompt to start with is in
this session's last message; the short version: deploy first, then audit RLS and
the storage policies against the client, and only then decide about a CSP.
