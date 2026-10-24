-- Backup email: the address that keeps an account reachable after the
-- student mailbox closes (UiTM retires it about a year after graduation).
--
-- Stored in profile_contacts, not profiles: profiles is readable by every
-- authenticated user, so a personal email there would be public. Here
-- only the owner can read their own row, and an owner of the app can read
-- one on request for a recovery (logged).
--
-- Not verified yet: there is no sending domain (see
-- docs/access-and-verification.md §12). Confirmation is added when the
-- code-verification flow ships. Until then it is a recovery hint, which
-- is why reading it is an audited owner-only operation.
--
-- Re-runnable.

alter table public.profile_contacts
  add column if not exists backup_email extensions.citext;

-- Deliberately loose: it must look like an address, not be deliverable.
alter table public.profile_contacts
  drop constraint if exists profile_contacts_backup_email_format;
alter table public.profile_contacts
  add constraint profile_contacts_backup_email_format
  check (backup_email is null
         or backup_email::text ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$');

comment on column public.profile_contacts.backup_email is
  'Where to reach the account holder once the student address closes. Readable by its owner and, for recovery, by the app owner only.';

-- ------------------------------------------------------- owner read
-- One address at a time, on request, always logged. There is no listing:
-- a recovery question ("can you see the backup email on this account?")
-- should be answered per account.
create or replace function public.admin_read_backup_email(p_user_id uuid)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text;
begin
  if not public.is_owner() then
    raise exception 'MOD:not_owner' using errcode = 'P0001';
  end if;

  select c.backup_email::text into v_email
  from public.profile_contacts c
  where c.user_id = p_user_id;

  perform public.mod_log('admin_read_backup_email', 'user', p_user_id::text, null,
    jsonb_build_object('had_backup', v_email is not null));

  return v_email;
end;
$$;

revoke execute on function public.admin_read_backup_email(uuid) from public, anon;
grant  execute on function public.admin_read_backup_email(uuid) to authenticated;
