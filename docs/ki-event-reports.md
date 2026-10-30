# KI event reports: design

Status: **phases 1–4 shipped (server, editor, answer page, analysis), no
`after_checkin` prompt yet.** Design written 2026-10-25 against 1.7.7 (`6da73ad`)
and rewritten twice the same day: once after the owner corrected the requirement
(the KI report *is* the job; the builder merely extends it), and once after
reading the two real documents — `BORANG KI QUIZ BAHASA ARAB (Responses).xlsx`
(what a Google Form collected) and `LAPORAN PROGRAM QUIZ BAHASA ARAB.pdf` (what
the club hands in).

- Phase 1 — `supabase/migrations/20261026007100_event_forms.sql`
  (58 assertions in `supabase/tests/forms/forms_test.mjs`).
- Phase 2 — the editor (`form_editor_screen.dart`).
- Phase 3 — the answer page (`event_form_screen.dart`).
- Phase 4 — the analysis screen (`form_responses_screen.dart`) and
  `lib/utils/form_csv.dart`: S1/S2/S3 with their means and `n`, copy-to-clipboard
  tables for the Word report, and the response CSV.

Client tests: 15 rules, 8 CSV/TSV, 6 editor, 7 answer, 4 analysis. **The
migration is not applied to the live project yet.**

## What the paperwork actually is

Every student activity ends with a report pack for HEP, under Borang
**L2-HEP/PKP/21 (Pindaan 2013)**, due **within 14 days** of the activity. The PDF
is that pack. It has three layers:

| Layer | What it is | Who produces it |
|---|---|---|
| The report form | MAKLUMAT AKTIVITI (club, activity, date, place, level, category, participant count), **1.0 Hasil Aktiviti** (5+ learning outcomes in prose), **2.0 KI matrix** (which of KI1–KI7 the activity involved, ticked for Penganjur and for Peserta), **3.3 Cadangan Penambah Baikan**, **4.0 Penilaian Keberkesanan** (level, VIP, media, achievement) | The club writes it; 4.0 is for the *Pensyarah/Pegawai Pengiring* |
| The three analyses | 3.1 and 3.2 point at **"analisa Excel S1 – PESERTA", "S2 – PENGANJUR", "S3 – PESERTA"** (forms L3/L4/L5-HEP/PKP/22–24) | Computed from survey responses |
| The attachments | Lampiran 1 timetable, 2 budget, 3 screenshots of the Google Form, 4 participant list grouped by class (NAMA / NOM MATRIK / PROGRAM) | Club + survey |

The Google Form in the workbook is the **data collection** step, and it is what
this app replaces. Its 26 columns:

- identity — Timestamp, Email, **Nama Penuh**, **Nombor Matrik**, **Pilih**
  (Peserta / Penganjur);
- **seven KI self-ratings before** the activity (1–5) — **8 answers**: the
  participants answered this part, the organisers did not;
- **the same seven after** the activity (1–5) — **13 answers**: everyone;
- **six feedback items** (1–5) — 13 answers — Pengisian Program, Persembahan
  multimedia, Lokasi, Aturcara dan Pengendalian, Mutu makanan dan minuman,
  Keseluruhan mutu;
- one free-text **Cadangan / maklum balas**.

(The class codes and "adakah anda orang Melayu" seen in Lampiran 3 of the PDF
belong to the *quiz* form, not this feedback form; they are not part of the
template.)

The seven KI elements are fixed and numbered in the report itself:

| Code | Element (as printed on the form) |
|---|---|
| KI1 | Kemahiran Berkomunikasi |
| KI2 | Pemikiran Kritis dan Kemahiran Menyelesaikan Masalah |
| KI3 | Kemahiran Kerja Berpasukan |
| KI4 | Pembelajaran Berterusan dan Pengurusan Maklumat |
| KI5 | Kemahiran Keusahawanan |
| KI6 | Etika dan Moral Profesional |
| KI7 | Kemahiran Kepimpinan |

