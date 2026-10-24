-- Admin console lock: an owner-set PIN, checked server-side, plus a
-- client-side idle lock (15 minutes). The hash never leaves the database:
-- admin_access has RLS on and no policies, and only these security-definer
-- functions touch it.
--
-- This is a UX gate in front of the console. The database still authorises
-- every admin RPC by role, so a stolen admin session is never widened by it.

create table if not exists public.admin_access (
  id         boolean primary key default true,
  pin_hash   text,
  updated_at timestamptz not null default now(),
  constraint admin_access_single check (id)
);

insert into public.admin_access (id) values (true) on conflict (id) do nothing;

alter table public.admin_access enable row level security;
revoke all on public.admin_access from anon, authenticated;

-- ------------------------------------------------------- status
create or replace function public.admin_pin_status()
returns jsonb
language plpgsql security definer stable
set search_path = public
as $$
begin
  perform public.mod_require_admin();
  return jsonb_build_object(
    'configured', coalesce((select pin_hash is not null from public.admin_access where id), false));
end;
$$;

-- ------------------------------------------------------- check
create or replace function public.admin_check_pin(p_pin text)
returns boolean
language plpgsql security definer stable
set search_path = public
as $$
begin
  perform public.mod_require_admin();
  return coalesce((
    select pin_hash is not null
       and pin_hash = extensions.crypt(coalesce(p_pin, ''), pin_hash)
    from public.admin_access where id), false);
end;
$$;

-- ------------------------------------------------------- set (owner)
create or replace function public.admin_set_pin(p_pin text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pin text := btrim(coalesce(p_pin, ''));
begin
  if not public.is_owner() then
    raise exception 'MOD:not_owner' using errcode = 'P0001';
  end if;
  if length(v_pin) < 4 or length(v_pin) > 64 then
    raise exception 'MOD:pin_length' using errcode = 'P0001';
  end if;
  update public.admin_access
  set pin_hash = extensions.crypt(v_pin, extensions.gen_salt('bf')),
      updated_at = now()
  where id;
  perform public.mod_log('admin_pin_set', 'admin', auth.uid()::text, null, '{}');
end;
$$;

revoke execute on function public.admin_pin_status()      from public, anon;
revoke execute on function public.admin_check_pin(text)   from public, anon;
revoke execute on function public.admin_set_pin(text)     from public, anon;

grant execute on function public.admin_pin_status()       to authenticated;
grant execute on function public.admin_check_pin(text)    to authenticated;
grant execute on function public.admin_set_pin(text)      to authenticated;
