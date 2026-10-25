# Handover — MYKerawang web

Written 2026-10-25. Everything below was verified, not remembered. Updated at
the end of the second session that day (PR #8 and #9 merged, two bugs fixed,
1.7.7 released).

## Where things stand

| | |
|---|---|
| Repo | `C:\src\project\Flutter\MYKerawang-web` |
| Worktree used | `.deepseek/worktrees/clubs-admin` (the one to reopen) |
| Branch | `deepseek/clubs-admin` — level with `origin/main` |
| Last merge | PR #9 → `6da73ad` (1.7.7); before it PR #8 → `e491899` (1.7.2–1.7.6) |
| Live | https://mykerawang-app.web.app — build `202610250823`, version **1.7.7** |
| Tests | 467 Flutter tests green; migration suites: moderation (all but 2 pre-existing), clubs 87, verification 13, forms 54; analyzer has 18 info/warning findings, no errors |
| Latest migration | `20261026007100_event_forms.sql` — **written and tested, not applied to live**; before it `20261026006100_club_recruitment.sql` (live) |

`main`, the branch and the live site are all at 1.7.7 (build `202610250823`).

## What changed this session

- **Merged** the branch twice: PR #8 (`e491899`, 1.7.2–1.7.6) and PR #9
  (`6da73ad`, 1.7.7), so `main` matches what is running.
- **Announcement Edit/Delete are the author's alone** (was: admins and owners
  too). `update_my_post` and `delete_my_post` both require
  `user_id = auth.uid()`, so the buttons were dead for everyone else — they
  only ever produced "not the author of this post". `AnnouncementDetailHead`
  now takes `mine` instead of `canManage`; the post card's own menu already
  did this. Admins still moderate other people's announcements, from the
  console (reports → hide/remove), which is where those rights live.
  Regression test: `test/announcement_detail_test.dart`.
- **The detail app bar shows the post's headline**, not the generic "Thread"
  (`postPageTitle` in `lib/utils/announcement_rules.dart`, unit-tested; falls
  back to "Announcement" or "Thread" when there is no headline).
- **Google sign-in leaves no history entry** (see below — unverified on a
  real browser).
- **Released 1.7.7** (build `202610250823`), then **designed and built phase 1 of
  the KI event reports**: `docs/ki-event-reports.md`, `docs/ki-template-fields.csv`
  (the survey as data), `20261026007100_event_forms.sql` and a 44-assertion test.
  The design took three passes — the first got the requirement wrong (a builder
  with a KI example), the owner corrected it (the KI report *is* the requirement),
  and the third is grounded in the two real documents the owner supplied. The
  owner then corrected again: templates are only **options**, picked and **edited
  in a simple editor**, with CSV as another way to fill that editor.

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
| Announcements | `create_announcement_screen.dart`, `lib/widgets/announcement_view.dart`, `lib/services/announcement_service.dart`, `lib/utils/announcement_rules.dart` |
| Categories | `lib/utils/categories.dart` (seeds), `lib/services/category_service.dart`, `lib/widgets/category_picker.dart` |
| Moderation | `lib/services/moderation_service.dart`, `lib/utils/moderation_logic.dart`, `lib/widgets/moderation_ui.dart` |
| Navigation / back | `lib/router.dart`, `lib/utils/app_nav.dart`, `lib/utils/browser_history_{web,stub}.dart` |
| Event forms / KI report | `supabase/migrations/20261026007100_event_forms.sql`, `lib/services/form_service.dart`, `lib/screens/events/form_editor_screen.dart`, `lib/utils/form_rules.dart`, `lib/l10n/form_strings.dart` |

## How to work

```powershell
cd C:\src\project\Flutter\MYKerawang-web\.deepseek\worktrees\clubs-admin
flutter analyze --no-pub
flutter test

# migrations (need PGlite once)
cd supabase/tests/moderation; npm i --no-save @electric-sql/pglite@0.2.17
node moderation_test.mjs ../../../     # applies every migration twice
# The other tests import pglite directly, and ESM resolves from the TEST FILE's
# folder, so a copy must exist one level up. One junction, done once:
#   New-Item -ItemType Junction -Path supabase/tests/node_modules `
#     -Target (Resolve-Path supabase/tests/moderation/node_modules)
cd supabase/tests
node clubs/clubs_test.mjs ../..        # (this command never worked as documented
node verification/verification_test.mjs ../..   #  until the junction existed)
node forms/forms_test.mjs ../..        # event forms: template, editor, S1/S2/S3

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
- A club officer **cannot** edit an announcement they did not write — the RPC is
  author-only. If the product wants officers to edit club announcements, that is
  a migration (`update_my_post` would need an officer branch), not a UI change.
- supabase_flutter hardcodes `webOnlyWindowName: '_self'` for OAuth, so it always
  *pushes* a history entry. `signInWithGoogle` now builds the same URL with
  `getOAuthSignInUrl` and calls `replaceLocationForOAuth` (push a spare entry,
  then `location.replace`) so Google never survives in the back stack. Web-only;
  the stub returns false on mobile and the library path runs as before.
