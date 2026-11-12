-- Public forms: a per-form switch that lets people without an account answer.
--
-- Why: clubs reach for Google Forms because anyone can fill one in. A public
-- MYKerawang form does the same, and the thank-you page invites the guest to
-- join — so the form brings people into the app instead of out of it.
--
--   is_public = false (the default, every existing form)
--     signed-in users answer as before. A guest sees the title, who made it
--     and a sign-in button; the questions and intro are no longer sent.
--   is_public = true
--     a guest sees the questions and answers with a name (required) and an
--     email (optional). Signed-in users answer exactly as before.
--
-- A guest answer is a form_responses row with user_id null and guest_name set.
-- It cannot be edited or withdrawn later (there is no account to tie it to).
--
-- Abuse limits for guests (no account means no per-person limit is possible):
--   * 50 guest answers per form per hour, on top of the existing 2000 per form
--   * a form that needs an RSVP, or that moderation has hidden, takes none
--   * everything else (blocked labels, closing date, response cap) as before
--
-- Re-runnable: the test harness applies every migration twice.

-- ====================================================== columns

alter table public.event_forms
  add column if not exists is_public boolean not null default false;

alter table public.form_responses alter column user_id drop not null;
alter table public.form_responses
  add column if not exists guest_name  text,
  add column if not exists guest_email text;

-- Every answer belongs to an account or carries a guest's name.
alter table public.form_responses drop constraint if exists form_responses_who;
alter table public.form_responses add constraint form_responses_who
  check (user_id is not null or nullif(trim(guest_name), '') is not null);

create index if not exists form_responses_guest_idx
  on public.form_responses (form_id, submitted_at desc) where user_id is null;

-- ====================================================== the switch

create or replace function public.set_form_public(p_form_id uuid, p_on boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  update public.event_forms
  set is_public = coalesce(p_on, false),
      updated_at = now()
  where id = p_form_id;

  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.set_form_public(uuid, boolean) from public, anon;
grant  execute on function public.set_form_public(uuid, boolean) to authenticated;

-- ====================================================== answer checking

-- The per-question checks from 007100's submit_form_response, lifted out so
-- the signed-in and the guest paths accept exactly the same answers. Returns
-- the cleaned answers; raises FORM:<code>:<field id> on the first bad one.
create or replace function public.form_clean_answers(p_form_id uuid, p_answers jsonb)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
declare
  v_field  public.form_fields;
  v_raw    text;
  v_num    numeric;
  v_clean  jsonb := '{}'::jsonb;
  v_choice text;
  v_multis jsonb;
begin
  for v_field in select * from public.form_fields
                  where form_id = p_form_id order by sort loop
    if v_field.kind = 'heading' then
      continue;
    end if;

    -- Multi choice is an array, so it is answered (or not) before the scalar
    -- path; treating it through a text read would look unanswered.
    if v_field.kind = 'multi_choice' then
      v_multis := p_answers -> v_field.id::text;
      if v_multis is null or jsonb_typeof(v_multis) <> 'array'
         or jsonb_array_length(v_multis) = 0 then
        if v_field.required then
          raise exception 'FORM:required:%', v_field.id using errcode = 'P0001';
        end if;
        continue;
      end if;
      for v_choice in select jsonb_array_elements_text(v_multis) loop
        if not exists (select 1 from jsonb_array_elements_text(v_field.options->'choices') c
                       where c = v_choice) then
          raise exception 'FORM:bad_choice:%', v_field.id using errcode = 'P0001';
        end if;
      end loop;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_multis);
      continue;
    end if;

    v_raw := nullif(trim(coalesce(
      public.form_answer_text(p_answers, v_field.id), '')), '');

    if v_raw is null then
      if v_field.required then
        raise exception 'FORM:required:%', v_field.id using errcode = 'P0001';
      end if;
      continue;
    end if;

    if v_field.kind = 'rating' then
      v_num := public.form_num(v_raw);
      if v_num is null
         or v_num <> trunc(v_num)
         or v_num < (v_field.options->>'min')::numeric
         or v_num > (v_field.options->>'max')::numeric then
        raise exception 'FORM:bad_rating:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_num);

    elsif v_field.kind = 'single_choice' then
      if not exists (select 1 from jsonb_array_elements_text(v_field.options->'choices') c
                     where c = v_raw) then
        raise exception 'FORM:bad_choice:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_raw);

    elsif v_field.kind = 'short_text' then
      if length(v_raw) > 200 then
        raise exception 'FORM:too_long:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_raw);

    elsif v_field.kind = 'long_text' then
      if length(v_raw) > 2000 then
        raise exception 'FORM:too_long:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_raw);

    elsif v_field.kind = 'student_id' then
      if v_raw !~ '^[0-9]{6,12}$' then
        raise exception 'FORM:bad_matric:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_raw);

    elsif v_field.kind = 'consent' then
      if v_raw <> 'true' then
        raise exception 'FORM:consent:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, true);

    elsif v_field.kind = 'number' then
      if public.form_num(v_raw) is null then
        raise exception 'FORM:bad_number:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, public.form_num(v_raw));

    elsif v_field.kind = 'date' then
      begin
        perform v_raw::timestamptz;
      exception when others then
        raise exception 'FORM:bad_date:%', v_field.id using errcode = 'P0001';
      end;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_raw);

    else
      -- email / phone: stored as given, length-capped only
      if length(v_raw) > 200 then
        raise exception 'FORM:too_long:%', v_field.id using errcode = 'P0001';
      end if;
      v_clean := v_clean || jsonb_build_object(v_field.id::text, v_raw);
    end if;
  end loop;

  return v_clean;
