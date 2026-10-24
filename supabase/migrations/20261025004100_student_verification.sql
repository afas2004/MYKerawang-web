-- Student verification, part 1: the record, the switch, and the gate.
--
-- Nothing changes for anyone yet: access_settings.verification_enabled
-- defaults to false, and only an owner can turn it on. With it off,
-- every row below behaves exactly as before.
--
-- With it on, three write paths start asking "is this account a verified
-- student?" — joining an event, creating an event, and selling:
--
--   event_participants → event_join
--   events             → event_create
--   listings           → sell
--
-- Posting and commenting stay open. Club joins and roster seats are
-- wired to require_verified() when the verification UI ships; the helper
-- below already exists for them.
--
-- The record is deliberately narrow: account, address, status, how it was
-- proven, when. No legal name, no matric number — a code in an inbox
-- proves the inbox, not the person. Impersonation is handled by reports.
--
-- Every statement is re-runnable.

-- ====================================================== the record
create table if not exists public.student_verifications (
  user_id        uuid primary key references public.profiles(id) on delete cascade,
  email          extensions.citext not null,
  status         text not null default 'verified'
                 check (status in ('pending','verified','rejected','revoked','expired')),
  method         text not null default 'admin'
                 check (method in ('legacy','auto','admin','otp')),
  verified_at    timestamptz,
  revoked_at     timestamptz,
  revoked_reason text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- One student address can belong to one account, ever (while pending or
-- verified). citext makes the comparison case-insensitive.
create unique index if not exists student_verifications_email_key
  on public.student_verifications (email)
  where status in ('pending','verified');

create index if not exists student_verifications_status_idx
  on public.student_verifications (status);

alter table public.student_verifications enable row level security;

drop policy if exists "student_verifications_select" on public.student_verifications;
create policy "student_verifications_select" on public.student_verifications
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

revoke all on public.student_verifications from anon, authenticated;
grant select on public.student_verifications to authenticated;

comment on table public.student_verifications is
  'One row per account: proof that it belonged to a UiTM student. Written only by security-definer functions.';

-- The predicate every gate uses.
create or replace function public.is_verified_student(p_user uuid default auth.uid())
returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from public.student_verifications v
    where v.user_id = p_user and v.status = 'verified');
$$;

revoke execute on function public.is_verified_student(uuid) from public;
grant  execute on function public.is_verified_student(uuid) to anon, authenticated;

-- ====================================================== the switch
create table if not exists public.access_settings (
  id                   boolean primary key default true check (id),
  verification_enabled boolean not null default false,
  student_domain       text not null default '@student.uitm.edu.my',
  updated_at           timestamptz not null default now(),
  updated_by           uuid references public.profiles(id) on delete set null
);

insert into public.access_settings (id) values (true) on conflict (id) do nothing;

alter table public.access_settings enable row level security;

drop policy if exists "access_settings_select" on public.access_settings;
create policy "access_settings_select" on public.access_settings
for select to authenticated using (true);

revoke all on public.access_settings from anon, authenticated;
grant select on public.access_settings to authenticated;

comment on column public.access_settings.verification_enabled is
  'Owner-only switch. When false (default) student verification gates nothing.';

-- One read for the client. The switch is not secret; the reason log is.
create or replace function public.access_policy()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select jsonb_build_object(
    'verification_enabled', coalesce(s.verification_enabled, false),
    'student_domain', s.student_domain)
  from public.access_settings s where s.id;
$$;

revoke execute on function public.access_policy() from public, anon;
grant  execute on function public.access_policy() to authenticated;

-- Which actions the switch covers. One list, so the guard and the copy
-- in the console cannot disagree.
create or replace function public.verification_required(p_capability text)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select coalesce((
    select s.verification_enabled
    from public.access_settings s where s.id), false)
  and p_capability in ('event_join','event_create','sell',
                       'club_join','club_officer','club_create');
$$;

