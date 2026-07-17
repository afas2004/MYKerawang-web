# UI/UX Audit — MYKerawang (Web + Mobile)

Audited from source code, 2026-07-17. Severity: 🔴 broken/blocking · 🟡 hurts usability · 🟢 polish.

### Overall impression

The app has a solid Material 3 foundation: seed-color theming with light/dark modes, a user-selectable accent color, consistent bottom-sheet menus, and sensible empty states in Market/Events. The mobile experience is clearly the home turf. The biggest opportunity: the web experience currently *assumes touch* — several core interactions (refresh, hover feedback, keyboard submit) have no mouse/keyboard equivalent, and a handful of hardcoded colors undermine the otherwise-good dark mode.

---

## A. Web-specific weaknesses

| # | Finding | Severity | Solution |
|---|---------|----------|----------|
| A1 | **No way to refresh with a mouse.** Home feed refresh is pull-to-refresh only (`LinearRefresher`). Desktop users cannot drag-scroll, so content never refreshes without F5 (which reloads the whole app). | 🔴 | Add a refresh `IconButton` to the Home/feed header (show always, or `if (kIsWeb)`). Same for post_detail. |
| A2 | **Enter key doesn't submit login.** No `onSubmitted`/`textInputAction` on email/password fields. Desktop users type password → press Enter → nothing. | 🔴 | `textInputAction: TextInputAction.next` on email, `TextInputAction.done` + `onSubmitted: (_) => submit()` on password. |
| A3 | **"Take Photo" offered on web.** Create Listing/Event bottom sheets offer camera; `ImageSource.camera` is unreliable/unsupported in desktop browsers — taps do nothing. | 🔴 | Hide the camera `ListTile` when `kIsWeb`. |
| A4 | **No pointer cursor on ~24 tap targets.** Cards, grid tiles, avatars, media thumbnails use `GestureDetector`, which gives no hover cursor or ripple on web — nothing signals "clickable". | 🟡 | Replace with `InkWell` (cursor + ripple + focus for free), or wrap in `MouseRegion(cursor: SystemMouseCursors.click)`. Prioritize: marketplace tiles, feed cards, profile grid. |
| A5 | **Text can't be copied.** Listing descriptions, prices, phone numbers, event details are all `Text` — web users expect to select/copy (e.g. copy a price into WhatsApp). | 🟡 | Wrap detail screens' body in `SelectionArea`, or use `SelectableText` for descriptions/contact info. |
| A6 | **No tooltips on icon-only buttons** (notification bell, settings gear, share, save). Hover reveals nothing; screen readers get nothing. | 🟡 | Add `tooltip:` to every `IconButton` (also fixes a11y on mobile). |
| A7 | **Browser tab always says "MYKerawang".** No per-screen titles; multiple tabs are indistinguishable and history is useless. | 🟢 | Wrap screens in `Title(title: 'Marketplace — MYKerawang', ...)` or set in route builders. |
| A8 | **Favicon/PWA icons are still the default Flutter logo** (`web/icons/`, `favicon.png` untouched). First thing classmates see in the tab/home screen. | 🟡 | Export the app logo at 16/32 (favicon), 192/512 + maskable (PWA icons). |

## B. Cross-platform weaknesses

