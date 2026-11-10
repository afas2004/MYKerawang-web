# Link previews

Written 2026-11-10, with the `feat/link-previews` branch.

## The problem

Flutter web serves one `index.html` for every URL. WhatsApp, Telegram and other
link previewers never run JavaScript, so they only read that file's `<meta>`
tags. Every shared listing, event and post got the same card: the logo and
"MYKerawang". A seller sharing a listing link into a group chat looked worse
than a seller posting a photo.

## What changed

| File | What it does |
|---|---|
| `functions/index.js` | The Firebase Function `linkPreview` (2nd gen, `asia-southeast1`) |
| `functions/handler.js` | Fetches the live `index.html`, looks the page up in Supabase, serves the result |
| `functions/preview.js` | Pure helpers: path parsing, title and description wording, tag injection |
| `functions/test/preview.test.js` | 22 tests, run with `cd functions && npm test` |
| `firebase.json` | A rewrite that sends `/item/:id`, `/event/:id` and `/post/:id` to the function, ahead of the catch-all |

For those three URL shapes only, the function:

1. fetches `https://<host>/index.html` (the static file, so it never loops
   back into itself, and it is always the current build with its `BUILD_ID`
   stamp);
2. reads the row from Supabase **as `anon`, with the publishable key**, so it
   sees exactly what a signed-out guest sees: hidden listings, hidden or
   private events and anonymous authors stay out, because RLS and
   `posts_public` already handle them;
3. removes the generic `description`, `og:*` and `twitter:*` tags and inserts
   the page's own right after `<meta charset>`;
4. serves the page to everyone. People get the normal app; there is no
   redirect and no crawler sniffing.

Deeper paths (`/item/:id/edit`, `/event/:id/checkin`, `/event/:id/form`…) do
not match the rewrite and are served as before.

### What a preview says

| Page | Title | Description | Image |
|---|---|---|---|
| Listing | `Samyang ramen · RM5.50`, with `SOLD · ` or `Reserved · ` in front when it applies | the listing description | the cover photo |
| Event | the title, with `CANCELLED · ` in front when it applies | `Sat, 15 Nov, 8:00 pm · <place> — <description>`, in Malaysia time | the event image |
| Post | the title, or else its first line, then `— <club, name or "Anonymous">` | the rest of the post | the cover, or else the first image |

With no image, the card falls back to the app icon.

### When something goes wrong

The function is never worse than before. If the row is missing, hidden or
private, or Supabase errors or takes more than 2.5 s, the page is served with
the generic tags, exactly as Hosting served it before. Only if `index.html`
itself cannot be fetched does it answer 503, which would mean Hosting is down
anyway.

### Caching and cost

- The response carries `Cache-Control: public, max-age=0, s-maxage=300`. The
  Hosting CDN keeps each page for 5 minutes, so a link tapped 50 times in a
  group runs the function about once. Every Hosting deploy purges that cache,
  so a new build never pairs with an old `index.html`. The trade-off is that
  marking an item sold can take up to 5 minutes to show in new previews.
- `maxInstances: 3` puts a hard ceiling on cost if a link is ever hammered.
- At college traffic this sits well inside the free allowance (2 million
  invocations a month), but **2nd gen functions need the Blaze
  (pay-as-you-go) plan**. Set a budget alert in Google Cloud Billing when you
  upgrade, at RM5 or similar.

## Deploying it

`deploy_web.bat` deploys **hosting only**, so do this once, in this order:

1. Upgrade the Firebase project `mykerawang-app` to Blaze and add a budget
   alert.
2. `cd functions && npm install`
3. From the repo root: `firebase deploy --only functions`. The first deploy
   enables Cloud Functions, Cloud Build and Artifact Registry and takes a few
   minutes.
4. Then `deploy_web.bat` as usual. The new rewrite in `firebase.json` goes out
   with hosting.

**Do not run step 4 before step 3.** If the rewrite points at a function that
does not exist, the Hosting deploy is likely to fail, or those three routes
break.

After that, `deploy_web.bat` is enough for app changes. Redeploy the function
(`firebase deploy --only functions`) only when something in `functions/`
changes.

## Checking it

1. Open `https://kerawang.my/item/<a real id>` in a browser. The app should load
   as normal.
2. View the page source. The `og:title` near the top should name the listing.
3. Paste the link into a WhatsApp chat with yourself. If the old generic card
   shows, WhatsApp cached it earlier; add `?v=1` to the link to get a fresh
   preview.
4. To test before going live: `firebase emulators:start --only hosting,functions`
   after a `flutter build web`, then open
   `http://localhost:5000/item/<id>` and view the source.

## Known limits

- **Large photos may be skipped by WhatsApp.** The app compresses uploads to
  1920×1080 at 75 % quality, which can come out above the roughly 300 KB that
  WhatsApp reliably shows as a thumbnail. If big photos turn up as a card with
  no image, the fix is a smaller thumbnail saved at upload time, which needs an
  app change.
- **Profiles (`/u/:id`) are not covered** on purpose. A profile card would put a
  student's name and photo into any chat the link lands in. Add `u` to the
  rewrite and to `parsePath` if you decide otherwise.
- **The preview text is in English**, like the existing generic tags.
- **The Supabase URL and publishable key are written in `handler.js`** as well
  as in `lib/main.dart`. If the key is rotated, change both.
- **The rewrite regex was not tested against live Hosting** from the
  environment this was built in, which could not reach `kerawang.my` or
  Supabase. Step 4 of "Checking it" covers that.
