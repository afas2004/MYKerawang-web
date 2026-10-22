-- Pinned comments: the post's author, the event's organiser, or an admin
-- can pin up to 3 comments per post / event. Pinned comments are listed
-- first with a "Pinned" label.
--
-- Pinning goes through pin_comment() so the limit and the permission
-- check can't be bypassed from the client; comments_public exposes
-- pinned_at. Safe to re-run.

alter table public.comments
  add column if not exists pinned_at timestamptz,
  add column if not exists pinned_by uuid references public.profiles(id) on delete set null;

create index if not exists comments_pinned_post_idx
  on public.comments (post_id) where pinned_at is not null;
create index if not exists comments_pinned_event_idx
  on public.comments (event_id) where pinned_at is not null;

-- ---------------------------------------------------------- view
-- Same as 20261019004100_moderation_core.sql (columns and hidden
-- filter); pinned_at is appended so `create or replace` keeps working.
create or replace view public.comments_public as
select
  c.id, c.post_id, c.event_id, c.body, c.is_anonymous, c.created_at,
  case when c.is_anonymous then null else c.user_id end as user_id,
  case
    when c.is_anonymous or pr.id is null then null
    else jsonb_build_object(
      'id', pr.id, 'username', pr.username,
      'display_name', pr.display_name, 'avatar_url', pr.avatar_url)
  end as profiles,
  c.pinned_at
from public.comments c
left join public.profiles pr on pr.id = c.user_id
where not c.is_hidden;

grant select on public.comments_public to authenticated, anon;

-- ---------------------------------------------------------- RPC
-- pin_comment(comment, true)  → pins (no-op if already pinned)
-- pin_comment(comment, false) → unpins
-- Errors (P0001, parsed by the app):
--   MOD:forbidden        not the post author / event organiser / admin
--   MOD:comment_pin_limit  already 3 pinned on this post or event
--                          (detail: {"max": 3})
create or replace function public.pin_comment(p_comment_id uuid, p_pin boolean)
returns timestamptz
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_post  uuid;
  v_event uuid;
  v_owner uuid;
  v_count int;
  v_max   constant int := 3;
  v_at    timestamptz;
begin
  select post_id, event_id, pinned_at into v_post, v_event, v_at
  from public.comments where id = p_comment_id;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;

  if v_post is not null then
    select user_id into v_owner from public.posts where id = v_post;
  elsif v_event is not null then
    select organizer_id into v_owner from public.events where id = v_event;
  end if;

  if v_uid is null or (v_owner is distinct from v_uid and not public.is_admin()) then
    raise exception 'MOD:forbidden' using errcode = 'P0001';
  end if;

  if not p_pin then
    update public.comments set pinned_at = null, pinned_by = null
    where id = p_comment_id;
    return null;
  end if;

  if v_at is not null then
    return v_at; -- already pinned
  end if;

  -- Serialise pins on the same target so two quick taps can't make 4.
  perform pg_advisory_xact_lock(hashtext(coalesce(v_post, v_event)::text));

  select count(*) into v_count from public.comments
  where pinned_at is not null
    and ((v_post is not null and post_id = v_post)
      or (v_event is not null and event_id = v_event));

  if v_count >= v_max then
    raise exception 'MOD:comment_pin_limit'
      using errcode = 'P0001',
            detail  = jsonb_build_object('max', v_max)::text,
            hint    = 'Unpin a comment first.';
  end if;

  v_at := now();
  update public.comments set pinned_at = v_at, pinned_by = v_uid
  where id = p_comment_id;
  return v_at;
end;
$$;

revoke execute on function public.pin_comment(uuid, boolean) from public, anon;
grant  execute on function public.pin_comment(uuid, boolean) to authenticated;
