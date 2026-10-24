-- Club roster: members are managed by the club itself, not only officers.
--
-- club_members.role stays the permission role (president / officer /
-- member); position is the title shown on the page (Secretary, Treasurer…).
-- Every write goes through these RPCs so RLS stays read-only.

-- ------------------------------------------------------- add
create or replace function public.add_club_member(
  p_club_id  uuid,
  p_username text,
  p_position text default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid;
  c      public.clubs;
  v_pos  text := nullif(btrim(coalesce(p_position, '')), '');
begin
  perform public.club_require_president(p_club_id);
  select * into c from public.clubs where id = p_club_id;
  select id into v_user from public.profiles
  where lower(username) = lower(btrim(replace(coalesce(p_username, ''), '@', '')));
  if v_user is null then
    raise exception 'CLUB:user_not_found' using errcode = 'P0001';
  end if;
  if v_pos is not null
     and v_pos not in ('president','vice_president','secretary','treasurer','committee','other') then
    raise exception 'CLUB:position_invalid' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.club_members where club_id = p_club_id and user_id = v_user) then
    raise exception 'CLUB:already_member' using errcode = 'P0001';
  end if;

  insert into public.club_members (club_id, user_id, role, position)
  values (p_club_id, v_user, 'member', v_pos);

  perform public.club_notify(v_user, 'You''re now a member of ' || c.name,
    'Your roster card is on the club page. Officers can give you a position from the manage page.',
    jsonb_build_object('kind', 'club_member_added', 'club_id', c.id, 'route', '/c/' || c.handle));
  perform public.mod_log('club_member_added', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', v_user, 'position', v_pos));
  return v_user;
end;
$$;

-- ------------------------------------------------------- remove / leave
create or replace function public.remove_club_member(p_club_id uuid, p_user_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select role into v_role from public.club_members where club_id = p_club_id and user_id = p_user_id;
  if v_role is null then
    raise exception 'CLUB:not_member' using errcode = 'P0001';
  end if;
  if v_role = 'president' then
    raise exception 'CLUB:president_must_transfer' using errcode = 'P0001';
  end if;
  -- President removes anyone; a member may only leave.
  if p_user_id is distinct from auth.uid() then
    perform public.club_require_president(p_club_id);
  end if;
  delete from public.club_members where club_id = p_club_id and user_id = p_user_id;
  perform public.mod_log('club_member_removed', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', p_user_id, 'self', p_user_id = auth.uid(), 'role', v_role));
end;
$$;

-- ------------------------------------------------------- position
create or replace function public.set_club_member_position(
  p_club_id  uuid,
  p_user_id  uuid,
  p_position text
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pos text := nullif(btrim(coalesce(p_position, '')), '');
begin
  perform public.club_require_president(p_club_id);
  if not exists (select 1 from public.club_members where club_id = p_club_id and user_id = p_user_id) then
    raise exception 'CLUB:not_member' using errcode = 'P0001';
  end if;
  if v_pos is not null
     and v_pos not in ('president','vice_president','secretary','treasurer','committee','other') then
    raise exception 'CLUB:position_invalid' using errcode = 'P0001';
  end if;
  update public.club_members set position = v_pos
  where club_id = p_club_id and user_id = p_user_id;
  perform public.mod_log('club_member_position', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', p_user_id, 'position', v_pos));
end;
$$;

-- ------------------------------------------------------- role
create or replace function public.set_club_member_role(
  p_club_id uuid,
  p_user_id uuid,
  p_role    text
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_role text;
  c      public.clubs;
begin
  perform public.club_require_president(p_club_id);
  if p_role not in ('officer','member') then
    raise exception 'CLUB:role_invalid' using errcode = 'P0001';
  end if;
  select role into v_role from public.club_members where club_id = p_club_id and user_id = p_user_id;
  if v_role is null then
    raise exception 'CLUB:not_member' using errcode = 'P0001';
  end if;
  if v_role = 'president' then
    raise exception 'CLUB:cannot_change_president' using errcode = 'P0001';
  end if;
  if p_role = 'officer' and v_role = 'member' then
    if (select count(*) from public.club_members
        where club_id = p_club_id and role in ('president','officer')) >= 15 then
      raise exception 'CLUB:too_many_officers' using errcode = 'P0001';
    end if;
  end if;

  update public.club_members set role = p_role
  where club_id = p_club_id and user_id = p_user_id;

  select * into c from public.clubs where id = p_club_id;
  if p_role = 'officer' then
    perform public.club_notify(p_user_id, 'You''re now an officer of ' || c.name,
      'You can post, create events and sell as @' || c.handle || '.',
      jsonb_build_object('kind', 'club_officer_added', 'club_id', c.id, 'route', '/c/' || c.handle));
  end if;
  perform public.mod_log('club_member_role', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', p_user_id, 'role', p_role));
end;
$$;

revoke execute on function public.add_club_member(uuid, text, text)              from public, anon;
revoke execute on function public.remove_club_member(uuid, uuid)                 from public, anon;
revoke execute on function public.set_club_member_position(uuid, uuid, text)     from public, anon;
revoke execute on function public.set_club_member_role(uuid, uuid, text)         from public, anon;

grant execute on function public.add_club_member(uuid, text, text)              to authenticated;
grant execute on function public.remove_club_member(uuid, uuid)                 to authenticated;
grant execute on function public.set_club_member_position(uuid, uuid, text)     to authenticated;
grant execute on function public.set_club_member_role(uuid, uuid, text)         to authenticated;
