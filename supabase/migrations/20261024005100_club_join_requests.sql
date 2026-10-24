-- Club join requests: a signed-in student asks to join an active club; the
-- president or an officer approves or declines. Approved requests insert a
-- club_members row with role 'member'. Admins can see and decide every
-- request from the console.
--
-- One pending request per (club, user); a rejected request can be sent
-- again (the partial unique index only covers status = 'pending').

create table if not exists public.club_join_requests (
  id            uuid primary key default gen_random_uuid(),
  club_id       uuid not null references public.clubs(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  message       text,
  status        text not null default 'pending',
  decided_by    uuid references public.profiles(id) on delete set null,
  decided_at    timestamptz,
  decision_note text,
  created_at    timestamptz not null default now()
);

alter table public.club_join_requests drop constraint if exists club_join_requests_status_valid;
alter table public.club_join_requests add constraint club_join_requests_status_valid
  check (status in ('pending', 'approved', 'rejected', 'withdrawn'));

alter table public.club_join_requests drop constraint if exists club_join_requests_message_length;
alter table public.club_join_requests add constraint club_join_requests_message_length
  check (message is null or length(message) <= 500);

create unique index if not exists club_join_requests_pending_key
  on public.club_join_requests (club_id, user_id) where status = 'pending';
create index if not exists club_join_requests_club_idx on public.club_join_requests (club_id);
create index if not exists club_join_requests_user_idx on public.club_join_requests (user_id);

alter table public.club_join_requests enable row level security;

drop policy if exists "club_join_requests_select" on public.club_join_requests;
create policy "club_join_requests_select" on public.club_join_requests
for select to authenticated
using (user_id = auth.uid() or public.is_club_officer(club_id) or public.is_admin());

revoke all on public.club_join_requests from anon;
revoke insert, update, delete on public.club_join_requests from authenticated;
grant select on public.club_join_requests to authenticated;

-- ------------------------------------------------------- apply
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

-- ------------------------------------------------------- club view
create or replace function public.club_join_requests(p_club_id uuid)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
begin
  if not (public.is_admin() or public.is_club_officer(p_club_id)) then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'user_id', r.user_id, 'message', r.message,
             'created_at', r.created_at,
             'user', jsonb_build_object(
               'id', p.id, 'username', p.username, 'display_name', p.display_name,
               'avatar_url', p.avatar_url))
           order by r.created_at)
    from public.club_join_requests r
    join public.profiles p on p.id = r.user_id
    where r.club_id = p_club_id and r.status = 'pending'), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------- applicant state
create or replace function public.my_club_join(p_club_id uuid)
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select jsonb_build_object(
    'member', exists (select 1 from public.club_members
                      where club_id = p_club_id and user_id = auth.uid()),
    'pending', exists (select 1 from public.club_join_requests
                       where club_id = p_club_id and user_id = auth.uid()
                         and status = 'pending'));
$$;

-- ------------------------------------------------------- decide (club or admin)
create or replace function public.decide_club_join_request(
  p_request_id uuid,
  p_approve    boolean,
  p_note       text default null
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r      public.club_join_requests;
  c      public.clubs;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into r from public.club_join_requests where id = p_request_id for update;
  if not found then
    raise exception 'CLUB:request_not_found' using errcode = 'P0001';
  end if;
  if r.status <> 'pending' then
    raise exception 'CLUB:not_pending' using errcode = 'P0001';
  end if;
  if not (public.is_admin() or public.is_club_officer(r.club_id)) then
    raise exception 'CLUB:not_officer' using errcode = 'P0001';
  end if;
  select * into c from public.clubs where id = r.club_id;

  if p_approve then
    insert into public.club_members (club_id, user_id, role)
    values (r.club_id, r.user_id, 'member')
    on conflict (club_id, user_id) do nothing;
  end if;

  update public.club_join_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      decided_by = auth.uid(),
      decided_at = now(),
      decision_note = v_note
  where id = r.id;

  if p_approve then
    perform public.club_notify(r.user_id, 'You''re in ' || c.name,
      'Your request was approved. Your roster card is on the club page.',
      jsonb_build_object('kind', 'club_join_approved', 'club_id', c.id,
                         'route', '/c/' || c.handle));
  else
    perform public.club_notify(r.user_id, 'Your request to join ' || c.name || ' wasn''t approved',
      coalesce(v_note, 'You can ask the club''s officers for more details.'),
      jsonb_build_object('kind', 'club_join_rejected', 'club_id', c.id,
                         'route', '/c/' || c.handle));
  end if;

  perform public.mod_log(case when p_approve then 'club_join_approved' else 'club_join_rejected' end,
    'club', r.club_id::text, v_note,
    jsonb_build_object('request_id', r.id, 'user_id', r.user_id));
end;
$$;

-- ------------------------------------------------------- admin view
create or replace function public.admin_join_requests()
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
begin
  perform public.mod_require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'message', r.message, 'created_at', r.created_at,
             'club_id', c.id, 'club_name', c.name, 'club_handle', c.handle::text,
             'club_logo', c.logo_url,
             'user', jsonb_build_object(
               'id', p.id, 'username', p.username, 'display_name', p.display_name,
               'avatar_url', p.avatar_url))
           order by r.created_at)
    from public.club_join_requests r
    join public.clubs c on c.id = r.club_id
    join public.profiles p on p.id = r.user_id
    where r.status = 'pending'), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------- grants
revoke execute on function public.apply_to_club(uuid, text)                     from public, anon;
revoke execute on function public.club_join_requests(uuid)                      from public, anon;
revoke execute on function public.my_club_join(uuid)                            from public, anon;
revoke execute on function public.decide_club_join_request(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_join_requests()                         from public, anon;

grant execute on function public.apply_to_club(uuid, text)                     to authenticated;
grant execute on function public.club_join_requests(uuid)                      to authenticated;
grant execute on function public.my_club_join(uuid)                            to authenticated;
grant execute on function public.decide_club_join_request(uuid, boolean, text) to authenticated;
grant execute on function public.admin_join_requests()                         to authenticated;
