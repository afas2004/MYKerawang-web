-- PDPA: let a user delete their own account and content.
--
-- delete_my_account(p_confirm_username) removes everything the user
-- authored or that points at them, then the profile and the auth user,
-- and writes a minimal audit row (no name, no content) so admins can
-- show the request was honoured.
--
-- Not covered: files in Storage (avatars, post/listing/event images,
-- payment QR). Supabase blocks deleting storage.objects rows from SQL;
-- clean those up with the Storage API (e.g. an Edge Function) if needed.

-- ---------------------------------------------------------- audit log
create table if not exists public.account_deletions (
  id         bigint generated always as identity primary key,
  user_id    uuid not null,
  deleted_at timestamptz not null default now(),
  counts     jsonb not null default '{}'::jsonb
);

-- No policies: only service_role / SQL editor can read it.
alter table public.account_deletions enable row level security;
revoke all on public.account_deletions from anon, authenticated;

-- ---------------------------------------------------------- helper
-- Runs `delete ... where <col> = uid` when the table/column exists, so
-- the function works whichever optional migrations have been applied.
create or replace function public._delete_rows_of(
  p_table text, p_column text, p_uid uuid)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  n integer := 0;
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = p_table
               and column_name = p_column) then
    execute format('delete from public.%I where %I = $1', p_table, p_column)
      using p_uid;
    get diagnostics n = row_count;
  end if;
  return n;
end;
$$;

revoke execute on function public._delete_rows_of(text, text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------- main RPC
create or replace function public.delete_my_account(p_confirm_username text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_profile  public.profiles%rowtype;
  -- ids as text so this works whatever the id column types are
  v_posts    text[];
  v_events   text[];
  v_listings text[];
  v_touched  text[];
  v_counts   jsonb := '{}'::jsonb;
  n          integer;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  if lower(coalesce(v_profile.username, '')) <>
     lower(trim(both '@ ' from coalesce(p_confirm_username, ''))) then
    raise exception 'username confirmation does not match' using errcode = '22023';
  end if;

  -- The last owner leaving would orphan the role ladder.
  if v_profile.role = 'owner' then
    raise exception 'owner_cannot_delete' using errcode = '42501';
  end if;

  select coalesce(array_agg(id::text), '{}') into v_posts
    from public.posts where user_id = v_uid;
  select coalesce(array_agg(id::text), '{}') into v_events
    from public.events where organizer_id = v_uid;
  select coalesce(array_agg(id::text), '{}') into v_listings
    from public.listings where seller_id = v_uid;

  -- Posts others commented on keep a correct comment_count below.
  select coalesce(array_agg(distinct post_id::text), '{}') into v_touched
    from public.comments
   where user_id = v_uid and not (post_id::text = any (v_posts));

  -- Comments: the user's own, and everything under the user's posts.
  delete from public.comments
   where user_id = v_uid or post_id::text = any (v_posts);
  get diagnostics n = row_count;
  v_counts := v_counts || jsonb_build_object('comments', n);

  update public.posts p
     set comment_count = (select count(*) from public.comments c where c.post_id = p.id)
   where p.id::text = any (v_touched);

  -- Posts that shared the user's events/listings lose the embed, not the post.
  update public.posts set shared_event_id = null
   where shared_event_id::text = any (v_events);
  update public.posts set shared_listing_id = null
   where shared_listing_id::text = any (v_listings);

  -- Notifications for, from, or about the user's content.
  delete from public.notifications
   where user_id = v_uid
      or actor_id = v_uid
      or data ->> 'post_id'    = any (v_posts)
      or data ->> 'event_id'   = any (v_events)
      or data ->> 'listing_id' = any (v_listings);

  if to_regclass('public.event_participants') is not null then
    delete from public.event_participants
     where user_id = v_uid or event_id::text = any (v_events);
  end if;

  if to_regclass('public.saved_items') is not null then
    delete from public.saved_items
     where user_id = v_uid
        or (item_type = 'post'    and item_id = any (v_posts))
        or (item_type = 'event'   and item_id = any (v_events))
        or (item_type = 'listing' and item_id = any (v_listings));
  end if;

  delete from public.posts where id::text = any (v_posts);
  v_counts := v_counts || jsonb_build_object('posts', cardinality(v_posts));
  delete from public.events where id::text = any (v_events);
  v_counts := v_counts || jsonb_build_object('events', cardinality(v_events));
  delete from public.listings where id::text = any (v_listings);
  v_counts := v_counts || jsonb_build_object('listings', cardinality(v_listings));

  v_counts := v_counts || jsonb_build_object(
    'follows', public._delete_rows_of('followers', 'follower_id', v_uid)
             + public._delete_rows_of('followers', 'following_id', v_uid));
  perform public._delete_rows_of('profile_contacts', 'user_id', v_uid);

  -- Reports the user filed: keep the moderation record, drop the link
  -- to the reporter. Falls back to deleting if reporter_id is NOT NULL.
  if to_regclass('public.reports') is not null then
    begin
      update public.reports set reporter_id = null where reporter_id = v_uid;
    exception when not_null_violation then
      delete from public.reports where reporter_id = v_uid;
    end;
  end if;

  insert into public.account_deletions (user_id, counts) values (v_uid, v_counts);

  delete from public.profiles where id = v_uid;
  -- Last: signs the user out everywhere and frees the email.
  delete from auth.users where id = v_uid;
end;
$$;

revoke execute on function public.delete_my_account(text) from public, anon;
grant  execute on function public.delete_my_account(text) to authenticated;
