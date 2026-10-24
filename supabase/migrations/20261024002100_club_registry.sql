-- Club registry: the recognised-club list an admin maintains.
--
-- Registration is select-only against this list, so a student never types a
-- club name or ID and two applicants cannot both create the same club. One
-- registry entry can back at most one club page (clubs.registry_id is
-- unique); once claimed it drops out of club_registry_open().
--
-- Registration also records the official club Gmail (clubs.contact_email),
-- the applicant's position and the council list (club_private). The old
-- free-text register_club(text, text, text, text, text) is replaced.

-- ------------------------------------------------------- registry
create table if not exists public.club_registry (
  id          uuid primary key default gen_random_uuid(),
  code        extensions.citext not null,
  name        text not null,
  faculty     text,
  category    text,
  is_active   boolean not null default true,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table public.club_registry drop constraint if exists club_registry_code_key;
alter table public.club_registry add constraint club_registry_code_key unique (code);

alter table public.club_registry drop constraint if exists club_registry_code_format;
alter table public.club_registry add constraint club_registry_code_format
  check (code::text ~ '^[A-Za-z0-9._/-]{2,64}$');

alter table public.club_registry drop constraint if exists club_registry_name_length;
alter table public.club_registry add constraint club_registry_name_length
  check (length(btrim(name)) between 2 and 80);

alter table public.club_registry drop constraint if exists club_registry_category_valid;
alter table public.club_registry add constraint club_registry_category_valid
  check (category is null or category in
    ('academic', 'arts', 'sports', 'religious', 'volunteer', 'tech', 'business', 'other'));

alter table public.clubs add column if not exists registry_id uuid;
alter table public.clubs drop constraint if exists clubs_registry_id_key;
alter table public.clubs add constraint clubs_registry_id_key unique (registry_id);
alter table public.clubs drop constraint if exists clubs_registry_id_fkey;
alter table public.clubs add constraint clubs_registry_id_fkey
  foreign key (registry_id) references public.club_registry(id) on delete restrict;

alter table public.club_private add column if not exists applicant_position text;
alter table public.club_private add column if not exists council_members jsonb not null default '[]'::jsonb;

-- The roster title (Secretary, Treasurer, …) is separate from the
-- permission role (president / officer / member).
alter table public.club_members add column if not exists position text;
alter table public.club_members drop constraint if exists club_members_position_valid;
alter table public.club_members add constraint club_members_position_valid
  check (position is null or position in
    ('president', 'vice_president', 'secretary', 'treasurer', 'committee', 'other'));

alter table public.club_registry enable row level security;

drop policy if exists "club_registry_select" on public.club_registry;
create policy "club_registry_select" on public.club_registry
for select to authenticated using (true);

revoke all on public.club_registry from anon;
revoke insert, update, delete on public.club_registry from authenticated;
grant select on public.club_registry to authenticated;

-- ------------------------------------------------------- available list
-- What the registration form may pick: active entries no club has claimed.
-- Security definer so a student never needs to see pending club rows.
create or replace function public.club_registry_open()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'code', r.code::text, 'name', r.name,
           'faculty', r.faculty, 'category', r.category)
         order by r.name), '[]'::jsonb)
  from public.club_registry r
  where r.is_active
    and auth.uid() is not null
    and not exists (select 1 from public.clubs c where c.registry_id = r.id);
$$;

revoke execute on function public.club_registry_open() from public, anon;
grant  execute on function public.club_registry_open() to authenticated;

-- ------------------------------------------------------- admin registry
create or replace function public.admin_club_registry()
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
begin
  perform public.mod_require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'code', r.code::text, 'name', r.name,
             'faculty', r.faculty, 'category', r.category,
             'is_active', r.is_active, 'created_at', r.created_at,
             'club_id', c.id, 'club_handle', c.handle::text, 'club_status', c.status)
           order by r.name)
    from public.club_registry r
    left join public.clubs c on c.registry_id = r.id), '[]'::jsonb);
end;
$$;

