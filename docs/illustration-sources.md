# Illustration sources: students, modern + traditional, and the hidden pages

Companion to [visual-identity-plan.md](visual-identity-plan.md) (Phase 5, Decision 4).
Researched 2026-10-28. Every licence below was read on the source's own page,
repo or Wikimedia Commons record, not taken from a blog list. Recheck before
downloading: licences change.

**The idea:** no single open library has "UiTM students + Malay tradition + modern
campus life". So we **mix three layers**, all recoloured at runtime to the
brand palette by `AppIllustration.recolor()`:

1. **People:** a CC0 character kit we can edit (add tudung, baju kurung, baju
   Melayu, songkok, lanyard, backpack).
2. **Malaysian culture:** the Wikimedia Malaysia "WP25" songket-stitch drawings
   (wau, nasi lemak, KLCC, sape…) and CC0 songket patterns. This is the
   "traditional" half, and its cross-stitch look echoes the kerawang K.
3. **Small basics:** Fluent Emoji (MIT) for tiny state glyphs where a full scene
   is too much.

---

## 1. The hidden pages that need art

Found in the code. Today 8 unDraw files cover the first group and the rest are an
icon or plain text.

| Page / state | Where | Today | Proposed art |
|---|---|---|---|
| Empty feed | `home_screen.dart`, `tag_feed_screen.dart`, `announcements_screen.dart` | unDraw `emptyFeed` | Students (one in tudung) on a campus bench, phones down |
| No results | `search_screen.dart` +5 | unDraw `noResults` | Peep with a magnifying glass under a wau |
| Empty market | `marketplace_screen.dart` | unDraw `emptyMarket` | Empty stall with a nasi lemak bungkus (WP25 Nasi Lemak) |
| No events | `events_screen.dart` +2 | unDraw `noEvents` | Wau Kucing resting on a calendar |
| No notifications | `notification_screen.dart` +2 | unDraw `noNotifications` | Peep relaxing (Open Doodles "chilling" style) |
| Offline | 3 call sites | unDraw `offline` | A wau with no wind, lying on the padang |
| Welcome / onboarding | `onboarding_screen.dart` +3 | unDraw `welcome` | Group of students, songket band behind them |
| Login | `login_screen.dart` | unDraw `login` | Student with backpack and lanyard |
| **404 page** | `router.dart` `errorBuilder` | raw `Icons.explore_off_outlined` + text | **Wau with a snapped string** ("Wau terputus tali"): the signature lost-page art |
| User / club not found | `profile_screen.dart`, `club_page_screen.dart` | `AppIcons.person` / `lock` | Empty chair at a meja, small |
| Not an officer / admin lock | `club_page_screen.dart`, `admin_lock_screen.dart` | `AppIcons.lock` | No illustration. Songket pattern band + lock glyph (serious, not cute) |
| Generic error | `widgets/error_state.dart` | icon | A songket strip with one unravelled thread |
| Account restricted / standing | `standing_screen.dart`, `restriction_gate.dart` | icon/text | **No illustration on purpose**: moderation pages stay plain and calm |
| Guest gate ("sign in to continue") | `utils/guest_access.dart`, `guest_views.dart` | icon | Peep peeking through a pintu gerbang |
| Student verification | `screens/verification/verify_sheet.dart` | none | Fluent "Woman student" / "Graduation cap", small |
| Club members empty, saved items empty | `club_page_screen.dart`, `saved_items_view.dart` | icon | Icon stays (compact states); no scene needed |

New `AppIllo` values: `notFound`, `error`, `guestGate`, `notFoundPerson`. The
other states reuse the existing enum names, so their 24 call sites don't change.

---

## 2. Sources, in order of preference

### A. Free to use, no credit needed (CC0 / MIT)

| Source | Licence (verified) | What fits us | Caveats |
|---|---|---|---|
| **Open Peeps** by Pablo Stanley, openpeeps.com | **CC0** (on the site) | Hand-drawn mix-and-match people; SVG + PNG; recolourable. Base for our students | The site lists hair options but **no head coverings**: we draw tudung / songkok parts ourselves (CC0 allows it) |
| **Humaaans** by Pablo Stanley, humaaans.com | **CC0** (on the site) | Flat modular people (poses, outfits). Cleaner, more "app" than Open Peeps | Same: add tudung / baju kurung parts. Pick **one** of Peeps or Humaaans, not both |
| **Open Doodles** by Pablo Stanley, opendoodles.com | **CC0**, "no need to credit" | 33 loose sketches: reading, sitting-reading, coffee, chilling, meditating, selfie, running | Small set; good for no-notifications / no-results moods |
| **Malay songket patterns** by EmpAhmadK, Wikimedia Commons (`Malay songket pattern - Delatar/Muktamad/Perseri.svg`) | **CC0** (Commons record) | Real Malay songket motifs as SVG, one colour, so they recolour cleanly to plum/marigold | Only 3 files. Use as bands/edges (sparingly: the lattice was retired as noise) |
| **Fluent Emoji** by Microsoft, github.com/microsoft/fluentui-emoji | **MIT** (repo) | Flat / Color / High-Contrast / 3D SVGs. Confirmed present: *Woman student*, *Man student*, ***Woman with headscarf*** (6 skin tones), *Graduation cap*, *Backpack*, *Open book*, *Books*, *Kite*, *Mosque*, *Cooked rice*, *Calendar*, *Shopping bags*, *Magnifying glass*, *Locked*, *No entry*, *Ghost*, *Sleeping face*, *Wilted flower*, *Satellite antenna*, *Party popper*, *Sparkles*, *Construction* | Use **Flat** or **High Contrast** only, small (≤48px), never mixed with scenes in the same view. The 3D style clashes with line art |
| **Openclipart**, openclipart.org | **CC0** for everything | Odd items: ketupat, wau, bunga raya, kampung house. Search per need | Quality varies a lot; skip anything tagged `pd_issue` (provenance under review) |
| **Muslim Illustration**, muslim-illustrations.vercel.app | Site states **CC0** for all, SVG + colour picker | Muslim-themed scenes, possibly hijab characters | **Author and catalogue size not stated, no repo.** Provenance unclear: check each file before use, or skip |
| **Lucide** (already in the app via `AppIcons`) | ISC | Icons stay as they are | — |

