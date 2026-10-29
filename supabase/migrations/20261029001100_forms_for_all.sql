-- Forms for everyone: standalone forms owned by a user or a club.
--
-- Until now every form belonged to an event (the KI report survey). This lets
-- any signed-in student make a form, link it from a post, event or
-- announcement (/f/:id), and read the answers — while keeping the event forms
-- exactly as they were.
--
-- Shape: `event_forms` is reused rather than copied, so the editor, the answer
-- page, the responses table and the CSV are one code path.
--
--   event_id  set      an event form; permissions come from the event (unchanged)
--   event_id  null     a standalone form; owner_id made it, club_id optional
--
-- Who may do what on a standalone form:
--   create          any signed-in user (bans, restrictions, the verification
--                   switch and the new-account hourly cap apply); a club form
--                   needs someone who can act for the club
--   edit / publish  the owner, or the club's acting officers
--   close / delete  same
--   read answers    the owner, or the club's officers. Not admins: moderators
--                   see the questions (mod_preview), never the answers
--   answer          signed-in users only; each may edit or withdraw their own
--
-- Abuse limits (forms open to everyone are a phishing / data-harvest tool):
--   * at most 10 draft-or-open personal forms per owner
--   * moderation_settings.new_account_forms_per_hour for new accounts
--   * labels asking for a password, OTP, PIN, CVV or card number are refused
--     on standalone forms (the editor also warns on IC / bank / address)
--   * 30 answers an hour per person (10 for new accounts), 2000 per form
--   * 'form' is a moderation target: reportable, hideable. A hidden form takes
--     no answers and its answers can no longer be read, even by the owner, so
--     harvested data cannot be exported after a takedown
--
-- Deletion: deleting a form deletes its fields and answers (FK cascade). When
-- an owner deletes their account, their personal forms go with them; club
-- forms stay with the club (owner_id is cleared). A responder's account
-- deletion already removes their answers (form_responses.user_id cascade).
--
-- Re-runnable: the test harness applies every migration twice.

-- ====================================================== columns

alter table public.event_forms alter column event_id drop not null;

alter table public.event_forms
  add column if not exists owner_id  uuid references public.profiles(id) on delete set null,
  add column if not exists club_id   uuid references public.clubs(id) on delete cascade,
  add column if not exists is_hidden boolean not null default false;

-- A form always has a home: its event, its club, or its owner.
alter table public.event_forms drop constraint if exists event_forms_has_home;
alter table public.event_forms add constraint event_forms_has_home
  check (event_id is not null or club_id is not null or owner_id is not null);

create index if not exists event_forms_owner_idx
  on public.event_forms (owner_id, updated_at desc) where event_id is null;
create index if not exists event_forms_club_idx
  on public.event_forms (club_id, updated_at desc) where event_id is null;
create index if not exists form_responses_user_idx
  on public.form_responses (user_id, submitted_at desc);

alter table public.moderation_settings
  add column if not exists new_account_forms_per_hour int not null default 2;
alter table public.moderation_settings drop constraint if exists moderation_settings_forms_sane;
alter table public.moderation_settings add constraint moderation_settings_forms_sane
  check (new_account_forms_per_hour >= 1);

-- ====================================================== permissions

-- Writing a form. Event branch is the 007100 rule, unchanged.
create or replace function public.can_manage_form(p_form_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.event_forms f
    left join public.events e on e.id = f.event_id
    where f.id = p_form_id
      and case
            when f.event_id is not null then
              e.organizer_id = auth.uid()
              or public.is_admin()
              or (e.club_id is not null and public.can_act_as_club(e.club_id))
            else
              f.owner_id = auth.uid()
              or (f.club_id is not null and public.can_act_as_club(f.club_id))
          end);
$$;

-- Reading the answers. A standalone form's answers are its owner's and its
-- club officers' only, and nobody's once moderation has hidden it.
create or replace function public.can_read_form(p_form_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.event_forms f
    left join public.events e on e.id = f.event_id
    where f.id = p_form_id
      and case
            when f.event_id is not null then
              e.organizer_id = auth.uid()
              or public.is_admin()
              or (e.club_id is not null and public.is_club_officer(e.club_id))
            else
              not f.is_hidden
              and (f.owner_id = auth.uid()
                   or (f.club_id is not null and public.is_club_officer(f.club_id)))
          end);
$$;

