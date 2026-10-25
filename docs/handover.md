# Handover — MYKerawang web

Written 2026-10-25 at the end of a long session, for the next one to start cold.
Everything below was checked against the repo, the live site and the database, not
remembered.

## Where things stand

| | |
|---|---|
| Repo | `C:\src\project\Flutter\MYKerawang-web` |
| Worktree to reopen | `.deepseek/worktrees/clubs-admin` |
| Branch | `deepseek/clubs-admin` — clean, pushed, merged into `main` as **PR #10** |
| `origin/main` | **1.8.3** — level with the branch and with production (this closed the gap left open since PR #9) |
| Live | https://mykerawang-app.web.app — build `202610251557`, version **1.8.3** |
| Tests | **516** Flutter tests green; analyzer 17 info/warnings, **no errors** |
| Migrations | **all applied to live**, nothing pending (see the table below) |
| Supabase | project `zxjuqpqzyzmegdjttzyz` |

Production, `main` and the branch are all at 1.8.3; carry on from the branch.

## First thing to ask the owner

The owner reported "not fix the edit/create event page" and I could not tell which
element they meant. **Ask for the specific thing** (a screenshot with it circled)
before changing that page again. What is *already* fixed there: the attendance
toggle is gone, contact channels are rows with their own icons, the cooperation
field takes mentions and suggests clubs, pictures are optional, categories are an
autocomplete field, and the description uses the announcement's light markup.

## Migrations, in order (all applied)

| Migration | What it does |
|---|---|
| `20261026007100_event_forms.sql` | The KI report survey: templates, forms, responses, `form_analysis` (S1/S2/S3), `event_open_form`, `event_form_summary`, `create_blank_form` |
| `20261026008100_event_links_pic.sql` | `events.action_links` (max 2 buttons, guarded by a trigger) and `events.pic` |
| `20261026009100_fix_checkin_token.sql` | **The attendance fix.** `event_checkin_token()` had a `returns table (…, expires_at)` output column and a bare `expires_at` in its cleanup `DELETE` → `42702 ambiguous`, so the rotating code never worked at all |
| `20261026010100_form_after_checkin.sql` | `set_form_after_checkin(form, bool)` — the "ask the KI form after check-in" switch |
| `20261026011100_checkin_does_not_join.sql` | A check-in no longer inserts into `event_participants`. Scanning used to inflate the event's places count — one number meaning two things |

Seeded data: `supabase/seed/2026-10-25_ki_test_event.sql` created **Malam Ujian KI**
(owner-owned, attendance on, a bulleted description, two buttons, a PIC) — the
event to test the whole report loop on. Re-runnable.

## What exists now (built between 1.7.2 and 1.8.3)

**Forms / KI report** — read `docs/ki-event-reports.md` first; it is the design and
it is grounded in the club's real documents. The short version:

- The app owns the **survey and its analysis**, not the HEP report PDF.
- A template is a **starting point**: pick it (28 rows from the club's Google Form,
  `docs/ki-template-fields.csv`), then edit in a deliberately plain editor. Blank
  and "paste a question list" are the other two ways in.
- Fields carry `analysis` (`ki_pre` / `ki_post` / `feedback`) and `ki_code` (1–7),
  because the source form numbers its KI questions out of order and twice as "6)".
- Answers: one row per person, role derived from the template's own role question.
- The organiser's analysis screen shows **S1** (participants, before/after per KI
  element, with the change), **S2** (organisers, after), **S3** (feedback) — every
  mean with its `n` — plus copy buttons (tab-separated) for the Word report and a
  CSV of all responses.
- Screens: `/event/:id/form/edit` (editor), `/event/:id/form` (answer),
  `/event/:id/form/responses` (analysis).

**Attendance flow** (`lib/screens/events/attendance_live_screen.dart`):

1. The event page's action for the organiser is **Take attendance**; it asks one
   question — *add the KI report?* — which writes `after_checkin`.
2. Start opens the door: rotating code (20 s token, redrawn every 10 s), a live
   count, the **last person in** (given name only, cut at bin/binti), and one
   **End attendance** button.
3. Ending shows an animated summary with **attendance CSV**, **KI CSV**, or both as
   two separate files.
4. A student who checks in is offered the KI form once, when it was part of the
   session.

**Event page / composer**

- The event page leads with the door for its owner; everything else is behind
  **Manage event** (Edit, KI report, Close registration). Contact channels are
  buttons, not a sheet.
- The check-in button appears to non-organisers only inside the window
  (`lib/utils/event_live.dart`: 15 min before the start → the end), which also
  drives a "Check-in is open" banner and a chip on the event card.
- Composer: announcement-style markup in the description, category **autocomplete**,
  up to two **buttons with links**, **person in charge**, **cooperation** with
  `@people` mentions *and* club-name suggestions (clubs have a handle but **no
  profile**, so `@club` notifies nobody — names are inserted instead).

## Infrastructure

- **Supabase** project `zxjuqpqzyzmegdjttzyz`. The app uses the **publishable** key
  in `lib/main.dart`; the legacy JWT keys are disabled and the old leaked
  `service_role` is dead. A privileged key, if ever needed, comes from
  `--dart-define=SUPABASE_SECRET_KEY=…` and is never committed.
- **Auth**: email + Google. Confirm email on, anonymous sign-ins off. SMTP through
  **Resend** on `kerawang.my`. Google sign-in launches with `getOAuthSignInUrl` +
  `replaceLocationForOAuth` so the account chooser does not survive in history.
- **Hosting**: Firebase `mykerawang-app`. A deploy stamps a build id into
  `build.json`, `index.html` and `flutter_bootstrap.js`.
