# Beta data reset (2026-10-24)

One-off cleanup before the first beta, with the club-first rollout in mind.

## What was there

18 accounts and ~90 content rows, almost all of it development output:
the `seeder.dart` script had run several times, so "Career Fair", "Sony
Headphones" and "Best nasi lemak nearby?" existed three or four times
each, mixed with hand-typed tests ("dfghf", "event123", "bola", "cat").
Zero announcements. One club (KMI). Zero registry entries.

## What was done

1. **Backup first.** Every content table plus the account list exported to
   JSON: `.deepseek/backups/2026-10-24-beta-reset/` (21 files, outside git).
2. **Three test accounts deleted** — `test@test.com`,
   `admin@uitm.edu.my` (seeder), `user@gmail.com` — with their content.
   All other accounts were kept, as asked.
3. **Everything else hidden, not deleted.** `is_hidden = true` on the
   remaining posts, events and listings, so it can be restored by flipping
   the flag or reloading from the backup. Notifications, the two test
   reports and their cases were deleted (they were by-products).
4. **The owner's and admin's own hidden rows deleted** — hidden content
   stays visible to its author, and those are the accounts used to demo.
5. **Seed applied** (`supabase/seed/2026-10-24_beta_seed.sql`):
   - KMI announces three things (membership, November schedule, weekly
     Quran class).
   - KMI hosts three upcoming events. *Malam Apresiasi KMI 2026* (14 Nov)
     and *Bengkel Pengurusan Jenazah* (21 Nov) carry merit and turn
     attendance on; *Program Jom Ke Masjid* (5 Dec) is plain.
   - A password-less **Demo Pelajar** account (`demo@mykerawang.local`,
     no login possible) authors four sample posts and three listings.

## Visibility fix that made hiding possible

`is_hidden` was only respected by the `*_public` views and the guest
policies; a signed-in list query still returned hidden events and
listings. Migration `20261026004100_hidden_content_visibility.sql` adds
restrictive select policies so hidden rows disappear for everyone —
except their author (so an edit or appeal is still possible). Admins
deliberately do **not** get a table-level pass: they would see the hidden
backlog mixed into the feed, and the moderation console reads hidden
content through security-definer RPCs anyway.

## Result

| | Before | After |
|---|---|---|
| Accounts | 18 | 16 (13 real testers + KMI + your two + demo) |
| Visible posts | 33 | 7 (3 announcements + 4 samples) |
| Visible events | 31 | 3 |
| Visible listings | 27 | 3 |
| Hidden (restorable) | 0 | 8 events, 4 listings, 6 posts |

Verified by acting as a real student under RLS (sees 3/3/7) and as the
owner (same, after removing their own rows).

## Still yours to do

- **Disable the legacy JWT keys.** The app now initialises Supabase with a
  publishable key (`sb_publishable_…`, 1.7.1, build 202610242323), so once
  the deploy has settled, click *API Keys → Legacy anon, service_role →
  Disable JWT-based API keys*. That retires the leaked `service_role`
  without rotating the JWT secret, so user sessions survive.
- Rotate the DB password (already on the list).
- Add `club_registry` entries for clubs that will join the beta (not KMI —
  it has a page).
- The seeded KMI announcements/events are drafts: edit or delete them in
  the app before real students see them.