-- ====================================================== label rules

-- Questions a student form has no business asking. Kept narrow on purpose:
-- IC, bank and address have real uses (trip insurance, refunds) and only get
-- a warning in the editor (lib/utils/form_rules.dart, same list).
create or replace function public.form_label_blocked(p_text text)
returns boolean
language sql immutable
as $$
  select coalesce(p_text, '') ~* (
    '\m(password|passwd|passcode|kata\s*laluan|otp|tac|pin|cvv|cvc)\M'
    || '|card\s*number|credit\s*card|debit\s*card'
    || '|nombor\s*kad\s*(kredit|debit)|no\.?\s*kad\s*(kredit|debit)');
$$;

create or replace function public.form_fields_guard()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.event_forms f
             where f.id = new.form_id and f.event_id is null)
     and (public.form_label_blocked(new.label) or public.form_label_blocked(new.help)) then
    raise exception 'FORM:blocked_label' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.form_fields_guard() from public, anon, authenticated;

drop trigger if exists trg_form_fields_guard on public.form_fields;
create trigger trg_form_fields_guard
before insert or update of label, help on public.form_fields
for each row execute function public.form_fields_guard();

-- ====================================================== the write gate

-- 25004100's guard plus one rate kind, 'form'. Event forms never reach it
-- (owner_id is null there, so the owner check returns early).
create or replace function public.mod_guard_write()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_scope  text := tg_argv[0];
  v_col    text := tg_argv[1];
  v_kind   text := nullif(tg_argv[2], '');
  v_cap    text := nullif(tg_argv[3], '');
  v_uid    uuid := auth.uid();
  v_owner  uuid;
  r        record;
  s        public.moderation_settings;
  v_age    interval;
  v_limit  int;
  v_count  int;
begin
  v_owner := (to_jsonb(new) ->> v_col)::uuid;

  if v_uid is null or v_owner is distinct from v_uid then
    return new;
  end if;

  select * into r from public.mod_active_restriction(v_uid, v_scope);
  if found then
    raise exception 'MOD:restricted:%', r.scope
      using errcode = 'P0001',
            detail  = jsonb_build_object('scope', r.scope, 'until', r.until, 'reason', r.reason)::text,
            hint    = 'This account is restricted from this action.';
  end if;

  if tg_op = 'INSERT' and v_cap is not null
     and public.verification_required(v_cap)
     and not public.is_admin()
     and not public.is_verified_student(v_uid) then
    raise exception 'VERIFY:required:%', v_cap
      using errcode = 'P0001',
            hint = 'Verify your student status to do this.';
  end if;

  if tg_op <> 'INSERT' or v_kind is null or public.is_admin() then
    return new;
  end if;

  s := public.mod_settings();
  select now() - u.created_at into v_age from auth.users u where u.id = v_uid;
  if v_age is null or v_age >= make_interval(hours => s.new_account_hours) then
    return new;
  end if;

  v_limit := case v_kind
    when 'post'    then s.new_account_posts_per_hour
    when 'comment' then s.new_account_comments_per_hour
    when 'listing' then s.new_account_listings_per_hour
    when 'event'   then s.new_account_events_per_hour
    when 'form'    then s.new_account_forms_per_hour
  end;
  if v_limit is null then return new; end if;

  execute format(
    'select count(*) from public.%I where %I = $1 and created_at > now() - interval ''1 hour''',
    tg_table_name, v_col)
  into v_count using v_uid;

  if v_count >= v_limit then
    raise exception 'MOD:rate_limited:%', v_kind
      using errcode = 'P0001',
            detail  = jsonb_build_object('limit', v_limit, 'hours', s.new_account_hours)::text,
            hint    = 'New accounts have an hourly limit.';
  end if;

  return new;
end;
$$;

revoke execute on function public.mod_guard_write() from public, anon, authenticated;

-- A posting restriction covers forms: both put words in front of students.
drop trigger if exists trg_mod_guard on public.event_forms;
create trigger trg_mod_guard
before insert on public.event_forms
for each row execute function public.mod_guard_write('post', 'owner_id', 'form', 'form_create');

create or replace function public.verification_required(p_capability text)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce((
    select s.verification_enabled
    from public.access_settings s where s.id), false)
  and p_capability in ('event_join','event_create','sell',
                       'club_join','club_officer','club_create',
                       'form_submit','form_create');
