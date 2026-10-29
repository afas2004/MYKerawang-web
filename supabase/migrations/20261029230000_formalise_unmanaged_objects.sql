-- The eight objects that only ever existed in the dashboard.
--
-- An audit of the live database (2026-10-29) found functions, triggers and
-- policies that no file under supabase/ created, and that `git log --all` had
-- never seen:
--
--   handle_new_user()        trigger on auth.users  → creates the profile row
--   update_comment_count()   trigger on comments    → posts.comment_count
--   notify_new_event()       trigger on events      → a notification per user
--   events_insert_own        INSERT policy on events
--   listings_insert_own      INSERT policy on listings
--   ensure_profile_exists()  callable by anon, inserted a hard-coded identity
--
-- They were created by hand while the schema was still being invented. Because
-- they are load-bearing, the database could not be rebuilt from migrations/ —
-- a fresh project would sign people up with no profile row, lose comment counts,
-- lose new-event notifications, and lose the ability to insert an event. This
-- file adopts the three functions and two policies, and drops the one that was
-- never anything but a prototype stub.
--
-- Behaviour is kept as it was, with three deliberate changes:
--   * `set search_path = public` on each security-definer function. Without it a
--     caller can shadow the objects the body resolves (a classic definer
--     escalation) — `handle_new_user` and friends had no search_path at all.
--   * `on conflict (id) do nothing` in handle_new_user, so a profile that already
--     exists cannot make a signup fail.
--   * comment_count cannot go below zero, and NULL is treated as 0.
--
-- Re-runnable: create-or-replace, drop-if-exists + create for triggers and
-- policies, and the drop of ensure_profile_exists is idempotent.

-- ------------------------------------------------------- 1. signup profile
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role, bio)
  values (new.id, 'New Student', 'student', 'UiTM Student')
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ------------------------------------------------------- 2. comment counts
create or replace function public.update_comment_count()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
    set comment_count = coalesce(comment_count, 0) + 1
    where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts
    set comment_count = greatest(coalesce(comment_count, 0) - 1, 0)
    where id = old.post_id;
  end if;
  return null;
end;
$$;

-- ------------------------------------------------------- 3. new-event notice
create or replace function public.notify_new_event()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, title, message)
  select u.id,
         'New Event: ' || new.title,
         'Check out ' || new.title || ' at ' || coalesce(new.location, 'the venue')
  from auth.users u
  join public.profiles p on p.id = u.id
  where u.id <> new.organizer_id
    and coalesce(p.notify_new_events, true);
  return new;
end;
$$;

-- ------------------------------------------------------- 4. the triggers
-- The auth.users trigger is only attached to a real Supabase auth schema. The
-- local PGlite stub models auth.users with four columns and no
-- raw_user_meta_data, and every test creates its own profile row; attaching the
-- trigger there would collide with those inserts rather than test anything.
-- Production has the column, so the trigger is created there — verified after
-- applying with `select ... from pg_trigger where tgname = 'on_auth_user_created'`.
do $$
begin
  if to_regclass('auth.users') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema = 'auth' and table_name = 'users'
                   and column_name = 'raw_user_meta_data') then
    drop trigger if exists on_auth_user_created on auth.users;
    create trigger on_auth_user_created
      after insert on auth.users
      for each row execute function public.handle_new_user();
  end if;
end;
$$;

drop trigger if exists on_comment_change on public.comments;
create trigger on_comment_change
  after insert or delete on public.comments
  for each row execute function public.update_comment_count();

drop trigger if exists on_event_created on public.events;
create trigger on_event_created
  after insert on public.events
  for each row execute function public.notify_new_event();

-- ------------------------------------------------------- 5. insert policies
-- Recreated with the exact expressions the live database had: permissive,
-- authenticated only, checking ownership of the row being inserted. The other
-- insert policies (club, mod_restricted) are permissive too, so they still OR.
drop policy if exists "events_insert_own" on public.events;
create policy "events_insert_own" on public.events
for insert to authenticated
with check (organizer_id = auth.uid());

drop policy if exists "listings_insert_own" on public.listings;
create policy "listings_insert_own" on public.listings
for insert to authenticated
with check (seller_id = auth.uid());

-- ------------------------------------------------------- 6. the prototype stub
-- Never called by the app (no reference in lib/ or test/), executable by anon,
-- and it inserted a profile with a hard-coded name and avatar. Nothing depends
-- on it: if something did, this drop would fail rather than leave a hole.
drop function if exists public.ensure_profile_exists(uuid);

-- ------------------------------------------------------- 7. least privilege
-- Trigger functions are not callable directly; only CREATE TRIGGER needs EXECUTE,
-- which the owner keeps. Revoking keeps them off the RPC surface.
revoke execute on function public.handle_new_user()      from public, anon, authenticated;
revoke execute on function public.update_comment_count() from public, anon, authenticated;
revoke execute on function public.notify_new_event()     from public, anon, authenticated;
