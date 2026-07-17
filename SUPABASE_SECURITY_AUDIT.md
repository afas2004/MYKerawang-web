# Supabase Security Audit Kit — MYKerawang

**Why this matters:** your `anonKey` ships inside the public JS bundle of the web app. Anyone can open DevTools, copy it, and call your Supabase API directly. Row Level Security (RLS) policies are the ONLY thing standing between them and your data. Every table and storage bucket must have RLS enabled with deliberate policies.

Tables detected in the app code: `profiles`, `listings`, `events`, `posts`, `comments`, `followers`, `event_participants`, `notifications`, `reports`.
Storage buckets detected: `avatars`, `images`.

Run everything below in **Supabase Dashboard → SQL Editor**.

---

## Step 1 — Find tables with RLS disabled (run first)

```sql
-- Tables in public schema WITHOUT RLS enabled  → these are fully exposed!
select tablename
from pg_tables
where schemaname = 'public'
  and rowsecurity = false;
```

```sql
-- Tables WITH RLS enabled but ZERO policies (RLS on + no policies = nobody
-- can access them via the API — app breaks silently)
select t.tablename
from pg_tables t
left join pg_policies p
  on p.schemaname = t.schemaname and p.tablename = t.tablename
where t.schemaname = 'public'
  and t.rowsecurity = true
group by t.tablename
having count(p.policyname) = 0;
```

```sql
-- Review every existing policy
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, cmd;
```

## Step 2 — Enable RLS everywhere

```sql
alter table public.profiles           enable row level security;
alter table public.listings           enable row level security;
alter table public.events             enable row level security;
alter table public.posts              enable row level security;
alter table public.comments           enable row level security;
alter table public.followers          enable row level security;
alter table public.event_participants enable row level security;
alter table public.notifications      enable row level security;
alter table public.reports            enable row level security;
```

## Step 3 — Policies (adjust column names if yours differ)

> Pattern used: public content is readable by signed-in users; rows can only be created/edited/deleted by their owner. `auth.uid()` is the caller's user id — it cannot be faked.

```sql
-- PROFILES: everyone signed-in can read, only you can edit yours
create policy "profiles_select" on public.profiles
  for select to authenticated using (true);
create policy "profiles_insert" on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy "profiles_update" on public.profiles
  for update to authenticated using (id = auth.uid());

-- LISTINGS: readable by all signed-in, writable by seller only
create policy "listings_select" on public.listings
  for select to authenticated using (true);
create policy "listings_insert" on public.listings
  for insert to authenticated with check (seller_id = auth.uid());
create policy "listings_update" on public.listings
  for update to authenticated using (seller_id = auth.uid());
create policy "listings_delete" on public.listings
  for delete to authenticated using (seller_id = auth.uid());

-- EVENTS: same pattern with organizer_id
create policy "events_select" on public.events
  for select to authenticated using (true);
create policy "events_insert" on public.events
  for insert to authenticated with check (organizer_id = auth.uid());
create policy "events_update" on public.events
  for update to authenticated using (organizer_id = auth.uid());
create policy "events_delete" on public.events
  for delete to authenticated using (organizer_id = auth.uid());

-- POSTS (adjust owner column: user_id / author_id)
create policy "posts_select" on public.posts
  for select to authenticated using (true);
create policy "posts_insert" on public.posts
  for insert to authenticated with check (user_id = auth.uid());
create policy "posts_update" on public.posts
  for update to authenticated using (user_id = auth.uid());
create policy "posts_delete" on public.posts
  for delete to authenticated using (user_id = auth.uid());

-- COMMENTS (adjust owner column)
create policy "comments_select" on public.comments
  for select to authenticated using (true);
create policy "comments_insert" on public.comments
  for insert to authenticated with check (user_id = auth.uid());
create policy "comments_delete" on public.comments
  for delete to authenticated using (user_id = auth.uid());

-- FOLLOWERS: you can only create/delete follows where YOU are the follower
create policy "followers_select" on public.followers
  for select to authenticated using (true);
create policy "followers_insert" on public.followers
  for insert to authenticated with check (follower_id = auth.uid());
create policy "followers_delete" on public.followers
  for delete to authenticated using (follower_id = auth.uid());

-- EVENT PARTICIPANTS: you can only join/leave as yourself
create policy "participants_select" on public.event_participants
  for select to authenticated using (true);
create policy "participants_insert" on public.event_participants
  for insert to authenticated with check (user_id = auth.uid());
create policy "participants_delete" on public.event_participants
  for delete to authenticated using (user_id = auth.uid());

-- NOTIFICATIONS: special case! Your app inserts notifications for OTHER
-- users (mentions, follows) from the client. So: users may INSERT rows
-- where they are the ACTOR, but only READ/UPDATE rows where they are the
-- RECIPIENT.
create policy "notifications_select" on public.notifications
  for select to authenticated using (user_id = auth.uid());
create policy "notifications_insert" on public.notifications
  for insert to authenticated with check (actor_id = auth.uid());
create policy "notifications_update" on public.notifications
  for update to authenticated using (user_id = auth.uid());

-- REPORTS: users can file reports as themselves; nobody reads them via
-- the API (review them in the dashboard, or add an admin role later)
create policy "reports_insert" on public.reports
  for insert to authenticated with check (reporter_id = auth.uid());
```

## Step 4 — Storage bucket policies

```sql
-- Check current storage policies
select * from pg_policies where schemaname = 'storage';
```

```sql
-- IMAGES bucket: public read (your app uses getPublicUrl),
-- signed-in users can upload; only uploader can overwrite/delete
create policy "images_public_read" on storage.objects
  for select using (bucket_id = 'images');
create policy "images_auth_upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'images');
create policy "images_owner_update" on storage.objects
  for update to authenticated using (bucket_id = 'images' and owner = auth.uid());
create policy "images_owner_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'images' and owner = auth.uid());

-- AVATARS bucket: same, but uploads restricted to the user's own folder
-- (app uploads to '<uid>/avatar_...' paths)
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatars_own_folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars'
              and (storage.foldername(name))[1] = auth.uid()::text);
```

## Step 5 — Dashboard settings checklist (no SQL)

1. **Auth → URL Configuration**: set Site URL to your deployed domain; add `http://localhost:8080` and the deployed URL to Redirect URLs. Remove anything you don't recognize.
2. **Auth → Providers → Email**: enable "Confirm email" so people can't sign up with someone else's address.
3. **Auth → Rate Limits**: keep defaults or tighten sign-up/sign-in limits.
4. **Auth → Passwords**: enable leaked-password protection (HaveIBeenPwned check) and minimum length ≥ 8.
5. **Storage → Buckets**: confirm `images` and `avatars` file-size limits (e.g. 5 MB) and allowed MIME types (`image/*`) so nobody uploads arbitrary files.
6. **Database → never expose `service_role` key** anywhere client-side. It bypasses RLS. Web bundle should only ever contain the `anon` key.

## Step 6 — Verify

After applying, re-run Step 1 queries (both should return zero rows), then test the app: browse, create a listing, edit profile. Then the hostile test — in DevTools console on your deployed site, verify this FAILS:

```js
// Should return an error / empty, NOT other users' rows being changed
const r = await fetch('https://zxjuqpqzyzmegdjttzyz.supabase.co/rest/v1/profiles?id=neq.own-id', {
  method: 'PATCH',
  headers: { apikey: 'ANON_KEY', 'Content-Type': 'application/json' },
  body: JSON.stringify({ bio: 'hacked' })
});
console.log(r.status); // expect 401/403 or 0 rows affected
```
