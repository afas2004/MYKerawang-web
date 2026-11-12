-- Short links and link previews for forms.
--
--   kerawang.my/f/57548532-c09a-…   still works, always
--   kerawang.my/f/sus-survey        optional short name the maker picks in the
--                                   form's settings (standalone forms only)
--
-- A short name is 3-40 characters of a-z, 0-9 and single dashes, unique across
-- all forms. Names that would make a form look official or ask for a login are
-- refused (uitm, official, rasmi, login, password, bank, …): a nicer link must
-- not make a phishing form more convincing.
--
-- form_preview() is what the link-preview function (functions/) reads to
-- build the WhatsApp/Telegram card: the form's own title, and its description
-- only when guests could read it anyway (a public form). Hidden forms get no
-- card at all.
--
-- Re-runnable: the test harness applies every migration twice.

-- ====================================================== column

alter table public.event_forms add column if not exists slug text;

alter table public.event_forms drop constraint if exists event_forms_slug_shape;
alter table public.event_forms add constraint event_forms_slug_shape
  check (slug is null or (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' and slug !~ '--'));

create unique index if not exists event_forms_slug_key
  on public.event_forms (slug) where slug is not null;

-- ====================================================== rules

-- Why a short name is refused, or null when it is fine. Kept in step with
-- lib/utils/form_rules.dart formSlugProblem().
create or replace function public.form_slug_problem(p_slug text)
returns text
language sql immutable
set search_path = public
as $$
  select case
    when p_slug is null
      or p_slug !~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'
      or p_slug ~ '--' then 'slug_bad'
    when p_slug in ('new', 'create', 'edit', 'responses', 'gallery', 'templates', 'forms')
      then 'slug_blocked'
    when p_slug ~ '(uitm|official|rasmi|login|signin|logmasuk|password|katalaluan|bank|mykerawang|admin|verify|sahkan|support)'
      then 'slug_blocked'
    when exists (select 1 from unnest(string_to_array(p_slug, '-')) w
                 where w in ('otp', 'pin', 'tac', 'hep', 'cvv'))
      then 'slug_blocked'
    else null
  end;
$$;

grant execute on function public.form_slug_problem(text) to anon, authenticated;

-- ====================================================== setting it

-- Returns the stored short name (null when cleared).
create or replace function public.set_form_slug(p_form_id uuid, p_slug text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_form    public.event_forms;
  v_slug    text := nullif(lower(trim(coalesce(p_slug, ''))), '');
  v_problem text;
begin
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  select * into v_form from public.event_forms where id = p_form_id for update;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if v_form.event_id is not null then
    raise exception 'FORM:event_form' using errcode = 'P0001';
  end if;
  if v_form.is_hidden then
    raise exception 'FORM:removed' using errcode = 'P0001';
  end if;

  if v_slug is not null then
    v_problem := public.form_slug_problem(v_slug);
    if v_problem is not null then
      raise exception 'FORM:%', v_problem using errcode = 'P0001';
    end if;
    if exists (select 1 from public.event_forms
               where slug = v_slug and id <> p_form_id) then
      raise exception 'FORM:slug_taken' using errcode = 'P0001';
    end if;
  end if;

  begin
    update public.event_forms
    set slug = v_slug, updated_at = now()
    where id = p_form_id;
  exception when unique_violation then
    raise exception 'FORM:slug_taken' using errcode = 'P0001';
  end;
  return v_slug;
end;
$$;

revoke execute on function public.set_form_slug(uuid, text) from public, anon;
grant  execute on function public.set_form_slug(uuid, text) to authenticated;

-- ====================================================== looking it up

-- `/f/<key>`: the form id for a uuid or a short name, or null.
create or replace function public.form_id_for_key(p_key text)
returns uuid
language plpgsql security definer stable
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_key ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select id into v_id from public.event_forms where id = p_key::uuid;
  else
    select id into v_id from public.event_forms where slug = lower(trim(p_key));
  end if;
  return v_id;
end;
$$;

revoke execute on function public.form_id_for_key(text) from public;
grant  execute on function public.form_id_for_key(text) to anon, authenticated;

-- The link card. Null for a missing or removed form.
create or replace function public.form_preview(p_key text)
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select jsonb_build_object(
           'id', f.id,
           'slug', f.slug,
           'title', f.title,
           'description', case when f.is_public then nullif(trim(f.intro), '') end)
  from public.event_forms f
  where f.id = public.form_id_for_key(p_key)
    and not f.is_hidden;
$$;

revoke execute on function public.form_preview(text) from public;
grant  execute on function public.form_preview(text) to anon, authenticated;

-- ====================================================== the answer page

-- 20261112000100's form_public, now also returning the short name.
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
      'slug', v_form.slug,
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
