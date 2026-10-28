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
| Migrations | two pending, both listed below: `20261026015100` (security review) and `20261028120000` (club review) |
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

Verify after `db push` (owner, SQL editor):

```sql
-- #1 nothing left stuck
select r.code, r.name, c.handle from clubs c
  join club_registry r on r.id = c.registry_id where c.status = 'rejected';
-- #2 clubs with more than 30 posts (were affected by the page bug)
select club_id, count(*) from posts
  where club_id is not null and not is_hidden group by club_id having count(*) > 30;
-- #4 club pins that were not set through the button
select id, club_id, club_pinned_until, club_pinned_by from posts
 where club_pinned_until is not null
   and (club_pinned_by is null
        or club_pinned_until > now() + make_interval(days => (select pin_duration_days from moderation_settings where id)));
```

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
| `20261026015100_security_review_fixes.sql` | **NOT APPLIED YET.** Form text caps, hidden-event counts, exact signup domain, verification-domain trigger, execute grants, and the `images` bucket write policies. Apply before the club year — see `docs/security-review.md`. |
| `20261028120000_club_review_fixes.sql` | **NOT APPLIED YET — owner runs `db push`.** Three club-review fixes: a **rejected** request releases its registry entry (`admin_decide_club_request` + one-time release of stuck rows), the **pin guard covers the club columns** (`club_pinned_until`/`club_pinned_by` were insertable straight from the client), and the roster notice credits **the president** rather than "officers". The app half of that review (club page pinned-post window, registry PIN lock, handle preview) is in 1.9.2. |

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
- **The history trap**: everything before `20261026015100` was pasted into the
  dashboard, so `supabase_migrations.schema_migrations` may be empty and a plain
  `db push` would replay ~51 files. `db_push.ps1 -Repair` records them as applied
  first; the script always dry-runs and shows the plan before touching anything.

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
