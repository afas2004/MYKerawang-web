# MYKerawang Design Spec

The requirements document. Every new screen and change gets checked against this. Agreed with Fahmi, 2026-07-17.

## 1. Principles

1. **Identity through consistency.** The shape language, motif, type system, and voice never change. Only palettes swap. If a screen could belong to any app, it's wrong.
2. **One job per column** (web): sidebar navigates, feed informs, rail tempts.
3. **Data over hardcode.** Categories, tags, channels come from tables, not const lists.
4. **History is content.** Ended events grey out, they don't disappear. Past posts stay searchable.
5. **Trust hierarchy.** Official > community, always visually distinguishable.
6. **Quiet trending.** High-engagement posts may rank higher in the feed. No trending sections, no fire emoji, no tag clouds.

## 2. Theme architecture

### Shared constants (the identity — same in all three themes)

- **Kerawang cut**: signature asymmetric corner radius `(topLeft 2, topRight 14, bottomRight 2, bottomLeft 14)` on hero cards, buttons, and images. Regular cards use 12.
- **Motif**: `KerawangDivider` in section breaks, empty states, login, sidebar footer. Gold, always subtle.
- **Type**: Fraunces for display/headline/titleLarge + wordmark; system/default for body. Scale: 26/20/17/15/13/11.
  - Decision: fonts stay constant across all three themes (identity > variety). Parked idea: per-theme heading fonts (e.g. geometric sans for Kampus) if themes ever need more distinction — 5-line change in buildAppTheme.
  - Known gap: many screens use hand-set `TextStyle(...)` that bypass the theme, so Fraunces currently shows only in AppBar titles/wordmark/login. Rule: every screen touched from now on migrates its text to theme styles (`textTheme.titleMedium` etc.), no new hand-set styles.
- **Spacing scale**: 4 / 8 / 12 / 16 / 24 / 32 only. No arbitrary values.
- **Gold rule**: gold marks *specialness only* — official badges, category labels on embeds, motif, prices. Never large fills, never body text.
- **Voice**: BM-mix in default locale ("Jom post", "Apa cerita kat kolej?"), localized via AppStrings.

### Three named themes (replaces the seed-color picker in Settings)

| | Kampus Bold (DEFAULT) | Istana Modern (bright) | Songket Noir (dark) |
|---|---|---|---|
| Mood | loud, young | crafted, warm | premium, nocturnal |
| Background | #FAF7FF | #F6F0E4 (cream) | #171122 |
| Surface/card | #FFFFFF | #FFFDF7 | #231A35 |
| Primary | #5B3E96 | #3D2B56 (aubergine) | #7E5FC7 |
| Gold accent | #F0A81C | #BA7517 | #E8C766 |
| Text | #241640 | #2C2050 | #EDE6FA |
| Border | #E4DCF2 | #E3D5B8 | #3D2E5C |
| Buttons | pill, filled, bold | kerawang cut, filled | kerawang cut, outlined gold |

Implementation: `AppTheme` enum in ThemeCubit {kampus, istana, noir}; persisted; default kampus. Settings shows three named cards, not a color row.

## 3. Layout rules (breakpoints)

- `<600` phone: bottom tabs, carousels allowed, full-width cards.
- `600–900`: mobile layout clamped to 840 centered.
- `>=900` desktop: sidebar (220) + feed column (max 680, centered) edge-to-edge canvas.
- `>=1150`: + right rail (300): events (3 rows) and fresh market (2×2), each with "See all".
- Pushed detail/create pages: `PageBody` 680 centered.
- All horizontal lists: chevrons on hover (web) + drag-scroll enabled.

## 4. Home feed

### Web (>=900)
- Composer box at top: avatar + "Apa cerita kat kolej?" + post button. Posting never leaves the feed.
- Slot 1: pinned official announcement (when channels ship; until then, latest event by kolej account).
- Then: pure posts. NO carousels, NO injected market/event cards on web (the rail owns discovery).

### Mobile (<600)
- Carousels stay (touch-native), with hover-free plain scroll.
- Feed injection: exactly one embed card after every 6th post. Deterministic, never `Random()`.

### Embed card (replaces the "weird wide card")
IG-style, same width as posts: full-bleed image (16:9, kerawang cut), gold category label (PASAR / ACARA), title, one line of description, price or date-countdown, single CTA button ("Lihat barang" / "Join event"). Tap anywhere → detail page.

### Ranking
Chronological; official pinned first; optionally boost high-engagement posts toward the top. Nothing else.

## 5. Tag system (unified)

- Freeform `#tags` on posts, events, listings. Autocomplete from existing tags (typeahead, same UX as @mentions). Stored in a `tags` table + join tables.
- Marketplace **categories** move from hardcoded chips to a `categories` table (admin-extendable); chips render from DB. Categories = structural filter; tags = everything specific.
- Reserved system tags with special filters: `#lostfound` (Lost & Found gets its own marketplace filter), future: `#official`.
- Tags render as plain tappable text — no chip clouds in feed, no counts.

## 6. Events

- Upcoming first (soonest first); **ended events stay**, greyed text + "Tamat" badge, sorted after upcoming.
- Countdown chip on cards: "3 hari lagi" (<7 days).
- "Add to calendar" (ICS download / calendar intent) on detail page.
- Friends attending: "5 kawan joined" using the follow graph.
- Recap flywheel: after end, organizer can open gallery for photo uploads; recap posts allowed.

## 7. Marketplace

- Listing states: **Available / Reserved / Sold** (replaces boolean is_sold; Reserved = "COD arranged, not final").
- Filter sheet: category, price range, state, sort (newest/cheapest).
- Categories from DB (see §5). Grid columns responsive (2–4 by width).

## 8. Saved

Bookmark icon on posts, listings, events → "Saved" collection (profile tab section). One table: saved_items(user, type, id).

## 9. Notifications

- **Phase 1 (no Firebase)**: current realtime in-app notifications; scheduled daily local notification on Android ("Check what you missed") via flutter_local_notifications; in-app digest banner listing missed announcements since last open.
- **Phase 2 (FCM)**: Firebase project + firebase_messaging; Supabase Edge Function on pg_cron sends 6pm digest push; web push for PWA (iOS 16.4+ installed only).

## 10. Non-goals (deliberate)

No 1:1 chat (WhatsApp redirect is the design). No stories. No seller ratings. No trending UI. No infinite theme customization.

## 11. Build order

1. Theme system (3 named themes; Settings UI swap)
2. Web home restructure (composer, pure feed, rail-owned discovery) + mobile deterministic injection with new embed card
3. Tags + categories tables and UI (marketplace first, then events/posts)
4. Events: ended-greyed, countdown, calendar
5. Saved + listing states
6. Perceived-speed polish pass (skeletons, image fade, memory cache) — built in the new visual language
7. Notifications phase 1 → (later) FCM
