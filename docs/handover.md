# Handover — MYKerawang web

Written 2026-10-25. Everything below was verified, not remembered.

## Where things stand

| | |
|---|---|
| Repo | `C:\src\project\Flutter\MYKerawang-web` |
| Worktree used | `.deepseek/worktrees/clubs-admin` (the one to reopen) |
| Branch | `deepseek/clubs-admin` — 5 commits ahead of `origin/main` |
| Last merge | PR #7 → `88c8578` (before 1.7.2). Merge again at the next natural stop. |
| Live | https://mykerawang-app.web.app — build `202610250751`, version **1.7.6** |
| Tests | 443 Flutter tests green; analyzer clean |
| Latest migration | `20261026006100_club_recruitment.sql` (applied to live) |

## Infrastructure

- **Supabase** project `zxjuqpqzyzmegdjttzyz`. The app uses a **publishable** key
  (`sb_publishable_…`) in `lib/main.dart`. The legacy JWT keys are **disabled**;
  the old `service_role` that leaked into git history is dead (verified 401).
  Any privileged key now comes from `--dart-define=SUPABASE_SECRET_KEY=…`; never commit it.
- **Auth**: email + Google. Confirm email **on**, anonymous sign-ins **off**,
  manual linking off. Custom SMTP through **Resend** with `kerawang.my`
  (DKIM + `rsend`/`send` CNAMEs at Hostinger, DMARC `p=none`). Confirmations
  verified received.
- **Hosting**: Firebase `mykerawang-app`. Deploy stamps a build id into
  `build.json`, `index.html` and `flutter_bootstrap.js`.

## Data

- 18 accounts (13 real testers, KMI, owner, admin, a password-less `demo` account).
- One club (KMI, active). Beta seed: 3 KMI announcements, 3 events (two with
  merit + attendance), 4 sample posts, 3 listings from `demo`.
- Old development content is **hidden** (`is_hidden`), not deleted. Backup:
  `.deepseek/backups/2026-10-24-beta-reset/` (outside git).
- One-off SQL: `supabase/seed/2026-10-24_beta_cleanup.sql` and `…_beta_seed.sql`.
  The seed refuses to run twice; the cleanup has a `created_at` guard.

## Switches that change behaviour

| Column | Where | Default |
|---|---|---|
| `access_settings.registration_mode` | owner console | `open` (live) |
| `access_settings.verification_enabled` | owner console | `false` |
| `clubs.recruitment_open` | club manage | `true` |

## Code map

| Area | Files |
|---|---|
| Auth / login | `lib/screens/login_cubit.dart`, `login_screen.dart`, `lib/services/registration_policy.dart` |
| Student verification | `lib/services/student_verification.dart`, `lib/screens/verification/verify_sheet.dart`, admin `verifications_tab.dart` |
| Clubs | `lib/screens/clubs/*`, `lib/services/club_service.dart` |
| Events | `lib/screens/create_event_screen.dart`, `event_detail_screen.dart`, `lib/screens/events/` (attendance + check-in) |
| Announcements | `create_announcement_screen.dart`, `lib/widgets/announcement_view.dart`, `lib/services/announcement_service.dart` |
| Categories | `lib/utils/categories.dart` (seeds), `lib/services/category_service.dart`, `lib/widgets/category_picker.dart` |
| Moderation | `lib/services/moderation_service.dart`, `lib/utils/moderation_logic.dart`, `lib/widgets/moderation_ui.dart` |

## How to work

```powershell
cd C:\src\project\Flutter\MYKerawang-web\.deepseek\worktrees\clubs-admin
flutter analyze --no-pub
flutter test

# migrations (need PGlite once)
cd supabase/tests/moderation; npm i --no-save @electric-sql/pglite@0.2.17
node moderation_test.mjs ../../..          # applies every migration twice
node ../clubs/clubs_test.mjs ../../..      # run from supabase/tests (pglite resolves there)
node ../verification/verification_test.mjs ../..

# deploy: bump BOTH places, then build/stamp/deploy
#   pubspec.yaml version: 1.7.x+N
#   lib/services/update_service.dart appVersion
flutter build web --release --wasm --pwa-strategy=none --dart-define=BUILD_ID=<yyyyMMddHHmm>
# write build.json, replace __BUILD_ID__ in index.html + flutter_bootstrap.js,
# copy sw_reset.js over flutter_service_worker.js, then:
firebase deploy --only hosting --project mykerawang-app
```

## Gotchas learned the hard way

- **Do not append Dart with `Add-Content`.** It mangled an em-dash into invalid
  UTF-8 and the analyzer reported "URI doesn't exist" for a file that was fine.
  Use the write/edit tools.
- After appending to a file, `flutter analyze` may report a stale
  "Target of URI doesn't exist" for that file; `flutter analyze <file>` is accurate.
- Generated plugin registrants (`linux/`, `macos/`, `windows/`) get touched by
  builds — `git checkout --` them before committing.
- The **owner account cannot delete itself** (`owner_cannot_delete`); the UI now
  says so before asking for a username.
- Hidden content stays visible to its author, so the owner still sees their own
  hidden rows. Admins do **not** get a feed pass.
- The `demo@mykerawang.local` account has no password and cannot be logged into.
- Attendance: the QR token lives 20 s, drawn every 10 s. The QR is a URL so the
  phone camera works as a fallback.
- Form section headers truncate rather than overflow (long titles on narrow phones).

## Open work

**Launch ops** (see `docs/launch-checklist.md`):
rotate the DB password; one attendance dry run before promising merit;
captcha (remember it covers sign-in too); invite the first club.

**Bugs still open:**
- Edit button appears for admins/owners on a club's announcement — decide whether
  to restrict Edit to the author/club officer and leave admins with hide/remove.
- Announcement detail app bar says "Thread" (it is the generic post title).
- Browser back after Google sign-in returns to the account chooser.
- Announcement categories are a fixed set of five.

**Features queued:**
- Per-post "post officially" toggle (owner currently always looks official).
- Event PIC field + tag clubs/people as collaborators.
- Registration toggle on the event page after publishing, with instant QR and a
  "add a form?" prompt.
- **Form builder** (the big one): `event_forms` / `form_fields` / `form_responses`,
  CSV import, public form page, linked to the attendance QR. Needs a design pass:
  per-event vs reusable, response privacy, require RSVP before answering.
- Recurring announcements (needs pg_cron or materialise-on-read).
- Shared-link thumbnails need per-URL OG tags (SPA limitation; needs a function
  or prerender).

## Suggested next session

Merge the branch, then either the three small bugs above (an hour) or start the
form builder with a design document before any UI.
