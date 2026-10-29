# MYKerawang design (locked)

The visual identity as built. Read this before changing any UI, so the app
doesn't drift back to the generic default. Background and reasoning:
[visual-identity-plan.md](visual-identity-plan.md), sources and licences:
[illustration-sources.md](illustration-sources.md).

## The layers (Round 3)

1. **One ground.** `KGround` sits behind the router: "Corak kampus", twelve
   line drawings (wau, ketupat, bunga raya, 8-point star, songket diamond,
   book, graduation cap, teh tarik, music, pencil, football, bicycle) at 6 %
   in the theme primary, like Telegram/WhatsApp chat wallpapers. The theme's
   scaffold background is transparent so it shows everywhere; opaque
   page-coloured fills use `colorScheme.surface`.
2. **A framed screen, soft edges.** App bar (`KBand`): solid plum on every
   main tab with rounded lower corners, no strip, no pattern. Nav bar
   (`CompactNavBar`): white with rounded top corners and a soft shadow; Create
   is the MYKerawang logo tile (no extra frame), big, rising above the bar; a rounded marigold
   mark sits above the active tab.
3. **Plain figures.** Cards are plain surfaces with the hairline. The
   author's colour is a thin ring on the post avatar, not a card edge.
4. **Special things keep one special shape** (table below).
5. **No photo = a calm tint** (`KTintCover`): a soft wash of the item's
   colour and one Malaysian stitch drawing in that colour (wau, sape for
   events; nasi lemak, sape, wau kucing for listings). Patterns are reserved for
   profile banners and club covers, which are those owners' identity.

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

## No pattern strips

The songket strip (`SongketHem`) was removed everywhere on 2026-10-29: bars,
login, official cards, covers, splash. Edges are soft and plain; the
culture lives in the ground's drawings and the stitch motifs.

## Header band (kepala kain) — `KBand`

The four main tabs' app bars are solid plum (deepened on dark themes) with
softly rounded lower corners and a 20 px title. No songket strip on the bars. No pattern: the ground has
the drawings. Other screens keep the plain app bar.

**Desktop (≥ 900) has no band.** The sidebar frames the page: wordmark, then
Create (the one primary action), the tabs and Clubs, then notifications,
settings and admin; the profile (or Sign in) is pinned to its foot. Each tab
opens with a quiet page header on the ground — the page name in the display
face (`headlineMedium`, 88 px row), only page-specific actions beside it
(`desktopActions`, e.g. New announcement); bell and avatar live in the
sidebar. The feed and the right rail are one centred block, the rail's first
card level with the content, and the rail leaves out the card for the tab
it sits beside.

## Patterns — `KPattern`

Star (bintang lapan), pucuk rebung, tabur; drawn in code, clipped to their box.
Only on profile banners and club covers. Everything else gets its texture
from the one ground.

## Shapes that mean something

| Content | Shape | Widget |
|---|---|---|
| Normal card | 1 px hairline, 16 px corners | `KCard` |
| Post | plain card; author's colour as a thin avatar ring (grey when anonymous) | `PostCard` |
| Official / pinned | marigold hairline, cut top-right corner, label row | `OfficialFrame` (via `KCard(official:)`) |
| Event date | ticket stub, plum, perforated edge | `DateBlock` |
| Market price | plain bold text in the accent colour | `MarketCard` |
| Announcement category | colour rail | `categoryColor` |
| No photo (events, listings) | soft tint + one stitch drawing; events add a date stub — never a grey box | `KTintCover` |
| No photo (clubs, profiles) | pattern cover (their identity) | `ClubCover`, `BrandCover` |
| No photo (announcement hero) | solid category colour + its icon | `_CategoryCover` |

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
- splash (`web/index.html`): the K tile settles, a rounded bar fills

## Credits

CC BY art must stay credited: `lib/services/art_credits.dart` (Settings →
Open-source credits) and the `LICENSE.md` files in `assets/brand/` and
`assets/illustrations/`.
