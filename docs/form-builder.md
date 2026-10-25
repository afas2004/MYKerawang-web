# Event forms: design

Status: **design only — no schema, no UI.** Written 2026-10-25 against 1.7.7
(`6da73ad`). Revised the same day after review: this is a **KI report
template**, not a form builder that happens to have a KI example.

## The actual need

Every club must hand in an **event response report** once an event ends — the
Kemahiran Insaniah (KI) report. The fields are fixed and have already been handed
out by the kolej, so the club is not designing anything: it is filling in a known
document, after every event, usually in a hurry.

So the first thing to build is **not** a builder:

1. the organiser opens the finished event and picks **"KI response report"**;
2. the template's fields arrive ready, official wording and order;
3. the report gets filled in and handed over.

A **form builder** — custom fields, reordering, choice options — is what makes
that mechanism useful for other things later. It is the extension, built on the
same tables, not the headline. Nothing in this document should force a club to
build a form in order to hand in its KI report.

## Scope

| | |
|---|---|
| **MVP** | The KI template end to end: create the report from the template on an existing event, fill it in, export it in the shape the kolej accepts. |
| **Extension** | A builder: add/remove/reorder fields, choice options, question-level help. |
| **Convenience** | Import a question list from CSV/paste, so nobody retypes a 40-question form. |
| **Optional** | Show the form after a QR check-in. Off unless the organiser asks for it. |

## Decisions

| Topic | Decision | Why |
|---|---|---|
| **Template first** | A report is created **from a template**, not from a blank field list. Templates are seeded data (`form_templates` + `form_template_fields`), like `content_categories`. | The KI field set is official and already handed out. Seeding it as data means the wording can be corrected without a code change or a release. |
| **Templates are copied, never referenced** | Picking a template **copies** its fields into the event's form. The template row is never edited by a club. | If the app read the template directly, an edit or a later correction would silently change reports already handed in. A copy freezes what was submitted. Admins may still correct the template for *future* reports. |
| **Who the report is about** | One `form_responses` row **per participant**, with `entered_by` recording who typed it (the student, or the organiser on their behalf). | A club hands in a list of people, not a paragraph. Storing the participant as `user_id` is what lets the KI report join to attendance and to the merit export by the same identifiers. Whether the rows are the students' own answers or the organiser's marks is a UI choice on top of the same schema — see Open questions. |
| **Response privacy** | Organiser, club officers of the owning club, and admins read responses. A student reads **only their own**. No `_public` view, no PostgREST path to the table. | Responses are PII (matric numbers, health/dietary notes). Same reasoning that kept `event_contacts` off `events`: the events table is guest-readable, so anything private gets its own table and its own policy. |
| **Import means questions** | CSV/paste import fills the **builder's field list**. Responses are never imported. | The original reason for import was not wanting to retype the questions. Importing loose answers from a spreadsheet would need a person-matching step and would silently create records nobody verified. |
| **Attendance is unrelated** | `event_forms.after_checkin` is **off by default**. The form never blocks check-in, and check-in never requires a form. | The report is a post-event admin duty, not a door policy. Turning it on gives "one more step" for the events that actually want it. |
| **RSVP gate** | `require_rsvp` per form, **default off**. | Off by default, because the KI report is normally filled in after the event and often for people who never joined in the app. Where the organiser needs "only those who registered may answer", it is one toggle. |
| **One open form per event** | Partial unique index `where status = 'open'`. | The check-in hand-off (when enabled) and the event page both need an unambiguous target. |
| **What is public** | The **questions** are readable by anyone (including guests); the **answers** never are. | A shared link has to show what it asks before asking you to sign in. The trade is that the question set is visible — acceptable for an official template. |
| **Storage** | `form_responses.answers jsonb`, keyed by field id, validated on write by one security-definer RPC. | The report is read whole (render, export). Validation is one pass. A row per answer triples the RLS surface for a query nobody needs. |
| **Deletion** | `on delete cascade` from `events` and from `profiles`. | An event that never happened must not leave a table of matric numbers behind; deleting an account takes its answers with it (the `profiles` FK cascade covers it — no change to `delete_my_account`). |

## Schema

