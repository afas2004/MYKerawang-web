# Visual identity plan

Status: **proposal, nothing implemented.** Pick a direction (see "Decisions for you"
at the end) before any code changes. Branch: `claude/visual-identity-plan-35c529`,
cut from `deepseek/clubs-admin` (live 1.9.0+25).

---

## 1. What the Threads post says

Source: a thread by @aidilazhxr (in Malay), read 2026-10-28, plus the README of
the repo it points to (github.com/Nutlope/hallmark).

**The subject is Hallmark**, an open-source (MIT) "anti AI-slop" design skill for
coding agents (Claude Code, Codex, Cursor, OpenCode), by Nutlope / Together AI,
~40k GitHub stars. The four screenshots in the first post are sample pages from
usehallmark.com, each in a different theme: a warm editorial page, a playful
colour-blocked reading app, a product page for a fragrance shop, and a dark
developer page with a green line-art hare. The point is that they share a skill
but don't look alike.

What it recommends:

- **The problem.** AI-built UIs converge on one look: a purple or green gradient,
  the same headings, the same layout. That sameness is what "AI slop" means here.
- **Themes as materials, not templates.** Fifty themes, each a *material*: its own
  fonts, colours, textures and components. A theme never dictates content or
  order, so two pages in one theme still differ.
- **Layout follows the page's job.** A shop page is built around buying, a booking
  page around booking, and the page ends on that action.
- **A checklist of tells** that read as machine-made, checked automatically:
  1. a small label (eyebrow) above every heading
  2. tracked-out capital-letter labels
  3. one coloured word in a headline
  4. an email sign-up at the end of every page
  5. a form that says "thanks" but sends nothing
  6. a hero that doesn't fit the screen
  7. a page of empty frames, or nothing but photographs
- **Gates in tiers.** *Floor* never ships broken: contrast, keyboard focus, reduced
  motion, invented facts, broken phone layout. *Reflex* gates catch the defaults a
  model falls into, and can be overruled with a stated reason. *Finish* checks are
  craft detail that never blocks a release.
- **Process.** Read the project first (fonts, palette, a locked `design.md`), ask
  for real material (photos, real numbers) and never invent it. Build the hero
  alone and review it before the rest. Render in a real browser at eight widths,
  then have a fresh reviewer (a new agent with no context) do the final pass.
- **Tools.** `npx skills add nutlope/hallmark -g`, or the Claude Code plugin
  (`/plugin marketplace add nutlope/hallmark`, `/plugin install hallmark@hallmark`).
  `/hallmark audit <path>` only reports; `/hallmark redesign <path>` rebuilds, so
  commit first. Needs Node 18+, and Chrome + `puppeteer-core` for browser checks.

Caveats the author gives honestly:

- Hacker News commenters found the results still generic, and the pages similar
  when the prompt is vague.
- One review says it suits **landing pages, not app UI**.
- In a reply, the author contrasts it with Claude Design (an app inside Claude
  that builds a design system from your logo, fonts and repo): if you already
  know what you want, that is enough. Hallmark is for people who don't know
  fonts or palettes and need the AI guided.

**What this means for us.** MYKerawang is app UI written in Flutter, which renders
to a canvas, so Hallmark's HTML linter can't read our screens and its `redesign`
would produce HTML/CSS we can't use. The useful parts are the **ideas**:
material-based identity, the tells checklist, the Floor/Reflex/Finish tiers, a
locked `design.md`, review at many widths with a fresh reviewer. We take those and
skip the tool, except for one place where it fits: the plain-HTML splash in
`web/index.html`.

---

## 2. Audit: where MYKerawang's identity stands

### The good part: the Floor is already strong

- `lib/theme/app_themes.dart` builds every colour through `_ensureContrast`, and
  `test/theme_contrast_test.dart` holds WCAG AA in all three themes.
- Visible focus rings (`KTokens.focusRing`), 48px touch targets, `KMotion` that
  drops to zero under reduced motion (tested in `test/brand_widgets_test.dart`).
