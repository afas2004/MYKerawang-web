-- Owner on/off switches for whole areas of the app, so it can run as a
-- general college app without the parts that need UiTM's approval.
--
--   announcements_enabled     the Announcements area
--   clubs_enabled             the Clubs area
--   student_features_enabled  student verification, student-email signup
--                             wording, matric prefill
--
-- All default to true: deploying this changes nothing until the owner
-- flips a switch. These are display switches read by the client; each
-- area's own rules (RLS, triggers) stay as they are.

alter table public.access_settings
  add column if not exists announcements_enabled    boolean not null default true,
  add column if not exists clubs_enabled            boolean not null default true,
  add column if not exists student_features_enabled boolean not null default true;

comment on column public.access_settings.announcements_enabled is
  'Owner-only. false hides the Announcements area in the app.';
comment on column public.access_settings.clubs_enabled is
  'Owner-only. false hides the Clubs area in the app.';
comment on column public.access_settings.student_features_enabled is
  'Owner-only. false hides student-specific features (verification, student-email wording, matric prefill).';

-- Same keys as 20261026005100_open_registration.sql, plus the three
-- switches. Read while signed out, so nothing private goes in here.
create or replace function public.access_policy()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select jsonb_build_object(
    'verification_enabled', coalesce(s.verification_enabled, false),
    'student_domain', s.student_domain,
    'registration_mode', coalesce(s.registration_mode, 'student_only'),
    'announcements_enabled', coalesce(s.announcements_enabled, true),
    'clubs_enabled', coalesce(s.clubs_enabled, true),
    'student_features_enabled', coalesce(s.student_features_enabled, true))
  from public.access_settings s where s.id;
$$;

revoke execute on function public.access_policy() from public;
grant  execute on function public.access_policy() to anon, authenticated;

-- ------------------------------------------------------- owner switch
-- p_feature is one of: announcements, clubs, student_features.
create or replace function public.set_feature_enabled(p_feature text, p_enabled boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_feature text := btrim(coalesce(p_feature, ''));
  v_on      boolean := coalesce(p_enabled, true);
  v_old     boolean;
begin
  if not public.is_owner() then
    raise exception 'MOD:not_owner' using errcode = 'P0001';
  end if;

  -- Explicit branches instead of dynamic SQL: only these three columns
  -- can ever be written.
  case v_feature
    when 'announcements' then
      select announcements_enabled into v_old from public.access_settings where id;
      update public.access_settings
      set announcements_enabled = v_on, updated_at = now(), updated_by = auth.uid()
      where id;
    when 'clubs' then
      select clubs_enabled into v_old from public.access_settings where id;
      update public.access_settings
      set clubs_enabled = v_on, updated_at = now(), updated_by = auth.uid()
      where id;
    when 'student_features' then
      select student_features_enabled into v_old from public.access_settings where id;
      update public.access_settings
      set student_features_enabled = v_on, updated_at = now(), updated_by = auth.uid()
      where id;
    else
      raise exception 'ACCESS:bad_feature' using errcode = 'P0001';
  end case;

  perform public.mod_log('feature_switch', 'admin', v_feature, null,
    jsonb_build_object('feature', v_feature, 'from', v_old, 'to', v_on));
end;
$$;

revoke execute on function public.set_feature_enabled(text, boolean) from public, anon;
grant  execute on function public.set_feature_enabled(text, boolean) to authenticated;
