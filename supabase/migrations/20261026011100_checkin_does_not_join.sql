-- Taking attendance no longer changes registration.
--
-- `checkin_with_token()` inserted the person into `event_participants` as a
-- convenience ("attending implies going"). That made the event's places read
-- "1 / 60" after a check-in even though nobody had joined, so the one number on
-- the page meant two different things — the bug reported as "registration and
-- attendance overlap".
--
-- A check-in is now only a check-in. Someone who wants a place in the list joins
-- the event, which is the action the counter is about.
--
-- Re-runnable; replaces the definition from 20261026003100 (which itself was
-- unchanged by 20261026009100).

create or replace function public.checkin_with_token(p_token text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  t       public.event_checkin_tokens;
  e       public.events;
  v_new   boolean;
begin
  if v_uid is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;

  select * into t from public.event_checkin_tokens where token = p_token;
  if not found then
    raise exception 'CHECKIN:invalid' using errcode = 'P0001';
  end if;
  if t.expires_at < now() then
    raise exception 'CHECKIN:expired' using errcode = 'P0001';
  end if;

  select * into e from public.events where id = t.event_id;
  if e.cancelled_at is not null then
    raise exception 'CHECKIN:cancelled' using errcode = 'P0001';
  end if;

  -- Merit only means something for verified students, so require it only
  -- while verification is switched on.
  if public.verification_required('event_join')
     and not public.is_verified_student(v_uid) then
    raise exception 'CHECKIN:verify' using errcode = 'P0001';
  end if;

  insert into public.event_attendance (event_id, user_id, method)
  values (t.event_id, v_uid, 'qr')
  on conflict (event_id, user_id) do nothing;
  v_new := found;

  return case when v_new then 'ok' else 'already' end;
end;
$$;

revoke execute on function public.checkin_with_token(text) from public, anon;
grant  execute on function public.checkin_with_token(text) to authenticated;