end;
$$;

revoke execute on function public.form_clean_answers(uuid, jsonb) from public, anon, authenticated;

-- 007100's submit, unchanged in behaviour, now using the shared checks.
create or replace function public.submit_form_response(
  p_form_id  uuid,
  p_for_user uuid,
  p_role     text,
  p_answers  jsonb
)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_user   uuid;
  v_role   text := coalesce(nullif(p_role, ''), 'peserta');
  v_form   public.event_forms;
  v_clean  jsonb;
  v_n      int;
  v_mine   uuid;
begin
  if v_uid is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;

  v_user := coalesce(p_for_user, v_uid);
  if v_user <> v_uid and not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;
  if v_role not in ('peserta', 'penganjur') then
    raise exception 'FORM:bad_role' using errcode = 'P0001';
  end if;

  select * into v_form from public.event_forms where id = p_form_id for update;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if v_form.status <> 'open' then
    raise exception 'FORM:closed' using errcode = 'P0001';
  end if;
  if v_form.closes_at is not null and v_form.closes_at < now() then
    raise exception 'FORM:closed' using errcode = 'P0001';
  end if;

  if v_form.require_rsvp
     and not exists (select 1 from public.event_participants p
                     where p.event_id = v_form.event_id and p.user_id = v_user) then
    raise exception 'FORM:join_first' using errcode = 'P0001';
  end if;

  select id into v_mine from public.form_responses
  where form_id = p_form_id and user_id = v_user;

  if v_mine is null and v_form.max_responses is not null then
    select count(*) into v_n from public.form_responses where form_id = p_form_id;
    if v_n >= v_form.max_responses then
      raise exception 'FORM:full' using errcode = 'P0001';
    end if;
  end if;

  v_clean := public.form_clean_answers(p_form_id, p_answers);

  if v_mine is null then
    insert into public.form_responses (form_id, user_id, role, entered_by, answers)
    values (p_form_id, v_user, v_role,
            case when v_user = v_uid then null else v_uid end, v_clean);
    return 'ok';
  end if;

  update public.form_responses
  set answers = v_clean,
      role = v_role,
      entered_by = case when v_user = v_uid then entered_by else v_uid end,
      updated_at = now()
  where id = v_mine;
  return 'updated';
end;
$$;

revoke execute on function public.submit_form_response(uuid, uuid, text, jsonb) from public, anon;
grant  execute on function public.submit_form_response(uuid, uuid, text, jsonb) to authenticated;

-- ====================================================== guest answers

