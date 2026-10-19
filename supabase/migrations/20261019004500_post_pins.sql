-- Pinned posts.
--   * clubs pin their OWN, non-anonymous posts: capped
--     (max_active_pins_per_club) and expiring (pin_duration_days)
--   * admins pin / unpin any post, uncapped, same duration
--   * pins expire by comparison with now(); nothing to clean up
--   * posts_public gains pinned_until + is_pinned so the feed can order
--     active pins first
--
-- Errors: 'MOD:pin_cap' (detail {"max", "pins":[{id,title}]}),
-- 'MOD:pin_not_allowed', 'MOD:pin_anonymous', 'MOD:not_found'.

alter table public.posts
  add column if not exists pinned_until timestamptz,
  add column if not exists pinned_by    uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'posts_pinned_by_fk') then
    alter table public.posts add constraint posts_pinned_by_fk
      foreign key (pinned_by) references public.profiles(id) on delete set null;
  end if;
end $$;

create index if not exists posts_pinned_idx on public.posts (pinned_by, pinned_until)
  where pinned_until is not null;

-- Pin columns change only through pin_post / unpin_post.
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
    new.pinned_until := null;
    new.pinned_by    := null;
  else
    new.pinned_until := old.pinned_until;
    new.pinned_by    := old.pinned_by;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_mod_guard_pin_columns on public.posts;
create trigger trg_mod_guard_pin_columns
before insert or update of pinned_until, pinned_by on public.posts
for each row execute function public.mod_guard_pin_columns();

create or replace function public.pin_post(p_post_id uuid, p_replace boolean default false)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  s        public.moderation_settings := public.mod_settings();
  v_uid    uuid := auth.uid();
  v_role   text;
  p        record;
  v_pins   jsonb;
  v_count  int;
  v_replaced uuid[] := '{}';
  v_until  timestamptz := now() + make_interval(days => s.pin_duration_days);
begin
  if v_uid is null then
    raise exception 'MOD:not_signed_in' using errcode = '42501';
  end if;

  select id, user_id, title, coalesce(is_anonymous, false) as anon, is_hidden
  into p from public.posts where id = p_post_id;
  if not found or p.is_hidden then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;

  select role into v_role from public.profiles where id = v_uid;

  if not public.is_admin() then
    if v_role is distinct from 'club' or p.user_id is distinct from v_uid then
      raise exception 'MOD:pin_not_allowed' using errcode = 'P0001';
    end if;
    if p.anon then
      raise exception 'MOD:pin_anonymous' using errcode = 'P0001';
    end if;
    if public.is_restricted('post') then
      raise exception 'MOD:restricted:post' using errcode = 'P0001';
    end if;

    select count(*),
           coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title)
                              order by pinned_until), '[]'::jsonb)
    into v_count, v_pins
    from public.posts
    where pinned_by = v_uid and pinned_until > now() and id <> p_post_id;

    if v_count >= s.max_active_pins_per_club then
      if not p_replace or s.max_active_pins_per_club = 0 then
        raise exception 'MOD:pin_cap' using errcode = 'P0001',
          detail = jsonb_build_object('max', s.max_active_pins_per_club, 'pins', v_pins)::text;
      end if;
      -- Free just enough slots, soonest-expiring first.
      select coalesce(array_agg(id), '{}') into v_replaced
      from (select id from public.posts
            where pinned_by = v_uid and pinned_until > now() and id <> p_post_id
            order by pinned_until
            limit v_count - s.max_active_pins_per_club + 1) x;
    end if;
  end if;

  perform set_config('mykerawang.pin_rpc', '1', true);
  if array_length(v_replaced, 1) > 0 then
    update public.posts set pinned_until = null, pinned_by = null where id = any (v_replaced);
  end if;
  update public.posts set pinned_until = v_until, pinned_by = v_uid where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('pin', 'post', p_post_id::text, null,
    jsonb_build_object('until', v_until, 'replaced', to_jsonb(v_replaced)));

  return jsonb_build_object('pinned_until', v_until, 'replaced', to_jsonb(v_replaced));
end;
$$;

create or replace function public.unpin_post(p_post_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  p     record;
begin
  select id, user_id, pinned_by into p from public.posts where id = p_post_id;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  if not public.is_admin()
     and p.pinned_by is distinct from v_uid and p.user_id is distinct from v_uid then
    raise exception 'MOD:pin_not_allowed' using errcode = 'P0001';
  end if;

  perform set_config('mykerawang.pin_rpc', '1', true);
  update public.posts set pinned_until = null, pinned_by = null where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('unpin', 'post', p_post_id::text, null, '{}');
end;
$$;

revoke execute on function public.mod_guard_pin_columns()     from public, anon, authenticated;
revoke execute on function public.pin_post(uuid, boolean)     from public, anon;
revoke execute on function public.unpin_post(uuid)            from public, anon;
grant  execute on function public.pin_post(uuid, boolean)     to authenticated;
grant  execute on function public.unpin_post(uuid)            to authenticated;

-- posts_public: same columns as 20260801000100, pin columns appended
-- (create or replace only allows adding at the end).
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
  coalesce(p.pinned_until > now(), false) as is_pinned
from public.posts p
left join public.profiles pr on pr.id = p.user_id
left join public.events   ev on ev.id = p.shared_event_id
left join public.listings li on li.id = p.shared_listing_id
where p.is_hidden = false;

grant select on public.posts_public to authenticated, anon;
