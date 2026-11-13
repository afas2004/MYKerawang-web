-- Attendance can offer ANY form after check-in, not only the event's own
-- KI report form.
--
--   events.checkin_form_id      the form the success screen offers; null means
--                               "fall back to the old rule" (the event's own
--                               open form, when its after_checkin flag is on)
--   set_event_checkin_form()    organiser / club officer / admin sets it
--   event_checkin_form()        what the check-in success screen asks for
--
-- Also:
--   * check-in asks for student verification only when BOTH
--     access_settings.verification_enabled and student_features_enabled are on,
--     so the two owner switches cannot contradict each other;
--   * club officers (can_act_as_club) may open the QR door for their club's
--     events and read its attendance, matching who can already see its form.
--
-- Re-runnable: add column if not exists, create or replace, drop policy if
-- exists. Replaces checkin_with_token (20261026011100), event_checkin_token
-- (20261026009100) and event_attendance_list (20261026003100).

-- ====================================================== the column
alter table public.events
  add column if not exists checkin_form_id uuid
  references public.event_forms(id) on delete set null;

comment on column public.events.checkin_form_id is
  'Form offered on the check-in success screen. Null: the event''s own open form when after_checkin is on.';

-- ====================================================== who runs the door
-- One place for "may take attendance for this event".
create or replace function public.can_take_attendance(p_event_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.events e
    where e.id = p_event_id
      and (e.organizer_id = auth.uid()
           or public.is_admin()
           or (e.club_id is not null and public.can_act_as_club(e.club_id))));
$$;

revoke execute on function public.can_take_attendance(uuid) from public, anon;
grant  execute on function public.can_take_attendance(uuid) to authenticated;

-- ====================================================== choosing the form
create or replace function public.set_event_checkin_form(p_event_id uuid, p_form_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  f     public.event_forms;
begin
  if v_uid is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;
  if not public.can_take_attendance(p_event_id) then
    raise exception 'CHECKIN:not_organizer' using errcode = 'P0001';
  end if;

  if p_form_id is not null then
    select * into f from public.event_forms where id = p_form_id;
    if not found or coalesce(f.is_hidden, false) or f.status = 'closed' then
      raise exception 'CHECKIN:form_unavailable' using errcode = 'P0001';
    end if;
    -- The event's own form, or a form the caller manages. coalesce: a
    -- standalone form has event_id null, and `not null` would let it through.
    if not coalesce(f.event_id = p_event_id
            or public.is_admin()
            or (f.event_id is null and f.owner_id = v_uid)
            or (f.event_id is null and f.club_id is not null
                and public.can_act_as_club(f.club_id)), false) then
      raise exception 'CHECKIN:form_not_yours' using errcode = 'P0001';
    end if;
  end if;

  update public.events set checkin_form_id = p_form_id where id = p_event_id;
end;
$$;

revoke execute on function public.set_event_checkin_form(uuid, uuid) from public, anon;
grant  execute on function public.set_event_checkin_form(uuid, uuid) to authenticated;

-- What the success screen offers: the chosen form while it is open, else the
-- old rule, so events set up before this keep working unchanged.
create or replace function public.event_checkin_form(p_event_id uuid)
returns uuid
language sql security definer stable
set search_path = public
as $$
  select coalesce(
    (select f.id
       from public.events e
       join public.event_forms f on f.id = e.checkin_form_id
      where e.id = p_event_id
        and f.status = 'open'
        and not coalesce(f.is_hidden, false)
        and (f.closes_at is null or f.closes_at > now())),
    (select f.id
       from public.event_forms f
      where f.event_id = p_event_id
        and f.status = 'open'
        and f.after_checkin
        and not coalesce(f.is_hidden, false)
        and (f.closes_at is null or f.closes_at > now())
        -- An explicit choice of another (now closed) form must not bring
        -- back the event's own one.
        and not exists (select 1 from public.events e
                         where e.id = p_event_id
                           and e.checkin_form_id is not null
                           and e.checkin_form_id <> f.id)
      order by f.created_at desc
      limit 1));
$$;

revoke execute on function public.event_checkin_form(uuid) from public;
grant  execute on function public.event_checkin_form(uuid) to anon, authenticated;

-- ====================================================== the door
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
  if not public.can_take_attendance(p_event_id) then
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

-- ====================================================== checking in
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

  -- Verification is a student feature: ask for it only while BOTH switches
  -- are on.
  if public.verification_required('event_join')
     and coalesce((select s.student_features_enabled
                   from public.access_settings s where s.id), true)
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

-- ====================================================== the list
create or replace function public.event_attendance_list(p_event_id uuid)
returns table (
  user_id       uuid,
  username      text,
  display_name  text,
  student_id    text,
  verified      boolean,
  checked_in_at timestamptz,
  method        text
)
language plpgsql security definer stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'CHECKIN:login_required' using errcode = '42501';
  end if;
  if not public.can_take_attendance(p_event_id) then
    raise exception 'CHECKIN:not_organizer' using errcode = 'P0001';
  end if;

  return query
  select a.user_id,
         p.username,
         p.display_name,
         split_part(v.email::text, '@', 1),
         coalesce(v.status = 'verified', false),
         a.checked_in_at,
         a.method
  from public.event_attendance a
  left join public.profiles p on p.id = a.user_id
  left join public.student_verifications v on v.user_id = a.user_id
  where a.event_id = p_event_id
  order by a.checked_in_at;
end;
$$;

revoke execute on function public.event_attendance_list(uuid) from public, anon;
grant  execute on function public.event_attendance_list(uuid) to authenticated;

-- The door's live count reads the table directly.
drop policy if exists "event_attendance_select" on public.event_attendance;
create policy "event_attendance_select" on public.event_attendance
for select to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
  or public.can_take_attendance(event_id));
