-- Two review fixes, both DB-only.
--
-- 1. A rejected club request used to keep its registry entry for ever.
--    `register_club()` stores `clubs.registry_id`, `admin_decide_club_request()`
--    set `status = 'rejected'` but left the id in place, and every later check
--    treats a non-null `registry_id` as "claimed":
--      * `club_registry_open()` hides the entry,
--      * `register_club()` raises CLUB:registry_claimed,
--      * the unique index on `clubs.registry_id` refuses a second club.
--    The rejection notice still promised "You can fix this and register again",
--    so any student could burn any entry by applying and being rejected — the
--    real club could then never register.
--
--    Rejection now releases the entry in the same transaction, and the entries
--    already stuck are released once, below.
--
-- 2. `mod_guard_pin_columns` (20261019004500) only guarded the global pin
--    columns (`pinned_until`, `pinned_by`). The club-local ones arrived later
--    (20261024004100) and were never added to the guard, so an officer posting
--    through the API could insert `club_pinned_until = '2099-01-01'` and get a
--    permanent pin past `max_active_pins_per_club`, and set `club_pinned_by` to
--    somebody else. The guard now covers all four columns; `club_pin_post` and
--    `club_unpin_post` already set `mykerawang.pin_rpc`, so they are unaffected.
--
-- Re-runnable: the functions are replaced, the trigger is dropped and recreated,
-- and the data fix only touches rows that are still wrong.

-- ------------------------------------------------------- 1. release on reject
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

  -- A rejection gives the entry back: otherwise the notice's "register again"
  -- is a lie and nobody else can ever claim that registry row.
  update public.clubs
  set status = case when p_approve then 'active' else 'rejected' end,
      is_verified = p_approve,
      registry_id = case when p_approve then c.registry_id else null end
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

revoke execute on function public.admin_decide_club_request(uuid, boolean, text) from public, anon;
grant  execute on function public.admin_decide_club_request(uuid, boolean, text) to authenticated;

-- One-time: give back the entries already burned by a rejection. Approved and
-- pending clubs keep theirs (a pending request still holds its entry on purpose,
-- so two students cannot fight over one row while an admin decides).
update public.clubs
set registry_id = null
where status = 'rejected' and registry_id is not null;

-- ------------------------------------------------------- 2. guard club pins
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
    new.club_pinned_until := null;
    new.club_pinned_by    := null;
  else
    new.pinned_until      := old.pinned_until;
    new.pinned_by         := old.pinned_by;
    new.club_pinned_until := old.club_pinned_until;
    new.club_pinned_by    := old.club_pinned_by;
  end if;
  return new;
end;
$$;

-- The column list matters: a trigger declared for the global columns alone never
-- fires for an update that only touches the club ones.
drop trigger if exists trg_mod_guard_pin_columns on public.posts;
create trigger trg_mod_guard_pin_columns
before insert or update of pinned_until, pinned_by, club_pinned_until, club_pinned_by
on public.posts
for each row execute function public.mod_guard_pin_columns();

revoke execute on function public.mod_guard_pin_columns() from public, anon, authenticated;

-- ------------------------------------------------------- 3. roster notice copy
-- The notice said "Officers can give you a position", but both add_club_member
-- and set_club_member_position go through club_require_president() — only the
-- president can. The copy now says so.
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
    'Your roster card is on the club page. The president can give you a position from the manage page.',
    jsonb_build_object('kind', 'club_member_added', 'club_id', c.id, 'route', '/c/' || c.handle));
  perform public.mod_log('club_member_added', 'club', p_club_id::text, null,
    jsonb_build_object('user_id', v_user, 'position', v_pos));
  return v_user;
end;
$$;

revoke execute on function public.add_club_member(uuid, text, text) from public, anon;
grant  execute on function public.add_club_member(uuid, text, text) to authenticated;

-- Notifications already sent keep the old sentence otherwise.
update public.notifications
set body = replace(body,
      'Officers can give you a position from the manage page.',
      'The president can give you a position from the manage page.')
where type = 'club'
  and data->>'kind' = 'club_member_added'
  and body like '%Officers can give you a position%';
