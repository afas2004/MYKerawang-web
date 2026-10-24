-- Two pin scopes, so a club's internal pin no longer promotes its post in
-- the global hub/home:
--
--   posts.pinned_until        admin → global (announcements hub, home)
--   posts.club_pinned_until   club officer → that club's own page only
--
-- Admin pins may stack (no cap). Club pins stay at
-- moderation_settings.max_active_pins_per_club (default 1) and replace the
-- current one. Legacy role='club' global pins stop working: those accounts
-- are club presidents now and use the club pin.

alter table public.posts add column if not exists club_pinned_until timestamptz;
alter table public.posts add column if not exists club_pinned_by uuid references public.profiles(id) on delete set null;

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
  coalesce(p.club_pinned_until > now(), false) as is_club_pinned
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
left join public.clubs    cl on cl.id = p.club_id
where p.is_hidden = false
  and public.post_visible_now(p.publish_at, p.user_id, p.club_id);

grant select on public.posts_public to authenticated, anon;

-- ------------------------------------------------------- global (admin)
create or replace function public.pin_post(p_post_id uuid, p_replace boolean default false)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s       public.moderation_settings := public.mod_settings();
  v_uid   uuid := auth.uid();
  p       record;
  v_until timestamptz := now() + make_interval(days => s.pin_duration_days);
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
  update public.posts set pinned_until = v_until, pinned_by = v_uid where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('pin', 'post', p_post_id::text, null,
    jsonb_build_object('until', v_until, 'scope', 'global'));
  return jsonb_build_object('pinned_until', v_until, 'replaced', '[]'::jsonb);
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
  update public.posts set pinned_until = null, pinned_by = null where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);
  perform public.mod_log('unpin', 'post', p_post_id::text, null, jsonb_build_object('scope', 'global'));
end;
$$;

-- ------------------------------------------------------- club-local
create or replace function public.club_pin_post(p_post_id uuid, p_replace boolean default false)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s          public.moderation_settings := public.mod_settings();
  v_uid      uuid := auth.uid();
  p          record;
  v_pins     jsonb;
  v_count    int;
  v_replaced uuid[] := '{}';
  v_until    timestamptz := now() + make_interval(days => s.pin_duration_days);
begin
  if v_uid is null then
    raise exception 'MOD:not_signed_in' using errcode = '42501';
  end if;

  select id, club_id, coalesce(is_anonymous, false) as anon, is_hidden
  into p from public.posts where id = p_post_id;
  if not found or p.is_hidden then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  if p.club_id is null or not public.can_act_as_club(p.club_id) then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  if p.anon then
    raise exception 'MOD:pin_anonymous' using errcode = 'P0001';
  end if;
  if public.is_restricted('post') then
    raise exception 'MOD:restricted:post' using errcode = 'P0001';
  end if;

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title)
                            order by x.club_pinned_until), '[]'::jsonb)
  into v_count, v_pins
  from public.posts x
  where x.club_pinned_until > now() and x.id <> p_post_id and x.club_id = p.club_id;

  if v_count >= s.max_active_pins_per_club then
    if not p_replace or s.max_active_pins_per_club = 0 then
      raise exception 'MOD:pin_cap' using errcode = 'P0001',
        detail = jsonb_build_object('max', s.max_active_pins_per_club, 'pins', v_pins)::text;
    end if;
    select coalesce(array_agg(y.id), '{}') into v_replaced
    from (select x.id from public.posts x
          where x.club_pinned_until > now() and x.id <> p_post_id and x.club_id = p.club_id
          order by x.club_pinned_until
          limit v_count - s.max_active_pins_per_club + 1) y;
  end if;

  perform set_config('mykerawang.pin_rpc', '1', true);
  if array_length(v_replaced, 1) > 0 then
    update public.posts set club_pinned_until = null, club_pinned_by = null
    where id = any (v_replaced);
  end if;
  update public.posts set club_pinned_until = v_until, club_pinned_by = v_uid
  where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('club_pin', 'post', p_post_id::text, null,
    jsonb_build_object('until', v_until, 'replaced', to_jsonb(v_replaced), 'club_id', p.club_id));
  return jsonb_build_object('club_pinned_until', v_until, 'replaced', to_jsonb(v_replaced));
end;
$$;

create or replace function public.club_unpin_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  p record;
begin
  select id, club_id into p from public.posts where id = p_post_id;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  if not public.is_admin()
     and (p.club_id is null or not public.can_act_as_club(p.club_id)) then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  perform set_config('mykerawang.pin_rpc', '1', true);
  update public.posts set club_pinned_until = null, club_pinned_by = null where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);
  perform public.mod_log('club_unpin', 'post', p_post_id::text, null, jsonb_build_object('club_id', p.club_id));
end;
$$;

revoke execute on function public.pin_post(uuid, boolean)     from public, anon;
revoke execute on function public.unpin_post(uuid)            from public, anon;
revoke execute on function public.club_pin_post(uuid, boolean) from public, anon;
revoke execute on function public.club_unpin_post(uuid)        from public, anon;

grant execute on function public.pin_post(uuid, boolean)      to authenticated;
grant execute on function public.unpin_post(uuid)             to authenticated;
grant execute on function public.club_pin_post(uuid, boolean) to authenticated;
grant execute on function public.club_unpin_post(uuid)        to authenticated;
