# Security review — MYKerawang web, before the club year

Date: 2026-10-25/26 · Branch `deepseek/clubs-admin` · Live build **202610251841 (1.9.1+26)**
Supabase project `zxjuqpqzyzmegdjttzyz` · Origin audited: **https://kerawang.my**

Method: read every migration and the client paths that touch each table, then
probe the live project with the *publishable* key only (the attacker's view).
Findings marked "measured" have a request/response behind them, not an
inference. Fixes marked **Done** are in this branch with tests; the rest need a
dashboard action or your sign-off.

---

## 0. Deploy first — done, and verified from the site

`pubspec.yaml` 1.9.1+26, `update_service.appVersion` 1.9.1, `deploy_web.bat`
run. From `https://kerawang.my`, not from the log:

| check | result |
|---|---|
| `/build.json` | `{"build_id":"202610251841"}` |
| `/version.json` | `1.9.1`, build `26` |
| `main.dart.js` | contains `1.9.1` (4,871,353 bytes) |
| headers | `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`, `Strict-Transport-Security: max-age=31556926` |

So the three hosting headers in the handover **are** live, and the app is no
longer behind the branch. (The six commits were already pushed; origin and the
worktree both sat at `874ef4f`.)

The client fixes in §10 were written **after** that deploy, so the live build
does not contain them yet. Nothing in the review depends on them being live
(the RLS findings were measured against the deployed build's database, which
is unchanged by a deploy). Run `.\deploy_web.bat` when you want them in
production; the only client behaviour changes are refusals (uploads that fail
the byte gate, links that fail the scheme check) and the CSV quoting.

---

## 1. Findings

Severity is about what an attacker can do without any credential, or with one
ordinary student account.

| # | Sev | Finding | Evidence | Exploit path | Fix |
|---|---|---|---|---|---|
| **C1** | **Critical** | The `images` bucket accepts anonymous create, overwrite, delete and listing | **Measured**: `POST /storage/v1/object/images/<any path>` → `200` with only the publishable key; `x-upsert:true` over an existing object → `200`; `DELETE` of an existing object → `200` *and the object 404s afterwards*; `POST /object/list/images {"prefix":"posts"}` → object names | No account needed. List `posts/`, then delete or replace every event/listing/post image; upload arbitrary image bytes (MIME allowlist still applies); burn your storage quota | `20261026015100_security_review_fixes.sql` drops the permissive policy and creates owner-scoped write policies. **Needs applying** (dashboard or `db push`) |
| **H1** | High | One ordinary account can hide anyone's post/comment/event/listing, with no admin and no threshold | `20261019004100:329-330` (insert = own report), `20261025001100:79-83` (client `category` accepted if in the enum), `:134` + `:166-167` (priority category → `mod_auto_hide`), `20261025003100:15` (`{harassment,inappropriate}` are priority). No rate limit on reports (`20261019004200:160-161` uses an empty kind) | `POST /rest/v1/reports {"target_type":"post","target_id":"…","category":"harassment","reason":"x"}` → target hidden immediately | Derive `category` from `reason` server-side and/or require reporter trust. SQL in `supabase/pending/…_security_signoff.sql` (block 3) — **your call**, it changes moderation behaviour |
| **H2** | High | `profiles`, `followers` and `event_participants` are world-readable, though the repo says anon gets only the public views | **Measured**: `GET /profiles?select=full_name` → `200`, 19 rows; `?select=device_id` → `200`; `/followers` → `200`, 8 rows; `/event_participants` → `200`. Repo intent: `20261019002100:5-10`, `20261022001100:8-10` | Anyone can scrape every student's full name, `device_id`, `is_banned`, `ban_reason`, `last_active_at`, plus the whole follow graph and who attends what | Revoke anon select + drop the `using (true)` anon policies — SQL in the signoff file (block 1). Guest pages use `profiles_public` / `follow_counts` / `event_participant_counts`, so they keep working |
| **H3** | High | Any signed-in user can insert a notification for any other user, with any title/body/type/data (route included) | `20261019003000:31-34`: `with check (actor_id = auth.uid())` — `user_id`, `type`, `title`, `body`, `data` unconstrained; client sends them directly (`create_event_screen.dart:408`, `profile_screen.dart:194`, `mention_service.dart:100`) | Spoof an "account will be deleted" notice, phish a link, or spam the bell forever | Replace with a relationship-checked policy (follow edge / authored mention) — signoff file block 2. Read `create_event_screen.dart:408` first: if that type is not follow/mention it needs its own clause |
| **M1** | Medium | A hidden (moderated) event is still enumerable through the counts view | `20261019002100:44-52` — owner-run view, only `is_public` filter, granted to anon | `GET /rest/v1/event_participant_counts` reveals hidden event ids + head-counts | **Done** in `…_security_review_fixes.sql` (adds `not coalesce(is_hidden,false)`) + test |
| **M2** | Medium | Sign-up domain check is a substring match | `20261026005100:47` `email like '%' \|\| domain` | Register `x@student.uitm.edu.my.attacker.example` while `registration_mode='student_only'` | **Done**: exact domain compare + test. (Currently moot — live mode is `open`) |
| **M3** | Medium | The admin verification path skips the student-domain rule | `20261025004100:336` only checks for an `@` | Any admin can mark a gmail address `verified`, unlocking gated actions | **Done**: `guard_verification_domain` trigger + test. Behaviour change: an admin can no longer verify a legacy non-domain address; do that by clearing `student_domain` for the operation, or ask for an owner-only override |
| **M4** | Medium | Form title/intro/help/choice caps are client-only | `20261026007100:544-546`, `:596`, `:604`; columns are plain `text`; `form_check_field` checked only the number of choices | Call `save_event_form` directly and store unbounded text | **Done**: column checks (120/500/300) + per-choice 60 in the validator + tests |
| **M5** | Medium | Club logo/cover/payment-QR pickers bypass every upload check | `club_manage_screen.dart:97-112` (before) — no `checkPhoto`; web compression is a no-op (`image_compressor.dart:13`) and `image_picker_for_web` never resizes GIFs | Officer uploads a renamed non-image or a sub-5 MB 65535×65535 GIF → decoded by every club-page visitor | **Done**: check at pick time + inside `PostService.uploadPhotos` (throws `PhotoUploadException`), plus a unit test |
| **M6** | Medium | Lossless WebP (VP8L) returned an unknown size, and `checkPhoto` allowed unknown | `photo_rules.dart:86` + `:134-136` (before) | VP8L decompression bomb passes the pixel ceiling | **Done**: VP8L dimensions parsed, unknown size now refused, tests |
| **M7** | Medium | Reporters can read the admin's internal decision note | `20261019004100:333-334` (row-level select, all columns) + `20261019004400:196-199` writes `resolution_note` | Reporter re-reads their own report row → admin's private reason | Column-level `revoke select (resolution_note, handled_by, decision ids)`; noted in the signoff file |
| **M8** | Medium | `delete_my_account` deletes/nulls *other* users' data | `20261019003200:99-100` (comments on my posts), `:109-112` (other users' posts' embeds), `:115-120` (their notifications), `:127-133` (their bookmarks), `:151` (nulls `reports.reporter_id`) | A user can wipe comments others wrote on their post and strip report attribution | Design decision — document it, or keep a pseudonymous reporter id. Not changed |
| **M9** | Medium | Admin PIN has no lockout, floor is 4 characters | `20261024006100:37-45` (server check ✓, bcrypt ✓), `:61` length floor | Stolen admin JWT + 10⁴ calls brute-forces the PIN | Add attempt counter/lockout; raise the floor. Dashboard/function change |
| **M10** | Medium | `admin_restrict_user` lets the user and the case disagree | `20261019004400:347-353` — `p_user_id` wins over `c.target_owner_id`, log uses the case | Restrict A while citing case B; audit points at B | Require the case to belong to the user, else ignore `p_user_id` |
| **M11** | Medium | `is_hidden` has no write guard; the invariant rests on base policies that are not in the repo | Pin columns got `mod_guard_pin_columns` (`20261019004500:33-44`), `is_hidden` got nothing; no `create table posts/comments/events/listings` anywhere in `supabase/migrations` | If any unseen UPDATE policy is `using (true)` (the test stub models exactly that), an author can unhide their own moderated post | Add a `mod_guard_hidden_columns` trigger (same shape as the pin guard). Not changed — needs to see the real policies first |
| **M12** | Medium | `event_contact()` reveals every event's WhatsApp/Telegram/e-mail/link to any signed-in user | `20261026003100:142-156` — only `auth.uid() is not null` | Enumerate all contacts for the year, harvest numbers | Per-user reveal cap like listing contacts (`20261019002600`) or "after joining". Product decision |
| **M13** | Medium | Hardcoded admin credentials in a shipped-looking file | `lib/utils/seeder.dart:57-58` (before): `admin@uitm.edu.my` / `StrongPassword123!`; a `service_role` JWT survives in git history | Anyone with the repo can try those credentials; the script force-creates a **confirmed** admin if run with a secret key | **Done**: both now come from `--dart-define`. Still rotate that password and confirm the old `service_role` JWT is revoked server-side |
| **M14** | Medium | CSV formula guard only looked at the first character | `text_rules.dart:84` (before) `codeUnitAt(0)` | `" =1+1"` or `"\n=1+1"` reaches Excel unprefixed (Excel trims leading whitespace before deciding) | **Done**: skip leading spaces/tabs, include LF, still pass numbers; tests |
| **M15** | Medium | Announcement action links skipped the scheme allowlist | `announcements_screen.dart:237-238` (before) called `launchUrl` directly; `announcements_repository.dart:56-58` accepted host-less `https:…` | No working `javascript:` path found (url_launcher_web refuses it), but the claimed single choke point was not real | **Done**: routed through `launchableUri` |
| **M16** | Medium | No Content-Security-Policy, no Permissions-Policy | measured: response headers on `/` | A hypothetical script injection has no second line of defence | **Tested** on a preview channel; header ready in §6 — not deployed |
| **M17** | Low | Session tokens live in `localStorage` (`sb-<ref>-auth-token`) | supabase_flutter web default; no custom persistence in `main.dart:56-59` | Readable by any XSS — which the app has no surface for today | Accepted for a canvas app; becomes relevant the day HTML renders DB text |
| **M18** | Low | `supabase` 2.10.0 sends the new-format key as `Authorization: Bearer sb_publishable_…` on every anonymous call | `supabase_client.dart:287,346-349` (locked version); fixed in 2.16.0 | Cosmetic/interop today (the key is public), a footgun if a secret key ever lands in `anonKey:` | `flutter pub upgrade` (no pubspec edit needed) |
| **M19** | Low | `followers`/`event_participants` exposure (same drift as H2) | as H2 | Social graph + attendance scraping | Included in H2's fix |
| **M20** | Low | DB-supplied URLs are fetched with `http.get` without a scheme check | `item_detail_screen.dart:308`, `share_service.dart:138` | Browser CORS limits the damage; a DB row can still make visitors hit an arbitrary host | Add an https/host check — not changed |
| **M21** | Low | Moderation thresholds readable by every signed-in user | `20261019004100:66-67` `using (true)` | Learn the auto-hide counts and priority categories, then trigger/evade | Accept or expose only a derived helper |
| **M22** | Low | `admin_unmask` is not bound to a case; accepted appeals leave the auto restriction | `20261019004400:455-484`, `:572-576` | Admin can unmask any anonymous post with a 10-char reason, unlogged to a case | Design note |
| **M23** | Low | Student e-mails are stored in the immutable, admin-wide `moderation_log` | `20261025005100:81-82`, `20261025004100:369-370` | Every admin can read every applicant's address forever | Store a hash or the domain only |
| **M24** | Low | `www.kerawang.my` has no certificate | handover, still true | Browser warning on a plausible typo'd host | Firebase Hosting → add domain (instruction 6) |

### SQL test suites are not green (found while adding tests)

* The shared stub had no `storage.buckets`, so **every** migration suite stopped
  at `20261026014100_storage_image_limits.sql` with *relation does not exist*.
  Fixed in `supabase/tests/moderation/stub.sql`. This is why the handover's
  "all applied, tests green" claim did not cover the SQL side.
* `moderation_test.mjs` still fails two assertions (pre-existing, documented) and
  then **crashes** at `select pin_post(...)` as a club account: `pin_post` is
  admin-only since `20261024004100_club_pins.sql`, and club pinning moved to
  `club_pin_post`. The test section was never updated.
* `create/*` and `posts_v13/*` are older harnesses that fail on their own data
  (`invalid input syntax for type uuid: "Debate Society"`) and a missing citext
  extension. They are not in the handover's list of suites to run.

---

## 2. The week's fixes — verified, not redone

| Claim | Verdict | Evidence |
|---|---|---|
| Link scheme allowlist before `launchUrl` | **Holds, one bypass closed** | `url_rules.dart:19-25` rejects host-less http(s) and every non-allowed scheme; used at `event_detail_screen.dart:445,1288`. The announcement link skipped it (fixed, M15) |
| PostgREST filter escaping | **Holds** | `filter_rules.dart:13-17`; every `.or()` value is `filterSafe`, a literal or a DB uuid (`club_service.dart:327`, `mention_input.dart:104,130`, `search_screen.dart:123,151,219`). No `.filter(`/`.textSearch(` call sites exist |
| CSV formula injection | **Holds, hardening applied** | All live exporters call `csvSafe` (`moderation_logic.dart:220-234`, `attendance_rules.dart:51-56`, `form_csv.dart:94-101`). Leading-whitespace/LF gap fixed (M14); unused `csvCell` now safe too |
| Upload caps | **Holds on 3 of 4 paths** | `media_picker_grid.dart:56`, `create_announcement_screen.dart:114`, `edit_profile_screen.dart:125`; the club manage pickers did not (fixed, M5) |
| Storage bucket MIME/size limits | **Applied and effective** | **Measured**: `text/html` upload to `images` → `400`; anonymous `image/png` upload is a separate (policy) hole, see C1 |
| Hosting headers | **Live** | See §0. No CSP and no Permissions-Policy yet (M16) |
| No HTML surface | **Holds** | No `HtmlElementView`, webview, `flutter_html` or `SelectableText.rich`; remote text renders through `Text`/`ParsedText` only |
| Client holds publishable key only | **Holds from 1.9.1** — but see M13/M18 | |

---

## 3. RLS, table by table

Legend: ✅ intended and enforced in the repo · ⚠️ drift or unverifiable · ❌ hole.

| Table | anon | authenticated | Owner-predicated? | Verdict |
|---|---|---|---|---|
| `profiles` | **select (all rows, 19 columns)** | select all; update own | base policy not in repo; `guard_profile_privileges` blocks role/is_verified/is_banned changes (`20260801000200:33-70`) | ⚠️ H2 — the trigger is good, the anon grant is not |
| `profiles_public` (view) | select | select | n/a — column-safe projection | ✅ |
| `posts` | select non-hidden, non-anonymous | select + insert/update/delete own | insert/update come from the base schema (not in repo); delete is `user_id = auth.uid()` (`20261019001100:187-189`); anonymity enforced in the policy (`20260801000100:33-37`) | ✅ for anonymity; ⚠️ base insert/update unverifiable |
| `posts_public` (view) | select | select | owner-run view, filters `is_hidden` + `post_visible_now`, nulls anonymous author | ✅ |
| `comments` | select non-hidden, non-anonymous | same + own | delete own (`20261019001100:191-193`); `is_hidden` via a restrictive policy (`20261019004100:410-416`) | ✅ |
| `comments_public` (view) | select | select | filters `is_hidden`, nulls anonymous author (`20261022003200:21-34`) | ✅ |
| `events` | select public, non-hidden | select + own writes | restrictive hidden filter (`20261026004100:14-19`) | ✅ |
| `listings` | select non-hidden | select + own writes | same | ✅ |
| `event_contacts` | **no access** (revoke all) | select/insert/update by the organiser | `event_contacts_owner` uses `events.organizer_id` (`20261026003100:125-138`) | ✅ for RLS; the RPC is the leak (M12) |
| `form_responses` | no access | **no access** — RPC only | `revoke all` (`20261026007100:118-119`); reads via `form_response_list` → `can_read_form` | ✅ |
| `form_fields` / `event_forms` | no access | no access (RPC only) | same | ✅ |
| `form_templates` | no access | select | templates are question text | ✅ |
| `notifications` | no access | select/update(is_read)/delete own; **insert for anyone** | select/update/delete by `user_id = auth.uid()`; insert only checks the actor | ❌ H3 |
| `club_members` | select for active clubs | select + own row | writes only via RPC | ✅ (public roster is intended) |
| `clubs` / `club_private` | active clubs only / none | + officer/admin | officers see their own club in any status | ✅ |
| `club_join_requests` | none | applicant + officers | `20261024005100:36-42` | ✅ |
| `event_attendance` | none | self + organiser + admin | `20261026003100:184-191` | ✅ |
| `event_participants` | **select** | select | repo says anon gets counts only | ⚠️ H2 |
| `followers` | **select** | select | repo says anon gets counts only | ⚠️ H2 |
| `saved_items` | none | own only | `user_id = auth.uid()` | ✅ |
| `reports` | select → `200`, 0 rows | insert own, select own | `reporter_id = auth.uid()` (`20261019004100:328-334`); update/delete revoked | ⚠️ M7 (column leak to the reporter) |
| `moderation_*`, `user_restrictions`, `appeals`, `student_verifications`, `access_settings`, `admin_access`, `account_deletions` | none | own rows, or admin | all `revoke all` + owner policies (`20261019004100`, `20261025004100`) | ✅ (M21 thresholds readable by design) |
| `content_categories` | select active | select active (+admin) | writes via RPC | ✅ |

The recurring defect is **not** the policies that exist — they are consistently
owner-predicated on `auth.uid()` — it is **drift**: tables the repo says anon
cannot read are readable on the live project. The repo cannot prove the base
table grants for `profiles`/`posts`/`comments`/`events`/`listings`/`reports`
because those `create table` statements are not in `supabase/migrations`; they
were made in the dashboard.

---

## 4. RPCs

All **157** security-definer functions in the migrations set
`search_path = public` — checked mechanically, zero exceptions. Every admin RPC
checks `mod_require_admin()` / `is_admin()` **before its first write**.

The ones you asked about:

| RPC | Auth check | Over-reach | Verdict |
|---|---|---|---|
| `form_response_list` | `can_read_form` = organiser / admin / **club officer** (`20261026007100:293-306`) | Returns every respondent's name, matric and raw answers to any of up to 15 officers | ✅ intended; data-minimisation note |
| `event_open_form` | none, **anon can call** | Returns only the id of an open form for an event | ✅ by design |
| `event_form_summary` | organiser / admin / club officer; returns null otherwise | count only | ✅ |
| `form_public` | anon | form definition + `mine` (own answers only) + `can_edit` | ✅ |
| `submit_form_response` | `auth.uid()`; `p_for_user` only with `can_manage_form` | An organiser can overwrite a respondent's earlier answers (`v_mine` lookup then `update`) | ⚠️ integrity: no lock/audit once submitted |
| `create_form_from_template` | organiser / admin / `can_act_as_club` | No cap on draft forms per event | ⚠️ minor |
| `mod_preview` | `case when public.is_admin()` in the query | none | ✅ |
| `mod_preview_raw`, `mod_set_hidden`, `mod_target_owner`, `mod_log`, `mod_notify` | none inside — **revoked from clients** | would be de-anonymisation / arbitrary-hide primitives | ✅ as long as the grants stay |
| `admin_*` (25 of them) | admin/owner first | `admin_restrict_user` (M10), `admin_unmask` (M22), `admin_set_student_verification` (M3) | ⚠️ |
| `is_admin` / `is_owner` | — | `revoke … from anon` does **not** remove the default PUBLIC grant, so anon could call them (returns false) | **Fixed**: revoked from `public, anon` |
| `forget_saved_target` | trigger-only | never revoked | **Fixed** |

---

## 5. Storage

Buckets: `images` (posts/photos/event covers, club logos, payment QRs, `qrs/`)
and `avatars`. MIME allowlist (`jpeg/png/webp/gif`) and 5 MB cap are applied and
effective — an HTML file is refused with `400`.

* `avatars`: anonymous upload/delete refused (`400`) — good, but its policies are
  dashboard-only; the owner scoping is unverified (an authenticated user
  overwriting another user's avatar by guessing `avatars/<uid>_<ts>.jpg` is
  possible unless the policy checks `owner`).
* `images`: **C1**. Anonymous create/overwrite/delete/list.
* Object names are generated (`posts/<stamp>_<i>.jpg`), but they are *not*
  uid-scoped, so even without listing an attacker can guess paths.

The migration replaces the `images` policies with:

```
read    anon, authenticated          bucket_id = 'images'
insert  authenticated                bucket_id = 'images' and owner = auth.uid()
update  authenticated, using/check   bucket_id = 'images' and owner = auth.uid()
delete  authenticated, using         bucket_id = 'images' and owner = auth.uid()
```

`avatars` is deliberately untouched: adding permissive policies would make it
*looser* (permissive policies OR together).

---

## 6. Hosting — CSP, tested, ready to propose

The wasm build cannot run under a CSP without `'wasm-unsafe-eval'`, and it needs
Google's CanvasKit on Android. Both verified by experiment:

1. **Control**: without `'wasm-unsafe-eval'` → `CompileError: WebAssembly.compileStreaming(): … violates … 'unsafe-eval' is not an allowed source` — 3 times, app never paints.
2. **Control**: without `'unsafe-inline'` → the four inline `<script>` blocks in `index.html` are refused (one of them carries the per-deploy `BUILD_ID`, so hashes cannot work without moving them to files).
3. **Target policy, local build** → zero violations, app boots.
4. **Target policy, preview channel** `https://mykerawang-app--csp-test-upj8aw7d.web.app` (deleted afterwards) → zero violations.
5. **Same preview, Android UA** (forces CanvasKit from `www.gstatic.com`) → `flutterCanvasKit: true`, `renderer: canvaskit`, zero violations.

Header actually served on the preview (this is the exact value to ship):

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'unsafe-inline' https://www.gstatic.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: blob: https://zxjuqpqzyzmegdjttzyz.supabase.co; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' https://zxjuqpqzyzmegdjttzyz.supabase.co wss://zxjuqpqzyzmegdjttzyz.supabase.co https://www.gstatic.com https://fonts.googleapis.com https://fonts.gstatic.com; media-src 'self' blob: https://zxjuqpqzyzmegdjttzyz.supabase.co; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'; upgrade-insecure-requests
Permissions-Policy: camera=(self), microphone=(), geolocation=(), payment=(), usb=(), accelerometer=(), gyroscope=(), magnetometer=()
```

Notes:
* `camera=(self)` is deliberate: the check-in QR scanner needs the camera.
* `'unsafe-inline'` stays because Flutter inlines four scripts and a splash
  `<style>`. It is the weakest part of the policy; the value here is
  `connect-src`/`img-src`/`script-src` host allowlisting, `object-src 'none'`,
  `base-uri` and `frame-ancestors`. If you later render any HTML content, move
  the inline scripts to files and switch to nonces.
* Every image URL in the live DB is on `zxjuqpqzyzmegdjttzyz.supabase.co`, hence
  the tight `img-src`. If anyone pastes an external image URL it will be blocked
  (broken image) until the host is added.
* Ship it as `Content-Security-Policy-Report-Only` for a few days first if you
  want zero risk; the enforcing value above is the one that was tested.
* `www.kerawang.my` has no certificate yet — add the domain before pointing
  anything at it.

---

## 7. Auth and sessions

| Item | State |
|---|---|
| Session storage | supabase_flutter default: `localStorage`, key `sb-<ref>-auth-token`. No custom persistence. XSS-readable but there is no HTML surface (M17) |
| OAuth redirect | built from `Uri.base.origin` + `/login?from=…` (`login_cubit.dart:165-178`), so it always returns to the origin the user is on — on kerawang.my it is kerawang.my. PKCE is the gotrue default (`gotrue_client.dart` `flowType = AuthFlowType.pkce`), and the app uses `getOAuthSignInUrl` + code exchange |
| `?from=` return path | `safeReturnPath` (`guest_access.dart:18-24`) rejects absolute URLs and `//host`; only same-app paths are honoured. No open redirect found |
| Email confirmation | `mailer_autoconfirm: false` — an unconfirmed account gets **no session**, so it cannot write; the app also treats `currentSession == null` as "check your email" (`login_cubit.dart:140-145`) |
| Unconfirmed / unverified writes | Supabase-level confirmation blocks writes. The app-level `verification_enabled` switch is **false** (`access_policy()`), so any confirmed address can post/sell/join — intended by the owner switch, worth knowing |
| Registration mode | `open` (`access_policy()`), so the student-domain rule is inactive; the sufi x bug is latent (M2) |
| Google provider | enabled (`/auth/v1/settings`: `google: true`), anonymous sign-in disabled, passkeys disabled |
| Password reset | `resetPasswordForEmail(email)` with **no** `redirectTo` (`login_screen.dart:98`) → uses the dashboard Site URL. Verify it is `https://kerawang.my` (instruction 2) |
| Brute force / captcha | none (Supabase's own rate limits only) — already on the launch checklist |

---

## 8. Client injection surface

Re-grepped `Uri.parse`, `launchUrl`, `canLaunchUrl`, `.or(`, `.filter(`,
`http.get`, `HtmlElementView`.

* 7 `launchUrl` sites: two DB-driven ones go through `launchableUri`
  (`event_detail_screen.dart:445,1288`); the announcement one now does too
  (`announcements_screen.dart:237`); one is a constructed `wa.me` link from
  digits; the rest are app routes.
* `clubs.socials` is rendered as `SelectableText`, never launched
  (`club_page_screen.dart:397`) — inert.
* `profile.website` is stored but never displayed.
* PostgREST filters: all interpolated `.or()` values pass `filterSafe`; none
  escape it.
* Two `http.get` calls on DB URLs (`item_detail_screen.dart:308`,
  `share_service.dart:138`) — CORS-limited, low (M20).
* No HTML/WebView/markup surface: `SvgPicture.string` only ever receives bundled
  assets.

---

## 9. Dependencies

`flutter pub outdated` + pub.dev advisories + the full OSV Pub dataset + GitHub
Advisory DB:

* **No resolved version is affected by any published advisory.** The only two
  advisories that touch packages in this tree (`http` CRLF injection,
  `shared_preferences_android` deserialization) affect versions *below* what is
  locked.
* One upgrade worth doing now, no CVE: `flutter pub upgrade` moves the Supabase
  stack (supabase 2.10.0 → 2.16.x, gotrue 2.16.0 → 2.27.x, supabase_flutter
  2.10.3 → 2.18.x) with no pubspec edit. 2.10.0 predates new-format key support
  and sends `Authorization: Bearer sb_publishable_…` on anonymous calls (M18).
* Everything else is behind-latest with no advisory (go_router 14→18,
  permission_handler 11→13, cached_network_image 3→4, etc.). No git/path
  dependencies; `pubspec.lock` is committed.

---

## 10. What changed in this branch

| File | Change |
|---|---|
| `supabase/migrations/20261026015100_security_review_fixes.sql` | **new** — form caps, hidden-event counts, exact signup domain, verification-domain trigger, `is_admin`/`is_owner`/`forget_saved_target` grants, `images` bucket policies (idempotent; storage block guarded) |
| `supabase/pending/20261026015200_security_signoff.sql` | **new** — the three changes that need your decision (anon profile/follow/attendance reads, notification insert, report category), commented out so nothing applies by accident |
| `supabase/tests/security/security_test.mjs` | **new** — 22 assertions covering every fixed property |
| `supabase/tests/moderation/stub.sql` | storage stub so the migration suites can run again |
| `lib/utils/photo_rules.dart` | VP8L size parsing; unknown size refused; `PhotoUploadException` |
| `lib/services/post_service.dart` | upload gate inside `uploadPhotos` (single choke point) |
| `lib/screens/clubs/club_manage_screen.dart` | logo/cover/QR picked images now pass `checkPhoto`, with the same message as other pickers |
| `lib/utils/text_rules.dart` | `csvSafe` skips leading whitespace, includes LF |
| `lib/utils/csv_saver.dart` | `csvCell` routes through `csvSafe` |
| `lib/screens/announcements/announcements_screen.dart` | action link goes through `launchableUri` |
| `lib/utils/seeder.dart` | no hardcoded e-mail/password; both from `--dart-define` |
| `test/photo_rules_test.dart`, `test/text_rules_test.dart` | new cases for the two holes |

Test runs:
* `flutter analyze --no-pub` → **0 errors** (pre-existing warnings only).
* `flutter test --no-pub` → **556 passed, 0 failed** (553 before + 3 new).
* `node supabase/tests/security/security_test.mjs .` → **22/22**.
* `clubs`, `forms`, `verification`, `events_links`, `attendance` → **ALL PASSED**.
* `moderation` → 2 known failures + the pre-existing `pin_post` crash (see
  "SQL test suites are not green" above).

Two things in the migration that are *tightenings*, not repairs:

* The new `event_forms` / `form_fields` check constraints are `NOT VALID`: they
  do not scan existing rows, but any future **update** of a legacy over-long
  row will fail until it is shortened. Forms already open are not touched.
* `guard_verification_domain` fires on `email`/`status` changes only, so
  existing verified rows are untouched; promoting a legacy address now needs
  `student_domain` cleared for that moment (see M3).

---

## 11. Do these, in this order

1. **Apply the fixes migration.** Supabase → SQL Editor, paste
   `supabase/migrations/20261026015100_security_review_fixes.sql`, run. Or
   `supabase db push` if you use the CLI. Then re-run the proof below.
   *Verify before/after:* before, with only the publishable key,
   `curl -s -o /dev/null -w "%{http_code}" -X POST
   "https://zxjuqpqzyzmegdjttzyz.supabase.co/storage/v1/object/images/probe.png"
   -H "apikey: <key>" -H "Content-Type: image/png" --data-binary @tiny.png`
   returns `200`; after it must be `400`/`403`. Delete the probe object.
2. **Supabase → Authentication → URL Configuration.** Site URL must be
   `https://kerawang.my`. Redirect URLs must list exactly
   `https://kerawang.my/**` (and `https://mykerawang-app.web.app/**` only while
   the old origin still serves sessions). Add nothing else — the table is the
   allowlist that stops a crafted `redirect_to`.
3. **Storage → Policies.** Look at `images`. If a policy named "Public Access"
   (or any `bucket_id = 'images'` policy for `ALL`/`INSERT` that does not check
   `owner`) survived the migration, delete it — two permissive policies OR
   together, so a leftover one keeps the hole open. Re-run the curl above.
4. **Storage → Policies → `avatars`.** Confirm the write policies require a
   signed-in user and, ideally, `owner = auth.uid()` for update/delete. The
   migration deliberately does not touch this bucket.
5. **Decide the three sign-off items** in
   `supabase/pending/20261026015200_security_signoff.sql`: anon reads on
   profiles/followers/participants (H2), the notification insert policy (H3),
   and server-derived report categories (H1). Each block states before/after and
   what could break.
6. **Firebase Hosting → add `www.kerawang.my`** (Custom domain → Add). Until
   then the www host serves a certificate warning.
7. **Ship the CSP** by pasting the two headers from §6 into `firebase.json`
   under the `**` source, then `firebase deploy --only hosting`
   (`*.web.app` preview channels inherit them). If you want a report-only
   shakedown, change the key to `Content-Security-Policy-Report-Only` first.
8. **Rotate `admin@uitm.edu.my`'s password** (the old one was committed) and
   confirm the legacy `service_role` JWT from git history is revoked in
   Settings → API.
9. **Add a failed-attempt lockout to `admin_check_pin`** (M9) and raise the
   4-character floor, or accept the PIN as a UX gate only.
10. **`flutter pub upgrade`** for the Supabase stack (M18), then re-run
    `flutter analyze` and the util tests.
11. **Optional, before inviting clubs:** confirm the base-table policies for
    `profiles`, `posts`, `comments`, `events`, `listings` and `reports` in the
    dashboard (Database → Policies) against §3. They are not in the repo, so
    that is the one part of the RLS picture I could not read.

---

## 12. Limits of this review

* No database password or Management API token was available here, so
  `pg_policies` could not be read directly. Repo-defined policies were read in
  full; dashboard-only policies and base-table grants were established by
  probing the live API as `anon`. **Authenticated** role behaviour could not be
  probed without creating a real account (sign-up needs e-mail confirmation), so
  the `authenticated` column in §3 is from the SQL, not from traffic. That is
  the gap instruction 11 closes.
* The CSP was verified on Edge/Chromium only (desktop and Android UA). Safari
  was not available; `wasm-unsafe-eval` is supported there since 16.4.
* Dependency advisories were checked to 2026-10-25.