$$;

-- ====================================================== creating

create or replace function public.create_standalone_form(
  p_title         text default null,
  p_club_id       uuid default null,
  p_template_slug text default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_tpl  public.form_templates;
  v_form uuid;
  v_n    int;
begin
  if v_uid is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;

  if p_club_id is not null and not public.can_act_as_club(p_club_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  select count(*) into v_n from public.event_forms
  where owner_id = v_uid and event_id is null and status <> 'closed';
  if v_n >= 10 then
    raise exception 'FORM:too_many' using errcode = 'P0001';
  end if;

  if p_template_slug is not null then
    select * into v_tpl from public.form_templates
    where slug = p_template_slug and active;
    if not found then
      raise exception 'FORM:no_template' using errcode = 'P0001';
    end if;
  end if;

  insert into public.event_forms (event_id, owner_id, club_id, template_id,
                                  title, intro, created_by)
  values (null, v_uid, p_club_id, v_tpl.id,
          left(coalesce(nullif(trim(p_title), ''), v_tpl.name, 'Untitled form'), 120),
          v_tpl.intro, v_uid)
  returning id into v_form;

  if v_tpl.id is not null then
    insert into public.form_fields
      (form_id, kind, label, help, required, options, analysis, ki_code, sort)
    select v_form, f.kind, f.label, f.help, f.required, f.options,
           f.analysis, f.ki_code, f.sort
    from public.form_template_fields f
    where f.template_id = v_tpl.id
    order by f.sort;
  end if;

  return v_form;
end;
$$;

revoke execute on function public.create_standalone_form(text, uuid, text) from public, anon;
grant  execute on function public.create_standalone_form(text, uuid, text) to authenticated;

-- ====================================================== deleting

-- Standalone forms only: an event form is part of the event's report.
create or replace function public.delete_form(p_form_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_form public.event_forms;
begin
  select * into v_form from public.event_forms where id = p_form_id;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if v_form.event_id is not null then
    raise exception 'FORM:event_form' using errcode = 'P0001';
  end if;
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;
  delete from public.event_forms where id = p_form_id;
end;
$$;

revoke execute on function public.delete_form(uuid) from public, anon;
grant  execute on function public.delete_form(uuid) to authenticated;

-- A responder takes their answers back. Standalone forms only, for the same
-- reason as above.
create or replace function public.withdraw_form_response(p_form_id uuid)
returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;
  if exists (select 1 from public.event_forms
             where id = p_form_id and event_id is not null) then
    raise exception 'FORM:event_form' using errcode = 'P0001';
  end if;
  delete from public.form_responses
  where form_id = p_form_id and user_id = auth.uid();
  return found;
end;
$$;

revoke execute on function public.withdraw_form_response(uuid) from public, anon;
grant  execute on function public.withdraw_form_response(uuid) to authenticated;

-- Account deletion: personal forms go with the owner; club forms stay.
create or replace function public.forms_owner_deleted()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  delete from public.event_forms
  where owner_id = old.id and event_id is null and club_id is null;
  return old;
end;
$$;

revoke execute on function public.forms_owner_deleted() from public, anon, authenticated;

drop trigger if exists trg_forms_owner_deleted on public.profiles;
create trigger trg_forms_owner_deleted
before delete on public.profiles
for each row execute function public.forms_owner_deleted();

-- ====================================================== listing

-- "My forms" and the composers' picker: personal forms plus forms of clubs the
-- caller is an officer of.
create or replace function public.my_forms()
returns table (
  id          uuid,
  title       text,
  status      text,
  club_id     uuid,
  club_name   text,
  club_handle text,
  responses   bigint,
  is_hidden   boolean,
  closes_at   timestamptz,
  updated_at  timestamptz
)
language sql security definer stable
set search_path = public
as $$
  select f.id, f.title, f.status, f.club_id, c.name, c.handle,
         (select count(*) from public.form_responses r where r.form_id = f.id),
         f.is_hidden, f.closes_at, f.updated_at
  from public.event_forms f
  left join public.clubs c on c.id = f.club_id
  where auth.uid() is not null
    and f.event_id is null
    and (f.owner_id = auth.uid()
         or (f.club_id is not null and public.is_club_officer(f.club_id)))
  order by f.status = 'closed', f.updated_at desc
  limit 200;
$$;

revoke execute on function public.my_forms() from public, anon;
grant  execute on function public.my_forms() to authenticated;

-- ====================================================== publishing

create or replace function public.publish_form(p_form_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_fields int;
  v_field  public.form_fields;
begin
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.event_forms where id = p_form_id and is_hidden) then
    raise exception 'FORM:removed' using errcode = 'P0001';
  end if;

  for v_field in select * from public.form_fields where form_id = p_form_id loop
    perform public.form_check_field(v_field.kind, v_field.label, v_field.required,
                                    v_field.options, v_field.analysis, v_field.ki_code);
  end loop;

  select count(*) into v_fields from public.form_fields
  where form_id = p_form_id and kind <> 'heading';
  if v_fields = 0 then
    raise exception 'FORM:empty' using errcode = 'P0001';
  end if;

  update public.event_forms set status = 'open', updated_at = now()
  where id = p_form_id and status = 'draft';
  if not found then
    raise exception 'FORM:not_draft' using errcode = 'P0001';
  end if;
end;
$$;

-- ====================================================== the answer page

-- 007100's read model plus who made it. A hidden form shows nothing to anyone
-- but its managers.
create or replace function public.form_public(p_form_id uuid)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_form    public.event_forms;
  v_event   public.events;
  v_uid     uuid := auth.uid();
  v_can     boolean := false;
  v_reason  text := null;
  v_n       int;
  v_mine    jsonb;
  v_manage  boolean;
  v_owner   jsonb;
  v_club    jsonb;
begin
  select * into v_form from public.event_forms where id = p_form_id;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;

  v_manage := public.can_manage_form(p_form_id);

  select * into v_event from public.events where id = v_form.event_id;

  if v_form.is_hidden then
    v_reason := 'removed';
  elsif v_uid is null then
    v_reason := 'signed_out';
  elsif v_form.status <> 'open' then
    v_reason := 'closed';
  elsif v_form.closes_at is not null and v_form.closes_at < now() then
    v_reason := 'closed';
  elsif v_form.event_id is not null and v_form.require_rsvp
        and not exists (select 1 from public.event_participants p
                        where p.event_id = v_form.event_id and p.user_id = v_uid) then
    v_reason := 'not_joined';
  else
    select count(*) into v_n from public.form_responses where form_id = p_form_id;
    if ((v_form.max_responses is not null and v_n >= v_form.max_responses)
        or (v_form.event_id is null and v_n >= 2000))
       and not exists (select 1 from public.form_responses
                       where form_id = p_form_id and user_id = v_uid) then
      v_reason := 'full';
    else
      v_can := true;
    end if;
  end if;

  select to_jsonb(r) - 'entered_by' into v_mine
  from public.form_responses r
  where r.form_id = p_form_id and r.user_id = v_uid;

  if v_form.event_id is null then
    select jsonb_build_object('id', p.id, 'username', p.username,
             'display_name', coalesce(p.display_name, p.full_name))
    into v_owner from public.profiles p where p.id = v_form.owner_id;
    select jsonb_build_object('id', c.id, 'name', c.name, 'handle', c.handle)
    into v_club from public.clubs c where c.id = v_form.club_id;
  end if;

  return jsonb_build_object(
    'form', jsonb_build_object(
      'id', v_form.id,
      'title', v_form.title,
      'intro', case when v_form.is_hidden and not v_manage then null else v_form.intro end,
      'status', v_form.status,
      'closes_at', v_form.closes_at,
      'require_rsvp', v_form.require_rsvp,
      'after_checkin', v_form.after_checkin,
      'max_responses', v_form.max_responses,
      'standalone', v_form.event_id is null,
      'is_hidden', v_form.is_hidden,
      'owner', v_owner,
      'club', v_club,
      'event', case when v_event.id is null then null else
        jsonb_build_object('id', v_event.id, 'title', v_event.title,
                           'start_datetime', v_event.start_datetime,
                           'end_datetime', v_event.end_datetime) end),
    'fields', case when v_form.is_hidden and not v_manage then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'kind', f.kind, 'label', f.label, 'help', f.help,
        'required', f.required, 'options', f.options, 'sort', f.sort)
        order by f.sort, f.created_at)
      from public.form_fields f where f.form_id = p_form_id), '[]'::jsonb) end,
    'mine', v_mine,
    'can_answer', v_can,
    'can_edit', v_manage,
    'can_read', public.can_read_form(p_form_id),
    'reason', v_reason);