create or replace function public.admin_save_club_registry(
  p_id       uuid,
  p_code     text,
  p_name     text,
  p_faculty  text,
  p_category text,
  p_active   boolean
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_code text := btrim(coalesce(p_code, ''));
  v_name text := btrim(coalesce(p_name, ''));
begin
  perform public.mod_require_admin();
  if v_code !~ '^[A-Za-z0-9._/-]{2,64}$' then
    raise exception 'CLUB:registry_code_invalid' using errcode = 'P0001';
  end if;
  if length(v_name) not between 2 and 80 then
    raise exception 'CLUB:name_invalid' using errcode = 'P0001';
  end if;
  if p_category is not null and p_category <> ''
     and p_category not in ('academic','arts','sports','religious','volunteer','tech','business','other') then
    raise exception 'CLUB:category_invalid' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.club_registry (code, name, faculty, category, is_active, created_by)
    values (v_code, v_name,
            nullif(btrim(coalesce(p_faculty, '')), ''),
            nullif(p_category, ''),
            coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    update public.club_registry
    set code = v_code,
        name = v_name,
        faculty = nullif(btrim(coalesce(p_faculty, '')), ''),
        category = nullif(p_category, ''),
        is_active = coalesce(p_active, true)
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'CLUB:registry_not_found' using errcode = 'P0001';
    end if;
  end if;

  perform public.mod_log('club_registry_saved', 'club_registry', v_id::text, null,
    jsonb_build_object('code', v_code, 'name', v_name, 'active', coalesce(p_active, true)));
  return v_id;
exception when unique_violation then
  raise exception 'CLUB:registry_code_taken' using errcode = 'P0001';
end;
$$;

-- ------------------------------------------------------- registration
drop function if exists public.register_club(text, text, text, text, text);

create or replace function public.register_club(
  p_registry_id   uuid,
  p_official_email text,
  p_position      text,
  p_council       jsonb,
  p_proof_note    text default null
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_email  text := lower(btrim(coalesce(p_official_email, '')));
  v_base   text;
  v_handle text;
  v_try    text;
  n        int := 0;
  v_id     uuid;
  r        public.club_registry;
  e        jsonb;
  v_council jsonb := coalesce(p_council, '[]'::jsonb);
begin
  if v_uid is null then
    raise exception 'CLUB:not_signed_in' using errcode = '42501';
  end if;
  if public.is_restricted('account') then
    raise exception 'MOD:restricted:account' using errcode = 'P0001';
  end if;
  if p_position is null
     or p_position not in ('president','vice_president','secretary','treasurer','committee','other') then
    raise exception 'CLUB:position_invalid' using errcode = 'P0001';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'CLUB:email_invalid' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_council) <> 'array' then
    raise exception 'CLUB:council_invalid' using errcode = 'P0001';
  end if;
  if jsonb_array_length(v_council) > 10 then
    raise exception 'CLUB:council_too_long' using errcode = 'P0001';
  end if;
  for e in select value from jsonb_array_elements(v_council) loop
    if jsonb_typeof(e) <> 'object'
       or length(btrim(coalesce(e->>'name', ''))) not between 2 and 80
       or length(btrim(coalesce(e->>'position', ''))) > 40 then
      raise exception 'CLUB:council_invalid' using errcode = 'P0001';
    end if;
  end loop;

  if (select count(*) from public.clubs where created_by = v_uid and status = 'pending') >= 2 then
    raise exception 'CLUB:too_many_pending' using errcode = 'P0001';
  end if;

  select * into r from public.club_registry
  where id = p_registry_id and is_active
  for update;
  if not found then
    raise exception 'CLUB:registry_not_found' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.clubs where registry_id = r.id) then
    raise exception 'CLUB:registry_claimed' using errcode = 'P0001';
  end if;

  -- The page handle is derived, never typed: the official code is the most
  -- stable source, the name is the fallback.
  v_base := left(regexp_replace(coalesce(r.code::text, r.name), '[^A-Za-z0-9_]', '', 'g'), 24);
  if length(v_base) < 3 then
    v_base := 'club' || v_base;
  end if;
  v_try := v_base;
  while exists (select 1 from public.clubs where handle = v_try::extensions.citext) loop
    n := n + 1;
    v_try := left(v_base, 26) || n::text;
  end loop;
  v_handle := v_try;

  insert into public.clubs
    (handle, name, category, faculty, contact_email, status, created_by, registry_id)
  values
    (v_handle, r.name, r.category, r.faculty, v_email, 'pending', v_uid, r.id)
  returning id into v_id;

  insert into public.club_members (club_id, user_id, role, position)
  values (v_id, v_uid, 'president', p_position);

  insert into public.club_private (club_id, proof_note, applicant_position, council_members)
  values (v_id, nullif(btrim(coalesce(p_proof_note, '')), ''), p_position, v_council);

  perform public.mod_log('club_registered', 'club', v_id::text, null,
    jsonb_build_object('handle', v_handle, 'registry_code', r.code::text));

  return jsonb_build_object('id', v_id, 'handle', v_handle);
end;
$$;

-- ------------------------------------------------------- pending queue
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
             'faculty', c.faculty, 'logo_url', c.logo_url, 'created_at', c.created_at,
             'official_email', c.contact_email,
             'registry_code', r.code::text,
             'proof_note', cp.proof_note,
             'applicant_position', cp.applicant_position,
             'council_members', coalesce(cp.council_members, '[]'::jsonb),
             'president', case when pr.id is null then null else jsonb_build_object(
               'id', pr.id, 'username', pr.username, 'display_name', pr.display_name,
               'avatar_url', pr.avatar_url) end)
           order by c.created_at)
    from public.clubs c
    left join public.club_registry r on r.id = c.registry_id
    left join public.club_private cp on cp.club_id = c.id
    left join public.club_members m on m.club_id = c.id and m.role = 'president'
    left join public.profiles pr on pr.id = m.user_id
    where c.status = 'pending'), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------- grants
revoke execute on function public.admin_club_registry()                                            from public, anon;
revoke execute on function public.admin_save_club_registry(uuid, text, text, text, text, boolean)  from public, anon;
revoke execute on function public.register_club(uuid, text, text, jsonb, text)                     from public, anon;
revoke execute on function public.admin_pending_clubs()                                            from public, anon;

grant execute on function public.admin_club_registry()                                            to authenticated;
grant execute on function public.admin_save_club_registry(uuid, text, text, text, text, boolean)  to authenticated;
grant execute on function public.register_club(uuid, text, text, jsonb, text)                     to authenticated;
grant execute on function public.admin_pending_clubs()                                            to authenticated;
