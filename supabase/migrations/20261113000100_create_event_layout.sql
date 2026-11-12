-- Owner choice of how the Create event page is laid out:
--
--   folded  one page; optional sections folded with a summary (default)
--   steps   four steps with a progress bar
--
-- A display setting only: both layouts write exactly the same rows.
-- Defaults to 'folded', so deploying this changes nothing until the owner
-- picks the other layout.

alter table public.access_settings
  add column if not exists create_event_layout text not null default 'folded';

alter table public.access_settings drop constraint if exists access_settings_event_layout_valid;
alter table public.access_settings add constraint access_settings_event_layout_valid
  check (create_event_layout in ('folded', 'steps'));

comment on column public.access_settings.create_event_layout is
  'Owner-only. folded | steps: how the Create event page is laid out.';

-- Same keys as 20261105000100_feature_switches.sql, plus the layout.
-- Read while signed out, so nothing private goes in here.
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
    'student_features_enabled', coalesce(s.student_features_enabled, true),
    'create_event_layout', coalesce(s.create_event_layout, 'folded'))
  from public.access_settings s where s.id;
$$;

revoke execute on function public.access_policy() from public;
grant  execute on function public.access_policy() to anon, authenticated;

-- ------------------------------------------------------- owner choice
create or replace function public.set_create_event_layout(p_layout text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_layout text := btrim(coalesce(p_layout, ''));
  v_old    text;
begin
  if not public.is_owner() then
    raise exception 'MOD:not_owner' using errcode = 'P0001';
  end if;
  if v_layout not in ('folded', 'steps') then
    raise exception 'ACCESS:bad_layout' using errcode = 'P0001';
  end if;

  select create_event_layout into v_old from public.access_settings where id;
  update public.access_settings
  set create_event_layout = v_layout, updated_at = now(), updated_by = auth.uid()
  where id;

  perform public.mod_log('layout_switch', 'admin', 'create_event', null,
    jsonb_build_object('setting', 'create_event_layout', 'from', v_old, 'to', v_layout));
end;
$$;

revoke execute on function public.set_create_event_layout(text) from public, anon;
grant  execute on function public.set_create_event_layout(text) to authenticated;
