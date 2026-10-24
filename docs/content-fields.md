# Content fields: events, listings, announcements

Status: **phases 1–5 shipped**.
Categories are data-driven; events carry registration, merit, contact and
attendance fields; announcements have a 16:9 / 1:1 cover.
Not built: waitlist, proximity proof for check-in.

## Decisions from review

| Topic | Decision |
|---|---|
| Categories | Data, not code. Any admin can add/rename/reorder/hide. Multi-select for events and listings (max 5). Announcement category stays fixed: it decides who may announce. |
| Merit | Ships with an **export**, not just a badge. Export must carry full name + student ID (the matric number is the local part of the verified student address). |
| Attendance | In-app QR scanning, organiser shows the code. Code **rotates every 10 seconds**. Camera only — no picking an image from the gallery. |
| Fallback | The QR encodes a URL, so a student who won't use the app can open it with their phone camera and land on the web check-in page. |
| Join deadline | A toggle for the organiser ("close registration at start"), not another date picker they have to fill in. |
| Contact | Multi-channel: WhatsApp, Telegram, Instagram, email, link. The organiser ticks the channels they want to publish. |

## Phase 1 — categories (shipped)

- `content_categories (kind, slug, name_en, name_ms, sort, active)` seeded with
  56 event topics and 26 listing categories.
- `events.categories` / `listings.categories` are `text[]` slugs; the first
  one is the primary. A trigger copies `categories[1]` into
  `listings.category` so old queries keep working.
- Backfill: `listings.category` and `events.tags` → lowercase slugs
  (27 listings, 10 events on the live project).
- Admin → Categories: add, rename, reorder, hide. Delete is refused while
  content still uses the slug; the slug itself cannot change while in use.
- The event filter chips used to filter a column nothing wrote to; they
  now read `categories`. Market filtering uses array-contains, so a listing
  in two categories shows under both.

## Phase 2 — event fields

| Field | Type | Notes |
|---|---|---|
| `join_deadline` | timestamptz | Toggle "close at start" fills it; organiser can close early |
| `capacity` | int, null = unlimited | Join refused when full; waitlist later |
| `audience` | text | `uitm` · `kolej` · `klab` · `awam` |
| `fee` | numeric | RM0 default |
| `merit_offered` | bool | officer/admin only |
| `merit_note` | text | free text ("2 merit, kokurikulum") |
| `activity_ref` | text | UiTM approval / TAPA reference |
| `co_organiser` | text | "dengan kerjasama" |

`merit_offered` is restricted to club officers and admins: if any account
could tick it, "merit" becomes bait.

## Phase 3 — contact channels

`event_contacts (event_id, channel, value)` with owner-only RLS, plus a
signed-in reveal RPC. Contact columns **cannot** live on `events`: that
table is readable by guests, so a number there would be public. Channels:
whatsapp, telegram, instagram, email, link.

## Phase 4 — attendance and merit export

```
event_checkin_tokens  (event_id, token, expires_at)   -- 10s window, issued by the organiser's device
event_attendance      (event_id, user_id, channel, checked_in_at)
```

- Organiser opens "Attendance" → the app asks for a token every 10 seconds
  and renders `https://…/event/<id>/checkin?t=<token>` as a QR.
- Student scans with the in-app scanner (live camera only). The scan calls
  `checkin_with_token(token)`; the server accepts only an unexpired token,
  a signed-in **verified** student, and a row that does not exist yet.
- Phone-camera fallback: the same URL opens the web app, which asks them to
  sign in and then checks them in. This is why the QR is a URL.
- Honest limit: rotation stops a screenshot shared later, not someone
  standing next to the organiser streaming the code. Proximity proof would
  need BLE/GPS; not in scope.
- Export: CSV of full name (display name) + student ID (local part of the
  verified address) + checked-in time — the format the eMerit application
  wants. Manual check-in by the organiser stays available for walk-ups.

## Phase 5 — announcement cover

`posts.cover_aspect` = `16:9` (default) or `1:1`. Composer gets a two-option
segmented control; the card and the hero read the stored value instead of
the hardcoded 16/9.
