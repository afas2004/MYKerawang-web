# Launch checklist

State as of 2026-10-25, build 1.7.x. Keep this short and true.

## Before inviting the first club

- [ ] **Custom SMTP (Resend or Brevo) wired into Supabase Auth.** The
      built-in sender is capped at a couple of emails per hour for the whole
      project; with Confirm-email on, that stalls any group signup. Auth →
      SMTP settings. This is the one item that actually blocks a rollout.
- [ ] **Anonymous sign-ins OFF** (Auth → User Signups). The app never uses
      them; they bypass Confirm-email.
- [ ] **Rotate the database password.** It has appeared in chat logs and in
      the pooler URL.
- [ ] **CAPTCHA** on auth (hCaptcha or Turnstile). Remember it applies to
      sign-in as well as sign-up, so the login screen needs the widget too.
- [ ] **One dry run of attendance**: a real event, five people, the QR on a
      phone screen, campus wifi. Confirm the 20-second window survives real
      scanning.
- [ ] **Manual backup** before opening up (`scripts` pattern used on
      2026-10-24: export each table to JSON).

## Known gaps, accepted for the beta

- No push notifications on web (the service returns early on `kIsWeb`).
- No service worker, so no offline and no install prompt; "Add to Home
  Screen" still works manually.
- No error reporting or analytics; Supabase logs are the only signal.
- Membership is cosmetic: a roster row, no member-only content yet.
- `is_hidden` now hides content from signed-in readers too (authors still
  see their own).
- The seeded KMI announcements and events are drafts — edit or delete them.

## After the beta starts

- Watch the moderation queue; open registration with no captcha will
  attract junk eventually.
- Decide whether "Demo Pelajar" and its posts stay.