| # | Finding | Severity | Solution |
|---|---------|----------|----------|
| B1 | **Dark mode broken on the Login screen.** `backgroundColor: Colors.white`, hardcoded purple, grey subtitle — in dark mode the login page stays blinding white while the rest of the app is dark. AuthGate's loading screen is also `Colors.white` (white flash on startup in dark mode). | 🔴 | Use `theme.colorScheme.surface` / `primary` / `onSurfaceVariant`. Same fix in AuthGate. |
| B2 | **Create Event description box: `Colors.grey[100]` background.** In dark mode this is a light box with light text — likely unreadable. | 🔴 | `theme.colorScheme.surfaceContainer`. |
| B3 | **Settings screen ignores the user's chosen accent color** (`final primary = const Color(0xFF5B3E96)`). User picks a different seed color in that very screen, but the screen stays purple. | 🟡 | Use `Theme.of(context).colorScheme.primary`. |
| B4 | **No error states, only silent failures.** Feed/network errors are `debugPrint`ed; user sees an eternally empty screen with no explanation or retry. On flaky campus Wi-Fi this reads as "app is broken". | 🔴 | Add error state to cubits/screens: message + Retry button. Home screen especially. |
| B5 | **Password field has no show/hide toggle.** | 🟡 | `suffixIcon` visibility toggle flipping `obscureText`. |
| B6 | **Feed reshuffles on every refresh.** Injected events/listings use `Random()` — refreshing rearranges everything, disorienting and makes "where was that item?" impossible. | 🟡 | Seed the Random with a stable value per session (e.g. day-of-year), or inject deterministically (every 6th slot). |
| B7 | **Tiny delete targets on media thumbnails.** The red ✕ on picked photos is a `CircleAvatar(radius: 10)` = 20 px — far below the 44–48 px minimum; frustrating on touch, fiddly with mouse. | 🟡 | Keep visual at 20 px but wrap in a padded `IconButton`/`InkWell` with ≥ 40 px hit area. |
| B8 | **Grid/feed images decode at full resolution.** `CachedNetworkImage` without `memCacheWidth` — 4K upload → 4K decode in a 200 px tile → jank + memory on phones. | 🟡 | Set `memCacheWidth: ~2× tile width` on grid/feed images. |
| B9 | **Follow button hardcodes `Colors.black`/`Colors.white`** foreground — risks invisible label depending on mode. | 🟢 | Use `colorScheme.onPrimary` / `onSurface`. |
| B10 | **Error snackbars hardcode `Colors.red`.** | 🟢 | `colorScheme.error` + `onError` text. |
| B11 | **Pull-to-refresh needs a 300 px drag** (`triggerDistance: 300`). Standard is ~100–150; many users will never trigger it (and then also have no refresh button — see A1). | 🟡 | Lower to ~120, and add A1's button. |
| B12 | **All 5 tabs load at startup** (`IndexedStack` + cubits created in `main`). Slower first paint, 3+ parallel queries before the user sees anything. | 🟢 | Acceptable trade-off for snappy tab switching; consider lazy-creating cubits later. |

## C. What works well

- Consistent Material 3 theming from a single seed color, with working light/dark switching and user-selectable accent — rare in student projects.
- The 840 px responsive shell + adaptive marketplace grid (added this session) give the web version a deliberate look instead of stretched mobile UI.
- Empty states exist ("No items found"), loading indicators are consistent, and destructive actions (delete listing) have confirmation dialogs.
- The unified media list with COVER badge in create flows is a genuinely good pattern — clearer than most marketplace apps.
- Bottom sheets for contextual actions are used consistently across the app.

## D. Priority plan

1. **Dark-mode fixes (B1, B2)** — login is the first screen everyone sees; a broken dark mode there taints the whole impression. ~30 min.
2. **Web input parity (A1, A2, A3)** — refresh button, Enter-to-submit, hide camera on web. Without these, desktop users hit dead ends. ~1 h.
3. **Error + retry states (B4)** — turns "app is broken" moments into recoverable ones. ~1 h.
4. **Hover/click affordances (A4, A6)** — InkWell + tooltips pass. Mechanical but broad. ~1–2 h.
5. **Branding pass (A8)** — favicon + PWA icons before sharing the URL. Needs your logo file.
6. Everything 🟢 as time allows.

## E. Needs human eyes (can't verify from code)

- Actual color contrast of grey-on-white subtitle text (likely borderline — send a screenshot of Home in both themes).
- Whether the marketplace card aspect ratio (0.7) clips titles at 3–4 columns on desktop.
- Real feel of the 840 px shell — send a desktop screenshot if anything looks off.
- iPhone Safari rendering (fonts, safe-area insets around the bottom nav) once deployed.