end;
$$;

revoke execute on function public.form_public(uuid) from public;
grant  execute on function public.form_public(uuid) to anon, authenticated;

-- ====================================================== answer limits

-- Runs under submit_form_response, so the 007100 submit path stays as it was.
create or replace function public.form_response_limits()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_form  public.event_forms;
  s       public.moderation_settings;
  v_age   interval;
  v_limit int := 30;
  v_n     int;
begin
  select * into v_form from public.event_forms where id = new.form_id;
  if v_form.is_hidden then
    raise exception 'FORM:removed' using errcode = 'P0001';
  end if;
  if tg_op <> 'INSERT' then
    return new;
  end if;

  if v_form.event_id is null then
    select count(*) into v_n from public.form_responses where form_id = new.form_id;
    if v_n >= 2000 then
      raise exception 'FORM:full' using errcode = 'P0001';
    end if;
  end if;

  -- Hourly cap per person, own answers only (an organiser entering paper
  -- forms for others is not this).
  if auth.uid() is not null and new.user_id = auth.uid() and not public.is_admin() then
    s := public.mod_settings();
    select now() - u.created_at into v_age from auth.users u where u.id = new.user_id;
    if v_age is null or v_age < make_interval(hours => s.new_account_hours) then
      v_limit := 10;
    end if;
    select count(*) into v_n from public.form_responses
    where user_id = new.user_id and submitted_at > now() - interval '1 hour';
    if v_n >= v_limit then
      raise exception 'FORM:rate_limited' using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.form_response_limits() from public, anon, authenticated;

