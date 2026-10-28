# MYKerawang design (locked)

The visual identity as built. Read this before changing any UI, so the app
doesn't drift back to the generic default. Background and reasoning:
[visual-identity-plan.md](visual-identity-plan.md), sources and licences:
[illustration-sources.md](illustration-sources.md).

## Personality

A campus noticeboard with craft: warm, local, a little formal where it's
official (announcements, admin), lively where students talk (feed, market).

## Colour — `lib/theme/app_themes.dart`

From the logo. Plum is the brand, marigold the one accent.

| Role | Kampus | Istana | Noir |
|---|---|---|---|
| primary (plum) | `#5E1A4F` | `#55163F` | `#D9A0C8` |
| accent (marigold) | `#E07128` | `#D0661F` | `#F29550` |
| background | `#F6F5F8` | `#F7F3EE` | `#130C11` |

- Text and controls go through `_ensureContrast`; `test/theme_contrast_test.dart`
  holds WCAG AA. Never lower the bar; change the palette.
- **Marigold**: prices, verified, pinned, and **one** accent button per
  screen (`accentButtonStyle`): Join an event, Contact a seller.
- **Club / profile colours**: only the six in `KPalette` (all ≥ 4.5:1 under
  white). Clubs get theirs from category (`clubColor`), profiles from their
  id, until owners can choose (needs a migration).

## Type

- **Fraunces** for display, headline and `titleLarge` (page names, empty-state
  titles, the wordmark).
- **Plus Jakarta Sans** for everything people read or tap.
- No tracked-out capitals for decoration; month abbreviations on date stubs
  are the only uppercase labels.

## Songket — the edge rule

`SongketHem` only, and only on **edges**: top/bottom of the login ground, the
bottom of a generated cover, the top of an official card, under the error
scene's top. Never across the middle of content, never as a texture.
(`identity_rules_test.dart` keeps the asset behind `SongketHem`.)

## Patterns — `KPattern`

Star (bintang lapan), pucuk rebung, tabur; drawn in code, clipped to their box.
Only on grounds with nothing else to say: login, banners, covers with no
photo. Feed, hub, market, events and admin stay plain.

## Shapes that mean something

| Content | Shape | Widget |
|---|---|---|
| Normal post / card | 1 px hairline, 16 px corners | `KCard` |
| Official / pinned | songket hem on top, marigold hairline, cut top-right corner | `OfficialFrame` (via `KCard(official:)`) |
| Event date | ticket stub, plum, perforated edge | `DateBlock` |
| Market price | marigold hanging tag | `PriceTag` |
| Announcement category | colour rail | `categoryColor` |
| No photo | generated cover | `BrandCover`, `ClubCover` |

## Illustration — `AppIllustration`

Open Peeps students (hijab included) in the theme ink, Malaysian stitch motifs
(wau, nasi lemak, sape) in plum or marigold, small Fluent emoji only beside a
person or in a dialog. Each scene is one 240 × 180 canvas scaled as a whole,
so nothing clips. **No illustrations on moderation or admin pages**
(`ErrorState(plain: true)`).

## Motion — `lib/widgets/brand/k_motion.dart`

150–450 ms, ease-out; everything still under reduced motion.

- `KEntrance`: first cards fade up 10 px, 60 ms apart
- `KLikeBurst`: save pops and bursts six marigold diamonds
- `KStampSwitcher`: Join/Follow ⇄ Joined/Following lands like a stamp
- `LinearRefresher`: a wau comes down on its string and flies while loading
- splash (`web/index.html`): the K tile settles, a songket hem weaves

## Credits

CC BY art must stay credited: `lib/services/art_credits.dart` (Settings →
Open-source credits) and the `LICENSE.md` files in `assets/brand/` and
`assets/illustrations/`.
