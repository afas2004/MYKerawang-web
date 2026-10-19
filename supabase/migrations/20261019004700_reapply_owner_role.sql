-- Re-applies 20260801000200_owner_role.sql. The live project's history
-- marked the August migrations as applied, but admin_unmask_post() from
-- 20260801000100 turned out to be missing, so the role guard trigger may
-- be missing too. Everything here is idempotent.

-- Role ladder: student, club_pending, club, admin, owner.
-- Admins moderate; only an owner creates or removes admins, so a single
-- compromised admin session cannot mint a replacement for itself.
--
-- RLS grants per row, not per column, so column-level restrictions on
-- profiles have to be a trigger.

create or replace function public.is_admin()
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce(
    (select role in ('admin','owner') from public.profiles where id = auth.uid()),
    false);
$$;

create or replace function public.is_owner()
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce(
    (select role = 'owner' from public.profiles where id = auth.uid()),
    false);
$$;

revoke execute on function public.is_admin() from anon;
revoke execute on function public.is_owner() from anon;
grant  execute on function public.is_admin() to authenticated;
grant  execute on function public.is_owner() to authenticated;

create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  -- No auth.uid() means SQL editor, dashboard or service_role.
  -- Required, or the first owner could never be created.
  if auth.uid() is null or public.is_owner() then
    return new;
  end if;

  if public.is_admin() then
    if new.role in ('admin','owner') and new.role is distinct from old.role then
      new.role := old.role;
    end if;
    if old.role in ('admin','owner') and new.role is distinct from old.role then
      new.role := old.role;
    end if;
    return new;
  end if;

  -- Ordinary account: may raise or withdraw a club request only.
  if not (
       (old.role = 'student'      and new.role = 'club_pending')
    or (old.role = 'club_pending' and new.role = 'student')
    or (new.role is not distinct from old.role)
  ) then
    new.role := old.role;
  end if;

  new.is_verified := old.is_verified;
  new.is_banned   := old.is_banned;
  new.ban_reason  := old.ban_reason;

  return new;
end;
$$;

drop trigger if exists trg_guard_profile_privileges on public.profiles;
create trigger trg_guard_profile_privileges
before update on public.profiles
for each row execute function public.guard_profile_privileges();

-- A typo such as 'Admin' matches no check and silently grants nothing,
-- which presents as an unexplained lockout. Fail loudly instead.
-- NOT VALID: enforced for new/changed rows without failing on any
-- legacy value already in the table.
alter table public.profiles drop constraint if exists profiles_role_valid;
alter table public.profiles add constraint profiles_role_valid
  check (role in ('student','club_pending','club','admin','owner')) not valid;