- Tokens are respected: only `login_screen.dart` has raw `Color(0x…)` literals (the
  Google "G", which is correct), no stray `Colors.red/blue/…` in screens, all
  `GoogleFonts` calls live in the theme, and icons go through `AppIcons`
  (Lucide), with about 30 raw `Icons.` left in ~10 files.

So this isn't a broken system. It's a **tidy system without a face**.

### The problem: it's the default look, almost item by item

Compared with the post's description of AI slop:

| Element | Today | Why it reads as generic |
|---|---|---|
| Primary | `#5B3E96` purple in all themes (`kThemeSpecs`) | Purple is the #1 default the post names |
| Accent | amber `#E9A21B` ("gold") | Unrelated to the logo's orange; a stock pairing |
| Type | Plus Jakarta Sans for everything, hierarchy by weight only | A very common AI/startup default |
| Shape | 16px cards, pill buttons, 1px hairlines | Default Material 3 / shadcn shape |
| Illustrations | 8 **unDraw** SVGs, accent recoloured to purple (`app_illustration.dart`) | unDraw is one of the most recognisable stock sets on the web |
| Announcement cover with no photo | purple → black `LinearGradient` (`announcements_screen.dart` `_CategoryCover`) | literally the gradient placeholder |
| Club page with no cover | empty `primaryContainer` box (`club_page_screen.dart` ~l.286) | "empty frame" tell |
| Logo in app | `logo_mark.jpg` (600px JPG) zoomed ×1.9 inside a white circle (`lib/widgets/app_logo.dart`) | A raster in a circle; not a mark the UI is built around |
| Wordmark | "MYKerawang" in Jakarta w800 (`shell_actions.dart`) | Plain typed name |
| Splash / PWA | `manifest.json` theme `#5B3E96`; splash is the JPG in a white circle | Same |

### The identity we already own but don't use

`assets/MyKerawang.png` is a strong mark: a **K built from kerawang filigree
(cut-work)**, shading from deep plum through magenta to orange. It's the only part
of the brand that couldn't belong to any other app, and the UI ignores its
colours.

Two things about the source file:

- It's a 1408×768 raster with a generator sparkle in the bottom-right corner (the
  crop in `logo_mark.jpg` already excludes it). It needs a clean **vector
  redraw** before it can be a proper mark.
- Past lesson (commit `1155535`): the kerawang lattice motif was **retired because
  it felt like decorative noise**. Its dead code is still there: `KerawangLattice`,
  `LatticeBand`, `KerawangDivider` and the `motif*` tokens all render nothing.
  So the cut-work must carry identity in **one or two deliberate places**, not as
  a texture over everything.

### Small tells in the code

- Tracked-capitals labels: `letterSpacing: 0.6–0.8` with `fontSize: 9.5, w800` in
  `form_editor_screen.dart` (~l.814, 1583, 1631–1644, 1983), plus 13
  `toUpperCase()` calls in screens and widgets. The `labelSmall` theme also adds
  `+0.4` tracking.
- 63 hard-coded `fontSize:` values outside the theme (23 in
  `form_editor_screen.dart`, 8 in `form_responses_screen.dart`), and
  `SectionHeader` forces `18 / w600`. These will fight any new type scale.
- `OfficialFrame` (the "official / pinned" marker) **has no call sites**. The one
  component meant to signal "official" isn't used.
- The admin console uses the same identity as the student app. That's fine, but it
  should be the quietest surface, not decorated.

---

## 3. Identity direction

The rule taken from the post: **identity comes from the material (colour, type,
the mark, one signature component), not from ornament.** Every direction below
keeps the Floor (contrast test, focus, reduced motion, 320px layouts).

### Direction A: "Kerawang Plum" (recommended)

Build everything from the logo.

- **Personality:** a campus noticeboard with craft. Warm, local, a little formal
  where it's official (announcements, admin), lively where students talk (feed,
  market). Not a startup, not a bank.
- **Colour:** primary moves from generic violet to the logo's **deep plum /
  aubergine** (≈ `#5A1846`–`#6B1F5C`, tuned per theme by `_ensureContrast`).
  The accent moves from amber to the logo's **marigold-orange** (≈ `#E86A1F` fill;
  text colour derived for AA). Magenta stays inside the mark only, as a bridge.
  Backgrounds: Kampus a cool off-white, Istana warm paper, Noir a plum-tinted
  near-black rather than neutral grey.
