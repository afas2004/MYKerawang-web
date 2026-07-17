# MYKerawang — Web Migration Log

Goal: make the Flutter app build and run on web (`flutter build web`), while keeping Android/iOS behavior unchanged.

## Session 1 — 2026-07-17

### Audit findings

The web platform folder (`web/`) already existed and the git remote was already connected to `https://github.com/afas2004/MYKerawang-web` (in sync with `origin/main`, with local uncommitted changes). Blockers found: `sqflite` cache (no web support), `dart:io` `File` usage in 8 files, `flutter_local_notifications` + `permission_handler` init at startup (would crash the web app before first paint), `gal` save-to-gallery (no web support), and placeholder web metadata.

### Fixes applied

**lib/services/notification_service.dart** — `init()`, `requestPermission()`, and `showNotification()` now early-return on web via `kIsWeb`. The app no longer touches Android-only plugins during web startup. Web push notifications are intentionally out of scope for now.

**lib/database_helper.dart** — all cache methods (`cacheListings`, `cacheEvents`, `getCachedListings`, `getCachedEvents`) are no-ops / return empty lists on web. The events and marketplace cubits already fall back to fetching from Supabase, so no cubit changes were needed. Offline cache remains active on mobile.

**lib/utils/local_image.dart (NEW)** — `LocalImage` class wrapping a picked `XFile` plus its bytes, so images can be shown with `Image.memory`/`MemoryImage` and uploaded with `uploadBinary` on every platform.

**lib/utils/image_compressor.dart** — rewritten from `compress(File) → File` to `compressBytes(Uint8List) → Uint8List` using `FlutterImageCompress.compressWithList`. On web, compression is skipped and original bytes are returned. Removed `dart:io` and `path_provider`.

**lib/screens/create_listing_screen.dart** and **lib/screens/create_event_screen.dart** — media list now stores `LocalImage` instead of `File`; previews use `Image.memory`; uploads use Supabase `uploadBinary` with `contentType: image/jpeg`.

**lib/screens/edit_profile_screen.dart** — avatar and DuitNow QR picks are `LocalImage`; previews use `MemoryImage`; uploads use `uploadBinary`.

**lib/screens/gallery_view_screen.dart** — accepts `LocalImage` or URL string; local items render via `MemoryImage`. Removed `dart:io`.

**lib/screens/image_preview_screen.dart** — `File? imageFile` parameter replaced with `Uint8List? imageBytes` (no existing callers used the file variant; all pass `imageUrl`).

**lib/screens/profile_cubit.dart** — `uploadAvatar` now takes an `XFile` and uploads bytes via `uploadBinary`. Removed `dart:io`. (Note: this method currently has no callers.)

**lib/services/share_service.dart** — sharing an image now uses `XFile.fromData(bytes)` instead of writing a temp file, removing `dart:io` and `path_provider`. Also made `sharePositionOrigin` null-safe instead of force-unwrapping the RenderBox.

**lib/screens/item_detail_screen.dart** — both "Save QR to Gallery" actions are guarded with `kIsWeb`; on web the image opens in a new tab (via `url_launcher`) so the user can save it manually. Mobile behavior via `gal` is unchanged.

**lib/screens/settings_screen.dart** — "Fix Notification Permissions" tile (uses `openAppSettings()` from `permission_handler`) is hidden on web.

