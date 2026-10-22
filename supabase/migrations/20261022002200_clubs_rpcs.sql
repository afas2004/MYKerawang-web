-- Clubs, part 2: RPCs. Errors are raised as 'CLUB:<code>' (P0001) for the
-- app to translate (lib/services/club_service.dart).
--
--   register_club(name, handle, description, category, proof_note) → uuid
--   admin_pending_clubs() → jsonb[]           (admin queue, with proof)
--   admin_decide_club_request(club_id, approve, reason)
--   admin_set_club_status(club_id, status, reason)   active ↔ suspended
--   update_club(club_id, …)                  officers edit the page
--   invite_officer(club_id, username) → uuid president adds an officer
--   remove_officer(club_id, user_id)         president removes / officer leaves
--   transfer_presidency(club_id, user_id)    president → an officer
--   my_clubs()                               clubs where I'm president/officer
--   pin_post / unpin_post                    + officers pin their club's posts

-- ------------------------------------------------------- notices
create or replace function public.club_notify(p_user uuid, p_title text, p_body text, p_data jsonb)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if p_user is null then return; end if;
  begin
    insert into public.notifications (user_id, actor_id, type, title, body, data)
    values (p_user, null, 'club', p_title, p_body, coalesce(p_data, '{}'));
  exception when others then
    perform public.mod_log('notify_failed', 'user', p_user::text, sqlerrm,
                           jsonb_build_object('title', p_title), true);
  end;
end;
$$;

revoke execute on function public.club_notify(uuid, text, text, jsonb) from public, anon, authenticated;

create or replace function public.club_require_president(p_club_id uuid)
returns void
language plpgsql stable security definer
set search_path = public
as $$
begin
  if public.club_role(p_club_id) is distinct from 'president' then
    raise exception 'CLUB:not_president' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.club_require_president(uuid) from public, anon, authenticated;

-- ------------------------------------------------------- register
create or replace function public.register_club(
  p_name        text,
  p_handle      text,
  p_description text,
  p_category    text,
  p_proof_note  text
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_handle text := btrim(coalesce(p_handle, ''));
  v_name   text := btrim(coalesce(p_name, ''));
  v_id     uuid;
begin
  if v_uid is null then
    raise exception 'CLUB:not_signed_in' using errcode = '42501';
  end if;
  if public.is_restricted('account') then
    raise exception 'MOD:restricted:account' using errcode = 'P0001';
  end if;
  if v_handle !~ '^[A-Za-z0-9_]{3,30}$' then
    raise exception 'CLUB:handle_invalid' using errcode = 'P0001';
  end if;
  if length(v_name) not between 2 and 80 then
    raise exception 'CLUB:name_invalid' using errcode = 'P0001';
  end if;
  if length(btrim(coalesce(p_proof_note, ''))) < 10 then
    raise exception 'CLUB:proof_required' using errcode = 'P0001';
  end if;
  if (select count(*) from public.clubs where created_by = v_uid and status = 'pending') >= 2 then
    raise exception 'CLUB:too_many_pending' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.clubs where handle = v_handle::extensions.citext) then
    raise exception 'CLUB:handle_taken' using errcode = 'P0001';
  end if;

  insert into public.clubs (handle, name, description, category, status, created_by)
  values (v_handle, v_name, nullif(btrim(coalesce(p_description, '')), ''),
          nullif(btrim(coalesce(p_category, '')), ''), 'pending', v_uid)
  returning id into v_id;

  insert into public.club_members (club_id, user_id, role) values (v_id, v_uid, 'president');
  insert into public.club_private (club_id, proof_note) values (v_id, btrim(p_proof_note));

  perform public.mod_log('club_registered', 'club', v_id::text, null,
    jsonb_build_object('handle', v_handle, 'name', v_name));
  return v_id;
exception when unique_violation then
  raise exception 'CLUB:handle_taken' using errcode = 'P0001';
end;
$$;

-- ------------------------------------------------------- admin
create or replace function public.admin_pending_clubs()
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
begin
  perform public.mod_require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'handle', c.handle::text, 'name', c.name,
             'description', c.description, 'category', c.category,
             'logo_url', c.logo_url, 'created_at', c.created_at,
             'proof_note', cp.proof_note,
             'president', case when pr.id is null then null else jsonb_build_object(
               'id', pr.id, 'username', pr.username, 'display_name', pr.display_name,
               'avatar_url', pr.avatar_url) end)
           order by c.created_at)
    from public.clubs c
    left join public.club_private cp on cp.club_id = c.id
    left join public.club_members m on m.club_id = c.id and m.role = 'president'
    left join public.profiles pr on pr.id = m.user_id
    where c.status = 'pending'), '[]'::jsonb);