### B. Free with a credit line (CC BY 4.0)

| Source | Licence (verified) | What fits us | Caveats |
|---|---|---|---|
| **Wikimedia Malaysia "WP25" set** by Geleparaplu for Wikimedia Malaysia, Commons files `WP25 MY …svg` | **CC BY 4.0** (Commons records) | **The best "modern + traditional" find.** Single-colour cross-stitch / songket-stitch drawings: *Wau Bulan*, *Wau Kucing*, *Wau Jala Budi*, *Nasi Lemak*, *KLCC*, *Penang Bridge*, *Terengganu Drawbridge*, *Sape*, *Sompoton*, *Sun bear* (head + full body), *Hai Rumi*, *Apa khabar Jawi*. One flat colour, so they recolour perfectly | Credit required: "Illustration: Geleparaplu / Wikimedia Malaysia, CC BY 4.0". **Don't use** the `WP25MY Background Corak Songket *.png` files: they carry the Wikipedia "W" mark (a trademark). The older `WIkipedia 20 - Malay Wau.svg` is **CC BY-SA** (share-alike): avoid |
| **Islamicons**, github.com/nureddinhaji/islamicons | MIT (repo; keep the licence text) | Islamic icons drawn to one standard (mosque, crescent, prayer times) | Very new / small project (1 star); only if we need such icons |

### C. Avoid for this app

| Source | Why not |
|---|---|
| **unDraw** (what we use now) | Licence is fine, but it's the most recognisable stock set on the web. It's the main "generic" tell in our audit |
| **Storyset** (Freepik) | Credit required, can't be used in logos, licence can be ended (then you must delete everything); restrictive terms |
| **Freepik / Vecteezy / IconScout** (where most "baju kurung / hijab student" vectors are) | Own licences, credit or premium, per-item terms; not open. Fine to *look at* for reference, not to ship |
| **DrawKit** free packs | No credit needed, but no redistribution and no use in templates or apps-as-templates; adds a different house style |
| **GetIllustrations** etc. | Paid |
| AI-generated "free" images (e.g. easy-peasy.ai baju kurung) | Unclear ownership, raster, and exactly the look the Hallmark thread warns against |

---

## 3. How to make them one family

Mixed sources only look intentional if they share rules:

- **One stroke, one palette.** Recolour everything to: ink (text colour), plum
  (primary), marigold (accent), one neutral fill. Extend the map in
  `AppIllustration.recolor()` (it already swaps unDraw's `#6c63ff`). The WP25
  drawings and songket patterns are single-colour, so they map to plum in one line.
- **People in line art, culture in stitch.** Characters from Open Peeps (or
  Humaaans) in the ink line; cultural objects in the songket-stitch texture. That
  contrast *is* the "modern student + tradition" story.
- **Representation:** UiTM is a Bumiputera campus. Most characters should wear
  tudung / baju kurung / baju Melayu, plus casual campus wear (hoodie, lanyard,
  backpack), with a mix of skin tones. We add these parts to the CC0 kit and keep
  them in `assets/illustrations/_parts/` (not bundled).
- **Size rules:** full scenes (≤ 200px) only on whole-page empty states and the
  404; compact states keep an icon; moderation and admin pages get none.
- **Dark theme:** test every new file in Songket Noir; `recolor()` already
  remaps inks and greys on dark, so new art must use the same placeholder colours.

## 4. Code and housekeeping (when Phase 5 runs)

- `assets/illustrations/*.svg`: new files under the same names as today, plus
  `not_found.svg`, `error.svg`, `guest_gate.svg`, `not_found_person.svg`.
- `lib/widgets/brand/app_illustration.dart`: new `AppIllo` values and an
  extended recolour map.
- `lib/router.dart` `errorBuilder`: use `BrandEmptyState(illo: AppIllo.notFound, …)`
  instead of the raw Material icon.
- `lib/widgets/error_state.dart`, `utils/guest_access.dart`: use the new illos.
- `assets/illustrations/LICENSE.md`: one row per file with source, author,
  licence and changes made.
- **Credits in the app:** there's no licence page today. CC BY needs one. Add an
  "Open-source credits" entry in `settings_screen.dart` that opens Flutter's
  `showLicensePage`, and register the art credits with
  `LicenseRegistry.addLicense` in `main.dart`.
- Tests: `test/brand_widgets_test.dart` "every illustration loads" covers new
  enum values automatically; extend the recolour test with one WP25 file.

## 5. Questions for you

1. **People kit:** Open Peeps (hand-drawn, warmer) or Humaaans (flat, cleaner)?
2. OK to carry a **credit line** (CC BY) for the WP25 Malaysia drawings, or CC0
   only?
3. Who draws the **tudung / baju kurung / songkok** parts? Me in SVG, for you to
   review, or a student designer (could be a club project)?
4. Is the **"wau terputus tali" 404** the right tone, or should the lost page be
   plainer?
