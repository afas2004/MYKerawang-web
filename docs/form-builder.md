# Event forms: design

Status: **design only — no schema, no UI.** Written 2026-10-25 against 1.7.7
(`6da73ad`). Read this before writing code; every open question at the bottom
needs an answer first.

## What this is

A club runs an event and needs a form: shirt size, dietary needs, IC number,
consent, a feedback round after the fact. Today the club uses a Google Form, so
the answers sit outside the app and cannot be joined to who actually attended.

**Goal:** the organiser builds a form on the event, students answer it in the
app, and the responses export as CSV next to the attendance sheet with the same
identifiers — so one sheet answers "who came and what did they ask for".

**Not a goal:** a general survey tool, a Google Forms clone, file uploads,
branching logic, or any form not attached to an event.

## Decisions

The three questions the handover left open, plus the ones the schema forces.

| Topic | Decision | Why |
|---|---|---|
| **Scope** | **Per-event**, not a reusable library. Reuse is a "copy from a previous event" action at creation time. | Forms inherit the event's lifecycle (deadline, RSVP gate, attendance). A shared library forces versioning: any edit would silently change what a past response *meant*. Copying gives most of the reuse for none of that. |
| **Response privacy** | Organiser, club officers of the owning club, and admins read responses. A student reads **only their own**. No `_public` view, no PostgREST path to the table. | Responses are PII (IC numbers, phone, dietary/health). Same reasoning that kept `event_contacts` off `events`: the events table is guest-readable, so anything private gets its own table and its own policy. |
| **RSVP before answering** | Per-form toggle `require_rsvp`, **default on** when the event has a capacity or a join deadline, off otherwise. Enforced server-side. | The useful join is `event_participants` ↔ `form_responses`. Defaulting on where capacity exists matches the organiser's mental model ("I need numbers"); defaulting off elsewhere avoids a pointless speed bump for an open talk. |
| **Storage** | `form_responses.answers jsonb`, keyed by field id, validated on write by one security-definer RPC. Not a row per answer. | The form is small and always read whole (render, export). Validation is one pass. A normalised `form_answers` table would triple the RLS surface for a query nobody needs yet. Revisit only if per-question analytics is ever wanted. |
| **One response per person** | `unique (form_id, user_id)`. Re-submitting updates while open; after `closes_at` the form is read-only. | Prevents a "did they answer?" loop in the organiser UI, and keeps one CSV row per student. |
| **Guest submissions** | **No** in v1: the page is a public URL, but answering requires sign-in. | Without an account there is no one to attribute the answer to, nothing to delete on account deletion, and no rate limit but captcha (not built yet). The public page therefore shows the form read-only with a "Sign in to answer" bar — the same `GuestActionBar` the rest of the app uses. |
| **Only one open form per event** | Partial unique index `where status = 'open'`. | The check-in hand-off ("one more step") has to pick *a* form; two open forms makes it ambiguous. |
| **What is public** | The **questions** are readable by anyone (including guests); the **answers** never are. `form_public` is granted to `anon` and returns the field list with `can_answer: false`. | A shared form link has to show what it is asking before it can ask you to sign in — otherwise the page is a bare "Sign in" wall. The trade is that the question set is visible; if a form asks for IC numbers, that intent is visible too. The alternative (sign-in before the fields render) is one line in the RPC's guard — say if you want it. |
| **Deletion** | `on delete cascade` from `events` down; extend `delete_my_account` to remove the user's responses. | An event that never happened must not leave a table of IC numbers behind. The account-deletion RPC already enumerates tables — a new one must be added there or the guarantee quietly breaks. |

## Schema

