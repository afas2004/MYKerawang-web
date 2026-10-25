# Mockups

Design mockups. **Not app code** — nothing here is imported by the Flutter app.

## `form-editor.html`

Self-contained mockup of the proposed **form editor** and **answer sheet** for the
KI report form (the screens behind `/event/:id/form/edit` and `/event/:id/form`).
No build step, no server: open the file in a browser.

Controls in the black bar at the top:

- **View** — Editor / Answer sheet.
- **Theme** — Kampus / Istana / Noir (the palettes in `lib/theme/app_themes.dart`).
- **Width** — Desktop / Phone.

URL parameters, so a specific state can be linked or screenshotted:

| Parameter | Values | Effect |
|---|---|---|
| `view` | `answer` | Opens the answer sheet |
| `width` | `phone` | Phone layout |
| `theme` | `kampus`, `istana`, `noir` | Palette |
| `state` | `errors`, `sent` | Submits with gaps (error state) or shows the sent state |

The editor is interactive: change a type, retag a row, drag a row by its six-dot
handle (or use the arrows), and the coverage rail and publish checks follow.

Screenshots, generated from this file with headless Edge:

- `form-editor-desktop.png`, `form-editor-phone.png`
- `answer-desktop.png`, `answer-phone.png`

These are the **mockup**. The `built-*.png` files are renders of the shipped
Flutter widgets (a throwaway preview `main` against a fake service, since
removed), so the two can be compared:

- `built-editor-desktop.png`, `built-editor-narrow.png`
- `built-answer-desktop.png`

They are outputs, not sources — regenerate them if the screens change.

**Status:** built. The editor and answer sheet landed in
`lib/screens/events/form_editor_screen.dart` and `event_form_screen.dart`; see
`docs/ki-event-reports.md` ("The editor — what 'simple' means").