drop trigger if exists trg_form_response_limits on public.form_responses;
create trigger trg_form_response_limits
before insert or update on public.form_responses
for each row execute function public.form_response_limits();

-- ====================================================== reading answers

-- 007100's list. The matric fallback (from a verified email) is for event
-- forms only: on a standalone form it would hand a stranger the matric of
-- someone who never typed it in.
create or replace function public.form_response_list(p_form_id uuid)
returns table (
  user_id      uuid,
  username     text,
  display_name text,
  student_id   text,
  role         text,
  submitted_at timestamptz,
  answers      jsonb
)
language plpgsql security definer stable
set search_path = public
as $$
declare
  v_event boolean;
begin
  if not public.can_read_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  select f.event_id is not null into v_event from public.event_forms f where f.id = p_form_id;

  return query
  select r.user_id,
         p.username,
         coalesce(p.display_name, p.full_name),
         coalesce(
           (select nullif(r.answers ->> f.id::text, '')
            from public.form_fields f
            where f.form_id = p_form_id and f.kind = 'student_id'
            order by f.sort limit 1),
           case when v_event then
             (select split_part(v.email::text, '@', 1)
              from public.student_verifications v where v.user_id = r.user_id) end),
         r.role,
         r.submitted_at,
         r.answers
  from public.form_responses r
  left join public.profiles p on p.id = r.user_id
  where r.form_id = p_form_id
  order by coalesce(p.display_name, p.full_name), r.submitted_at;
end;
$$;

-- ====================================================== moderation target