So the deliverable is not "a form builder" and not "a printable PDF of the whole
report". It is: **collect the survey, then produce S1, S2 and S3 as numbers.**

**`docs/ki-template-fields.csv` is that survey, as data** — 28 rows (24 questions,
4 section headings) with the same order, kinds, scales and `ki_pre`/`ki_post`/
`feedback` tags the analysis needs. It was generated from the workbook, not typed
by hand, so it cannot drift from the source. It is both the seed for phase 1 and
the worked example of the paste-import format.

Two things the workbook itself shows, which the design has to respect:

- the source numbers its KI questions in a different order from the report's
  KI1–KI7 matrix and numbers two of them "6)" — mapping by **name** is the only
  safe way, which is why fields carry `ki_code` rather than relying on labels;
- **4 of the 13 respondents used a personal Gmail**, not a student address, so a
  matric number cannot always be derived from the email.

## Scope

| | |
|---|---|
| **MVP** | The survey end to end, and the three analyses: create the survey on the event (from a template, from a pasted question list, or blank), edit it in a simple editor, publish, students answer, the organiser sees S1/S2/S3 and exports the CSV. |
| **Needed early** | The **editor**. A template is only a starting point — "they will select that and edit". There is no path where a club hands in a form it did not at least look at. |
| **Extension** | A richer builder: per-field help text UI, sections, conditional fields, duplicate. |
| **Out of scope** | The report prose (1.0 outcomes, 3.3 suggestions, 4.0 effectiveness), the budget, the timetable, the participant-list formatting. The club keeps producing those in Word as it does now. |

## Decisions

