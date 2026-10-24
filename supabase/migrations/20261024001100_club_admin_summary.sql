-- Admin console: count club requests from the clubs table.
--
-- 20261022002300 moved clubs from the old account role (profiles.role in
-- 'club' / 'club_pending') onto real club pages, but admin_queue_summary
-- kept counting profiles.role = 'club_pending'. register_club() never sets
-- that role, so the "Club requests" card read 0 while the Clubs tab had
-- requests. Count clubs.status = 'pending' instead, and expose how many
-- pages are suspended for the console.
--
-- Same signature and keys as 20261019004400, plus suspended_clubs; the
-- existing grant is preserved by create or replace.

create or replace function public.admin_queue_summary()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  perform public.mod_require_admin();
  perform public.mod_sweep_expired(null);
  select jsonb_build_object(
    'open_cases',      (select count(*) from public.moderation_cases where status in ('open','hidden')),
    'hidden_cases',    (select count(*) from public.moderation_cases where status = 'hidden'),
    'oldest_open_at',  (select min(first_reported_at) from public.moderation_cases where status in ('open','hidden')),
    'pending_appeals', (select count(*) from public.appeals where status = 'pending'),
    'club_requests',   (select count(*) from public.clubs where status = 'pending'),
    'suspended_clubs', (select count(*) from public.clubs where status = 'suspended'),
    'active_restrictions', (select count(*) from public.user_restrictions
                            where lifted_at is null and (until is null or until > now())))
  into v;
  return v;
end;
$$;
