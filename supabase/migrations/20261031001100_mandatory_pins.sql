-- Mandatory pins, and two gaps in comment pins.
--   * An admin can make a global pin mandatory: it never expires
--     (pinned_until = 'infinity') and the Home pin bar offers no close button.
--   * pin_post gains p_mandatory. The old two-argument version is dropped:
--     keeping both would make a call with two arguments ambiguous.
--   * pin_comment: a pinned comment that moderation hid no longer takes one of
--     the three slots, club officers may pin on their club's posts and events,
--     and pins are logged.
-- Safe to re-run.

alter table public.posts
  add column if not exists pin_mandatory boolean not null default false;

-- ------------------------------------------------------- column guard
-- From 20261028120000, which added the club columns; pin_mandatory joins them.
create or replace function public.mod_guard_pin_columns()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null
     or coalesce(current_setting('mykerawang.pin_rpc', true), '') = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.pinned_until      := null;
    new.pinned_by         := null;
    new.pin_mandatory     := false;
    new.club_pinned_until := null;
    new.club_pinned_by    := null;
  else
    new.pinned_until      := old.pinned_until;
    new.pinned_by         := old.pinned_by;
    new.pin_mandatory     := old.pin_mandatory;
    new.club_pinned_until := old.club_pinned_until;
    new.club_pinned_by    := old.club_pinned_by;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_mod_guard_pin_columns on public.posts;
create trigger trg_mod_guard_pin_columns
before insert or update of pinned_until, pinned_by, pin_mandatory,
                           club_pinned_until, club_pinned_by
on public.posts
for each row execute function public.mod_guard_pin_columns();

revoke execute on function public.mod_guard_pin_columns() from public, anon, authenticated;

-- ------------------------------------------------------- pin / unpin
drop function if exists public.pin_post(uuid, boolean);

create or replace function public.pin_post(
  p_post_id   uuid,
  p_replace   boolean default false,
  p_mandatory boolean default false
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s       public.moderation_settings := public.mod_settings();
  v_uid   uuid := auth.uid();
  p       record;
  v_until timestamptz := case when p_mandatory then 'infinity'::timestamptz
                              else now() + make_interval(days => s.pin_duration_days) end;
begin
  if v_uid is null then
    raise exception 'MOD:not_signed_in' using errcode = '42501';
  end if;
  if not public.is_admin() then
    raise exception 'MOD:pin_not_allowed' using errcode = 'P0001';
  end if;
  select id, coalesce(is_anonymous, false) as anon, is_hidden
  into p from public.posts where id = p_post_id;
  if not found or p.is_hidden then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;

  perform set_config('mykerawang.pin_rpc', '1', true);
  update public.posts
  set pinned_until = v_until, pinned_by = v_uid, pin_mandatory = p_mandatory
  where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('pin', 'post', p_post_id::text, null,
    jsonb_build_object('until', v_until, 'scope', 'global', 'mandatory', p_mandatory));
  return jsonb_build_object('pinned_until', v_until, 'replaced', '[]'::jsonb,
                            'mandatory', p_mandatory);
end;
$$;

create or replace function public.unpin_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'MOD:pin_not_allowed' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  perform set_config('mykerawang.pin_rpc', '1', true);
  update public.posts
  set pinned_until = null, pinned_by = null, pin_mandatory = false
  where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);
  perform public.mod_log('unpin', 'post', p_post_id::text, null, jsonb_build_object('scope', 'global'));
end;
$$;

revoke execute on function public.pin_post(uuid, boolean, boolean) from public, anon;
grant  execute on function public.pin_post(uuid, boolean, boolean) to authenticated;

-- ------------------------------------------------------- posts_public
-- Same as 20261026003100; pin_mandatory appended last, because
-- `create or replace view` matches columns by position.
create or replace view public.posts_public as
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
  case when ev.id is null or ev.is_hidden then null else to_jsonb(ev) end as events,
  case when li.id is null or li.is_hidden then null else to_jsonb(li) end as listings,
  case when p.pinned_until > now() then p.pinned_until end as pinned_until,
  coalesce(p.pinned_until > now(), false) as is_pinned,
  case when cl.id is null or cl.status <> 'active' then null
       else jsonb_build_object('id', cl.id, 'handle', cl.handle::text, 'name', cl.name,
                               'logo_url', cl.logo_url, 'is_verified', cl.is_verified)
  end as club,
  case when cl.status = 'active' then p.club_id end as club_id,
  p.is_announcement,
  p.announcement_category,
  p.cover_url,
  p.action_links,
  p.linked_event_id,
  p.publish_at,
  p.feature_until,
  p.comments_enabled,
  p.show_in_feed,
  case when p.club_pinned_until > now() then p.club_pinned_until end as club_pinned_until,
  coalesce(p.club_pinned_until > now(), false) as is_club_pinned,
  p.cover_aspect,
  coalesce(p.pin_mandatory, false) as pin_mandatory
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
left join public.clubs    cl on cl.id = p.club_id
where p.is_hidden = false
  and public.post_visible_now(p.publish_at, p.user_id, p.club_id);

grant select on public.posts_public to authenticated, anon;

-- ------------------------------------------------------- comment pins
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
  v_club  uuid;
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
    select user_id, club_id into v_owner, v_club from public.posts where id = v_post;
  elsif v_event is not null then
    select organizer_id, club_id into v_owner, v_club from public.events where id = v_event;
  end if;

  if v_uid is null or (
       v_owner is distinct from v_uid
       and not public.is_admin()
       and not (v_club is not null and public.can_act_as_club(v_club))) then
    raise exception 'MOD:forbidden' using errcode = 'P0001';
  end if;

  if not p_pin then
    update public.comments set pinned_at = null, pinned_by = null
    where id = p_comment_id;
    perform public.mod_log('unpin', 'comment', p_comment_id::text, null, '{}');
    return null;
  end if;

  if v_at is not null then
    return v_at; -- already pinned
  end if;

  -- Serialise pins on the same target so two quick taps can't make 4.
  perform pg_advisory_xact_lock(hashtext(coalesce(v_post, v_event)::text));

  select count(*) into v_count from public.comments
  where pinned_at is not null
    and not coalesce(is_hidden, false)
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
  perform public.mod_log('pin', 'comment', p_comment_id::text, null, '{}');
  return v_at;
end;
$$;

revoke execute on function public.pin_comment(uuid, boolean) from public, anon;
grant  execute on function public.pin_comment(uuid, boolean) to authenticated;