end;
$$;

create or replace function public.admin_decide_club_request(p_club_id uuid, p_approve boolean, p_reason text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  c        public.clubs;
  v_pres   uuid;
  v_reason text;
begin
  perform public.mod_require_admin();
  perform public.mod_rpc_begin();
  v_reason := case when p_approve then nullif(btrim(coalesce(p_reason, '')), '')
                   else public.mod_require_reason(p_reason) end;

  select * into c from public.clubs where id = p_club_id for update;
  if not found then
    raise exception 'CLUB:not_found' using errcode = 'P0001';
  end if;
  if c.status <> 'pending' then
    raise exception 'CLUB:not_pending' using errcode = 'P0001';
  end if;

  update public.clubs
  set status = case when p_approve then 'active' else 'rejected' end,
      is_verified = p_approve
  where id = c.id;

  insert into public.club_private (club_id, decision_reason, decided_by, decided_at)
  values (c.id, v_reason, auth.uid(), now())
  on conflict (club_id) do update
  set decision_reason = excluded.decision_reason, decided_by = excluded.decided_by,
      decided_at = excluded.decided_at;

  select user_id into v_pres from public.club_members where club_id = c.id and role = 'president';

  -- Legacy role flow keeps working: a club_pending president becomes 'club'.
  update public.profiles
  set role = case when p_approve then 'club' else 'student' end
  where id = v_pres and role = 'club_pending';

  if p_approve then
    perform public.club_notify(v_pres, c.name || ' is approved',
      'Your club page @' || c.handle || ' is live. Officers can now post, create events and sell as the club.',
      jsonb_build_object('kind', 'club_approved', 'club_id', c.id, 'handle', c.handle::text,
                         'route', '/c/' || c.handle));
  else
    perform public.club_notify(v_pres, c.name || ' wasn''t approved',
      'Reason: ' || v_reason || '. You can fix this and register again.',
      jsonb_build_object('kind', 'club_rejected', 'club_id', c.id, 'route', '/clubs/register'));
  end if;

  perform public.mod_log(case when p_approve then 'club_approved' else 'club_rejected' end,
    'club', c.id::text, v_reason, jsonb_build_object('handle', c.handle::text));
end;
$$;

create or replace function public.admin_set_club_status(p_club_id uuid, p_status text, p_reason text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  c        public.clubs;
  v_reason text;
begin
  perform public.mod_require_admin();
  v_reason := public.mod_require_reason(p_reason);
  if p_status not in ('active','suspended') then
    raise exception 'CLUB:bad_status' using errcode = 'P0001';
  end if;
  select * into c from public.clubs where id = p_club_id for update;
  if not found or c.status not in ('active','suspended') then
    raise exception 'CLUB:not_found' using errcode = 'P0001';
  end if;
  update public.clubs set status = p_status where id = c.id;
  perform public.club_notify(
    (select user_id from public.club_members where club_id = c.id and role = 'president'),
    case when p_status = 'suspended' then c.name || ' is suspended' else c.name || ' is active again' end,
    'Reason: ' || v_reason || '.',
    jsonb_build_object('kind', 'club_' || p_status, 'club_id', c.id, 'route', '/c/' || c.handle));
  perform public.mod_log('club_' || p_status, 'club', c.id::text, v_reason, '{}');
end;
$$;

-- ------------------------------------------------------- page
create or replace function public.update_club(
  p_club_id       uuid,
  p_name          text,
  p_description   text,
  p_logo_url      text,
  p_cover_url     text,
  p_category      text,
  p_faculty       text,
  p_contact_email text,
  p_socials       jsonb
)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_club_officer(p_club_id) then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  if length(btrim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'CLUB:name_invalid' using errcode = 'P0001';
  end if;
  if p_contact_email is not null and btrim(p_contact_email) <> ''
     and p_contact_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'CLUB:email_invalid' using errcode = 'P0001';
  end if;
  update public.clubs
  set name          = btrim(p_name),
      description   = nullif(btrim(coalesce(p_description, '')), ''),
      logo_url      = nullif(btrim(coalesce(p_logo_url, '')), ''),
      cover_url     = nullif(btrim(coalesce(p_cover_url, '')), ''),
      category      = nullif(btrim(coalesce(p_category, '')), ''),
      faculty       = nullif(btrim(coalesce(p_faculty, '')), ''),
      contact_email = nullif(btrim(coalesce(p_contact_email, '')), ''),
      socials       = coalesce(p_socials, '{}')
  where id = p_club_id;
end;
$$;

-- ------------------------------------------------------- officers
create or replace function public.invite_officer(p_club_id uuid, p_username text)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid;
  c      public.clubs;
begin
  perform public.club_require_president(p_club_id);
  select * into c from public.clubs where id = p_club_id;
  select id into v_user from public.profiles
  where lower(username) = lower(btrim(replace(coalesce(p_username, ''), '@', '')));
  if v_user is null then
    raise exception 'CLUB:user_not_found' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.club_members
             where club_id = p_club_id and user_id = v_user and role in ('president','officer')) then
    raise exception 'CLUB:already_officer' using errcode = 'P0001';
  end if;
  if (select count(*) from public.club_members
      where club_id = p_club_id and role in ('president','officer')) >= 15 then
    raise exception 'CLUB:too_many_officers' using errcode = 'P0001';
  end if;

  insert into public.club_members (club_id, user_id, role) values (p_club_id, v_user, 'officer')
  on conflict (club_id, user_id) do update set role = 'officer';

  perform public.club_notify(v_user, 'You''re now an officer of ' || c.name,
    'You can post, create events and sell as @' || c.handle || '. You can leave from the club''s manage page.',
    jsonb_build_object('kind', 'club_officer_added', 'club_id', c.id, 'route', '/c/' || c.handle));
  perform public.mod_log('club_officer_added', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', v_user));
  return v_user;
end;
$$;

create or replace function public.remove_officer(p_club_id uuid, p_user_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select role into v_role from public.club_members where club_id = p_club_id and user_id = p_user_id;
  if v_role is null or v_role = 'member' then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  if v_role = 'president' then
    raise exception 'CLUB:president_must_transfer' using errcode = 'P0001';
  end if;
  -- The president removes anyone; an officer may only leave.
  if p_user_id is distinct from auth.uid() then
    perform public.club_require_president(p_club_id);
  end if;
  delete from public.club_members where club_id = p_club_id and user_id = p_user_id;
  perform public.mod_log('club_officer_removed', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', p_user_id, 'self', p_user_id = auth.uid()));
end;
$$;

create or replace function public.transfer_presidency(p_club_id uuid, p_user_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  c public.clubs;
begin
  perform public.club_require_president(p_club_id);
  if p_user_id = auth.uid() then
    raise exception 'CLUB:already_president' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.club_members
                 where club_id = p_club_id and user_id = p_user_id and role = 'officer') then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  select * into c from public.clubs where id = p_club_id;

  -- Demote first: one president at a time (unique index).
  update public.club_members set role = 'officer'
  where club_id = p_club_id and user_id = auth.uid();
  update public.club_members set role = 'president'
  where club_id = p_club_id and user_id = p_user_id;

  perform public.club_notify(p_user_id, 'You''re now president of ' || c.name,
    'The previous president handed the club to you. You can manage officers from the club page.',
    jsonb_build_object('kind', 'club_president', 'club_id', c.id, 'route', '/c/' || c.handle));
  perform public.mod_log('club_president_transferred', 'club', p_club_id::text, null,
    jsonb_build_object('from', auth.uid(), 'to', p_user_id));
end;
$$;

create or replace function public.my_clubs()
returns table (id uuid, handle text, name text, logo_url text, status text,
               is_verified boolean, role text)
language sql security definer stable
set search_path = public
as $$
  select c.id, c.handle::text, c.name, c.logo_url, c.status, c.is_verified, m.role
  from public.club_members m
  join public.clubs c on c.id = m.club_id
  where m.user_id = auth.uid() and m.role in ('president','officer')
  order by (c.status = 'active') desc, c.name;
$$;

-- ------------------------------------------------------- queue summary
-- 20261019004400's summary, with club requests from the clubs table.
create or replace function public.admin_queue_summary()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  perform public.mod_require_admin();
  perform public.mod_sweep_expired(null);
  select jsonb_build_object(
    'open_cases',      (select count(*) from public.moderation_cases where status in ('open','hidden')),
    'hidden_cases',    (select count(*) from public.moderation_cases where status = 'hidden'),
    'oldest_open_at',  (select min(first_reported_at) from public.moderation_cases where status in ('open','hidden')),
    'pending_appeals', (select count(*) from public.appeals where status = 'pending'),
    'club_requests',   (select count(*) from public.clubs where status = 'pending'),
    'active_restrictions', (select count(*) from public.user_restrictions
                            where lifted_at is null and (until is null or until > now())))
  into v;
  return v;
end;
$$;

-- ------------------------------------------------------- pins
-- 20261019004500's pin rules, plus: officers of an active club pin that
-- club's posts (cap counted per club). Legacy role='club' own-post pins
-- keep working.
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
  v_club   boolean;
begin
  if v_uid is null then
    raise exception 'MOD:not_signed_in' using errcode = '42501';
  end if;

  select id, user_id, title, club_id, coalesce(is_anonymous, false) as anon, is_hidden
  into p from public.posts where id = p_post_id;
  if not found or p.is_hidden then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;

  select role into v_role from public.profiles where id = v_uid;
  v_club := p.club_id is not null and public.can_act_as_club(p.club_id);

  if not public.is_admin() then
    if not v_club and (v_role is distinct from 'club' or p.user_id is distinct from v_uid) then
      raise exception 'MOD:pin_not_allowed' using errcode = 'P0001';
    end if;
    if p.anon then
      raise exception 'MOD:pin_anonymous' using errcode = 'P0001';
    end if;
    if public.is_restricted('post') then
      raise exception 'MOD:restricted:post' using errcode = 'P0001';
    end if;

    select count(*),
           coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title)
                              order by x.pinned_until), '[]'::jsonb)
    into v_count, v_pins
    from public.posts x
    where x.pinned_until > now() and x.id <> p_post_id
      and (case when v_club then x.club_id = p.club_id else x.pinned_by = v_uid end);

    if v_count >= s.max_active_pins_per_club then
      if not p_replace or s.max_active_pins_per_club = 0 then
        raise exception 'MOD:pin_cap' using errcode = 'P0001',
          detail = jsonb_build_object('max', s.max_active_pins_per_club, 'pins', v_pins)::text;
      end if;
      select coalesce(array_agg(y.id), '{}') into v_replaced
      from (select x.id from public.posts x
            where x.pinned_until > now() and x.id <> p_post_id
              and (case when v_club then x.club_id = p.club_id else x.pinned_by = v_uid end)
            order by x.pinned_until
            limit v_count - s.max_active_pins_per_club + 1) y;
    end if;
  end if;

  perform set_config('mykerawang.pin_rpc', '1', true);
  if array_length(v_replaced, 1) > 0 then
    update public.posts set pinned_until = null, pinned_by = null where id = any (v_replaced);
  end if;
  update public.posts set pinned_until = v_until, pinned_by = v_uid where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('pin', 'post', p_post_id::text, null,
    jsonb_build_object('until', v_until, 'replaced', to_jsonb(v_replaced), 'club_id', p.club_id));

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
  select id, user_id, pinned_by, club_id into p from public.posts where id = p_post_id;
  if not found then
    raise exception 'MOD:not_found' using errcode = 'P0001';
  end if;
  if not public.is_admin()
     and p.pinned_by is distinct from v_uid and p.user_id is distinct from v_uid
     and not (p.club_id is not null and public.can_act_as_club(p.club_id)) then
    raise exception 'MOD:pin_not_allowed' using errcode = 'P0001';
  end if;

  perform set_config('mykerawang.pin_rpc', '1', true);
  update public.posts set pinned_until = null, pinned_by = null where id = p_post_id;
  perform set_config('mykerawang.pin_rpc', '', true);

  perform public.mod_log('unpin', 'post', p_post_id::text, null, '{}');
end;
$$;

-- ------------------------------------------------------- grants
revoke execute on function public.register_club(text, text, text, text, text)                       from public, anon;
revoke execute on function public.admin_pending_clubs()                                             from public, anon;
revoke execute on function public.admin_decide_club_request(uuid, boolean, text)                    from public, anon;
revoke execute on function public.admin_set_club_status(uuid, text, text)                           from public, anon;
revoke execute on function public.update_club(uuid, text, text, text, text, text, text, text, jsonb) from public, anon;
revoke execute on function public.invite_officer(uuid, text)                                        from public, anon;
revoke execute on function public.remove_officer(uuid, uuid)                                        from public, anon;
revoke execute on function public.transfer_presidency(uuid, uuid)                                   from public, anon;
revoke execute on function public.my_clubs()                                                        from public, anon;

grant execute on function public.register_club(text, text, text, text, text)                       to authenticated;
grant execute on function public.admin_pending_clubs()                                             to authenticated;
grant execute on function public.admin_decide_club_request(uuid, boolean, text)                    to authenticated;
grant execute on function public.admin_set_club_status(uuid, text, text)                           to authenticated;
grant execute on function public.update_club(uuid, text, text, text, text, text, text, text, jsonb) to authenticated;
grant execute on function public.invite_officer(uuid, text)                                        to authenticated;
grant execute on function public.remove_officer(uuid, uuid)                                        to authenticated;
grant execute on function public.transfer_presidency(uuid, uuid)                                   to authenticated;
grant execute on function public.my_clubs()                                                        to authenticated;
