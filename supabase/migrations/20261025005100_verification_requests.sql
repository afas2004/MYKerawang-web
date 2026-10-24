-- Student verification, part 2: the request a student can make, and the
-- queue an admin works through.
--
-- There is no code-by-email yet (no sending domain), so a request is
-- proved by a human: the student submits their UiTM address, and an
-- admin approves it from the console. Approving verifies the inbox was
-- theirs to the best of our knowledge — it does not prove a name.
--
-- Only usable while access_settings.verification_enabled is on, so the
-- feature stays invisible until an owner opens it.
--
-- Re-runnable.

-- ------------------------------------------------------- student request
create or replace function public.request_student_verification(p_email text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_domain  text;
  v_enabled boolean;
  v_status  text;
  v_updated timestamptz;
begin
  if v_uid is null then
    raise exception 'VERIFY:login_required' using errcode = 'P0001';
  end if;

  select coalesce(s.verification_enabled, false), s.student_domain
  into v_enabled, v_domain
  from public.access_settings s where s.id;

  if not coalesce(v_enabled, false) and not public.is_admin() then
    raise exception 'VERIFY:closed' using errcode = 'P0001';
  end if;

  if v_email = '' or v_email not like '%_@_%._%' then
    raise exception 'VERIFY:email_invalid' using errcode = 'P0001';
  end if;

  if coalesce(v_domain, '') <> '' and v_email not like '%' || lower(v_domain) then
    raise exception 'VERIFY:domain' using errcode = 'P0001';
  end if;

  select v.status, v.updated_at into v_status, v_updated
  from public.student_verifications v where v.user_id = v_uid;

  if v_status = 'verified' then
    raise exception 'VERIFY:already_verified' using errcode = 'P0001';
  end if;

  -- One submission per ten minutes: a typo fix is fine, refreshing a
  -- queue position is not.
  if v_updated is not null and v_updated > now() - interval '10 minutes' then
    raise exception 'VERIFY:wait' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.student_verifications v
             where v.email = v_email::extensions.citext
               and v.user_id <> v_uid
               and v.status in ('pending','verified')) then
    raise exception 'VERIFY:email_taken' using errcode = 'P0001';
  end if;

  insert into public.student_verifications
    (user_id, email, status, method, verified_at, revoked_at, revoked_reason, updated_at)
  values
    (v_uid, v_email, 'pending', 'admin', null, null, null, now())
  on conflict (user_id) do update
    set email          = excluded.email,
        status         = 'pending',
        method         = 'admin',
        verified_at    = null,
        revoked_at     = null,
        revoked_reason = null,
        updated_at     = now();

  perform public.mod_log('student_verification_requested', 'user', v_uid::text, null,
    jsonb_build_object('email', v_email));

  return 'pending';
end;
$$;

revoke execute on function public.request_student_verification(text) from public, anon;
grant  execute on function public.request_student_verification(text) to authenticated;

-- ------------------------------------------------------- admin queue
-- Pending requests only, oldest first: the decision is the existing
-- admin_set_student_verification(user, email, status).
create or replace function public.admin_verification_queue()
returns table (
  user_id      uuid,
  email        text,
  status       text,
  method       text,
  created_at   timestamptz,
  updated_at   timestamptz,
  username     text,
  display_name text
)
language plpgsql security definer stable
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'MOD:not_admin' using errcode = 'P0001';
  end if;

  return query
    select v.user_id,
           v.email::text,
           v.status,
           v.method,
           v.created_at,
           v.updated_at,
           p.username,
           p.display_name
    from public.student_verifications v
    left join public.profiles p on p.id = v.user_id
    where v.status = 'pending'
    order by v.created_at;
end;
$$;

revoke execute on function public.admin_verification_queue() from public, anon;
grant  execute on function public.admin_verification_queue() to authenticated;
