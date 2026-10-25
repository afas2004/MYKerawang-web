-- Event forms: the KI response survey and its three analyses.
--
-- What this serves: after every student activity a club must hand in the
-- L2-HEP/PKP/21 report, which asks for three "analisa Excel" attachments —
-- S1 (peserta), S2 (penganjur) and S3 (program feedback). Those are means of
-- 1-5 ratings collected by a questionnaire. This migration stores the
-- questionnaire, its answers, and computes S1/S2/S3 in one place so the
-- screen and the CSV cannot disagree.
--
-- Shape:
--   form_templates / form_template_fields   shipped starting points, copied
--                                           into a form, never referenced
--   event_forms / form_fields               one form per event, editable
--   form_responses                           one row per (form, person)
--
-- Fields carry `analysis` (ki_pre / ki_post / feedback) and `ki_code` (1-7)
-- because the source questionnaire numbers its KI questions out of order and
-- has two numbered "6)". The averages key off the tags, not the wording.
--
-- Every table here is RPC-only: no direct grants to anon/authenticated. The
-- answers are PII (names, matric numbers) so they never appear in a view.
--
-- Re-runnable: the test harness applies every migration twice.

-- ====================================================== tables

create table if not exists public.form_templates (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  name_ms    text,
  intro      text,
  source     text not null default 'official'
             check (source in ('official', 'club')),
  active     boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.form_template_fields (
  id          uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.form_templates(id) on delete cascade,
  kind        text not null,
  label       text not null,
  help        text,
  required    boolean not null default false,
  options     jsonb,
  analysis    text,
  ki_code     int,
  sort        int not null default 0
);
create index if not exists form_template_fields_tpl_idx
  on public.form_template_fields (template_id, sort);

create table if not exists public.event_forms (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events(id) on delete cascade,
  template_id   uuid references public.form_templates(id) on delete set null,
  title         text not null,
  intro         text,
  status        text not null default 'draft'
                check (status in ('draft', 'open', 'closed')),
  closes_at     timestamptz,
  max_responses int check (max_responses is null or max_responses > 0),
  require_rsvp  boolean not null default false,
  after_checkin boolean not null default false,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists event_forms_event_idx
  on public.event_forms (event_id, created_at desc);

-- The check-in hand-off and the event page both need one unambiguous target.
create unique index if not exists event_forms_one_open
  on public.event_forms (event_id) where status = 'open';

create table if not exists public.form_fields (
  id         uuid primary key default gen_random_uuid(),
  form_id    uuid not null references public.event_forms(id) on delete cascade,
  kind       text not null,
  label      text not null,
  help       text,
  required   boolean not null default false,
  options    jsonb,
  analysis   text,
  ki_code    int,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists form_fields_form_idx on public.form_fields (form_id, sort);

create table if not exists public.form_responses (
  id           uuid primary key default gen_random_uuid(),
  form_id      uuid not null references public.event_forms(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  role         text not null default 'peserta'
               check (role in ('peserta', 'penganjur')),
  entered_by   uuid references public.profiles(id) on delete set null,
  answers      jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now(),
  updated_at   timestamptz,
  unique (form_id, user_id)
);

alter table public.form_templates       enable row level security;
alter table public.form_template_fields enable row level security;
alter table public.event_forms          enable row level security;
alter table public.form_fields          enable row level security;
alter table public.form_responses       enable row level security;

-- Templates are question text, not answers: readable so the chooser can render
-- without an RPC, writable by nobody (they change by migration).
revoke all on public.form_templates, public.form_template_fields from anon, authenticated;
grant select on public.form_templates, public.form_template_fields to authenticated;

-- Everything else is RPC-only.
revoke all on public.event_forms, public.form_fields, public.form_responses
  from anon, authenticated;

-- ====================================================== the shipped template

insert into public.form_templates (slug, name, name_ms, intro, source, sort)
values (
  'ki',
  'KI response report',
  'Borang laporan KI',
  'Penilaian kendiri Kemahiran Insaniah sebelum dan selepas program, '
  'serta maklum balas perlaksanaan. Isi selepas program tamat.',
  'official',
  10
)
on conflict (slug) do nothing;

-- 28 rows, generated from the owner's Google-Form export (docs/ki-template-fields.csv).
-- Seeded only when the template has no fields, so a re-run cannot duplicate them
-- and an admin's later correction is not overwritten.
insert into public.form_template_fields
  (template_id, kind, label, help, required, options, analysis, ki_code, sort)
select t.id, v.kind, v.label, v.help, coalesce(v.required, false),
       v.options::jsonb, v.analysis, v.ki_code, v.sort
from public.form_templates t
cross join (values
  ('heading', 'Maklumat peserta', null, null, null, null, null, 10),
  ('short_text', 'Nama penuh', 'Prefilled from your profile.', true, null, null, null, 20),
  ('student_id', 'Nombor matrik', 'Your UiTM student number.', true, null, null, null, 30),
  ('single_choice', 'Saya menyertai program ini sebagai', null, true, '{"choices":["Peserta","Penganjur"]}', null, null, 40),
  ('heading', 'Penilaian Kemahiran Insaniah — sebelum program', 'Rate yourself before the programme. 1 = very low, 5 = very high.', null, null, null, null, 50),
  ('rating', 'KI1 Kemahiran Berkomunikasi', null, true, '{"min":1,"max":5}', 'ki_pre', 1, 60),
  ('rating', 'KI2 Pemikiran Kritis dan Kemahiran Menyelesaikan Masalah', null, true, '{"min":1,"max":5}', 'ki_pre', 2, 70),
  ('rating', 'KI3 Kemahiran Kerja Berpasukan', null, true, '{"min":1,"max":5}', 'ki_pre', 3, 80),
  ('rating', 'KI4 Pembelajaran Berterusan dan Pengurusan Maklumat', null, true, '{"min":1,"max":5}', 'ki_pre', 4, 90),
  ('rating', 'KI5 Kemahiran Keusahawanan', null, true, '{"min":1,"max":5}', 'ki_pre', 5, 100),
  ('rating', 'KI6 Etika dan Moral Profesional', null, true, '{"min":1,"max":5}', 'ki_pre', 6, 110),
  ('rating', 'KI7 Kemahiran Kepimpinan', null, true, '{"min":1,"max":5}', 'ki_pre', 7, 120),
  ('heading', 'Penilaian Kemahiran Insaniah — selepas program', 'Rate yourself after the programme, on the same scale.', null, null, null, null, 130),
  ('rating', 'KI1 Kemahiran Berkomunikasi', null, true, '{"min":1,"max":5}', 'ki_post', 1, 140),
  ('rating', 'KI2 Pemikiran Kritis dan Kemahiran Menyelesaikan Masalah', null, true, '{"min":1,"max":5}', 'ki_post', 2, 150),
  ('rating', 'KI3 Kemahiran Kerja Berpasukan', null, true, '{"min":1,"max":5}', 'ki_post', 3, 160),
  ('rating', 'KI4 Pembelajaran Berterusan dan Pengurusan Maklumat', null, true, '{"min":1,"max":5}', 'ki_post', 4, 170),
  ('rating', 'KI5 Kemahiran Keusahawanan', null, true, '{"min":1,"max":5}', 'ki_post', 5, 180),
  ('rating', 'KI6 Etika dan Moral Profesional', null, true, '{"min":1,"max":5}', 'ki_post', 6, 190),
  ('rating', 'KI7 Kemahiran Kepimpinan', null, true, '{"min":1,"max":5}', 'ki_post', 7, 200),
  ('heading', 'Maklum balas program', '1 = very poor, 5 = very good.', null, null, null, null, 210),
  ('rating', 'Pengisian program', null, true, '{"min":1,"max":5}', 'feedback', null, 220),
  ('rating', 'Persembahan multimedia', null, true, '{"min":1,"max":5}', 'feedback', null, 230),
  ('rating', 'Lokasi program', null, true, '{"min":1,"max":5}', 'feedback', null, 240),
  ('rating', 'Aturcara dan pengendalian program', null, true, '{"min":1,"max":5}', 'feedback', null, 250),
  ('rating', 'Mutu makanan dan minuman', null, true, '{"min":1,"max":5}', 'feedback', null, 260),
  ('rating', 'Keseluruhan mutu aktiviti', null, true, '{"min":1,"max":5}', 'feedback', null, 270),
  ('long_text', 'Cadangan / maklum balas', null, false, null, null, null, 280)
) as v(kind, label, help, required, options, analysis, ki_code, sort)
where t.slug = 'ki'
  and not exists (select 1 from public.form_template_fields f
                  where f.template_id = t.id);

-- ====================================================== small helpers

-- A rating answer, or null when the value is not a plain number.
create or replace function public.form_num(p_value text)
returns numeric
language sql immutable
as $$
  select case when p_value ~ '^[0-9]+(\.[0-9]+)?$' then p_value::numeric end;
$$;

-- The kinds a field may be. One list, checked on every save and submit.
create or replace function public.form_kind_ok(p_kind text)
returns boolean
language sql immutable
as $$
  select p_kind in ('short_text','long_text','rating','single_choice',
                    'multi_choice','number','date','email','phone',
                    'student_id','consent','heading');
$$;

-- One answer as text. Values arrive as number, string or boolean; an array
-- (multi choice) has no scalar form and reads as null, which is why the submit
-- path handles that kind before this is reached.
create or replace function public.form_answer_text(p_answers jsonb, p_field uuid)
returns text
language sql immutable
as $$
  select case jsonb_typeof(p_answers -> p_field::text)
           when 'string'  then p_answers ->> p_field::text
           when 'number'  then p_answers ->> p_field::text
           when 'boolean' then p_answers ->> p_field::text
           else null
         end;
$$;

-- Validates one field definition; raises with a code the client can explain.
create or replace function public.form_check_field(
  p_kind     text,
  p_label    text,
  p_required boolean,
  p_options  jsonb,
  p_analysis text,
  p_ki_code  int
)
returns void
language plpgsql immutable
as $$
declare
  v_min int;
  v_max int;
begin
  -- A JSON null is not a SQL null and would slip past the checks below.
  if p_options = 'null'::jsonb then
    p_options := null;
  end if;

  if not public.form_kind_ok(p_kind) then
    raise exception 'FORM:bad_kind' using errcode = 'P0001';
  end if;
  if p_label is null or length(trim(p_label)) = 0 or length(p_label) > 200 then
    raise exception 'FORM:bad_label' using errcode = 'P0001';
  end if;
  if p_kind = 'heading' and coalesce(p_required, false) then
    raise exception 'FORM:heading_required' using errcode = 'P0001';
  end if;

  if p_kind in ('single_choice', 'multi_choice') then
    if p_options is null or jsonb_typeof(p_options->'choices') <> 'array'
       or jsonb_array_length(p_options->'choices') < 2
       or jsonb_array_length(p_options->'choices') > 40 then
      raise exception 'FORM:bad_choices' using errcode = 'P0001';
    end if;
  end if;

  if p_kind = 'rating' then
    v_min := (p_options->>'min')::int;
    v_max := (p_options->>'max')::int;
    if v_min is null or v_max is null or v_min < 1 or v_max > 10 or v_min >= v_max then
      raise exception 'FORM:bad_scale' using errcode = 'P0001';
    end if;
  end if;

  -- An analysis tag is what the averages are made of, so it must be exact:
  -- a KI field is a rating and carries a code, feedback is a rating without one.
  if p_analysis is not null and p_analysis not in ('ki_pre','ki_post','feedback') then
    raise exception 'FORM:bad_analysis' using errcode = 'P0001';
  end if;
  if p_analysis is not null and p_kind <> 'rating' then
    raise exception 'FORM:analysis_needs_rating' using errcode = 'P0001';
  end if;
  if (p_analysis in ('ki_pre','ki_post')) <> (p_ki_code is not null) then
    raise exception 'FORM:bad_ki_code' using errcode = 'P0001';
  end if;
  if p_ki_code is not null and (p_ki_code < 1 or p_ki_code > 7) then
    raise exception 'FORM:bad_ki_code' using errcode = 'P0001';
  end if;
end;
$$;

-- Writing a form: the organiser, an officer of its active club, or staff.
create or replace function public.can_manage_form(p_form_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.event_forms f
    join public.events e on e.id = f.event_id
    where f.id = p_form_id
      and (e.organizer_id = auth.uid()
           or public.is_admin()
           or (e.club_id is not null and public.can_act_as_club(e.club_id))));
$$;

-- Reading the answers: also officers of a club mid-approval.
create or replace function public.can_read_form(p_form_id uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.event_forms f
    join public.events e on e.id = f.event_id
    where f.id = p_form_id
      and (e.organizer_id = auth.uid()
           or public.is_admin()
           or (e.club_id is not null and public.is_club_officer(e.club_id))));
$$;

revoke execute on function public.can_manage_form(uuid) from public, anon;
revoke execute on function public.can_read_form(uuid)   from public, anon;
grant  execute on function public.can_manage_form(uuid) to authenticated;
grant  execute on function public.can_read_form(uuid)   to authenticated;

-- ====================================================== reading and creating

create or replace function public.form_templates_list()
returns table (slug text, name text, name_ms text, intro text, field_count bigint)
language sql security definer stable
set search_path = public
as $$
  select t.slug, t.name, t.name_ms, t.intro,
         (select count(*) from public.form_template_fields f where f.template_id = t.id)
  from public.form_templates t
  where t.active
  order by t.sort, t.name;
$$;

revoke execute on function public.form_templates_list() from public, anon;
grant  execute on function public.form_templates_list() to authenticated;

-- Creating from a template copies the fields: a later edit of the template
-- must not rewrite a form that already has answers.
create or replace function public.create_form_from_template(
  p_event_id      uuid,
  p_template_slug text default 'ki'
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_tpl   public.form_templates;
  v_event public.events;
  v_form  uuid;
begin
  if v_uid is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;

  select * into v_event from public.events where id = p_event_id;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if not (v_event.organizer_id = v_uid
          or public.is_admin()
          or (v_event.club_id is not null and public.can_act_as_club(v_event.club_id))) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  select * into v_tpl from public.form_templates
  where slug = p_template_slug and active;
  if not found then
    raise exception 'FORM:no_template' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.event_forms
             where event_id = p_event_id and status = 'open') then
    raise exception 'FORM:already_open' using errcode = 'P0001';
  end if;

  insert into public.event_forms (event_id, template_id, title, intro, created_by)
  values (p_event_id, v_tpl.id,
          'Laporan KI — ' || coalesce(v_event.title, 'Program'),
          v_tpl.intro, v_uid)
  returning id into v_form;

  insert into public.form_fields
    (form_id, kind, label, help, required, options, analysis, ki_code, sort)
  select v_form, f.kind, f.label, f.help, f.required, f.options,
         f.analysis, f.ki_code, f.sort
  from public.form_template_fields f
  where f.template_id = v_tpl.id
  order by f.sort;

  return v_form;
end;
$$;

revoke execute on function public.create_form_from_template(uuid, text) from public, anon;
grant  execute on function public.create_form_from_template(uuid, text) to authenticated;

-- Blank start: the editor's "from nothing" and "from a pasted list" paths both
-- begin with an empty form, because every later write targets a form id.
create or replace function public.create_blank_form(
  p_event_id uuid,
  p_title    text default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_event public.events;
  v_form  uuid;
begin
  if v_uid is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;

  select * into v_event from public.events where id = p_event_id;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if not (v_event.organizer_id = v_uid
          or public.is_admin()
          or (v_event.club_id is not null and public.can_act_as_club(v_event.club_id))) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  if exists (select 1 from public.event_forms
             where event_id = p_event_id and status = 'open') then
    raise exception 'FORM:already_open' using errcode = 'P0001';
  end if;

  insert into public.event_forms (event_id, title, created_by)
  values (p_event_id, coalesce(nullif(trim(p_title), ''), 'Borang program'), v_uid)
  returning id into v_form;

  return v_form;
end;
$$;

revoke execute on function public.create_blank_form(uuid, text) from public, anon;
grant  execute on function public.create_blank_form(uuid, text) to authenticated;

-- What the event page needs to label its button: the newest form for the event
-- (draft or open), or null. Managers only — a student never sees this.
create or replace function public.event_form_summary(p_event_id uuid)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
declare
  v_form public.event_forms;
  v_n    int;
begin
  if auth.uid() is null then
    return null;
  end if;
  if not exists (select 1 from public.events e
                 where e.id = p_event_id
                   and (e.organizer_id = auth.uid()
                        or public.is_admin()
                        or (e.club_id is not null and public.can_act_as_club(e.club_id)))) then
    return null;
  end if;

  select * into v_form from public.event_forms
  where event_id = p_event_id and status in ('draft', 'open')
  order by created_at desc limit 1;
  if not found then
    return null;
  end if;

  select count(*) into v_n from public.form_responses where form_id = v_form.id;

  return jsonb_build_object(
    'id', v_form.id, 'status', v_form.status, 'title', v_form.title,
    'responses', v_n, 'closes_at', v_form.closes_at);
end;
$$;

revoke execute on function public.event_form_summary(uuid) from public, anon;
grant  execute on function public.event_form_summary(uuid) to authenticated;

-- The form a student should answer, if there is one. Deliberately open to
-- guests (it leaks nothing but the existence of a published form), because the
-- event page is readable by guests and the button has to know.
create or replace function public.event_open_form(p_event_id uuid)
returns uuid
language sql security definer stable
set search_path = public
as $$
  select f.id
  from public.event_forms f
  where f.event_id = p_event_id
    and f.status = 'open'
    and (f.closes_at is null or f.closes_at > now())
  order by f.created_at desc
  limit 1;
$$;

revoke execute on function public.event_open_form(uuid) from public;
grant  execute on function public.event_open_form(uuid) to anon, authenticated;

-- ====================================================== the editor's write

-- The whole field list in one call, so the client never has to keep three
-- writes in step. Kept idempotent in shape: fields with an id are updated,
-- fields without one are inserted, and anything missing from the list is
-- removed (refused if it has answers).
create or replace function public.save_event_form(
  p_form_id uuid,
  p_form    jsonb,
  p_fields  jsonb
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_form    public.event_forms;
  v_row     jsonb;
  v_id      uuid;
  v_keep    uuid[] := '{}';
  v_sort    int := 0;
  v_pre     int := 0;
  v_post    int := 0;
  v_kind    text;
  v_label   text;
  v_options jsonb;
  v_analysis text;
  v_ki      int;
  v_drop    uuid;
begin
  select * into v_form from public.event_forms where id = p_form_id for update;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;
  if v_form.status = 'closed' then
    raise exception 'FORM:closed' using errcode = 'P0001';
  end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'array' then
    raise exception 'FORM:bad_fields' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_fields) > 40 then
    raise exception 'FORM:too_many_fields' using errcode = 'P0001';
  end if;

  update public.event_forms set
    title         = coalesce(nullif(trim(p_form->>'title'), ''), title),
    intro         = coalesce(p_form->>'intro', intro),
    closes_at     = case when p_form ? 'closes_at'
                         then nullif(p_form->>'closes_at', '')::timestamptz
                         else closes_at end,
    max_responses = case when p_form ? 'max_responses'
                         then nullif(p_form->>'max_responses', '')::int
                         else max_responses end,
    require_rsvp  = coalesce((p_form->>'require_rsvp')::boolean, require_rsvp),
    after_checkin = coalesce((p_form->>'after_checkin')::boolean, after_checkin),
    updated_at    = now()
  where id = p_form_id;

  for v_row in select value from jsonb_array_elements(p_fields) loop
    v_sort     := v_sort + 10;
    v_kind     := v_row->>'kind';
    v_label    := trim(coalesce(v_row->>'label', ''));
    v_options  := nullif(v_row->'options', 'null'::jsonb);
    v_analysis := nullif(v_row->>'analysis', '');
    v_ki       := nullif(v_row->>'ki_code', '')::int;
    v_id       := nullif(v_row->>'id', '')::uuid;

    perform public.form_check_field(v_kind, v_label,
                                    coalesce((v_row->>'required')::boolean, false),
                                    v_options, v_analysis, v_ki);

    if v_analysis = 'ki_pre'  then v_pre  := v_pre  + 1; end if;
    if v_analysis = 'ki_post' then v_post := v_post + 1; end if;

    if v_id is not null
       and exists (select 1 from public.form_fields
                   where id = v_id and form_id = p_form_id) then
      -- Redefining a question that already has answers is refused: it would
      -- change what a past answer meant.
      if exists (select 1 from public.form_responses r
                 where r.form_id = p_form_id
                   and nullif(r.answers->>v_id::text, '') is not null)
         and (select kind from public.form_fields where id = v_id) <> v_kind then
        raise exception 'FORM:kind_has_answers' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.form_responses r
                 where r.form_id = p_form_id
                   and nullif(r.answers->>v_id::text, '') is not null)
         and coalesce((select options from public.form_fields where id = v_id),
                      '{}'::jsonb) -> 'choices'
             is distinct from v_options -> 'choices' then
        raise exception 'FORM:choices_have_answers' using errcode = 'P0001';
      end if;

      update public.form_fields set
        kind = v_kind, label = v_label,
        help = nullif(v_row->>'help', ''),
        required = coalesce((v_row->>'required')::boolean, false),
        options = v_options, analysis = v_analysis, ki_code = v_ki,
        sort = v_sort
      where id = v_id;
    else
      insert into public.form_fields
        (form_id, kind, label, help, required, options, analysis, ki_code, sort)
      values (p_form_id, v_kind, v_label, nullif(v_row->>'help', ''),
              coalesce((v_row->>'required')::boolean, false),
              v_options, v_analysis, v_ki, v_sort)
      returning id into v_id;
    end if;

    v_keep := v_keep || v_id;
  end loop;

  if v_pre > 7 or v_post > 7 then
    raise exception 'FORM:too_many_ki' using errcode = 'P0001';
  end if;

  -- Dropped rows.
  for v_drop in select id from public.form_fields
                where form_id = p_form_id
                  and not (id = any(v_keep)) loop
    if exists (select 1 from public.form_responses r
               where r.form_id = p_form_id
                 and nullif(r.answers->>v_drop::text, '') is not null) then
      raise exception 'FORM:field_has_answers' using errcode = 'P0001';
    end if;
    delete from public.form_fields where id = v_drop;
  end loop;
end;
$$;

revoke execute on function public.save_event_form(uuid, jsonb, jsonb) from public, anon;
grant  execute on function public.save_event_form(uuid, jsonb, jsonb) to authenticated;

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

  -- Publishing is the last gate before students see it, so every field is
  -- re-checked here: a template copy could otherwise carry a bad tag in.
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

create or replace function public.close_form(p_form_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;
  update public.event_forms set status = 'closed', updated_at = now()
  where id = p_form_id and status <> 'closed';
end;
$$;

revoke execute on function public.publish_form(uuid) from public, anon;
revoke execute on function public.close_form(uuid)   from public, anon;
grant  execute on function public.publish_form(uuid) to authenticated;
grant  execute on function public.close_form(uuid)   to authenticated;

-- ====================================================== the answer page

-- Public read model: the questions are visible to anyone (a shared link has to
-- show what it asks), the answers never are. Guests get can_answer = false.
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
begin
  select * into v_form from public.event_forms where id = p_form_id;
  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;

  select * into v_event from public.events where id = v_form.event_id;

  if v_uid is null then
    v_reason := 'signed_out';
  elsif v_form.status <> 'open' then
    v_reason := 'closed';
  elsif v_form.closes_at is not null and v_form.closes_at < now() then
    v_reason := 'closed';
  elsif v_form.require_rsvp
        and not exists (select 1 from public.event_participants p
                        where p.event_id = v_form.event_id and p.user_id = v_uid) then
    v_reason := 'not_joined';
  else
    select count(*) into v_n from public.form_responses where form_id = p_form_id;
    if v_form.max_responses is not null and v_n >= v_form.max_responses
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

  return jsonb_build_object(
    'form', jsonb_build_object(
      'id', v_form.id,
      'title', v_form.title,
      'intro', v_form.intro,
      'status', v_form.status,
      'closes_at', v_form.closes_at,
      'require_rsvp', v_form.require_rsvp,
      'after_checkin', v_form.after_checkin,
      'max_responses', v_form.max_responses,
      'event', case when v_event.id is null then null else
        jsonb_build_object('id', v_event.id, 'title', v_event.title,
                           'start_datetime', v_event.start_datetime,
                           'end_datetime', v_event.end_datetime) end),
    'fields', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'kind', f.kind, 'label', f.label, 'help', f.help,
        'required', f.required, 'options', f.options, 'sort', f.sort)
        order by f.sort, f.created_at)
      from public.form_fields f where f.form_id = p_form_id), '[]'::jsonb),
    'mine', v_mine,
    'can_answer', v_can,
    'can_edit', public.can_manage_form(p_form_id),
    'reason', v_reason);
end;
$$;

revoke execute on function public.form_public(uuid) from public;
grant  execute on function public.form_public(uuid) to anon, authenticated;

-- ====================================================== answering

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
  v_field  public.form_fields;
  v_raw    text;
  v_num    numeric;
  v_clean  jsonb := '{}'::jsonb;
  v_n      int;
  v_mine   uuid;
  v_choice text;
  v_multis jsonb;
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

revoke execute on function public.form_answer_text(jsonb, uuid) from public, anon;
grant  execute on function public.form_answer_text(jsonb, uuid) to authenticated;

revoke execute on function public.submit_form_response(uuid, uuid, text, jsonb) from public, anon;
grant  execute on function public.submit_form_response(uuid, uuid, text, jsonb) to authenticated;

-- ====================================================== reading answers

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
begin
  if not public.can_read_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  return query
  select r.user_id,
         p.username,
         coalesce(p.display_name, p.full_name),
         coalesce(
           (select nullif(r.answers ->> f.id::text, '')
            from public.form_fields f
            where f.form_id = p_form_id and f.kind = 'student_id'
            order by f.sort limit 1),
           (select split_part(v.email::text, '@', 1)
            from public.student_verifications v where v.user_id = r.user_id)),
         r.role,
         r.submitted_at,
         r.answers
  from public.form_responses r
  left join public.profiles p on p.id = r.user_id
  where r.form_id = p_form_id
  order by coalesce(p.display_name, p.full_name), r.submitted_at;
end;
$$;

revoke execute on function public.form_response_list(uuid) from public, anon;
grant  execute on function public.form_response_list(uuid) to authenticated;

-- ====================================================== S1 / S2 / S3

-- The three analyses the HEP report asks for, as one jsonb document so the
-- screen, the CSV and anything added later read the same numbers.
--
--   s1  peserta,  per KI code: n and mean before, n and mean after
--   s2  penganjur, per KI code: n and mean after
--   s3  peserta,  per feedback item: n and mean
create or replace function public.form_analysis(p_form_id uuid)
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
declare
  v_peserta   int;
  v_penganjur int;
begin
  if not public.can_read_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  select count(*) filter (where r.role = 'peserta'),
         count(*) filter (where r.role = 'penganjur')
  into v_peserta, v_penganjur
  from public.form_responses r where r.form_id = p_form_id;

  return jsonb_build_object(
    'responses', jsonb_build_object('peserta', v_peserta, 'penganjur', v_penganjur),

    's1', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ki_code', k.ki_code,
        'label', k.label,
        'n_before', k.n_before,
        'mean_before', k.mean_before,
        'n_after', k.n_after,
        'mean_after', k.mean_after,
        'delta', case when k.mean_after is not null and k.mean_before is not null
                      then round(k.mean_after - k.mean_before, 2) end)
        order by k.ki_code)
      from (
        select f.ki_code,
               min(f.label) as label,
               count(x.v) filter (where f.analysis = 'ki_pre')  as n_before,
               round(avg(x.v) filter (where f.analysis = 'ki_pre'), 2)  as mean_before,
               count(x.v) filter (where f.analysis = 'ki_post') as n_after,
               round(avg(x.v) filter (where f.analysis = 'ki_post'), 2) as mean_after
        from public.form_fields f
        left join lateral (
          select public.form_num(r.answers ->> f.id::text) as v
          from public.form_responses r
          where r.form_id = f.form_id and r.role = 'peserta'
        ) x on true
        where f.form_id = p_form_id and f.analysis in ('ki_pre', 'ki_post')
        group by f.ki_code
      ) k), '[]'::jsonb),

    's2', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ki_code', k.ki_code,
        'label', k.label,
        'n_after', k.n_after,
        'mean_after', k.mean_after)
        order by k.ki_code)
      from (
        select f.ki_code,
               min(f.label) as label,
               count(x.v) filter (where f.analysis = 'ki_post') as n_after,
               round(avg(x.v) filter (where f.analysis = 'ki_post'), 2) as mean_after
        from public.form_fields f
        left join lateral (
          select public.form_num(r.answers ->> f.id::text) as v
          from public.form_responses r
          where r.form_id = f.form_id and r.role = 'penganjur'
        ) x on true
        where f.form_id = p_form_id and f.analysis in ('ki_pre', 'ki_post')
        group by f.ki_code
      ) k), '[]'::jsonb),

    's3', coalesce((
      select jsonb_agg(jsonb_build_object(
        'field_id', k.id,
        'label', k.label,
        'n', k.n,
        'mean', k.mean)
        order by k.sort)
      from (
        select f.id, f.label, f.sort,
               count(x.v) as n,
               round(avg(x.v), 2) as mean
        from public.form_fields f
        left join lateral (
          select public.form_num(r.answers ->> f.id::text) as v
          from public.form_responses r
          where r.form_id = f.form_id and r.role = 'peserta'
        ) x on true
        where f.form_id = p_form_id and f.analysis = 'feedback'
        group by f.id, f.label, f.sort
      ) k), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.form_analysis(uuid) from public, anon;
grant  execute on function public.form_analysis(uuid) to authenticated;

-- ====================================================== moderation hooks

-- Form answers are a write like any other: bans, restrictions and the student
-- verification switch must cover them.
create or replace function public.verification_required(p_capability text)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce((
    select s.verification_enabled
    from public.access_settings s where s.id), false)
  and p_capability in ('event_join','event_create','sell',
                       'club_join','club_officer','club_create','form_submit');
$$;

revoke execute on function public.verification_required(text) from public, anon;
grant  execute on function public.verification_required(text) to authenticated;

drop trigger if exists trg_mod_guard on public.form_responses;
create trigger trg_mod_guard
before insert on public.form_responses
for each row execute function public.mod_guard_write('events', 'user_id', '', 'form_submit');
