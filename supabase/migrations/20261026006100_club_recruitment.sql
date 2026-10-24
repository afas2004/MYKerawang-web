-- Recruitment becomes a club-level switch.
--
--   clubs.recruitment_open  default true: anyone may request to join
--                           false: the page shows no join entry point and
--                                  apply_to_club refuses
--
-- Only the president can flip it. Existing clubs start open, which is the
-- current behaviour.

alter table public.clubs
  add column if not exists recruitment_open boolean not null default true;

comment on column public.clubs.recruitment_open is
  'President-controlled: whether the club accepts join requests at all.';

-- Same function, plus the closed check right after the active check.
create or replace function public.apply_to_club(p_club_id uuid, p_message text default null)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  c      public.clubs;
  v_name text;
  v_note text := nullif(btrim(coalesce(p_message, '')), '');
  v_id   uuid;
begin
  if v_uid is null then
    raise exception 'CLUB:not_signed_in' using errcode = '42501';
  end if;
  if public.is_restricted('account') then
    raise exception 'MOD:restricted:account' using errcode = 'P0001';
  end if;
  select * into c from public.clubs where id = p_club_id;
  if not found or c.status <> 'active' then
    raise exception 'CLUB:not_active' using errcode = 'P0001';
  end if;
  if not c.recruitment_open then
    raise exception 'CLUB:recruitment_closed' using errcode = 'P0001';
  end if;
  if v_note is not null and length(v_note) > 500 then
    raise exception 'CLUB:message_too_long' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.club_members where club_id = c.id and user_id = v_uid) then
    raise exception 'CLUB:already_member' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.club_join_requests
             where club_id = c.id and user_id = v_uid and status = 'pending') then
    raise exception 'CLUB:already_requested' using errcode = 'P0001';
  end if;

  insert into public.club_join_requests (club_id, user_id, message)
  values (c.id, v_uid, v_note)
  returning id into v_id;

  select coalesce(nullif(btrim(display_name), ''), username) into v_name
  from public.profiles where id = v_uid;
  perform public.club_notify(
    (select user_id from public.club_members where club_id = c.id and role = 'president'),
    coalesce(v_name, 'Someone') || ' wants to join ' || c.name,
    coalesce(v_note, 'Open the club''s manage page to approve or decline.'),
    jsonb_build_object('kind', 'club_join_requested', 'club_id', c.id,
                       'route', '/c/' || c.handle || '/manage'));
  perform public.mod_log('club_join_requested', 'club', c.id::text, null,
    jsonb_build_object('user_id', v_uid));
  return v_id;
end;
$$;

create or replace function public.set_club_recruitment(p_club_id uuid, p_open boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  c public.clubs;
begin
  perform public.club_require_president(p_club_id);
  select * into c from public.clubs where id = p_club_id;
  if not found then
    raise exception 'CLUB:not_found' using errcode = 'P0001';
  end if;

  update public.clubs set recruitment_open = coalesce(p_open, true)
  where id = p_club_id;

  perform public.mod_log('club_recruitment', 'club', p_club_id::text, null,
    jsonb_build_object('open', coalesce(p_open, true)));
end;
$$;

revoke execute on function public.apply_to_club(uuid, text)          from public, anon;
revoke execute on function public.set_club_recruitment(uuid, boolean) from public, anon;
grant  execute on function public.apply_to_club(uuid, text)          to authenticated;
grant  execute on function public.set_club_recruitment(uuid, boolean) to authenticated;