```sql
-- 20261026007100_event_forms.sql (next free number)

create table if not exists public.event_forms (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events(id) on delete cascade,
  title         text not null,
  intro         text,
  status        text not null default 'draft'
                check (status in ('draft', 'open', 'closed')),
  closes_at     timestamptz,
  max_responses int check (max_responses is null or max_responses > 0),
  require_rsvp  boolean not null default true,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- One open form per event (the check-in hand-off needs an unambiguous target).
create unique index if not exists event_forms_one_open
  on public.event_forms (event_id) where status = 'open';

create table if not exists public.form_fields (
  id         uuid primary key default gen_random_uuid(),
  form_id    uuid not null references public.event_forms(id) on delete cascade,
  kind       text not null check (kind in
             ('short_text','long_text','single_choice','multi_choice',
              'number','date','email','phone','student_id','consent','heading')),
  label      text not null,
  help       text,
  required   boolean not null default false,
  options    jsonb,          -- [{value,label}] for the two choice kinds
  max_length int,
  sort       int not null default 0,
  created_at timestamptz not null default now(),
  -- choices need options; nothing else may carry them
  check ((kind in ('single_choice','multi_choice')) = (options is not null))
);

create table if not exists public.form_responses (
  id           uuid primary key default gen_random_uuid(),
  form_id      uuid not null references public.event_forms(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  answers      jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now(),
  updated_at   timestamptz,
  imported_by  uuid references public.profiles(id) on delete set null,
  unique (form_id, user_id)
);

alter table public.event_forms   enable row level security;
alter table public.form_fields   enable row level security;
alter table public.form_responses enable row level security;

-- All three are RPC-only: no direct select/insert for anyone.
revoke all on public.event_forms, public.form_fields, public.form_responses
  from anon, authenticated;
```

The `answers` shape is `{"<field_id>": value}` where value is a string, a number,
`true` (consent), or `["a","b"]` (multi choice). The server never trusts the key
set: unknown field ids are dropped and every field is re-validated.

## Server API

All `security definer`, `set search_path = public`, explicit `auth.uid()` checks,
`NS:code` errors with `errcode` `P0001` / `42501` — the house pattern.

| Function | Who | Does |
|---|---|---|
| `save_event_form(p_event_id, p_form jsonb, p_fields jsonb)` | organiser, club officer of the event's club, admin | Creates or rewrites a draft/open form and its fields in one transaction. Refuses if responses already exist and a field is removed (see "Editing a live form"). |
| `form_public(p_form_id)` | anyone, including guests | The read model: title, intro, fields, my response (null for a guest), `can_answer`, the reason not (`closed`, `not_joined`, `full`, `signed_out`). Returns no one else's data ever. |
| `submit_form_response(p_form_id, p_answers jsonb)` | signed in | The only write. Checks open + deadline + `max_responses` + `require_rsvp` + one-per-user, validates every answer against the field list, upserts. |
| `withdraw_form_response(p_form_id)` | the respondent | Deletes their row while the form is open. |
| `form_response_list(p_form_id)` | organiser, club officer, admin | Rows joined to profile (display name, username, verified student id) for the table and the CSV — same shape as `event_attendance_list`. |
| `import_form_responses(p_form_id, p_rows jsonb)` | organiser, admin | Rows collected offline; each one resolves a username or student email to a user, runs the same validation, reports `{imported, skipped: [{row, reason}]}`. |

`submit_form_response` calls `require_verified('form_submit')`, so the student
verification switch covers form answers too. Add `'form_submit'` to the list
inside `verification_required`, and attach the same capability to
`mod_guard_write` for `form_responses` (scope `events`, owner column `user_id`),
so a restricted account cannot submit.

## Validation rules (one place)

`lib/utils/form_rules.dart`, pure and unit-tested, mirrored by the server:

| Rule | Value |
|---|---|
| Fields per form | 25 max |
| Label | 1–200 chars |
| Options per choice field | 2–40, values unique |
| Short text | ≤ 200 chars |
| Long text | ≤ 2000 chars |
| Number | finite, ≤ 9 digits before the point |
| Consent | must be `true` when `required` |
| Heading | takes no answer, cannot be required |

The client validates for a good error message; the server validates because the
client is a browser. They must not disagree — the server wins and its message is
shown as-is through `describeWriteError`.

## Linking to attendance

`checkin_with_token` keeps returning `ok` / `already`. The check-in page then
reads `form_public` for the event's open form and, if `can_answer`, shows it as
**one more step** after the success state ("You're checked in — T-shirt size?").
The form's `require_rsvp` is satisfied automatically, because check-in inserts
the `event_participants` row (it already does, best-effort, inside a
`begin … exception` block).

No change to the QR flow, the 20-second token, or the attendance export. The
attendance CSV gains nothing; the form CSV is a second file with the same
identity columns (`display_name`, `student_id`) so the two join in a spreadsheet.

## Client plan

