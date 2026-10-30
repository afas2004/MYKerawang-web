-- 20261026015100_security_review_fixes.sql
--
-- Fixes from the October 2026 pre-club-year security review that do NOT change
-- who may do what, plus one that does: the `images` bucket write policies.
--
-- Everything here is re-runnable (the test harness applies every migration
-- twice) and every statement is a no-op when the object is already correct.
--
-- Not in this file, on purpose (needs the owner's sign-off first, see
-- docs/security-review.md):
--   * revoking anon SELECT on public.profiles / followers / event_participants
--   * tightening the notifications INSERT policy
--   * deriving reports.category server-side instead of trusting the client
--
-- The storage section is the one change that could break an existing flow.
-- Before: observed from the live project on 2026-10-25 —
--   anon POST   /storage/v1/object/images/<any path>            → 200
--   anon POST   same path with x-upsert:true (overwrite)        → 200
--   anon DELETE /storage/v1/object/images/<existing object>     → 200, object gone
--   anon POST   /storage/v1/object/list/images {"prefix":"posts"} → 200, object names
-- After (this file):
--   read stays public; insert/update/delete require a signed-in user and,
--   for update/delete, the object's owner. The app uploads as a signed-in
--   user with a generated name and never lists, so nothing in the client
--   depends on the anonymous access that is being removed.
-- Rollback: drop the four policies created below and re-create the previous
-- dashboard policy. The old policy definition is not in the repo; capture it
-- from Storage → Policies before applying if you want a literal rollback.

-- ====================================================== form text caps (server)
-- The client caps these (lib/utils/text_rules.dart) but save_event_form wrote
-- title/intro/help unchecked, so a direct RPC call could store any length.
-- NOT VALID: legacy rows are not scanned, new writes are checked.

alter table public.event_forms drop constraint if exists event_forms_title_len;
alter table public.event_forms add constraint event_forms_title_len
  check (length(title) between 1 and 120) not valid;

alter table public.event_forms drop constraint if exists event_forms_intro_len;
alter table public.event_forms add constraint event_forms_intro_len
  check (intro is null or length(intro) <= 500) not valid;

alter table public.form_fields drop constraint if exists form_fields_help_len;
alter table public.form_fields add constraint form_fields_help_len
  check (help is null or length(help) <= 300) not valid;

-- Per-choice cap (60) lives in the validator, which every save and every
-- publish runs, so it cannot be skipped by editing around the editor.
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
  v_min   int;
  v_max   int;
  v_choice text;
begin
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
    for v_choice in select jsonb_array_elements_text(p_options->'choices') loop
      if length(trim(v_choice)) = 0 or length(v_choice) > 60 then
        raise exception 'FORM:bad_choice_label' using errcode = 'P0001';
      end if;
    end loop;
  end if;

  if p_kind = 'rating' then
    v_min := (p_options->>'min')::int;
    v_max := (p_options->>'max')::int;
    if v_min is null or v_max is null or v_min < 1 or v_max > 10 or v_min >= v_max then
      raise exception 'FORM:bad_scale' using errcode = 'P0001';
    end if;
  end if;

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

-- ====================================================== hidden events
-- The counts view runs as its owner (bypasses RLS) and had no is_hidden
-- filter, so a moderated event's id and attendance count stayed readable by
-- guests. Same columns, only the WHERE changes.
create or replace view public.event_participant_counts as
select e.id as event_id, count(ep.user_id)::int as participant_count
from public.events e
left join public.event_participants ep on ep.event_id = e.id
where coalesce(e.is_public, true)
  and not coalesce(e.is_hidden, false)
group by e.id;

grant select on public.event_participant_counts to anon, authenticated;

-- ====================================================== student domain
-- `like '%' || domain` is a substring match: an address at
-- <student.uitm.edu.my>.attacker.example passed it. Compare the domain
-- exactly instead.
create or replace function public.enforce_student_email_signup()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_mode   text;
  v_domain text;
  v_want   text;
  v_got    text;
begin
  if coalesce((new.raw_app_meta_data ->> 'allow_non_student')::boolean, false) then
    return new;
  end if;

  select s.registration_mode, s.student_domain
  into v_mode, v_domain
  from public.access_settings s
  where s.id;

  if coalesce(v_mode, 'student_only') = 'open' then
    return new;
  end if;

  v_want := lower(ltrim(coalesce(nullif(btrim(v_domain), ''), '@student.uitm.edu.my'), '@'));
  v_got  := lower(split_part(coalesce(new.email, ''), '@', 2));
  if v_got is distinct from v_want then
    raise exception 'Sign-up requires a @student.uitm.edu.my email address'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_student_email_signup on auth.users;