```sql
-- 20261026007100_event_forms.sql (next free number)

create table if not exists public.form_templates (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,          -- 'ki', later others
  name       text not null,                 -- "KI response report"
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
              ('short_text','long_text','single_choice','multi_choice',
               'number','date','email','phone','student_id','consent','heading')),
  label       text not null,
  help        text,
  required    boolean not null default false,
  options     jsonb,
  sort        int not null default 0
);

create table if not exists public.event_forms (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events(id) on delete cascade,
  template_id   uuid references public.form_templates(id) on delete set null,
  title         text not null,
  intro         text,
  status        text not null default 'draft'
                check (status in ('draft', 'open', 'closed')),
  closes_at     timestamptz,
  max_responses int check (max_responses is null or max_responses > 0),
  require_rsvp  boolean not null default false,
  after_checkin boolean not null default false,   -- "one more step" for this form
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index if not exists event_forms_one_open
  on public.event_forms (event_id) where status = 'open';

create table if not exists public.form_fields (   -- the form's own copy
  id         uuid primary key default gen_random_uuid(),
  form_id    uuid not null references public.event_forms(id) on delete cascade,
  kind       text not null check (kind in (                          -- same list
             'short_text','long_text','single_choice','multi_choice',
             'number','date','email','phone','student_id','consent','heading')),
  label      text not null,
  help       text,
  required   boolean not null default false,
  options    jsonb,
  max_length int,
  sort       int not null default 0,
  created_at timestamptz not null default now(),
  check ((kind in ('single_choice','multi_choice')) = (options is not null))
);

create table if not exists public.form_responses (
  id           uuid primary key default gen_random_uuid(),
  form_id      uuid not null references public.event_forms(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  entered_by   uuid references public.profiles(id) on delete set null,
  answers      jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now(),
  updated_at   timestamptz,
  unique (form_id, user_id)
);

alter table public.form_templates       enable row level security;
alter table public.form_template_fields enable row level security;
alter table public.event_forms          enable row level security;
alter table public.form_fields          enable row level security;
alter table public.form_responses       enable row level security;
```

Templates are readable by everyone signed in and writable only by admins; the
rest are RPC-only (`revoke all … from anon, authenticated`, no direct grants).
`answers` is `{"<field_id>": value}`, value being a string, a number, `true`
(consent) or `["a","b"]` (multi choice). The server drops unknown keys and
re-validates every field.

## Server API

All `security definer`, `set search_path = public`, explicit `auth.uid()` checks,
`NS:code` errors with `errcode` `P0001` / `42501` — the house pattern.

| Function | Who | Does |
|---|---|---|
| `form_templates_list()` | any signed-in user | Active templates with their field counts, for the chooser. |
| `create_form_from_template(p_event_id, p_template_slug)` | organiser, club officer of an **active** club (`can_act_as_club`), admin | The MVP entry point: creates a **draft** form, copies the template's fields in order, returns the form id. Refuses if an open form already exists. |
| `save_event_form(p_event_id, p_form jsonb, p_fields jsonb)` | same | The builder's write: add/remove/reorder fields on a draft, or on an open form within the limits below. |
| `publish_form(p_form_id)` / `close_form(p_form_id)` | same | `draft → open → closed`. Publishing validates the field set. |
| `form_public(p_form_id)` | anyone, including guests | Read model: title, intro, fields, the caller's own response (null for a guest), `can_answer`, and the reason not (`closed`, `not_joined`, `full`, `signed_out`). Never returns anyone else's data. |
| `submit_form_response(p_form_id, p_for_user uuid, p_answers jsonb)` | signed in | The only write. `p_for_user` must be the caller, unless the caller is the organiser/an admin entering on someone's behalf (sets `entered_by`). Checks open + deadline + `max_responses` + `require_rsvp`, validates answers, upserts. |
| `form_response_list(p_form_id)` | organiser, club officer (`is_club_officer`), admin | Rows joined to profile — display name, username, verified student id, answers — the shape `event_attendance_list` already uses. |
| `form_response_csv(p_form_id)` | same | Rows already flattened to column order, so the export shape lives in one place (the client only quotes and saves). |

`submit_form_response` calls `require_verified('form_submit')`, so the student
verification switch covers reports too. Add `'form_submit'` to the list inside
`verification_required`, and attach the same capability to `mod_guard_write` for
`form_responses` (scope `events`, owner column `user_id`), so a restricted
account cannot submit.

Two club helpers decide the officer path and are not interchangeable:
`can_act_as_club(club_id)` (president/officer of an **active** club — the rule
that already lets them publish events) gates **writing** the form, while
`is_club_officer(club_id)` (any status) gates **reading** responses.

## Editing a live form

| Change | Allowed after responses exist |
|---|---|
| Add a field | yes (optional, or required only for new answers) |
| Edit a label / help text / order | yes |
| Change a choice's option values | **no** — it silently redefines previous answers |
| Remove a field that has answers | **no** |
| Tighten `closes_at` / `require_rsvp` | yes |

The rule: changing what an answer *meant* is refused; changing what the form
*asks next* is fine.

## Handing it in

The report exists to be given to someone. Two outputs, both from the same rows:

