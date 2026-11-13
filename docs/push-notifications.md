# Notifications and phone push

Design and mockup: [`docs/mockups/notifications.html`](mockups/notifications.html).

## How it fits together

```
something happens (comment, form answer, event change…)
  → a database trigger adds a row to `notifications`
      (notifications_prepare: settings, grouping, "push due?")
  → the bell updates live (Supabase Realtime), and a toast shows if the app is open
  → if the row should reach the phone: GitHub Actions runs worker/push.py
      → push_take(): quiet hours, 8-a-day cap, devices
      → Firebase Cloud Messaging → the phone's lock screen
  → tapping it opens the exact post comment / event / form answers
```

Words:

- **Push**: a notification the phone shows even when MYKerawang is closed.
- **Service worker**: a small script the browser keeps in the background.
  `web/firebase-messaging-sw.js` receives pushes. It lives in its own scope, so
  `sw_reset.js` (which `deploy_web.bat` copies over `flutter_service_worker.js`)
  never touches it, and it caches nothing.
- **FCM**: Firebase Cloud Messaging, Google's free push relay (same as efoc).
- **iPhone**: push only works after "Add to Home Screen" (iOS 16.4+). The app
  shows the three steps instead of asking.

| Piece | File |
|---|---|
| Tables, triggers, queue, reminders | `supabase/migrations/20261114000100_notifications_v2.sql` |
| Sender | `worker/push.py` (+ `worker/test_push.py`) |
| Schedule | `.github/workflows/push.yml` (every 5 min, plus instant starts) |
| App: device on/off | `lib/services/push_service.dart`, `lib/config/push_config.dart` |
| App: settings | `lib/screens/notification_settings_screen.dart` |
| App: bell | `lib/screens/notification_screen.dart`, `lib/services/notification_text.dart` |

## One-time setup (owner)

Until steps 2–3 are done the app says "Phone notifications are coming soon";
everything else (bell, grouping, settings, reminders in the bell) works after
step 1.

### 1. Database

From this branch's folder, in PowerShell:

```powershell
.\db_push.ps1
```

It shows the pending list (only `20261114000100_notifications_v2.sql` is
expected), then asks for the database password.

### 2. Web Push key (public)

Firebase console → project **mykerawang-app** → Project settings → Cloud
Messaging → Web configuration → Web Push certificates → **Generate key pair**.
Copy the key into `kWebPushVapidKey` in `lib/config/push_config.dart` (it is
public and safe to commit; or send it to Claude to commit).

### 3. GitHub secrets (private)

GitHub → afas2004/MYKerawang-web → Settings → Secrets and variables → Actions
→ New repository secret, three times:

| Name | Value |
|---|---|
| `SUPABASE_URL` | `https://zxjuqpqzyzmegdjttzyz.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Project settings → API keys → a **secret** key |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase → Project settings → Service accounts → Generate new private key → paste the whole JSON file |

Then Actions → "Phone notifications" → Run workflow → tick "Check the setup
only" to see it start without sending.

### 4. Optional: instant delivery

GitHub's 5-minute schedule is often late (10–15 min). To send within about
30 seconds, let the database start the workflow:

1. GitHub → Settings → Developer settings → Fine-grained tokens → new token,
   only this repository, permission **Actions: Read and write**.
2. Supabase → Database → Extensions → enable **pg_net**.
3. Supabase → SQL editor:
   ```sql
   select vault.create_secret('<the token>', 'github_push_dispatch');
   ```

Without it, nothing breaks: pushes just wait for the schedule.

## Cost

All free on the current plans: the repository is public (GitHub Actions
minutes are unlimited), FCM is free, and the database work is a few small
queries per notification.

## Checking it works

- Settings → Notifications → "Turn on" on a phone; the device appears under
  Devices.
- Comment on that person's post from another account: the bell updates at
  once; the phone gets it on the next sender run.
- Actions tab → "Phone notifications" logs say "N notification(s): sent …".
