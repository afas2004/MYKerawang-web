-- Open registration becomes an owner switch.
--
--   student_only (default)  new accounts need the configured student domain
--   open                    any email address may sign up
--
-- The rule lives in the auth.users trigger, so it cannot be bypassed by
-- calling the Auth API directly. The client only reads the mode to show
-- the right message and to avoid a pointless round trip.
--
-- Existing accounts are never touched: the trigger is BEFORE INSERT only.

alter table public.access_settings
  add column if not exists registration_mode text not null default 'student_only';

alter table public.access_settings
  drop constraint if exists access_settings_registration_mode;
alter table public.access_settings
  add constraint access_settings_registration_mode
  check (registration_mode in ('student_only', 'open'));

comment on column public.access_settings.registration_mode is
  'Owner-only. student_only keeps signup to the configured student domain; open accepts any email.';

create or replace function public.enforce_student_email_signup()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_mode   text;
  v_domain text;
begin
  -- Staff/test accounts created from the dashboard or Admin API.
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

  if lower(coalesce(new.email, '')) not like '%' || lower(coalesce(v_domain, '@student.uitm.edu.my')) then
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

-- The client reads this while signed out, so the login screen knows which
-- message to show. Nothing in it is private.
create or replace function public.access_policy()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select jsonb_build_object(
    'verification_enabled', coalesce(s.verification_enabled, false),
    'student_domain', s.student_domain,
    'registration_mode', coalesce(s.registration_mode, 'student_only'))
  from public.access_settings s where s.id;
$$;

revoke execute on function public.access_policy() from public;
grant  execute on function public.access_policy() to anon, authenticated;

-- ------------------------------------------------------- owner switch
create or replace function public.set_registration_mode(p_mode text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_mode text := btrim(coalesce(p_mode, ''));
  v_old  text;
begin
  if not public.is_owner() then
    raise exception 'MOD:not_owner' using errcode = 'P0001';
  end if;
  if v_mode not in ('student_only', 'open') then
    raise exception 'ACCESS:bad_mode' using errcode = 'P0001';
  end if;

  select registration_mode into v_old from public.access_settings where id;

  update public.access_settings
  set registration_mode = v_mode,
      updated_at = now(),
      updated_by = auth.uid()
  where id;

  perform public.mod_log('registration_mode_changed', 'admin', null, null,
    jsonb_build_object('from', v_old, 'to', v_mode));
end;
$$;

revoke execute on function public.set_registration_mode(text) from public, anon;
grant  execute on function public.set_registration_mode(text) to authenticated;
