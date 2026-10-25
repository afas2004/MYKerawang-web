# Mobile form & flow rules — what this app follows

Written after the attendance/KI rework, from the guidance below. The point is not
to cite sources, it is that the next change to a form does not have to guess.

Sources read (2026-10-25):

- Wroblewski-style mobile form reference — labels, input types, multi-step
  wizards, progress, success states:
  [mobile-form-navigation.md](https://raw.githubusercontent.com/phazurlabs/sumi/main/skills/mobile-ux-design/references/mobile-form-navigation.md)
- Validation timing (on-submit vs on-blur vs on-change vs hybrid):
  [validation-concepts.md](https://raw.githubusercontent.com/ancoleman/ai-design-components/main/skills/building-forms/references/validation-concepts.md)
- Error copy formula (what is wrong → how to fix):
  [Validation Timing & Recovery, Genesys Spark](https://spark.genesys.com/latest/patterns/forms/error-management/validation-timing-and-recovery-K3dJH2VS)
- Progressive disclosure as a general pattern:
  [UXPin](https://www.uxpin.com/studio/blog/what-is-progressive-disclosure/)

## The rules this app applies

### Forms

1. **Validate on blur, then on change once the field has an error, and again on
   submit.** Never validate a pristine field; never wait until submit to say
   anything. Implementation: `validateAnswer()` in `lib/utils/form_rules.dart`,
   used by field blur, by change-after-error, and by the submit pass in
   `event_form_screen.dart`. One function, three callers — so the three agree.
2. **On submit, show everything and go to the first problem.** All fields are
   marked touched, the first invalid one is scrolled into view, and the toast
   says how many remain. The submit button is never disabled without an
   explanation.
3. **A label is not a placeholder.** Every field keeps its label above the
   value (`InputDecoration.labelText`), with `*` for required.
4. **Errors are text, not just colour.** Red decoration *and* a sentence under
   the field; a fixed field shows a tick rather than merely losing the red.
5. **Long forms show progress.** The KI form is 24+ questions, so the answer page
   carries a bar and "7 of 24 answered" — the honest version, not a percentage.
6. **Multi-step only when steps are real.** The attendance flow has three
   states (ask → run → close) because each has a different job; the form is one
   scroll because it is one job.
7. **Tap targets ≥ 48 px, buttons full-width on phones**, keyboard types per
   field (`TextInputType.number` for matric, `emailAddress` for email, digits-only
   formatter for matric).

### Flows

8. **One number, one meaning.** If two ideas are displayed as a count, they get
   two counts. (Attendance used to inflate "places" — see
   `20261026011100_checkin_does_not_join.sql`.)
9. **Progressive disclosure, not a settings dump.** The event page leads with the
   one action its owner needs (`Take attendance`); everything else is behind
   `Manage event`. A student's view of that page is the same page minus the
   owner's actions.
10. **Ask at the moment of use.** "Add the KI report?" is asked when attendance
    starts, not pre-configured somewhere else.
11. **Endings are explicit.** A session is closed with a button and confirmed;
    the result is a summary, not a toast that disappears.
12. **Summaries are animated but quick** (300–450 ms, ease-out). No animation
    carries meaning on its own.
13. **Live means live.** A count that changes while the screen is open subscribes
    to it and re-reads; it never patches a guess. Realtime is best-effort —
    guests have no socket — so the value is always correct on load.

### Copy

14. **English and Malay for everything.** `_t(en, ms, ja)` in the `l10n` files;
    Malay is not optional, and the l10n extensions live beside `AppStrings`.
15. **Action labels are verbs** (`Take attendance`, `End attendance`,
    `Answer the KI form`), and the error copy says what to do
    ("A matric number is 6-12 digits"), not what failed.

## Where to look

| Rule | Code |
|---|---|
| Field validation | `lib/utils/form_rules.dart` (`validateAnswer`, `answerProgress`) |
| Answer page timing | `lib/screens/events/event_form_screen.dart` (`_touch`, `_check`, `_submit`) |
| Progress | `_Progress` in the same file |
| Attendance flow | `lib/screens/events/attendance_live_screen.dart` |
| Window rule | `lib/utils/event_live.dart` |
| Copy | `lib/l10n/*.dart` |
