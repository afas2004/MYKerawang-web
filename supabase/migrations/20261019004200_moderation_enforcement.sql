-- Moderation, part 2: enforcement of restrictions and new-account limits.
--
-- Two layers:
--   * RLS: restrictive INSERT policies calling is_restricted(scope), so a
--     restricted user's direct REST inserts are refused.
--   * Triggers: the same check on insert and on content edits. Needed
--     because author edits/deletes go through security-definer RPCs
--     (update_my_post etc.) that bypass RLS, and because RLS errors can't
--     say *why*. Triggers raise first with a machine-readable message the
--     app translates:
--
--       message 'MOD:restricted:<scope>'   detail {"scope","until","reason"}
--       message 'MOD:rate_limited:<kind>'  detail {"limit","hours"}
--
-- Expired restrictions stop applying by themselves (until > now()); no
-- cron needed. profiles.is_banned counts as a permanent account ban.

create or replace function public.mod_active_restriction(p_user uuid, p_scope text)
returns table (id uuid, scope text, until timestamptz, reason text)
language sql security definer stable
set search_path = public
as $$
  select x.id, x.scope, x.until, x.reason
  from (
    select r.id, r.scope, r.until, r.reason
    from public.user_restrictions r
    where r.user_id = p_user
      and r.lifted_at is null
      and (r.until is null or r.until > now())
      and r.scope in (p_scope, 'account')
    union all
    select null::uuid, 'account'::text, null::timestamptz, coalesce(pr.ban_reason, '')::text
    from public.profiles pr
    where pr.id = p_user and coalesce(pr.is_banned, false)
  ) x
  -- account before scope, permanent before temporary, longest first
  order by x.scope = 'account' desc, x.until is null desc, x.until desc
  limit 1;
$$;

create or replace function public.is_restricted_user(p_user uuid, p_scope text)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select p_user is not null
     and exists (select 1 from public.mod_active_restriction(p_user, p_scope));
$$;

-- For RLS policies and the app: is the *caller* restricted in this scope?
create or replace function public.is_restricted(p_scope text)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select public.is_restricted_user(auth.uid(), p_scope);
$$;

revoke execute on function public.mod_active_restriction(uuid, text) from public, anon, authenticated;
revoke execute on function public.is_restricted_user(uuid, text)     from public, anon, authenticated;
revoke execute on function public.is_restricted(text)                from public, anon;
grant  execute on function public.is_restricted(text)                to authenticated;

-- ------------------------------------------------------- write guard
-- TG_ARGV: [0] scope, [1] owner column, [2] rate-limit kind ('' = none)
create or replace function public.mod_guard_write()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_scope  text := tg_argv[0];
  v_col    text := tg_argv[1];
  v_kind   text := nullif(tg_argv[2], '');
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

-- Built dynamically so a column that doesn't exist on this project
-- (e.g. events.tags) is skipped instead of failing the migration.
-- UPDATE OF lists content columns only: marking sold, counters and
-- moderation flags are not "writing".
do $$
declare
  spec  record;
  cols  text;
  kind  text;
begin
  for spec in
    select * from (values
      ('posts',              'post',    'user_id',      'post',
         array['title','body','image_url','gallery_urls','tags']),
      ('comments',           'comment', 'user_id',      'comment',
         array['body']),
      ('listings',           'market',  'seller_id',    'listing',
         array['title','description','price','image_url','gallery_urls','category']),
      ('events',             'events',  'organizer_id', 'event',
         array['title','description','location','start_datetime','end_datetime',
               'image_url','gallery_urls','tags','registration_link']),
      ('event_participants', 'events',  'user_id',      '',
         array[]::text[]),
      ('followers',          'account', 'follower_id',  '',
         array[]::text[]),
      ('reports',            'account', 'reporter_id',  '',
         array[]::text[])
    ) as t(tbl, scope, owner_col, rate_kind, upd_cols)
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
      'for each row execute function public.mod_guard_write(%L, %L, %L)',
      case when cols is null then '' else ' or update of ' || cols end,
      spec.tbl, spec.scope, spec.owner_col, kind);

    execute format('drop policy if exists "mod_restricted_insert" on public.%I', spec.tbl);
    execute format(
      'create policy "mod_restricted_insert" on public.%I as restrictive '
      'for insert to authenticated with check (not public.is_restricted(%L))',
      spec.tbl, spec.scope);
  end loop;
end $$;