revoke execute on function public.verification_required(text) from public, anon;
grant  execute on function public.verification_required(text) to authenticated;

-- Called by RPCs (and available to future ones); triggers raise directly.
create or replace function public.require_verified(p_capability text)
returns void
language plpgsql security definer stable
set search_path = public
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return;  -- guests are stopped by RLS; staff never need a student email
  end if;
  if not public.verification_required(p_capability) then
    return;
  end if;
  if public.is_verified_student(auth.uid()) then
    return;
  end if;
  raise exception 'VERIFY:required:%', p_capability
    using errcode = 'P0001',
          hint = 'Verify your student status to do this.';
end;
$$;

revoke execute on function public.require_verified(text) from public, anon;
grant  execute on function public.require_verified(text) to authenticated;

-- ====================================================== the gate
-- Same guard as 004200 (bans + rate limits), plus a fourth TG_ARGV: the
-- capability it protects. Missing (older triggers) means "not gated".
create or replace function public.mod_guard_write()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_scope  text := tg_argv[0];
  v_col    text := tg_argv[1];
  v_kind   text := nullif(tg_argv[2], '');
  v_cap    text := nullif(tg_argv[3], '');
  v_uid    uuid := auth.uid();
  v_owner  uuid;
  r        record;
  s        public.moderation_settings;
  v_age    interval;
  v_limit  int;
  v_count  int;
begin
  v_owner := (to_jsonb(new) ->> v_col)::uuid;

  -- Only the author acting on their own row. System/admin writes (auto-
  -- hide, counters, SQL editor) are never blocked.
  if v_uid is null or v_owner is distinct from v_uid then
    return new;
  end if;

  select * into r from public.mod_active_restriction(v_uid, v_scope);
  if found then
    raise exception 'MOD:restricted:%', r.scope
      using errcode = 'P0001',
            detail  = jsonb_build_object('scope', r.scope, 'until', r.until, 'reason', r.reason)::text,
            hint    = 'This account is restricted from this action.';
  end if;

  -- Student verification. Inserts only: turning the switch on must not
  -- lock someone out of editing content they already own.
  if tg_op = 'INSERT' and v_cap is not null
     and public.verification_required(v_cap)
     and not public.is_admin()
     and not public.is_verified_student(v_uid) then
    raise exception 'VERIFY:required:%', v_cap
      using errcode = 'P0001',
            hint = 'Verify your student status to do this.';
  end if;

  if tg_op <> 'INSERT' or v_kind is null or public.is_admin() then
    return new;
  end if;

  s := public.mod_settings();
  select now() - u.created_at into v_age from auth.users u where u.id = v_uid;
  if v_age is null or v_age >= make_interval(hours => s.new_account_hours) then
    return new;
  end if;

  v_limit := case v_kind
    when 'post'    then s.new_account_posts_per_hour
    when 'comment' then s.new_account_comments_per_hour
    when 'listing' then s.new_account_listings_per_hour
    when 'event'   then s.new_account_events_per_hour
  end;
  if v_limit is null then return new; end if;

  execute format(
    'select count(*) from public.%I where %I = $1 and created_at > now() - interval ''1 hour''',
    tg_table_name, v_col)
  into v_count using v_uid;

  if v_count >= v_limit then
    raise exception 'MOD:rate_limited:%', v_kind
      using errcode = 'P0001',
            detail  = jsonb_build_object('limit', v_limit, 'hours', s.new_account_hours)::text,
            hint    = 'New accounts have an hourly limit.';
  end if;

  return new;
end;
$$;

revoke execute on function public.mod_guard_write() from public, anon, authenticated;

-- Re-create only the gated triggers, with the capability attached.
-- Columns are resolved dynamically: a column missing on this project is
-- skipped instead of failing the migration.
do $$
declare
  spec record;
  cols text;
  kind text;