do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.moderation_cases'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%target_type%'
  loop
    execute format('alter table public.moderation_cases drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.moderation_cases add constraint moderation_cases_target_type_check
  check (target_type in ('post','comment','event','listing','user','form'));

create or replace function public.mod_is_hideable(p_type text)
returns boolean
language sql immutable
as $$ select p_type in ('post','comment','event','listing','form'); $$;

create or replace function public.mod_type_label(p_type text)
returns text
language sql immutable
as $$
  select case p_type
    when 'post' then 'post' when 'comment' then 'comment'
    when 'event' then 'event' when 'listing' then 'listing'
    when 'form' then 'form'
    else 'profile' end;
$$;

create or replace function public.mod_scope_for(p_type text)
returns text
language sql immutable
as $$
  select case p_type
    when 'post' then 'post' when 'comment' then 'comment'
    when 'listing' then 'market' when 'event' then 'events'
    when 'form' then 'post'
    else null end;
$$;

-- An event form answers to its organiser; a club form whose maker left has no
-- owner to strike, which is fine (the case still hides it).
create or replace function public.mod_target_owner(p_type text, p_id text)
returns table (owner_id uuid, anonymous boolean)
language plpgsql security definer stable
set search_path = public
as $$
begin
  case p_type
    when 'post' then
      return query select p.user_id, coalesce(p.is_anonymous, false)
                   from public.posts p where p.id = p_id::uuid;
    when 'comment' then
      return query select c.user_id, coalesce(c.is_anonymous, false)
                   from public.comments c where c.id = p_id::uuid;
    when 'event' then
      return query select e.organizer_id, false from public.events e where e.id = p_id::uuid;
    when 'listing' then
      return query select l.seller_id, false from public.listings l where l.id = p_id::uuid;
    when 'user' then
      return query select pr.id, false from public.profiles pr where pr.id = p_id::uuid;
    when 'form' then
      return query select coalesce(f.owner_id, e.organizer_id), false
                   from public.event_forms f
                   left join public.events e on e.id = f.event_id
                   where f.id = p_id::uuid;
    else
      return;
  end case;
exception when invalid_text_representation then
  return;
end;
$$;

create or replace function public.mod_set_hidden(p_type text, p_id text, p_hidden boolean)
returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
  case p_type
    when 'post'    then update public.posts       set is_hidden = p_hidden where id = p_id::uuid;
    when 'comment' then update public.comments    set is_hidden = p_hidden where id = p_id::uuid;
    when 'event'   then update public.events      set is_hidden = p_hidden where id = p_id::uuid;
    when 'listing' then update public.listings    set is_hidden = p_hidden where id = p_id::uuid;
    when 'form'    then update public.event_forms set is_hidden = p_hidden where id = p_id::uuid;
    else return false;
  end case;
  return found;
end;
$$;

-- The moderator sees the questions, never the answers.
create or replace function public.mod_preview_raw(p_type text, p_id text)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
declare
  v jsonb;
begin
  case p_type
    when 'post' then
      select jsonb_build_object('title', p.title, 'body', left(p.body, 600),
               'image_url', p.image_url, 'anonymous', coalesce(p.is_anonymous, false),
               'hidden', p.is_hidden, 'created_at', p.created_at)
      into v from public.posts p where p.id = p_id::uuid;
    when 'comment' then
      select jsonb_build_object('body', left(c.body, 600), 'post_id', c.post_id,
               'event_id', c.event_id, 'anonymous', coalesce(c.is_anonymous, false),
               'hidden', c.is_hidden, 'created_at', c.created_at)
      into v from public.comments c where c.id = p_id::uuid;
    when 'event' then
      select jsonb_build_object('title', e.title, 'body', left(e.description, 600),
               'image_url', e.image_url, 'hidden', e.is_hidden, 'starts_at', e.start_datetime)
      into v from public.events e where e.id = p_id::uuid;
    when 'listing' then
      select jsonb_build_object('title', l.title, 'body', left(l.description, 600),
               'image_url', l.image_url, 'price', l.price, 'hidden', l.is_hidden)
      into v from public.listings l where l.id = p_id::uuid;
    when 'user' then
      select jsonb_build_object('title', coalesce(pr.display_name, pr.username),
               'username', pr.username, 'body', left(pr.bio, 600),
               'image_url', pr.avatar_url, 'role', pr.role, 'banned', coalesce(pr.is_banned, false))
      into v from public.profiles pr where pr.id = p_id::uuid;
    when 'form' then
      select jsonb_build_object('title', f.title,
               'body', left(concat_ws(E'\n', f.intro,
                         (select string_agg('• ' || x.label, E'\n' order by x.sort)
                          from public.form_fields x
                          where x.form_id = f.id and x.kind <> 'heading')), 600),
               'hidden', f.is_hidden, 'status', f.status, 'created_at', f.created_at,
               'responses', (select count(*) from public.form_responses r where r.form_id = f.id))
      into v from public.event_forms f where f.id = p_id::uuid;
    else
      v := null;
  end case;
  return v;
exception when invalid_text_representation then
  return null;
end;
$$;

revoke execute on function public.mod_target_owner(text, text)        from public, anon, authenticated;
revoke execute on function public.mod_set_hidden(text, text, boolean) from public, anon, authenticated;
revoke execute on function public.mod_preview_raw(text, text)         from public, anon, authenticated;

drop trigger if exists trg_mod_target_deleted on public.event_forms;
create trigger trg_mod_target_deleted after delete on public.event_forms
for each row execute function public.mod_target_deleted('form');