create or replace function public.submit_guest_form_response(
  p_form_id uuid,
  p_name    text,
  p_email   text,
  p_answers jsonb
)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_form  public.event_forms;
  v_name  text := nullif(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), '');
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_n     int;
begin
  -- Signed-in people answer with their account, so the organiser sees who.
  if auth.uid() is not null then
    raise exception 'FORM:use_account' using errcode = 'P0001';
  end if;

  select * into v_form from public.event_forms where id = p_form_id for update;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if v_form.is_hidden then
    raise exception 'FORM:removed' using errcode = 'P0001';
  end if;
  -- A private form says nothing more to a guest than "sign in".
  if not v_form.is_public or v_form.require_rsvp then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;
  if v_form.status <> 'open'
     or (v_form.closes_at is not null and v_form.closes_at < now()) then
    raise exception 'FORM:closed' using errcode = 'P0001';
  end if;

  if v_name is null then
    raise exception 'FORM:guest_name' using errcode = 'P0001';
  end if;
  if length(v_name) > 80 then
    raise exception 'FORM:guest_name' using errcode = 'P0001';
  end if;
  if v_email is not null
     and (length(v_email) > 200 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'FORM:guest_email' using errcode = 'P0001';
  end if;

  if v_form.max_responses is not null then
    select count(*) into v_n from public.form_responses where form_id = p_form_id;
    if v_n >= v_form.max_responses then
      raise exception 'FORM:full' using errcode = 'P0001';
    end if;
  end if;

  insert into public.form_responses (form_id, user_id, role, answers, guest_name, guest_email)
  values (p_form_id, null, 'peserta',
          public.form_clean_answers(p_form_id, p_answers), v_name, v_email);
  return 'ok';
end;
$$;

revoke execute on function public.submit_guest_form_response(uuid, text, text, jsonb) from public;
grant  execute on function public.submit_guest_form_response(uuid, text, text, jsonb) to anon;

-- 029001100's limits, plus an hourly cap on guest answers per form: a guest
-- has no account, so the per-person cap cannot apply to them.
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

  if new.user_id is null then
    select count(*) into v_n from public.form_responses
    where form_id = new.form_id and user_id is null
      and submitted_at > now() - interval '1 hour';
    if v_n >= 50 then
      raise exception 'FORM:rate_limited' using errcode = 'P0001';
    end if;
    return new;
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

-- ====================================================== the answer page

-- 029001100's form_public with the switch: a guest on a private form gets the
-- title and who made it, not the questions; on a public form they may answer.
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
  v_shut    boolean;
begin
  select * into v_form from public.event_forms where id = p_form_id;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;

  v_manage := public.can_manage_form(p_form_id);

  select * into v_event from public.events where id = v_form.event_id;

  if v_form.is_hidden then
    v_reason := 'removed';
  elsif v_uid is null and not v_form.is_public then
    v_reason := 'signed_out';
  elsif v_form.status <> 'open' then
    v_reason := 'closed';
  elsif v_form.closes_at is not null and v_form.closes_at < now() then
    v_reason := 'closed';
  elsif v_uid is null and v_form.require_rsvp then
    v_reason := 'signed_out';
  elsif v_form.event_id is not null and v_form.require_rsvp
        and not exists (select 1 from public.event_participants p
                        where p.event_id = v_form.event_id and p.user_id = v_uid) then
    v_reason := 'not_joined';
  else
    select count(*) into v_n from public.form_responses where form_id = p_form_id;
    if ((v_form.max_responses is not null and v_n >= v_form.max_responses)
        or (v_form.event_id is null and v_n >= 2000))
       and (v_uid is null
            or not exists (select 1 from public.form_responses
                           where form_id = p_form_id and user_id = v_uid)) then
      v_reason := 'full';
    else
      v_can := true;
    end if;
  end if;

  -- What a viewer may not see: a removed form's content (unless they run it),
  -- and a private form's content when they are not signed in.
  v_shut := (v_form.is_hidden and not v_manage)
            or (v_uid is null and not v_form.is_public);

  if v_uid is not null then
    select to_jsonb(r) - 'entered_by' - 'guest_name' - 'guest_email' into v_mine
    from public.form_responses r
    where r.form_id = p_form_id and r.user_id = v_uid;
  end if;

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
      'intro', case when v_shut then null else v_form.intro end,
      'status', v_form.status,
      'closes_at', v_form.closes_at,
      'require_rsvp', v_form.require_rsvp,
      'after_checkin', v_form.after_checkin,
      'max_responses', v_form.max_responses,
      'standalone', v_form.event_id is null,
      'is_hidden', v_form.is_hidden,
      'is_public', v_form.is_public,
      'owner', v_owner,
      'club', v_club,
      'event', case when v_event.id is null then null else
        jsonb_build_object('id', v_event.id, 'title', v_event.title,
                           'start_datetime', v_event.start_datetime,
                           'end_datetime', v_event.end_datetime) end),
    'fields', case when v_shut then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'kind', f.kind, 'label', f.label, 'help', f.help,
        'required', f.required, 'options', f.options, 'sort', f.sort)
        order by f.sort, f.created_at)
      from public.form_fields f where f.form_id = p_form_id), '[]'::jsonb) end,
    'mine', v_mine,
    'guest', v_uid is null,
    'can_answer', v_can,
    'can_edit', v_manage,
    'can_read', public.can_read_form(p_form_id),
    'reason', v_reason);
end;
$$;

revoke execute on function public.form_public(uuid) from public;
grant  execute on function public.form_public(uuid) to anon, authenticated;

-- ====================================================== reading answers

-- 029001100's list plus who a guest said they were. The return shape changes,
-- so the old function is dropped first.
drop function if exists public.form_response_list(uuid);
create function public.form_response_list(p_form_id uuid)
returns table (
  response_id  uuid,
  user_id      uuid,
  username     text,
  display_name text,
  student_id   text,
  role         text,
  submitted_at timestamptz,
  answers      jsonb,
  is_guest     boolean,
  guest_email  text
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
  select r.id,
         r.user_id,
         p.username,
         coalesce(p.display_name, p.full_name, r.guest_name),
         coalesce(
           (select nullif(r.answers ->> f.id::text, '')
            from public.form_fields f
            where f.form_id = p_form_id and f.kind = 'student_id'
            order by f.sort limit 1),
           case when v_event and r.user_id is not null then
             (select split_part(v.email::text, '@', 1)
              from public.student_verifications v where v.user_id = r.user_id) end),
         r.role,
         r.submitted_at,
         r.answers,
         r.user_id is null,
         r.guest_email
  from public.form_responses r
  left join public.profiles p on p.id = r.user_id
  where r.form_id = p_form_id
  order by coalesce(p.display_name, p.full_name, r.guest_name), r.submitted_at;
end;
$$;

revoke execute on function public.form_response_list(uuid) from public, anon;
grant  execute on function public.form_response_list(uuid) to authenticated;