begin
  for spec in
    select * from (values
      ('listings',           'market', 'seller_id',    'listing', 'sell',
         array['title','description','price','image_url','gallery_urls','category']),
      ('events',             'events', 'organizer_id', 'event',   'event_create',
         array['title','description','location','start_datetime','end_datetime',
               'image_url','gallery_urls','tags','registration_link']),
      ('event_participants', 'events', 'user_id',      '',        'event_join',
         array[]::text[])
    ) as t(tbl, scope, owner_col, rate_kind, capability, upd_cols)
  loop
    if to_regclass('public.' || spec.tbl) is null then
      continue;
    end if;

    select string_agg(quote_ident(c), ', ') into cols
    from unnest(spec.upd_cols) c
    where exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = spec.tbl and column_name = c);

    kind := spec.rate_kind;
    if kind <> '' and not exists (select 1 from information_schema.columns
                                  where table_schema = 'public' and table_name = spec.tbl
                                    and column_name = 'created_at') then
      kind := '';
    end if;

    execute format('drop trigger if exists trg_mod_guard on public.%I', spec.tbl);
    execute format(
      'create trigger trg_mod_guard before insert%s on public.%I '
      'for each row execute function public.mod_guard_write(%L, %L, %L, %L)',
      case when cols is null then '' else ' or update of ' || cols end,
      spec.tbl, spec.scope, spec.owner_col, kind, spec.capability);
  end loop;
end $$;

-- ====================================================== the switch RPC
create or replace function public.set_verification_enabled(p_enabled boolean, p_reason text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'MOD:not_owner' using errcode = 'P0001';
  end if;

  update public.access_settings
  set verification_enabled = coalesce(p_enabled, false),
      updated_at = now(),
      updated_by = auth.uid()
  where id;

  perform public.mod_log('verification_switch', 'admin', null,
    nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('enabled', coalesce(p_enabled, false)));
end;
$$;

revoke execute on function public.set_verification_enabled(boolean, text) from public, anon;
grant  execute on function public.set_verification_enabled(boolean, text) to authenticated;

-- ====================================================== manual verify
-- The escape hatch: works before any code-by-email flow exists, and is
-- how a dispute or an expired mailbox gets resolved by hand.
create or replace function public.admin_set_student_verification(
  p_user_id uuid,
  p_email   text,
  p_status  text default 'verified'
)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if not public.is_admin() then
    raise exception 'MOD:not_admin' using errcode = 'P0001';
  end if;
  if p_status not in ('verified','rejected','revoked') then
    raise exception 'VERIFY:bad_status' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'VERIFY:user_not_found' using errcode = 'P0001';
  end if;

  if p_status = 'verified' then
    if v_email = '' or v_email not like '%@%' then
      raise exception 'VERIFY:email_required' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.student_verifications v
               where v.email = v_email::extensions.citext
                 and v.user_id <> p_user_id
                 and v.status in ('pending','verified')) then
      raise exception 'VERIFY:email_taken' using errcode = 'P0001';
    end if;

    insert into public.student_verifications
      (user_id, email, status, method, verified_at, revoked_at, revoked_reason, updated_at)
    values
      (p_user_id, v_email, 'verified', 'admin', now(), null, null, now())
    on conflict (user_id) do update
      set email          = excluded.email,
          status         = 'verified',
          method         = 'admin',
          verified_at    = now(),
          revoked_at     = null,
          revoked_reason = null,
          updated_at     = now();
  else
    update public.student_verifications
    set status = p_status,
        revoked_at = case when p_status = 'revoked' then now() else revoked_at end,
        updated_at = now()
    where user_id = p_user_id;
    if not found then
      raise exception 'VERIFY:not_found' using errcode = 'P0001';
    end if;
  end if;

  perform public.mod_log('student_verification_' || p_status, 'user', p_user_id::text, null,
    jsonb_build_object('email', v_email));
end;
$$;

revoke execute on function public.admin_set_student_verification(uuid, text, text) from public, anon;
grant  execute on function public.admin_set_student_verification(uuid, text, text) to authenticated;