- **Type:** keep **Plus Jakarta Sans for body and UI**. It's an Indonesian
  typeface, regionally apt, and already tuned. Add **one display face** for
  headlines, the wordmark and announcement titles. Candidates (all with Latin
  Extended for Malay; Japanese falls back to Noto Sans JP either way):
  - *Fraunces*: soft serif, warm, editorial (best for the "noticeboard" feel)
  - *Bricolage Grotesque*: quirky grotesk, younger
  - *Instrument Serif*: elegant, but thin at small sizes on phones
- **Mark and wordmark:** a vector K (SVG) in three versions: full colour, single
  plum, and white for photos and dark. No white circle; the mark stands on the
  surface. Wordmark: "MYKerawang" set in the display face, one colour (not a
  coloured "MY": that's the one-coloured-word tell).
- **Iconography:** keep Lucide through `AppIcons` (it's neutral and consistent).
  Identity doesn't come from icons. Commission or draw **only two brand glyphs**:
  "official/verified" and "pinned", in the K's cut-work style.
- **Illustration:** retire unDraw. Options in Decisions, Q4.
- **Signature component (the one place kerawang lives in the UI):** the **"cut"
  edge**. A small filigree notch / corner cut from the K, used *only* on official
  and pinned content (`OfficialFrame`), on the no-photo announcement cover, and
  on the generated club cover. Three uses, all meaning "this is official / this
  is ours".
- **Motion:** keep `KMotion` (150–250 ms). Add one brand moment: the splash mark
  resolves into the app bar mark on first load. Nothing else new. Reduced motion
  removes it.

### Direction B: "Kampus Editorial"

Lead with type, like a student newspaper. Serif headlines everywhere, rules
(lines) instead of card outlines in the feed and hub, almost monochrome (ink +
paper) with plum only for actions. Most distinctive in the announcements hub,
weaker in market and clubs, which need colour and photos. Bigger layout change,
so more layout-test churn.

### Direction C: "Polish only"

Keep purple and Jakarta. Only fix the tells: vector logo, kill unDraw and the
gradient placeholder, fill the empty club cover, remove tracked caps. Lowest
risk, smallest identity gain.

**Recommendation:** A, borrowing B's serif headlines for the announcements hub.

---

## 4. Concrete changes (Direction A), by file

### Tokens and theme

- `lib/theme/app_themes.dart`
  - `kThemeSpecs`: new `primary`, `gold`→accent, backgrounds and borders for
    `kampus`, `istana`, `noir`. Keep display names, or rename (Q6).
  - Text theme: `display*`, `headline*` and `titleLarge` in the display face;
    others stay Jakarta. Drop the `+0.4` tracking on `labelSmall`.
  - Load fonts from bundled assets rather than a runtime fetch (avoids a font swap
    flash on web); keep `debugUseSystemFonts` for tests.
  - `_CategoryCover`'s gradient goes away (see components).
- `lib/theme/tokens.dart`
  - `KTokens`: rename the meaning of `gold` to `accent` (keep `gold` as a
    deprecated alias so 11 call sites compile); add `accentFill` + `onAccentFill`;
    add `brandInk` (the plum used for the mark on light surfaces).
  - Remove the dead `motif*` fields only in the cleanup phase (they're 0 everywhere).
- `pubspec.yaml`: `fonts:` entries for the display face (+ Jakarta if bundled);
  `assets/brand/`.
- `test/theme_contrast_test.dart`: unchanged bar. Add pairs for
  `onAccentFill / accentFill` and `brandInk / background`.

### Brand assets

- New `assets/brand/mark.svg`, `mark_mono.svg`, `mark_white.svg`, `wordmark.svg`
  (from the vector redraw).
- `lib/widgets/app_logo.dart`: render the SVG via `flutter_svg` (already a
  dependency), with no white circle and no `Transform.scale(1.9)`; a `variant`
  parameter. Same constructor, so the 4 call sites (`login_screen.dart`,
  `main_scaffold.dart`, `shell_actions.dart`) keep working.
- `lib/widgets/shell_actions.dart`: the wordmark uses the display face (or
  `wordmark.svg`).
- `web/icons/Icon-*.png`, `Icon-maskable-*.png`, `web/favicon.png`: regenerate
  from the SVG (maskable with the safe zone).
- `web/manifest.json`: `theme_color` / `background_color` to the new plum.
- `web/index.html`: splash uses the inline SVG mark instead of the JPG in a white
  circle; `theme-color` meta values. This is plain HTML, the one place
  `/hallmark audit web/index.html` can be run.
- `assets/logo_mark.jpg` stays until nothing references it, then is removed.

### Components

- `lib/widgets/brand/official_frame.dart`: becomes the signature component (the cut
  corner, the official/pinned glyph, an accent hairline) and gets **wired up**:
  pinned announcements (`announcement_view.dart` / `announcements_screen.dart`),
  pinned and official-club posts (`post_card.dart`, `pin_controls.dart`).
- New `lib/widgets/brand/brand_cover.dart`: a generated cover for anything without
  a photo. Flat plum or accent field, the cut-work corner, and the category icon
  or club initials. Replaces `_CategoryCover` (announcements) and the empty box in
  `club_page_screen.dart`.
- `lib/widgets/brand/section_header.dart`: use `titleMedium` from the theme (no
  forced 18/w600). No eyebrow labels, ever.
- `lib/widgets/brand/app_illustration.dart`: same `AppIllo` enum and call sites
  (24), new art files; update `recolor()`'s map to the new art's placeholder
  colours.
- `lib/widgets/brand/brand_empty_state.dart`: tune for type-led empty states if
  illustrations are dropped (Q4).
- `lib/widgets/status_badge.dart`: accent and plum roles instead of ad-hoc tints.
- Delete the dead `kerawang_lattice.dart`, `lattice_band.dart` (keep
  `LatticeBand.preferred` as a plain divider helper, or inline it) and
  `widgets/kerawang_motif.dart` once grep shows no call sites. The audit found 0
  uses of the lattice classes outside `brand/`.

### Guardrails (a small "slop lint" for Flutter)

New `test/identity_rules_test.dart`: a source scan (like a lint) that fails on:

- `Color(0x` outside `lib/theme/` (allow-list `login_screen.dart` for the Google G)
- `LinearGradient` outside photo scrims (allow-list the scrim and the skeleton)
- `letterSpacing` > 0.2 combined with `toUpperCase()` in `lib/screens`
- `assets/illustrations/` files whose SVG still contains unDraw's `#6c63ff`

Each rule keeps an allow-list, so the test passes on day one and only blocks new
tells (Hallmark's "Reflex" tier: overrulable with a reason).

### A locked `docs/design.md`

The decisions as a short spec (palette, type scale, the signature component, the
tells we refuse). Hallmark, Claude Design and future agent sessions read this
before touching UI, so the identity doesn't drift back to the default.

---

## 5. Which screens first

Order is by how many people see it and how generic it looks today:

1. **First impression:** `web/index.html` splash, `login_screen.dart`,
   `onboarding_screen.dart`, `guest_views.dart`, the shell
   (`main_scaffold.dart`, `app_sidebar.dart`, `shell_actions.dart`). The mark,
   wordmark and colour show up here.
2. **Announcements hub:** `announcements_screen.dart`, `announcement_view.dart`.
   The most "official" surface: display-face titles, `BrandCover` instead of the
   gradient, `OfficialFrame` on pinned items.
3. **Home feed:** `home_screen.dart`, `post_card.dart`, `feed_composer.dart`.
   Mostly inherits from tokens; pinned/official posts get the frame.
4. **Clubs:** `club_page_screen.dart`, `club_directory_screen.dart`,
   `club_widgets.dart`. Generated covers and the official-club marker.
   ⚠ **Another agent is working on club registry/pin fixes on the same branch**,
   so this phase waits until that work has landed, to avoid conflicts in
   `club_page_screen.dart` and `pin_controls.dart`.
5. **Events and market:** `events_screen.dart`, `event_detail_screen.dart`,
   `marketplace_screen.dart`, `item_detail_screen.dart`. Accent on prices and
   dates, covers. Also the `fontSize` cleanup in `events/form_editor_screen.dart`
   and `form_responses_screen.dart`.
6. **Admin console last, and deliberately quiet:** `lib/screens/admin/*`.
   Neutral surfaces, plum only for actions, no covers, no cut-work. Utility first.

---

## 6. Phases (each ships alone, `flutter test` green at the end of each)

| Phase | Content | Visible change | Test risk |
|---|---|---|---|
| **0. Groundwork** | `docs/design.md`; `test/identity_rules_test.dart` with today's allow-lists; delete dead lattice/motif code; replace 63 `fontSize:` literals with theme styles; remove tracked caps | ~none | Low. Layout tests may shift a pixel where a hard-coded size changes; review per file |
| **1. Mark** | Vector mark + `AppLogo` SVG; wordmark; web icons, manifest, splash | Logo everywhere | Low. Logo sizes unchanged; `widget_test` / shell tests keep passing |
| **2. Colour** | New `kThemeSpecs`, `KTokens.accent*`, `brandInk`; contrast test pairs | Whole app recolours | Medium. Contrast test is the gate; `_ensureContrast` will adjust, check visually in all 3 themes |
| **3. Type** | Bundled display face for display/headline/titleLarge | Headlines change | Medium. Wider glyphs can overflow at 320px: run `screens_responsive_test`, `ui_layout_test`, `shell_layout_test`, `feed_layout_test`; tests use system fonts, so also check by eye in the browser at 320/375/768/1280 |
| **4. Signature** | `OfficialFrame` redesign + wiring; `BrandCover`; remove `_CategoryCover` gradient | Pinned/official look; no-photo covers | Low–medium. `announcements_hub_test`, `post_card_variants_test`, `v13_comment_pins_test` |
| **5. Illustration** | New art (or type-led empty states) behind the same `AppIllo` enum | Empty states | Low. `brand_widgets_test` "every illustration loads" covers it |
| **6. Surfaces** | Per-screen polish in the order of §5; clubs after the club work lands | Screen by screen | Per screen |

Every phase ends with a fresh-eyes review (a new agent session given only
`docs/design.md` and screenshots at 320/375/768/1280 in all three themes), checked
against the tells list. Deploys follow `deploy_web.bat` (BUILD_ID,
`--pwa-strategy none`, the service-worker reset), never a plain
`flutter build web`. Phase 1 changes icons, so the SW reset matters most there.
No phase touches `supabase/`.

---

## 7. Decisions for you

1. **Direction:** A (Kerawang Plum, recommended), B (Kampus Editorial), or C
   (polish only)?
2. **Colour:** move the primary from violet to the logo's plum, and the accent from
   amber to the logo's orange? Or keep purple as primary and only take the orange?
3. **Display font:** Fraunces (warm serif), Bricolage Grotesque (young grotesk),
   or no display font (Jakarta only)?
4. **Illustrations:** (a) commission or draw a small own set in the cut-work line
   style, (b) drop illustrations and use type-led empty states with the mark, or
   (c) keep unDraw for now and do it later? Open-licence sources, the hidden
   pages that need art, and a page-by-page proposal are in
   [illustration-sources.md](illustration-sources.md). *Partly decided
   2026-10-28: people in the new art are built on **Open Peeps** (CC0); still
   open: whether the set replaces unDraw now or later.*
5. **The logo redraw:** who makes the vector K? You or a designer from the
   original art, or should I trace a first version for you to approve? The current
   file is AI-generated raster, so check usage rights / originality before it
   becomes the official mark.
6. **Theme names and count:** keep Kampus Bold / Istana Modern / Songket Noir as
   they are, retune them, or cut to two (light + dark)?
7. **Kerawang in the UI:** OK to bring it back in exactly one form (the cut edge on
   official/pinned content and generated covers), given the lattice was retired
   as noise before?
8. **Admin console:** agree it should be the plainest surface?
9. **Timing:** ship Phases 0–2 before the next deploy and the rest after, or hold
   the deploy until the whole identity is in?
10. **Hallmark itself:** install it to audit `web/index.html` and any future
    marketing / landing page, or just use its checklist (this plan)?
