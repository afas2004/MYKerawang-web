# MYKerawang — Product Direction Notes

Captured from planning discussion, 2026-07-17. Not yet implementation tasks.

## Vision

Evolve from group project (CSC661, "Marketplace + Events") into the college's real platform. Positioning: **Threads × Instagram for the kolej** — one trusted feed where official announcements and student community live together. Daily driver is the announcements hub; marketplace and events are retention features (already built); room selection is the semesterly adoption spike.

## Pillar 1 — Announcements hub (the core product)

Problem: info fragmented across official Telegram (incomplete) and gender-separated WhatsApp groups; knowing something depends on which group you're in. No search, no archive, announcements drown in chatter.

Direction:
- Verified channels/roles on top of the existing feed: kolej office, JPK, clubs, faculty. Official posts visually distinct (badge / pinned / kerawang-gold accent).
- One source posts once; audience targeting replaces duplicated boys/girls groups.
- Notifications per followed channel; searchable archive.
- Trust promise: "if it's not here, it's not happening."
- Explicitly NOT building 1:1 chat — WhatsApp redirect for transactions stays.

## Pillar 2 — Room selection module (semesterly, needs kolej blessing)

Status quo: selection done via a shared Excel sheet. A previous website existed but was dropped by UiTM over data privacy concerns (data involved is only student name + ID).

Concept: RedBus-style visual picker, one level deeper — **Block → Floor → Room → Bed**.
- Block pre-filtered (blocks are gender-assigned — handles the split automatically).
- Floor chips; room grid cells show state: empty / 1-of-4 / full / locked (JPK, maintenance).
- Tap room → see beds → claim bed.
- Scale: ~1,300 students competing, ~1,000 get rooms, per selection window.

Technical guardrails:
- Atomic claims: unique constraint per bed + one claim per student per window; graceful "someone got it first" UX. No double-booking, ever — reputation dies otherwise.
- Supabase realtime: rooms grey out live as others claim (also the wow demo).
- Expect a stampede when the window opens — load-test before pilot.

Adoption keys:
- Admin-side: import their existing Excel room inventory to seed the map; one-click export of final assignments back to Excel. Zero change to their downstream workflow.
- Privacy pitch (answers why the old site died): data minimization (name + ID only), nothing public, RLS so students see only their own claim, purge after window closes, Supabase is open-source and can be self-hosted on campus if UiTM demands control.
- Killer student feature Excel can't do: rooming near friends — opt-in visibility of who claimed which room, possibly group claiming later.

Open questions (blocking the spec):
1. FCFS when window opens, or preference submission + office approval?
2. Does the office assign students to blocks first, or is block choice part of selection?
3. Route to stakeholder: kolej office? JPK? A lecturer sponsor?

## Sequence (agreed direction, not scheduled)

1. Current UI polish to commercial feel (in progress — see UI_UX_AUDIT.md).
2. Announcements: verified channels/roles layer on the existing feed.
3. Room selection: mockup + data model as pitch material → kolej blessing → build → pilot one semester.
4. Hosting + RLS remain prerequisites for anything public.