- **No Supabase CLI, no `psql`, no DB password here.** Migrations are applied by
  pasting the file into
  https://supabase.com/dashboard/project/zxjuqpqzyzmegdjttzyz/sql/new and pressing
  Run. Every migration in this repo is re-runnable.

## How to work

```powershell
cd C:\src\project\Flutter\MYKerawang-web\.deepseek\worktrees\clubs-admin
flutter analyze --no-pub
flutter test

# migration suites (PGlite). Install once:
cd supabase/tests/moderation; npm i --no-save @electric-sql/pglite@0.2.17
node moderation_test.mjs ../../../         # applies every migration twice
# The other suites import pglite directly and ESM resolves from the TEST FILE's
# folder, so a copy must exist one level up. One junction, done once:
#   New-Item -ItemType Junction -Path supabase/tests/node_modules `
#     -Target (Resolve-Path supabase/tests/moderation/node_modules)
cd supabase/tests
node clubs/clubs_test.mjs ../..            # 87 assertions
node verification/verification_test.mjs ../..
node forms/forms_test.mjs ../..            # 62
node events/events_links_test.mjs ../..    # 10
node events/attendance_flow_test.mjs ../.. # 15

# deploy: bump BOTH places, then build/stamp/deploy
#   pubspec.yaml           version: 1.8.x+N
#   lib/services/update_service.dart   appVersion
flutter build web --release --wasm --pwa-strategy=none --dart-define=BUILD_ID=<yyyyMMddHHmm>
# then write build.json, replace __BUILD_ID__ in index.html + flutter_bootstrap.js,
# copy sw_reset.js over flutter_service_worker.js, and:
firebase deploy --only hosting --project mykerawang-app
# verify from the site, not the log: build.json, version.json, and the id inside
# main.dart.js
```

Two moderation assertions fail **without** any of the new migrations too
("two reports → one open case", "priority category hidden on first report") —
pre-existing, not yours.

## Code map

| Area | Files |
|---|---|
| Events | `lib/screens/event_detail_screen.dart`, `events_screen.dart`, `create_event_screen.dart` |
| Attendance | `events/attendance_live_screen.dart`, `events/checkin_screens.dart`, `lib/utils/attendance_rules.dart`, `lib/utils/event_live.dart` |
| Forms / KI | `lib/services/form_service.dart`, `events/form_editor_screen.dart`, `events/event_form_screen.dart`, `events/form_responses_screen.dart`, `lib/utils/form_rules.dart`, `lib/utils/form_csv.dart`, `lib/l10n/form_strings.dart` |
| Mentions | `lib/widgets/mention_input.dart` (`suggestClubs`) |
| Auth | `lib/screens/login_cubit.dart`, `login_screen.dart`, `lib/router.dart` (`authRedirect`) |
| Navigation | `lib/router.dart`, `lib/utils/app_nav.dart`, `browser_history_{web,stub}.dart` |
| Docs | `docs/ki-event-reports.md`, `docs/mobile-ui-rules.md`, `docs/launch-checklist.md`, `docs/handover.md` |

## Open work

**Waiting on the owner:** what exactly is wrong on the edit/create event page.

**Bugs:**
- Announcement categories are still a fixed set of five.
- The "check-in is open" indicator is missing from the **feed/announcement** cards.
  It exists on the event page and the event card in the Events list.

**Launch ops** (`docs/launch-checklist.md`): rotate the DB password; one real
attendance dry run; **captcha** (needs an hCaptcha/Turnstile site key from the
owner, and it will touch the OAuth launch); a manual backup before inviting clubs.

**Form builder, if it continues:** a paste-import UI for new template versions, a
richer builder, and the open design questions at the end of
`docs/ki-event-reports.md` (MPP's version as a second template; whether the matric
stays editable — 4 of 13 respondents signed in with Gmail).

## Gotchas that cost real time

- **Do not rewrite text files with PowerShell** (`Get-Content -Raw` → `Set-Content`,
  or `-replace`). It double-encoded em-dashes, arrows and middle dots in
  `handover.md` and twice in Dart. Use the edit/write tools. If a file is already
  mangled, `.deepseek/fix_mojibake.py <file>` reverses the common sequences.
- `app_strings.save` is `"SAVE"` (uppercase) and `cancel` is `"Cancel"`. Widget
  tests that tap a dialog button must match the case exactly.
- `DropdownButtonFormField` needs `isExpanded: true` in a narrow dialog; a bare
  `DropdownButton` with it needs a bounded width (`Expanded`), or the dialog
  overflows at 375 px.
- **`returns table (a, b, …)` makes those names PL/pgSQL variables.** An
  unqualified column with the same name raises `42702 … ambiguous` at run time —
  that is how the attendance QR shipped broken and nobody noticed.
- The PGlite stub's `event_participants` now has the `(event_id, user_id)` primary
  key production has; without it `ON CONFLICT DO NOTHING` cannot dedupe and a test
  can insert the same person twice and still pass.
- `supabase_flutter` hardcodes `webOnlyWindowName: '_self'` for OAuth, so it always
  pushes a history entry; hence the custom launch.
- The **owner account cannot delete itself** (`owner_cannot_delete`).
- The `demo@mykerawang.local` account has no password and cannot be logged into.
- Hidden content stays visible to its author; admins do not get a feed pass.
- Generated plugin registrants (`linux/`, `macos/`, `windows/`) get touched by
  builds — `git checkout --` them before committing.
- Student data supplied for design work (`BORANG KI…xlsx`, `LAPORAN…pdf`) is
  git-ignored by name and must never be committed.

## Suggested next session

1. Ask what is wrong on the edit/create page, and fix that specifically.
2. Then either the feed's "check-in is open" indicator (small), or the launch ops
   that are actually blocking a first club: DB password rotation, captcha, a real
   attendance dry run.
