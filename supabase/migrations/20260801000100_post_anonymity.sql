-- Anonymous posts and comments must not expose their author.
-- RLS filters rows, not columns, so the flag alone is not enough:
-- base-table reads are narrowed to the author, and public reads go
-- through a view that nulls the author on anonymous rows.

-- ---------------------------------------------------------- defaults
update public.posts    set is_anonymous = false where is_anonymous is null;
update public.posts    set is_hidden    = false where is_hidden    is null;
update public.comments set is_anonymous = false where is_anonymous is null;

alter table public.posts
  alter column is_anonymous set default false,
  alter column is_hidden    set default false;
alter table public.comments
  alter column is_anonymous set default false;

-- ---------------------------------------------------------- helpers
create or replace function public.is_admin()
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

revoke execute on function public.is_admin() from anon;
grant  execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------- policies
-- coalesce(): `null = false` is null, which would hide the row.
drop policy if exists "Public read posts"   on public.posts;
drop policy if exists "posts_select_public" on public.posts;
create policy "posts_select_public" on public.posts
for select using (
  coalesce(is_hidden, false) = false
  and (coalesce(is_anonymous, false) = false or user_id = auth.uid())
);

drop policy if exists "Public read comments"   on public.comments;
drop policy if exists "comments_select_public" on public.comments;
create policy "comments_select_public" on public.comments
for select using (
  coalesce(is_anonymous, false) = false or user_id = auth.uid()
);

drop policy if exists "posts_select_admin" on public.posts;
create policy "posts_select_admin" on public.posts
for select to authenticated using (public.is_admin());

drop policy if exists "comments_select_admin" on public.comments;
create policy "comments_select_admin" on public.comments
for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------- views
-- Not security_invoker: these run as owner and bypass RLS, which is how
-- anonymous rows reach the feed at all. is_hidden is therefore enforced
-- here. Views carry no FK metadata, so relations are built as jsonb
-- rather than left to PostgREST embedding.
drop view if exists public.posts_public;
create view public.posts_public as
select
  p.id, p.title, p.body, p.image_url, p.gallery_urls, p.tags,
  p.upvotes, p.comment_count, p.is_anonymous,
  p.shared_event_id, p.shared_listing_id, p.created_at,
  case when p.is_anonymous then null else p.user_id end as user_id,
  case
    when p.is_anonymous or pr.id is null then null
    else jsonb_build_object(
      'id', pr.id, 'username', pr.username, 'display_name', pr.display_name,
      'avatar_url', pr.avatar_url, 'is_verified', pr.is_verified)
  end as profiles,
  case when ev.id is null then null else to_jsonb(ev) end as events,
  case when li.id is null then null else to_jsonb(li) end as listings
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
where p.is_hidden = false;

grant select on public.posts_public to authenticated, anon;

drop view if exists public.comments_public;
create view public.comments_public as
select
  c.id, c.post_id, c.event_id, c.body, c.is_anonymous, c.created_at,
  case when c.is_anonymous then null else c.user_id end as user_id,
  case
    when c.is_anonymous or pr.id is null then null
    else jsonb_build_object(
      'id', pr.id, 'username', pr.username,
      'display_name', pr.display_name, 'avatar_url', pr.avatar_url)
  end as profiles
from public.comments c
left join public.profiles pr on pr.id = c.user_id;

grant select on public.comments_public to authenticated, anon;

-- ---------------------------------------------------------- moderation
create or replace function public.admin_unmask_post(p_post_id uuid)
returns table (post_id uuid, author_id uuid, display_name text, username text)
language sql security definer stable
set search_path = public
as $$
  select p.id, p.user_id, pr.display_name, pr.username
  from public.posts p
  left join public.profiles pr on pr.id = p.user_id
  where p.id = p_post_id and public.is_admin();
$$;

revoke execute on function public.admin_unmask_post(uuid) from anon;
grant  execute on function public.admin_unmask_post(uuid) to authenticated;