| Piece | File |
|---|---|
| Service (RPC calls, caching, change notification) | `lib/services/form_service.dart` |
| Organiser builder | `lib/screens/events/form_builder_screen.dart` |
| Student page | `lib/screens/events/event_form_screen.dart` |
| Responses table + CSV + import | `lib/screens/events/form_responses_screen.dart` |
| Per-kind input widgets | `lib/widgets/form_field_input.dart` |
| Pure rules | `lib/utils/form_rules.dart` |
| Copy (en/ms, ja→en as elsewhere) | `lib/l10n/form_strings.dart` |

Routes: `/event/:id/form` (answer) and `/event/:id/form/responses` (organiser).
Both go through `appBack`/`backFallbackFor` (add the `/event/:id/form` case → the
event page) and the guest path list, since the answer page is public-but-gated.

Entry points: the event page action row for organisers ("Form"), and the
post-publish prompt the handover already asks for ("Add a form?" right after
publishing an event).

CSV: reuse `csvCell` / `saveCsv` from `lib/utils/csv_saver.dart` — one column per
field, labelled with the field label plus `display_name`, `student_id`,
`submitted_at`.

## Phases

1. **Schema + RPCs + `supabase/tests/forms/forms_test.mjs`.** No UI. Gates
   everything else and is testable without a browser.
2. **Answer page + builder.** A form exists, can be filled, appears after
   check-in.
3. **Responses table, CSV export, CSV import.**
4. **Copy from a previous event's form**, and the post-publish "Add a form?"
   prompt.

Ship 1–2 as one release; 3 can follow. Nothing in phase 1 changes existing
tables, so it is safe to merge before the UI lands.

## Tests

`forms_test.mjs` runs every migration twice in PGlite (the house harness,
`node ../forms/forms_test.mjs ../../..`), then:

1. an officer saves a form for their club's event; a student reads it through
   `form_public`;
2. a student cannot save a form; a non-officer club member cannot either;
3. submit rejects: closed form, `require_rsvp` without a join, unknown field ids,
   a missing required answer, an answer over the length limit, a bad choice value;
4. submitting twice upserts one row, not two;
5. after `closes_at`, submit fails but reading still works;
6. `form_response_list` raises for a student and for a different club's officer;
7. anon cannot submit;
8. deleting the event removes forms, fields and responses;
9. account deletion removes the user's responses;
10. import skips an unknown username with a reason and imports the rest.

Widget tests: each field kind renders and validates, the required-error text
appears on submit, the post-check-in prompt only shows when `can_answer`, and the
CSV header matches the field order.

## Honest limits

- **No file uploads.** Storage cost, abuse, and a virus-scanning question best not
  answered in a hurry. "Upload your receipt" stays a WhatsApp/email step.
- **No branching or conditional fields.** That is a graph editor and a validation
  engine; nothing in the current use cases needs it.
- **No anonymous answers** (see the decision table). If a truly public form is
  needed later, it needs captcha first — the same captcha the login screen is
  waiting on.
- **No per-field analytics.** Counts and the CSV only.
- **Not a merit record.** Merit still comes from attendance; a form does not
  award anything.
- **Editing a live form is restricted.** Removing a field that already has
  answers, or changing a choice's values, is refused; you may add fields, edit
  labels and help text, reorder, and tighten `closes_at`. Renaming a label is
  honest enough; silently redefining "size: M" is not.
- **Retention** is the event's lifetime. There is no field-level retention or
  "delete my answer" for organisers to run in bulk yet.

## Open questions (answer before phase 1)

1. **CSV import means what?** This design assumes *responses collected offline*
   (paper/Sheets) imported against existing accounts by username or student
   email. The other reading — importing the *field list* — is much less useful;
   confirm.
2. **Sign-in-only answers** — agreed for v1? It rules out a genuinely public form
   (an open day where passers-by scan a QR).
3. **Do club officers see responses, or only the organiser and admins?** The
   design says officers too (they run the event). If responses can contain health
   information, narrower is defensible.
4. **Is a form answer required to be after the event started?** Today the design
   allows answering any time the form is open, including before the event (which
   is what "shirt size" needs) and after it (feedback). Say if feedback should be
   a separate form with `closes_at` after the event rather than a mode.
5. **Are the questions public?** The design shows the field list to guests so a
   shared link is useful. If a form asks for sensitive data, that intent becomes
   visible to anyone with the link — tell me if sign-in should come first instead.