create trigger trg_enforce_student_email_signup
before insert on auth.users
for each row execute function public.enforce_student_email_signup();

-- Same rule on the admin path, which only checked for an '@'. A trigger
-- covers every writer (request_student_verification, admin_set_student_verification,
-- dashboard SQL) without re-writing either function.
create or replace function public.guard_verification_domain()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_domain text;
  v_off    boolean;
begin
  if new.status is distinct from 'verified' then
    return new;
  end if;

  select coalesce(nullif(btrim(s.student_domain), ''), '@student.uitm.edu.my')
  into v_domain
  from public.access_settings s where s.id;

  -- An empty domain means "do not check" (same as the request path).
  if v_domain is null then return new; end if;

  if lower(split_part(coalesce(new.email, ''), '@', 2))
     is distinct from lower(ltrim(v_domain, '@')) then
    raise exception 'VERIFY:domain' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_verification_domain on public.student_verifications;
create trigger trg_guard_verification_domain
before insert or update of email, status on public.student_verifications
for each row execute function public.guard_verification_domain();

-- ====================================================== execute grants
-- `revoke ... from anon` does not remove the default PUBLIC grant, so these
-- were callable by anyone. They return false for an anon caller, but the
-- comment in 20261019004100 relies on the opposite being true.
revoke execute on function public.is_admin()  from public, anon;
revoke execute on function public.is_owner()  from public, anon;
grant  execute on function public.is_admin()  to authenticated;
grant  execute on function public.is_owner()  to authenticated;

-- Trigger-only helper that was never revoked.
revoke execute on function public.forget_saved_target() from public, anon, authenticated;

-- ====================================================== storage writes
-- `images`: anonymous create/update/delete/list, demonstrated against the live
-- project. Replace every policy on storage.objects that mentions this bucket
-- with an owner-scoped set. Read stays public (the bucket is public; the
-- public object endpoint does not consult these policies anyway).
--
-- Avatars are deliberately NOT touched here: anonymous writes to that bucket
-- were already refused, and adding permissive policies would make it looser
-- (permissive policies OR together). Verify it in the dashboard instead.
do $$
declare
  pol record;
begin
  -- Guard on the table, not the schema: the test stub has storage.buckets
  -- but no storage.objects.
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage' and c.relname = 'objects'
  ) then
    return;
  end if;

  for pol in
    select p.polname
    from pg_policy p
    where p.polrelid = 'storage.objects'::regclass
      and coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' ||
          coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ilike '%images%'
  loop
    execute format('drop policy %I on storage.objects', pol.polname);
  end loop;

  -- Insert: any signed-in user, any path. Deliberately NOT owner-checked:
  -- `owner` is written by the storage API, and if a deployment ever stored it
  -- as null an owner check here would refuse every upload. The app generates
  -- the object name itself and never overwrites an existing one (every path
  -- carries a timestamp), so insert alone cannot touch another user's object.
  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                 and polname = 'images_insert') then
    create policy "images_insert" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'images');
  end if;

  -- Update/delete: only the uploader's own objects. `owner` is set by the
  -- storage API from the JWT. If an object has no owner (uploaded before auth
  -- was enforced), nobody but the service role can replace or delete it — that
  -- degrades to "cleanup skipped", never to a failed upload.
  -- `x-upsert` is INSERT … ON CONFLICT DO UPDATE, so it needs this policy too:
  -- that is what stops one user overwriting another's image by guessing a path.
  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                 and polname = 'images_update') then
    create policy "images_update" on storage.objects
      for update to authenticated
      using (bucket_id = 'images' and owner = auth.uid())
      with check (bucket_id = 'images' and owner = auth.uid());
  end if;

  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                 and polname = 'images_delete') then
    create policy "images_delete" on storage.objects
      for delete to authenticated
      using (bucket_id = 'images' and owner = auth.uid());
  end if;

  -- Read stays as it was: public URLs never consult this policy (they are
  -- served by the public object endpoint), but listing remains possible. It is
  -- harmless once writes are closed, and removing it is a bigger change than
  -- this fix needs.
  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                 and polname = 'images_read') then
    create policy "images_read" on storage.objects
      for select to anon, authenticated
      using (bucket_id = 'images');
  end if;
end $$;
