-- Fixes the attendance QR: `event_checkin_token()` could never issue a token.
--
-- The function returns `table (token text, expires_at timestamptz)`, so those
-- names are PL/pgSQL variables. Its cleanup DELETE then referenced the bare
-- column `expires_at`, which PL/pgSQL refuses as ambiguous:
--
--   column reference "expires_at" is ambiguous        (42702)
--
-- That is the error the attendance screen showed, and it means the rotating
-- 20-second code has never worked — every call failed before writing anything.
-- The column reference is now qualified, which is all it needed.
--
-- Re-runnable; replaces the definition from 20261026003100.

create or replace function public.event_checkin_token(p_event_id uuid)
returns table (token text, expires_at timestamptz)
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.events e
                 where e.id = p_event_id
                   and (e.organizer_id = v_uid or public.is_admin())) then
    raise exception 'CHECKIN:not_organizer' using errcode = 'P0001';
  end if;

  -- Qualified: `expires_at` is also an output column of this function.
  delete from public.event_checkin_tokens t
  where t.event_id = p_event_id
    and t.expires_at < now() - interval '5 minutes';

  insert into public.event_checkin_tokens (token, event_id, expires_at)
  values (gen_random_uuid()::text, p_event_id, now() + interval '20 seconds')
  returning event_checkin_tokens.token, event_checkin_tokens.expires_at
  into token, expires_at;

  return next;
end;
$$;

revoke execute on function public.event_checkin_token(uuid) from public, anon;
grant  execute on function public.event_checkin_token(uuid) to authenticated;

-- The same mistake is worth failing loudly on elsewhere. `checkin_with_token`
-- and `event_attendance_list` were checked and are fine: their column
-- references are already qualified or do not collide with the output names.
