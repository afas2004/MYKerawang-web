# MYKerawang

A student community platform for Kolej Kerawang, UiTM Terengganu Cendering, built with Flutter and Supabase. It combines a confession/announcement social feed, a campus marketplace, and an events calendar in one app, with first-class support for both mobile and web.

## Screenshots

| Home Feed | Marketplace | Events |
| :---: | :---: | :---: |
| <img width="300" alt="image" src="https://github.com/user-attachments/assets/849677ad-6f74-4ba1-acd5-1ac143ee8455" /> | <img width="300" alt="image" src="https://github.com/user-attachments/assets/aa24445c-2ac8-41f4-9c7c-497e8b13c6d0" /> | <img width="300" alt="image" src="https://github.com/user-attachments/assets/0bc3abd9-e753-4bf2-bfd7-86ecf33b268d" /> |


## Web app

[**Access the website here**](https://mykerawang-app.web.app/)

*Sign up using email or Google account*

## Features

**Social feed**
- Post announcements, questions, confessions, lost & found notices, rants, or academic queries — anonymously if you'd rather
- Tag posts and `@mention` other students inline
- Share a marketplace listing or event straight into the feed as a card

**Marketplace**
- Browse and list items for sale
- Contact a seller directly via WhatsApp

**Events**
- Browse upcoming and past campus events
- Open a full detail page for each one

**Trust & safety**
- Report a post, listing, or user for spam, hate speech, inappropriate content, misinformation, or other reasons
- Reports go straight to Supabase for review

**Profiles & notifications**
- Follow other students and see follower/following lists
- Get realtime updates pushed to your device as local notifications (mobile)

**Built for mobile and web, from one codebase**
- Bottom-nav layout on mobile, sidebar + discovery rail on web
- Clean, shareable URLs on web (`/market`, `/event/:id`, `/post/:id`, and so on)
- QR generation and in-app scanning for quick actions
- Listings and events cache locally on mobile, so the feed still loads something offline

## Tech stack

- **Framework:** Flutter (Dart SDK `^3.8.1`), targeting Android, iOS, and Web from one codebase
- **Backend:** [Supabase](https://supabase.com) (Postgres + Auth + Realtime + Storage)
- **State management:** `flutter_bloc` (Cubits per feature: events, marketplace, profile, theme, language, login)
- **Routing:** `go_router`, with clean web URLs via `flutter_web_plugins`' path URL strategy
- **Local storage:** `sqflite` (mobile-only offline cache), `shared_preferences` (theme/language persistence)
- **Media:** `image_picker`, `flutter_image_compress`, `cached_network_image`, `photo_view`, `gal`
- **Other integrations:** `flutter_local_notifications` + `permission_handler` (push notifications), `url_launcher` (WhatsApp hand-off), `share_plus`, `qr_flutter` / `mobile_scanner`, `timeago`, `flutter_typeahead`, `flutter_parsed_text`

## Project structure

```
lib/
├── screens/          # Feature screens: home, search, marketplace, events, profile,
│                      # post/item/event detail, create post/listing/event, settings, login
├── widgets/           # Shared UI: post card, feed composer, embed card, mention input,
│                       # hover carousel, right rail, sidebar, kerawang motif, universal card
├── services/          # notification_service, share_service
├── utils/             # Responsive/adaptive layout helpers, image compression, file saving
│                       # (web vs. native), report_helper, feed seeder
├── theme/             # Named app themes (Kampus Bold / Istana Modern / Songket Noir)
├── l10n/              # Lightweight localisation (English / Bahasa Melayu / Japanese)
├── database_helper.dart  # sqflite offline cache (mobile only; skipped on web)
├── router.dart         # go_router route table
└── main.dart           # App entry point, Supabase init, global Cubit providers
```

## Getting started

**Prerequisites:** a Flutter SDK compatible with Dart `^3.8.1`, plus the Android Studio/Xcode toolchain for whichever platform you're targeting, and a Supabase project.

```bash
git clone https://github.com/afas2004/MYKerawang-web.git
cd MYKerawang-web
flutter pub get
flutter run
```

To run the web build specifically:

```bash
flutter run -d chrome
```



## Author

Built by Afas as a student project for Kolej Kerawang, UiTM Terengganu Cendering.