- **CSV** with one row per participant and one column per field, plus
  `display_name`, `student_id`, `submitted_at` — the same identifiers as the
  attendance CSV, so the two join in a spreadsheet.
- **A print/PDF view** of the same table, for the signature-and-stamp step that
  paper processes usually want.

Which of these the kolej actually accepts is an open question below; the shape
of the data does not change either way.

## Attendance link: optional

`checkin_with_token` is untouched — it keeps returning `ok` / `already`, and it
never asks about forms. When `after_checkin` is true **and** a form is open, the
check-in success screen offers it as a skippable next step ("You're checked in —
fill in the KI report?"). `require_rsvp` is separate and defaults off.

## Client plan

| Piece | File |
|---|---|
| Service (RPC calls, caching, change notification) | `lib/services/form_service.dart` |
| MVP: pick a template, create the report | `lib/screens/events/form_create_screen.dart` |
| Fill it in | `lib/screens/events/event_form_screen.dart` |
| Builder (extension) | `lib/screens/events/form_builder_screen.dart` |
| Responses table + CSV + print | `lib/screens/events/form_responses_screen.dart` |
| Per-kind input widgets | `lib/widgets/form_field_input.dart` |
| Pure rules | `lib/utils/form_rules.dart` |
| Copy (en/ms, ja→en as elsewhere) | `lib/l10n/form_strings.dart` |

Routes `/event/:id/form` (answer) and `/event/:id/form/responses` (organiser).
Add the answer route to `backFallbackFor` (→ the event page) and to the guest
path list.

Entry points: the event page for organisers ("KI report" when the event has
ended; "Form" once published), and — later — the post-publish prompt.

## Phases

1. **Template + report + export.** Seed the KI template, `create_form_from_template`,
   submit, responses table, CSV. No builder, no import, no QR. This is the thing
   being asked for.
2. **Builder.** Blank/custom fields, reordering, choice options, publish/close.
3. **Question import** (CSV/paste into the builder).
4. **`after_checkin` prompt**, and copy-a-previous-form as the reuse shortcut.

Phase 1 changes no existing table and is testable without a browser.

## Tests

`supabase/tests/forms/forms_test.mjs` applies every migration twice in PGlite
(the house harness: `node ../forms/forms_test.mjs ../../..`), then:

1. the KI template is seeded, active, with its fields in order;
2. an officer creates a report from the template; the fields are **copied**
   (editing the template afterwards does not change the created form);
3. a student, a non-officer, and a guest cannot create or publish a form;
4. a student cannot read another student's response; an officer of the same
   club can; an officer of a different club cannot;
5. submit rejects: closed form, missing required answer, unknown field id,
   over-length answer, bad choice value, `require_rsvp` without a join;
6. submitting twice upserts one row; `entered_by` records an organiser-entered row;
7. `max_responses` stops the next new participant but still allows an edit of an
   existing row;
8. editing a choice's option values after responses exist is refused;
9. deleting the event removes forms, fields and responses; account deletion
   removes that user's responses;
10. `form_response_csv` column order matches the field order.

Widget tests: each field kind renders and validates, required errors surface on
submit, a guest sees the form read-only, the CSV header matches, and the
`after_checkin` prompt appears only when the flag is on.

## Honest limits

- **No file uploads.** "Attach the attendance photo" stays a WhatsApp step.
- **No branching or conditional fields.** Nothing in the KI report needs it.
- **No anonymous answers.** A report row needs a person; the matric number is
  the point.
- **No response import.** Questions import; answers are entered in the app.
- **Templates are official.** A club copies one; it does not edit it.
- **Not a merit record.** Merit still comes from attendance.
- **Retention** is the event's lifetime. No bulk purge by year yet.

## Open questions (answer before phase 1)

1. **What are the KI fields?** The exact wording, order, required-ness and the
   answer scale come from the form the clubs were handed, and I do not have it.
   Paste it (or a photo/PDF) and it becomes the seed — no code change. The seven
   national KI elements are communication, critical thinking and problem solving,
   teamwork, continuous learning and information management, entrepreneurship,
   professional ethics and morals, and leadership; whether the report *scores*
   each of those per participant, or instead records which elements the event
   addressed plus participation numbers, decides the field kinds.
2. **Who fills it in?** Students answering about themselves (in the app, after
   the event), or the organiser entering everyone's marks in one sitting? Both
   work on this schema; the UI and the permission story differ.
3. **What does "hand in" mean?** A CSV upload, a printed page for a signature,
   or entering it into a kolej system by hand? If there is an official document
   the output must match, its column order and headings go into
   `form_response_csv`, not into the screen.
4. **Is the KI report required to close an event?** Should the event page nag
   ("report outstanding") until one exists, or stay silent?