**web/index.html** and **web/manifest.json** — title, app name, and description updated from Flutter placeholders to MYKerawang; theme color set to the app purple (#5B3E96).

### Verification done

Grep-verified: zero `dart:io` imports remain in `lib/`, zero `File(`/`Image.file`/`FileImage` usages, all `Gal.` calls behind `kIsWeb` guards, all storage uploads use `uploadBinary`. Flutter SDK is not available in this environment, so compile/run verification is pending on the dev machine.

### Still to do (next session)

1. On your machine: `flutter pub get`, `flutter analyze`, then `flutter run -d chrome` to smoke-test login, feed, marketplace, create listing/event with photos, profile edit, QR save, and share.
2. `flutter build web --release` and pick a host (Firebase Hosting, Vercel, or GitHub Pages).
3. Supabase: add the deployed URL to Auth → URL Configuration (redirect URLs), and confirm RLS is enabled on all tables (the anon key ships in the JS bundle).
4. Camera capture on web: `ImageSource.camera` support in browsers is limited; the gallery picker path works. Consider hiding "Take Photo" on web if it misbehaves.
5. Git hygiene: `android/build/` artifacts are tracked — add to .gitignore and untrack. Commit and push this migration.
6. Optional: real web notifications (e.g. Supabase Realtime + in-app snackbars, or FCM web push) to replace the no-op.

## Session 2 — 2026-07-17

### Verified

`flutter analyze` on the dev machine: **0 errors**. Remaining output is pre-existing lints (deprecated `withOpacity`, unused imports, `print` in seeder). App confirmed running in browser by Fahmi.

### Multi-browser / phone testing

Debug mode (`flutter run`) only serves one attached browser. For multi-device testing use a release build: `flutter build web --release`, then `cd build\web && python -m http.server 8080 --bind 0.0.0.0` and open `http://<PC-LAN-IP>:8080` on the phone (same Wi-Fi). Caveat: service workers/PWA install require HTTPS (localhost exempt), so PWA behavior only fully testable once deployed to HTTPS hosting.

### Responsive UI (adaptive pass)

- **lib/utils/responsive.dart (NEW)** — `Responsive` breakpoints/helpers and `ResponsiveShell`, which centers the whole app at max 840 px on wide screens (with themed gutters) and overrides `MediaQuery.size` to match. No-op on phones.
- **lib/main.dart** — wired `ResponsiveShell` via `MaterialApp.builder`, so every screen (including dialogs and pushed routes) is constrained at once. Also removed 7 unused imports flagged by analyze.
- **lib/screens/marketplace_screen.dart** — grid now computes columns from available width via `LayoutBuilder` (2 on phones → up to 4 wide).
- Profile photo grid left at 3 columns (Instagram-style, looks right within the 840 px shell). Feed/events are ListViews and behave fine when constrained.

### PWA status

Flutter web ships a service worker + manifest automatically. Manifest and iOS meta tags were fixed in session 1 (name, theme color #5B3E96, apple-touch-icon). Remaining requirement is HTTPS hosting; then iPhone Safari → Share → Add to Home Screen installs it standalone. Note iOS PWA limits: web push requires iOS 16.4+ and an installed PWA; no background sync.

### Security

- **SUPABASE_SECURITY_AUDIT.md (NEW)** — full RLS audit kit: queries to find unprotected tables, enable-RLS statements, per-table policies for all 9 tables detected in code (`profiles`, `listings`, `events`, `posts`, `comments`, `followers`, `event_participants`, `notifications`, `reports` — note the special notifications actor/recipient pattern), storage policies for `avatars`/`images` buckets, dashboard settings checklist, and a hostile verification test. **Action for Fahmi: run it in the Supabase SQL editor.**

### Still to do

1. Pick hosting (Vercel / Firebase / GitHub Pages) — discussion pending; needed for phone PWA testing.
2. Run the RLS audit kit in Supabase.
3. `flutter analyze` + smoke test the responsive changes (resize browser window; check marketplace grid).
4. Commit + push (with android/build gitignore fix).
5. Optional cleanup of pre-existing lints; add `shared_preferences` to pubspec (currently a transitive dep used by theme_cubit).

## Session 3 — 2026-07-17

### Fixed en route

- OAuth stuck on web: `login_cubit.dart` redirected to the mobile deep link `mykerawang://login-callback`; now `kIsWeb ? Uri.base.origin : deep link`. Requires the serving URL in Supabase Auth → Redirect URLs.
- `serve_phone.bat` added for LAN testing (release build + dhttpd + IP detection).
- `UI_UX_AUDIT.md` created — 20 findings, prioritized.
- `SUPABASE_SECURITY_AUDIT.md` created — full RLS kit (still needs to be run by Fahmi).

### Kerawang identity + desktop layout (decisions: BM/English mix, sidebar + right rail, crafted serif)

- **Theme** (`main.dart` → `buildKerawangTheme`): Fraunces serif for display/headline/titleLarge + app bar titles; songket gold (#C9A227) as `tertiary`; light/dark built from one function. AuthGate loading screen no longer hardcodes white (audit B1 partial).
- **lib/widgets/kerawang_motif.dart (NEW)**: `KerawangDivider` diamond ornament — used in login and sidebar; reuse in empty states later.
- **lib/screens/main_scaffold.dart (REBUILT)**: <900px keeps bottom tabs; ≥900px gets a 220px sidebar (serif wordmark, BM labels: Utama/Cari/Pasar/Acara/Profil, "Jom post" button, motif footer); ≥1150px adds a 300px right rail. Tab labels BM on mobile too.
- **lib/widgets/right_rail.dart (NEW)**: "Acara minggu ini" (3 upcoming events) + "Baru masuk pasar" (4 item thumbnails with RM price overlay), self-fetching, navigates to detail screens.
- **lib/utils/responsive.dart**: outer shell clamp raised 840 → 1320 to fit 3 columns; added `feedMaxWidth` (680) and `PageBody` widget.
- **PageBody applied to 9 pushed screens** (item/event/post detail, create listing/event/post, edit profile, settings, notifications) so they read as centered 680px pages on desktop instead of stretching to 1320.
- **Login screen redesigned**: theme-aware colors (fixes audit B1), serif heading, kerawang ornament, BM copy ("Selamat kembali", "Log masuk", "Jom sertai MYKerawang"), password show/hide toggle (audit B5), Enter-to-submit (audit A2), content capped at 420px.

### Session 3b — analyze fixes + audit items

`flutter analyze` after the PageBody script revealed 5 files with truncated tails (script bug). All repaired: settings/create_event/create_listing/item_detail restored from git HEAD content, edit_profile rebuilt manually. Then audit fixes applied: **A1** web refresh button + **A6** tooltips on Home app bar actions (BM: Muat semula/Notifikasi/Tetapan), **B4** Home error state with "Cuba semula" retry button, **A3** "Take Photo" hidden on web in both create screens, **B2** create-event description box uses theme color (dark mode fix), **B3** settings switches now follow the user's chosen accent color instead of hardcoded purple.

### Session 3c — i18n (EN default / BM / JA)

Visual test passed on all three breakpoints; commit landed. Then per Fahmi's decision, UI language switched to English-default with a switcher:

- **lib/l10n/app_strings.dart (NEW)** — `AppStrings` with full EN / MS / JA string sets (~35 keys).
- **lib/language_cubit.dart (NEW)** — `LanguageCubit` persisted via shared_preferences (same pattern as ThemeCubit) + `context.l10n` shorthand extension.
- **pubspec.yaml** — `shared_preferences` promoted to a direct dependency (was transitive; fixes lint).
- Strings applied to: MainScaffold (nav labels, Jom post→Create post), Home (section headers, tooltips, error state), Login (all copy), Marketplace (title, search hint, empty state), RightRail (both card titles).
- **Settings** — new Language section with SegmentedButton: English / B. Melayu / 日本語.
- Note: Fraunces has no Japanese glyphs; JA headings fall back to system font (acceptable).

## Session 4 — DESIGN_SPEC build order #1: three-theme system

Direction docs created earlier this session: PRODUCT_NOTES.md (announcements hub + room selection) and DESIGN_SPEC.md (the requirements doc; build order in §11). Also fixed: edge-to-edge desktop (shell no-ops ≥900), global mouse drag-scroll, HoverCarousel chevrons on Home.

Theme system (spec §2):
- **lib/theme/app_themes.dart (NEW)** — `AppTheme` enum {kampus, istana, noir}, `kThemeSpecs` palette table, `kerawangCut` signature border radius, `buildAppTheme()` with per-theme button shapes (kampus pills / others kerawang cut), Fraunces headings, gold as tertiary.
- **theme_cubit.dart (REWRITTEN)** — state is now just the named theme; persisted as 'appTheme'; legacy migration (old dark-mode users → Noir once; old seedColor prefs removed).
- **main.dart** — single `theme:` (no darkTheme/themeMode); old buildKerawangTheme removed.
- **settings_screen.dart** — Dark Mode switch + 6-color picker replaced by three horizontal theme cards (palette swatches, name, tagline, selected ring); dead `_colorButton` removed.

Verified via grep: no stale seedColor/toggleTheme/changeColor/themeMode references. Needs `flutter analyze` + visual pass on all three themes before commit.

Note for future sessions: the sandbox mount can serve stale file reads to bash — verify file state with host-side Read/Grep tools, not `tail`/`grep` in bash.

### Still to do

1. `flutter analyze` + visual test at multiple window widths (phone, ~1000px, ≥1200px).
2. Remaining audit items: refresh button on web (A1), hide "Take Photo" on web (A3), error/retry states (B4), InkWell/tooltip pass (A4/A6), favicon/PWA icons (A8), BM microcopy on remaining screens.
3. RLS kit, hosting decision, commit + push.

### Notes / decisions

- Chose "skip cache on web" over `sqflite_common_ffi_web` to keep the change minimal — the DB is purely an offline cache.
- Chose bytes-based (`XFile`/`Uint8List`) image handling everywhere instead of platform-conditional code, so mobile and web share one code path.
- `mobile_scanner` (QR scanning) supports web, left as is.
