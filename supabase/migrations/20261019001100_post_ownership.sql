-- Authors manage their own posts and comments — including anonymous ones,
-- whose author posts_public / comments_public blank out. Ownership is
-- answered by security-definer functions that only ever talk about the
-- caller's own rows, so nobody else learns who wrote what.
--
-- Writes go through functions rather than a broad UPDATE policy so an
-- author can't touch moderation or counter columns (is_hidden, upvotes,
-- comment_count, user_id) via the REST API.
--
-- Mention notifications are written here too: the anonymity flag is read
-- from the row itself, and anonymous mentions carry no actor_id.

-- ---------------------------------------------------------- notifications
-- Anonymous mentions have no actor (no-op if already nullable).
alter table public.notifications alter column actor_id drop not null;

-- ---------------------------------------------------------- ownership
create or replace function public.my_post_ids()
returns setof uuid
language sql security definer stable
set search_path = public
as $$
  select id from public.posts where user_id = auth.uid();
$$;

create or replace function public.my_comment_ids(p_post_id uuid)
returns setof uuid
language sql security definer stable
set search_path = public
as $$
  select id from public.comments
  where post_id = p_post_id and user_id = auth.uid();
$$;

-- ---------------------------------------------------------- posts
create or replace function public.update_my_post(
  p_post_id      uuid,
  p_title        text,
  p_body         text,
  p_tags         text[],
  p_image_url    text,
  p_gallery_urls text[]
)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  update public.posts
  set title        = p_title,
      body         = p_body,
      tags         = coalesce(p_tags, '{}'),
      image_url    = p_image_url,
      gallery_urls = coalesce(p_gallery_urls, '{}')
  where id = p_post_id and user_id = auth.uid();

  if not found then
    raise exception 'not the author of this post' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.delete_my_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.posts where id = p_post_id and user_id = auth.uid()
  ) then
    raise exception 'not the author of this post' using errcode = '42501';
  end if;

  delete from public.comments where post_id = p_post_id;
  delete from public.notifications where data->>'post_id' = p_post_id::text;
  delete from public.posts where id = p_post_id;
end;
$$;

-- ---------------------------------------------------------- comments
create or replace function public.update_my_comment(p_comment_id uuid, p_body text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  update public.comments set body = p_body
  where id = p_comment_id and user_id = auth.uid();

  if not found then
    raise exception 'not the author of this comment' using errcode = '42501';
  end if;
end;
$$;

-- Recounts rather than decrements, so it stays right whatever triggers
-- already maintain comment_count.
create or replace function public.delete_my_comment(p_comment_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_post_id uuid;
begin
  delete from public.comments
  where id = p_comment_id and user_id = auth.uid()
  returning post_id into v_post_id;

  if not found then
    raise exception 'not the author of this comment' using errcode = '42501';
  end if;

  delete from public.notifications where data->>'comment_id' = p_comment_id::text;

  if v_post_id is not null then
    update public.posts
    set comment_count = (select count(*) from public.comments where post_id = v_post_id)
    where id = v_post_id;
  end if;
end;
$$;

-- ---------------------------------------------------------- mentions
-- Notifies @usernames about the caller's own post (p_comment_id null) or
-- comment. Title/body come from the client in the canonical language.
create or replace function public.notify_mentions(
  p_post_id    uuid,
  p_comment_id uuid,
  p_usernames  text[],
  p_title      text,
  p_body       text
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_anon boolean;
begin
  if p_comment_id is null then
    select coalesce(is_anonymous, false) into v_anon
    from public.posts where id = p_post_id and user_id = auth.uid();
  else
    select coalesce(is_anonymous, false) into v_anon
    from public.comments
    where id = p_comment_id and post_id = p_post_id and user_id = auth.uid();
  end if;

  if v_anon is null then
    raise exception 'not the author' using errcode = '42501';
  end if;

  insert into public.notifications (user_id, actor_id, type, title, body, data)
  select pr.id,
         case when v_anon then null else auth.uid() end,
         'mention', p_title, p_body,
         jsonb_build_object('post_id', p_post_id, 'comment_id', p_comment_id)
  from public.profiles pr
  where pr.username = any(p_usernames) and pr.id <> auth.uid();
end;
$$;

-- ---------------------------------------------------------- grants
do $$
declare f text;
begin
  foreach f in array array[
    'public.my_post_ids()',
    'public.my_comment_ids(uuid)',
    'public.update_my_post(uuid, text, text, text[], text, text[])',
    'public.delete_my_post(uuid)',
    'public.update_my_comment(uuid, text)',
    'public.delete_my_comment(uuid)',
    'public.notify_mentions(uuid, uuid, text[], text, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant  execute on function %s to authenticated', f);
  end loop;
end;
$$;

-- ---------------------------------------------------------- policies
-- Direct deletes of one's own rows (the app uses the functions above,
-- which also clean up comments and notifications).
drop policy if exists "posts_delete_own" on public.posts;
create policy "posts_delete_own" on public.posts
for delete to authenticated using (user_id = auth.uid());

drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_delete_own" on public.comments
for delete to authenticated using (user_id = auth.uid());