- **The migration tests never ran as documented.** PGlite was installed only in
  `supabase/tests/moderation/node_modules`, but Node resolves a bare import from
  the *test file's* folder, so `node ../clubs/clubs_test.mjs` could not find it.
  Fixed with one junction at `supabase/tests/node_modules` (see How to work);
  `node_modules/` is now in `.gitignore`. With it, clubs (87 assertions) and
  verification (13) run again — they had been silently unrunnable.
- The PGlite stub's `event_participants` has **no `ON DELETE CASCADE`**, so a test
  that deletes an event must clear participants first — otherwise the FK blocks
  it and the failure looks like it belongs to the migration under test.
- **`app_strings.save` is `"SAVE"` and `cancel` is `"Cancel"`** — widget tests
  that tap a dialog button must use the exact case (`find.widgetWithText(
  FilledButton, 'SAVE')`), or the finder matches nothing and the failure looks
  like a broken screen.
- A `DropdownButtonFormField` needs `isExpanded: true` inside a narrow dialog,
  and a bare `DropdownButton` with `isExpanded` needs a bounded width
  (`Expanded`) — otherwise the dialog overflows on a 375 px phone.
- Do not rewrite a Dart file with PowerShell `-replace` + `Set-Content`: it
  mangled an en-dash into `â€“` in `form_editor_screen.dart`, twice. Use the
  edit tool.
- Two `moderation_test.mjs` assertions ("two reports → one open case" and
  "priority category hidden on first report") fail **without** the forms
  migration too. They are pre-existing; don't chase them while testing forms.

## Open work

**Launch ops** (see `docs/launch-checklist.md`):
rotate the DB password; one attendance dry run before promising merit;
captcha (remember it covers sign-in too — **and it will interact with the OAuth
launch above**, since the captcha token rides in `queryParams`); invite the
first club.

**Deployed on 1.7.7 but not verified on a real browser yet:** The Google sign-in
history fix. There is no widget test for it (`location` is not reachable from a
test), so check it on the live build, in this order:

1. sign in with Google, then press the browser's Back — it must **not** show
   Google's account chooser;
2. sign out, start Google sign-in again, press Back **on Google's page** —
   it must land back on `/login`;
3. sign in from a shared post link (`/post/…` → "Log in to comment") and
   confirm `?from=` still returns you to the post.

If sign-in breaks, `git revert` the login commit — it is one file plus a helper,
and the old `signInWithOAuth` path still compiles.

**Bugs still open:**
- Announcement categories are a fixed set of five.

**Features queued:**
- Per-post "post officially" toggle (owner currently always looks official).
- Event PIC field + tag clubs/people as collaborators.
- Registration toggle on the event page after publishing, with instant QR and a
  "add a form?" prompt.
- **KI event reports.** Phase 1 (server) is **built and tested**; see
  `docs/ki-event-reports.md`, with the survey itself as data in
  `docs/ki-template-fields.csv` (28 rows, generated from the owner's Google-Form
  export). Files: `supabase/migrations/20261026007100_event_forms.sql` and
  `supabase/tests/forms/forms_test.mjs`.
  The requirement, as corrected by the owner: every club hands in a Kemahiran
  Insaniah report after **every** event, under L2-HEP/PKP/21, within 14 days, and
  the field set is already fixed — so a **template is a starting point** the
  organiser picks, then **edits in a deliberately simple editor** (one list of
  fields; no drag-and-drop, no sections). CSV/paste is the other way to get
  questions in; it fills the same editor, which is why there is no server-side
  template authoring.
  The app owns the *survey* and the three analyses (**S1 Peserta**,
  **S2 Penganjur**, **S3 feedback** — the "analisa Excel" the report asks for),
  not the report PDF. Template fields carry `ki_code` / `analysis` tags so the
  averages are computable whatever the wording; ratings are a first-class kind;
  students answer for themselves; responses are private to organiser + club
  officers + admins; the form is **optional to the QR** (`after_checkin`,
  default off).
  Next: **phase 3, the answer page** — a published form can be filled by
  students. Then phase 4, the S1/S2/S3 screen and CSV export.
  The migration is **not applied to live**; apply it when the answer page needs
  it. Five design questions remain at the end of the doc; the two that matter are
  whether MPP's version ships as a second template, and whether the matric must
  stay editable (**4 of 13 respondents used Gmail**).
- **KI editor (phase 2) is built**: `/event/:id/form/edit`, opened from a
  "KI report" button on the event page for the organiser. Start chooser
  (template / blank / pasted list), one plain list of questions with label, kind,
  required, options, scale and analysis tag, up/down/delete, save and publish.
  `save_event_form` reloads after saving so new questions get their ids — without
  that, every save would insert another copy of each new question.
- Recurring announcements (needs pg_cron or materialise-on-read).
- Shared-link thumbnails need per-URL OG tags (SPA limitation; needs a function
  or prerender).

## Suggested next session

1. Run the three Google sign-in checks above on the live 1.7.7. If any fails,
   revert the login commit and redeploy before anything else.
2. Build **phase 3 of the KI reports: the answer page** (`/event/:id/form`) —
   render each field kind, submit through `submit_form_response`, show the
   "you answered" state. Then phase 4, the S1/S2/S3 screen and CSV. Apply
   `20261026007100_event_forms.sql` to live when the answer page is ready to try,
   not before. Or the captcha work first — that is the last code item before
   inviting a club, and it needs a hCaptcha/Turnstile site key from the owner.
