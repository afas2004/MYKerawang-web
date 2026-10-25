-- The organiser's "ask the KI form after check-in" switch.
--
-- `event_forms.after_checkin` already existed, but the only way to set it was
-- `save_event_form()`, which rewrites the whole field list — too much to hang on
-- a switch in the event's manage sheet. This is the one-column update.
--
-- It is a *form* setting, not an event one: the same event can have a form with
-- it on and a later one with it off, and the check-in screen asks the open form.
--
-- Re-runnable.

create or replace function public.set_form_after_checkin(p_form_id uuid, p_on boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.can_manage_form(p_form_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  update public.event_forms
  set after_checkin = coalesce(p_on, false),
      updated_at = now()
  where id = p_form_id;

  if not found then
    raise exception 'FORM:not_found' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.set_form_after_checkin(uuid, boolean) from public, anon;
grant  execute on function public.set_form_after_checkin(uuid, boolean) to authenticated;