| Topic | Decision | Why |
|---|---|---|
| **The survey is the unit, not the report** | The app owns the questionnaire, the responses and the three analyses. The PDF stays with the club. | The report is half prose and half an officer's signature; reproducing it would be a document generator, not a feature. The part that hurts — collating 13 spreadsheets by hand — is exactly the survey. |
| **Templates are data, and multiple** | `form_templates` + fields, seeded with the club's KI version now; **another version is a new template row, not a release**. | The owner confirmed versions differ (MPP's is extended). If adding a version needed a deploy, the feature would be useless within a club year. |
| **The app offers options, not policy** | Three ways in — **blank**, **a template**, or **a pasted question list (CSV)** — and all three land in the same editor. The shipped templates are starting points, never a fixed form. | "We only just give them options. If they want to use templates, they select that and edit." A club that must hand in a slightly different version is the normal case, not the exception. |
| **A template is copied, then edited** | Picking a template copies its fields into the event's form; every subsequent edit is to that copy. | Nothing a club edits can change the template other clubs see, and a correction to a template cannot rewrite a form that already has answers. |
| **The editor is plain, but nothing is hidden** | One list, one row per question, and every setting that row has is on the row: label, kind, counting tag, KI element, scale, required, options. Reorder by drag or by arrows. No sections-as-nesting, no conditional fields. | "The editor just simple one" — but the owner rejected the first version's dialogs: *"hidden options is tiring … someone who edits should know how the field was handled in first glance."* Simple means few concepts, not concealed ones. |
| **Fields carry an analysis tag** | Each field may be tagged `analysis` = `ki_pre` / `ki_post` / `feedback`, plus `ki_code` 1–7 for the KI ones — and the tag is **editable in the editor**, on the row itself. | This is what makes S1/S2/S3 computable no matter how a version words or orders its questions. Without tags the app would guess from labels — and the source form already has two questions numbered "6)". |
| **Ratings are a first-class field kind** | `kind = 'rating'`, with `options {"min":1,"max":5}`. Not a bare number field. | The analysis is means of 1–5 ratings; a generic number field would let 7 and 0 into the average. |
| **Who answers** | **Students answer for themselves** (owner's decision). The role — Peserta or Penganjur — is **derived**: club officer or event committee → Penganjur, otherwise Peserta, correctable by the respondent. | The Google Form asked, and 5 of 13 respondents said Penganjur. Deriving removes a question and a class of error; the overview still needs an override because a committee member may attend as a participant. |
| **Three analyses, one definition** | `form_analysis(p_form_id)` returns S1/S2/S3 computed server-side; the screen and the CSV both read it. | "They will process the CSV themselves, but we can count the average rating ourselves too" — the averages must agree with the export, so they are computed once. |
| **Response privacy** | Organiser, club officers of the owning club, admins. A student reads only their own. No `_public` view. | Responses are PII: full names and matric numbers. Same reasoning that kept `event_contacts` off the guest-readable `events` table. |
| **Attendance stays separate** | `after_checkin` defaults off; the survey never blocks check-in and check-in never requires it. | The owner: "forms also optional for the qr, not explicitly embedded with attendance". |
| **Due date is the report's** | The event page shows "KI report due `<end + 14 days>`" until a survey exists. | The 14-day deadline is printed on the checklist (PERINGATAN). It is the one piece of paperwork timing worth surfacing. |

## Schema

```sql
-- 20261026007100_event_forms.sql (next free number)

create table if not exists public.form_templates (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,          -- 'ki', 'ki-mpp', ...
  name       text not null,                 -- "Borang KI (Kelab Bahasa Arab)"
  name_ms    text,
  intro      text,
  source     text not null default 'official'
             check (source in ('official', 'club')),
  active     boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.form_template_fields (
  id          uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.form_templates(id) on delete cascade,
  kind        text not null check (kind in
              ('short_text','long_text','rating','single_choice','multi_choice',
               'number','date','email','phone','student_id','consent','heading')),
  label       text not null,
  help        text,
  required    boolean not null default false,
  options     jsonb,          -- choices: {"choices":["Peserta","Penganjur"]}
                              -- rating:  {"min":1,"max":5}
  analysis    text check (analysis in ('ki_pre','ki_post','feedback')),
  ki_code     int  check (ki_code between 1 and 7),
  sort        int not null default 0,
  -- a KI tag belongs on a KI field, and only on one
  check ((analysis in ('ki_pre','ki_post')) = (ki_code is not null)),
  check ((kind in ('single_choice','multi_choice')) = (options is not null))
);
```

`event_forms` gains `template_id`, `after_checkin` (default false) and
`require_rsvp` (default false); it is otherwise as in the previous draft.
`form_fields` is the event's **copy** of the template fields, carrying the same
`analysis` / `ki_code` tags, so a later template edit cannot rewrite a past
analysis.

`form_responses` gains `role text check (role in ('peserta','penganjur'))` and
`entered_by uuid` (organiser entering on someone's behalf). One row per
`(form_id, user_id)`, upserted on re-submit.

## Server API

House pattern: `security definer`, `set search_path = public`, explicit
`auth.uid()` checks, `NS:code` errors.

| Function | Who | Does |
|---|---|---|
| `form_templates_list()` | signed in | Active templates for the "start from" chooser. |
| `create_form_from_template(p_event_id, p_template_slug)` | organiser, `can_act_as_club`, admin | Creates a **draft** form with the template's fields copied in, then opens it in the editor. |
| **`save_event_form(p_form_id, p_form jsonb, p_fields jsonb)`** | same | The **editor's** single write: title/intro/deadline/toggles plus the whole field list (add, remove, reorder, relabel, retag). Validates and refuses the changes listed under "Editing a live form". A blank form starts here too, with `p_fields = []`. |
| `publish_form(p_form_id)` / `close_form(p_form_id)` | same | `draft → open → closed`; publish validates the field set and its analysis tags. |
| `form_public(p_form_id)` | anyone incl. guests | Form + fields + the caller's own response + `can_answer` (+ reason). Never anyone else's data. |
| `submit_form_response(p_form_id, p_for_user, p_role, p_answers)` | signed in | The only write: open + deadline + `require_rsvp` + validation, upsert. |
| `form_response_list(p_form_id)` | organiser, `is_club_officer`, admin | Rows + profile + answers, for the table and the CSV. |
| **`form_analysis(p_form_id)`** | same | **S1, S2, S3** — see below. One definition for screen and export. |

There is **no server-side template authoring**. A pasted question list is parsed
on the client into the same `p_fields` payload `save_event_form` already takes, so
CSV import needs no RPC of its own and the editor is the single validation point.
Only admins can change a shipped template, and only by migration.

`submit_form_response` calls `require_verified('form_submit')`; add that
capability to `verification_required` and to the `mod_guard_write` trigger on
`form_responses` (scope `events`, owner `user_id`).

## What S1, S2 and S3 are

Computed over submitted responses, restricted by `role`:

| Analysis | Population | Columns |
|---|---|---|
| **S1 — PESERTA** | role = `peserta` | per KI element (KI1–KI7): n, mean **before**, mean **after**, difference |
| **S2 — PENGANJUR** | role = `penganjur` | per KI element: n, mean **after** (the source form has no "before" for organisers) |
| **S3 — PESERTA** | role = `peserta` | per feedback item: n, mean; plus the free-text answers |

Means are of the 1–5 ratings, rounded to 2 dp, computed **server-side** so the
screen, the CSV and any future export cannot disagree. A null rating is excluded
from that element's `n`, and `n` is reported beside every mean — an average of 2
answers is not an average of 13.

## Response validation

`lib/utils/form_rules.dart`, pure and unit-tested, mirrored by the server (the
server is authoritative; its message is shown as-is through `describeWriteError`):

| Rule | Value |
|---|---|
| Fields per form | 40 max (a KI version has ~26) |
| Label | 1–200 chars |
| Rating | `min`/`max` from options, both 1–10, `min < max`; answer an integer in range |
| Choice | answer must be one of the field's option values |
| Short text | ≤ 200; long text ≤ 2000 |
| Required | present and non-empty; a heading is never required |
| Analysis tags | `ki_code` only on `ki_pre` / `ki_post`, exactly one per field; `feedback` carries none; at most 7 `ki_pre` and 7 `ki_post` per template |

### Text, cleaned and capped on the way in

`lib/utils/text_rules.dart` is the client half of that contract: the inputs
enforce the cap while typing, so nobody types 3,000 characters and is told at
the end. Label 200, title 120, introduction 500, help 300, one choice 60 (at
most 40 choices). `cleanLine` drops control characters, collapses whitespace
and trims — a pasted multi-line label cannot become a three-line heading;
`cleanBlock` keeps paragraphs for the introduction; `cleanChoices` drops
blanks and duplicates. Both screens and the save path use the same functions.

### What leaves the app is a spreadsheet

Answers are exported as CSV and the S1/S2/S3 tables are copied as TSV, both
opened in Excel and pasted into Word. A cell starting with `=`, `+`, `-` or `@`
is a formula there, so every exported cell goes through `csvSafe`: a leading
apostrophe forces text, except for plain numbers (`-5` stays a number). This
covers the response CSV, the attendance CSV and the copied tables. It is the
only injection surface that matters here — Flutter draws text, it does not
render markup, so answers cannot script the page.

**Not** done on the server: title, introduction, help text and the choice
strings themselves are stored as sent (the RPC only caps the label and the
answers). The write path is organiser-only, and the client caps all of them;
enforcing it against a crafted RPC call would mean another `form_check_field`
migration.

## Attendance link: optional

`checkin_with_token` is untouched. When `after_checkin` is on **and** a survey is
open, the success screen offers it as a skippable next step. Nothing gates.

## The editor — what "simple" means

Simpler than it was, not smaller in what it shows. The first version put each
question's settings behind a dialog; the owner's verdict was "hidden options is
tiring — someone who edits should know how the field was handled in first
glance". The editor is now a **ledger**: every setting a question has sits on
its own row, in the same place on every row.

One screen, one list. Opening it asks **what to start from**: blank, a shipped
template, or a pasted question list. All three produce the same editable list.

Each row, left to right:

| Where | Control | Notes |
|---|---|---|
| label line | Label | the question, 1–200 chars, edited in place |
| under the label | Help text | only when it has one, or after "Add help" |
| control strip | Kind | short / long text, rating, single choice, multi choice, number, date, email, phone, matric, consent, heading |
| control strip | Analysis | ratings only: none / KI before / KI after / feedback, tinted purple / gold / teal |
| control strip | KI element | only for a KI tag; defaults to the first free element in that phase |
| control strip | Scale | ratings only, 1–10 |
| control strip | Required | a pill that reads "Required" or "Optional" |
| row edge | Drag / Up / Down / Duplicate / Delete | one group at the card's border: drag the handle, or use the arrows |

A row that is **not** counted in the report says so — a "Not counted" chip in the
place the analysis pill would be — instead of hiding the control. That was the
core complaint: absence read as "maybe there is a setting I have not found".

On a wide window the right rail shows what the form *measures* — the KI1–KI7
before/after grid, the feedback count, S1 pairs complete — and the publish
checks, all recomputed as you type. On a phone that collapses to one line
("Ready to publish") or the failing checks.

Not in it: sections as a nesting level (headings are rows, and the lane they
open is a colour), conditional fields, live preview. Duplicate and drag are in;
the published form is still the preview.

Pasting a question list is the only bulk path: one question per line, with the
same columns as `docs/ki-template-fields.csv` (`kind, label, required, options,
analysis, ki_code`). It fills the list and stops — the editor is where any of it
gets fixed, which is why there is no server-side import.

Once the form has answers, the editor shows those rows read-only rather than
hiding them, and disables the destructions listed under "Editing a live form".

## Client plan

| Piece | File |
|---|---|
| Service | `lib/services/form_service.dart` |
| Start-from chooser + field editor | `lib/screens/events/form_editor_screen.dart` |
| Answer page | `lib/screens/events/event_form_screen.dart` |
| Responses + S1/S2/S3 + CSV | `lib/screens/events/form_responses_screen.dart` |
| KI before/after bars | `lib/widgets/ki_chart.dart` (drawn, no chart package) |
| Per-kind inputs | `lib/widgets/form_field_input.dart` |
| Pure rules + CSV/paste parsing | `lib/utils/form_rules.dart` |
| Copy (en/ms, ja→en) | `lib/l10n/form_strings.dart` |

Routes `/event/:id/form/edit` (organiser), `/event/:id/form` (answer) and
`/event/:id/form/responses`. Add the answer route to `backFallbackFor` (→ event
page) and to the guest paths.

The analysis screen is the point of the feature: three compact tables (S1, S2, S3)
plus the free-text list, each with a copy button, because the numbers get typed
into the Word report by hand.

## Phases

1. **Schema + RPCs + `form_analysis` + the seeded KI template + `forms_test.mjs`.**
   No UI. **Done** — `20261026007100_event_forms.sql` (five tables, the 28-row
   seeded template, `save_event_form`, publish/close, `form_public`,
   `submit_form_response`, `form_response_list`, `form_analysis`) and
   `supabase/tests/forms/forms_test.mjs` (54 assertions, migrations applied
   twice). **Not applied to the live project**, because nothing public calls it.
2. **The editor** (start chooser, field list, save, publish) — a form can be
   built, from nothing or from a template, and looked at. **Done**:
   `/event/:id/form/edit`, reached from a "KI report" button on the event page
   for the organiser. Server-side it also needed `create_blank_form()` (every
   write targets a form id) and `event_form_summary()` (the event page's label).
   Tests: `test/form_rules_test.dart` (15) and `test/form_editor_test.dart` (6,
   against a fake `FormService`).
3. **The answer page.** A published form can be filled. **Done**:
   `/event/:id/form`, reached from a "Program form" button on the event page
   whenever the event has an open form. Renders every kind, pre-fills the matric
   from a student address, shows an existing answer with "Update answers", and
   gives guests the sign-in bar rather than a blank rejection. Needed one more
   RPC: `event_open_form()` — the manager-only summary is no use to a student.
4. **S1/S2/S3 screen + CSV export.** **Done**:
   `/event/:id/form/responses`, reached from the list icon in the editor's app
   bar. Three tables (S1 per KI element with before/after and the change, S2 the
   organiser after-state, S3 feedback), each with a copy button that yields
   tab-separated numbers ready to paste into the Word report; a bar per mean with
   its `n`; the free-text suggestions with their authors; the respondent list;
   and the CSV download. `lib/utils/form_csv.dart` builds both artefacts, pure
   and tested, so the CSV columns and the copied tables cannot drift from the
   fields.
5. **`after_checkin` prompt** — **done**: the check-in success screen offers the
   form once when the open form has `after_checkin` and the caller has not
   answered yet; the organiser turns it on from Manage event
   (`set_form_after_checkin`) or in the editor. Then the richer builder.

## Tests

`supabase/tests/forms/forms_test.mjs` (house harness, migrations applied twice).
Run it from `supabase/tests` — `node forms/forms_test.mjs ../..` — see the
handover for why that directory now needs its own `node_modules`:

1. the seeded KI template has 7 `ki_pre`, 7 `ki_post`, 6 `feedback` fields, KI1–7;
2. creating from a template **copies** fields; editing the template afterwards
   changes neither the form nor its analysis;
3. a student, a guest, and an officer of another club cannot create or publish;
4. a student cannot read another's response; a same-club officer can;
5. submit refuses: closed, missing required, out-of-range rating (0, 6, 3.5), an
   option value not in the field, an unknown field id;
6. re-submitting upserts one row; a role correction is accepted;
7. **`form_analysis` means**: fixtures where S1's KI2-before is 4 and 5 → mean
   4.5, and `n` counts only non-null answers;
8. S1 excludes `penganjur` rows and S2 excludes `peserta` rows;
9. a template row with a bad tag (ki_code on a feedback field) is refused;
10. deleting the event removes forms, fields and responses; account deletion
    removes that user's responses.

Widget tests: rating widget, required errors, guest sees read-only, the S1 table
renders the fixture means, CSV header order.

## Honest limits

- **No PDF of the report.** The club still assembles L2-HEP/PKP/21 in Word.
- **No automatic participant list by class.** The class code is an answer, not a
  profile field; grouping the Lampiran 4 list is the club's job.
- **No file uploads, no branching, no anonymous answers.**
- **No merit.** Merit still comes from attendance.
- **Ratings only.** A version that asks Yes/No or free text per KI element falls
  outside S1/S2 — the paste-import validates this and says so.

## Open questions

1. **How many starting options ship?** This design ships **one** (your Bahasa
   Arab KI form, from the CSV) plus blank and paste — on the reasoning that a
   club that wants MPP's version pastes it in and edits. Say if MPP's should be a
   second shipped option instead; it is one more entry in the seed, no code.
2. **Is `Pilih` (Peserta / Penganjur) derived or asked?** This design derives it
   from club office and lets the respondent correct it; the Google Form asked.
3. **Nombor Matrik** — the workbook exports it as a float (`2023837334.0`), a
   spreadsheet artifact. The app pre-fills it from the verified student email
   (the part before `@`), but **4 of 13 respondents signed in with Gmail**, so it
   must stay editable rather than read-only. Confirm that is acceptable.
4. **The 14-day nag** — show "report due" on past events, or keep quiet?
5. **Do organisers need a "before" rating too?** S2 as printed shows only the
   after-state, which matches the data (only 8 of 13 answered the "before" part).
   If MPP's version has both, the schema allows it (`ki_pre` fields for
   organisers) but the seeded KI template would not include them.
