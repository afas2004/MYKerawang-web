-- Notifications v2: preferences, grouping, new kinds, event reminders and
-- phone push (design: docs/mockups/notifications.html).
--
-- What changes
--   * notification_settings: per-category level ('push' | 'bell' | 'off'),
--     quiet hours and the reader's language, one row per user (optional;
--     defaults apply without it).
--   * Every insert into notifications passes notifications_prepare():
--       - a category is filled in from the type;
--       - 'off' drops the row (account & safety notices are never dropped);
--       - a row with a group_key merges into the reader's unread row with the
--         same key ("5 new answers to your form") instead of adding another;
--       - push_due_at is set when the level is 'push', at most once per
--         15 minutes per group.
--   * New kinds, made by triggers so no client can forget them:
--       comment         someone commented on your post / your event
--       also_commented  someone commented on a post you commented on
--       form_answer     someone answered your form
--       event_join      someone joined your event
--       event_changed   an event you joined moved (time or place)
--       event_cancelled (was type 'event')
--       event_reminder  an event you joined starts within the hour
--       new_event       now off unless the reader turns it on
--   * push_tokens: one row per device that allowed notifications (FCM token).
--   * push_take(): the GitHub Actions sender (worker/push.py, service role)
--     takes what is due, after quiet hours and the daily cap.
--   * make_event_reminders(): called by the same sender each run.
--   * push_kick(): optional. With pg_net and a Vault secret named
--     'github_push_dispatch' (a GitHub token allowed to run workflows), a due
--     push starts the sender at once instead of waiting for its schedule.
--     Without them nothing happens and the schedule still delivers.
--
-- Text is written in English as before (title/body) and also carried as
-- structured data, so the app and the sender show it in the reader's
-- language.
--
-- Re-runnable: the test harness applies every migration twice.

-- ====================================================== settings
create table if not exists public.notification_settings (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  prefs         jsonb   not null default '{}'::jsonb,
  quiet_enabled boolean not null default true,
  quiet_start   time    not null default '23:00',
  quiet_end     time    not null default '07:00',
  language      text    not null default 'en' check (language in ('en', 'ms', 'ja')),
  updated_at    timestamptz not null default now()
);

alter table public.notification_settings enable row level security;

drop policy if exists notification_settings_own on public.notification_settings;
create policy notification_settings_own on public.notification_settings
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update on public.notification_settings to authenticated;
revoke all on public.notification_settings from anon;

-- ====================================================== categories & levels
create or replace function public.notif_category(p_type text, p_title text default null)
returns text
language sql immutable
as $$
  select case
    when p_type = 'mention'                                   then 'mentions'
    when p_type = 'follow'                                    then 'follows'
    when p_type in ('comment', 'also_commented')              then 'comments'
    when p_type in ('event', 'event_cancelled', 'event_changed') then 'event_changes'
    when p_type = 'event_reminder'                            then 'reminders'
    when p_type = 'event_join'                                then 'event_joins'
    when p_type = 'form_answer'                               then 'form_answers'
    when p_type = 'new_event'                                 then 'new_events'
    -- The old dashboard trigger wrote no type.
    when p_type is null and p_title like 'New Event:%'        then 'new_events'
    else 'account'
  end
$$;

-- The defaults the Settings page shows.
create or replace function public.notif_default_level(p_category text)
returns text
language sql immutable
as $$
  select case p_category
    when 'reminders'     then 'push'
    when 'event_changes' then 'push'
    when 'comments'      then 'push'
    when 'mentions'      then 'push'
    when 'form_answers'  then 'push'
    when 'event_joins'   then 'bell'
    when 'follows'       then 'bell'
    when 'new_events'    then 'off'
    else 'push' -- account & safety
  end
$$;

create or replace function public.notif_level(p_user uuid, p_category text)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare v text;
begin
  if p_category = 'account' then return 'push'; end if;
  select s.prefs ->> p_category into v
  from public.notification_settings s where s.user_id = p_user;
  if v in ('push', 'bell', 'off') then
    -- Follows never reach the phone (the Settings page doesn't offer it).
    if p_category = 'follows' and v = 'push' then return 'bell'; end if;
    return v;
  end if;
  return public.notif_default_level(p_category);
end;
$$;

revoke execute on function public.notif_level(uuid, text) from public, anon, authenticated;

-- ====================================================== notification columns
alter table public.notifications
  add column if not exists category    text,
  add column if not exists group_key   text,
  add column if not exists count       int not null default 1,
  add column if not exists actor_ids   uuid[] not null default '{}',
  add column if not exists push_due_at timestamptz,
  add column if not exists pushed_at   timestamptz;

create index if not exists notifications_group_idx
  on public.notifications (user_id, group_key) where is_read = false and group_key is not null;
create index if not exists notifications_push_due_idx
  on public.notifications (push_due_at) where push_due_at is not null;

update public.notifications set category = public.notif_category(type, title)
where category is null;

-- ====================================================== insert pipeline
create or replace function public.notifications_prepare()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_level text;
  v_old   public.notifications%rowtype;
begin
  if new.user_id is null then return null; end if;

  new.category := public.notif_category(new.type, new.title);
  v_level := public.notif_level(new.user_id, new.category);
  if v_level = 'off' then return null; end if;

  new.count := 1;
  new.actor_ids := case when new.actor_id is null then '{}'::uuid[] else array[new.actor_id] end;
  new.pushed_at := null;
  new.push_due_at := case when v_level = 'push' then now() end;
  new.is_read := false;

  if new.group_key is not null then
    select * into v_old from public.notifications
    where user_id = new.user_id and group_key = new.group_key and is_read = false
    order by created_at desc limit 1
    for update;

    if found then
      update public.notifications set
        count      = v_old.count + 1,
        actor_id   = new.actor_id,
        actor_ids  = (case when new.actor_id is null then v_old.actor_ids
                      else (array[new.actor_id] || array_remove(v_old.actor_ids, new.actor_id))[1:3] end),
        title      = new.title,
        body       = new.body,
        data       = coalesce(new.data, v_old.data),
        created_at = now(),
        push_due_at = case when v_level = 'push'
                      then greatest(now(), coalesce(v_old.pushed_at, '-infinity'::timestamptz)
                                           + interval '15 minutes') end
      where id = v_old.id;
      return null;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notifications_prepare on public.notifications;
create trigger trg_notifications_prepare
before insert on public.notifications
for each row execute function public.notifications_prepare();

-- ====================================================== push kick (optional)
create table if not exists public.push_kick_state (
  id      int primary key default 1 check (id = 1),
  last_at timestamptz not null default '-infinity'
);
insert into public.push_kick_state (id) values (1) on conflict (id) do nothing;
alter table public.push_kick_state enable row level security;
revoke all on public.push_kick_state from public, anon, authenticated;

create or replace function public.push_kick()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare v_token text;
begin
  if to_regnamespace('net') is null or to_regclass('vault.decrypted_secrets') is null then
    return null;
  end if;
  -- Bell-only rows and read receipts need no sender.
  if not exists (select 1 from public.notifications
                 where push_due_at is not null and push_due_at <= now() + interval '1 minute') then
    return null;
  end if;
  -- At most one start every 20 seconds; the sender keeps checking for a
  -- while, so anything in between is picked up by the run already going.
  update public.push_kick_state set last_at = now()
  where id = 1 and last_at < now() - interval '20 seconds';
  if not found then return null; end if;

  execute $q$select decrypted_secret from vault.decrypted_secrets
             where name = 'github_push_dispatch' limit 1$q$ into v_token;
  if v_token is null then return null; end if;

  execute $q$select net.http_post(
      url     := 'https://api.github.com/repos/afas2004/MYKerawang-web/actions/workflows/push.yml/dispatches',
      body    := '{"ref":"main"}'::jsonb,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || $1,
        'Accept', 'application/vnd.github+json',
        'User-Agent', 'mykerawang-push',
        'Content-Type', 'application/json'))$q$ using v_token;
  return null;
exception when others then
  -- A notification must never fail because the sender couldn't be woken.
  return null;
end;
$$;

drop trigger if exists trg_notifications_push_kick on public.notifications;
create trigger trg_notifications_push_kick
after insert or update of push_due_at on public.notifications
for each statement execute function public.push_kick();

-- ====================================================== devices
create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null default 'web',
  label      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;

drop policy if exists push_tokens_select_own on public.push_tokens;
create policy push_tokens_select_own on public.push_tokens
  for select to authenticated using (user_id = auth.uid());

drop policy if exists push_tokens_delete_own on public.push_tokens;
create policy push_tokens_delete_own on public.push_tokens
  for delete to authenticated using (user_id = auth.uid());

grant select, delete on public.push_tokens to authenticated;
revoke all on public.push_tokens from anon;

-- Registers this device for the caller. A browser that signs into another
-- account keeps the same token, so the row moves to the new owner (a plain
-- upsert can't: RLS hides the old owner's row).
create or replace function public.register_push_token(p_token text, p_platform text default 'web', p_label text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'bad token' using errcode = '22023';
  end if;
  insert into public.push_tokens (token, user_id, platform, label)
  values (p_token, auth.uid(), coalesce(left(p_platform, 20), 'web'), left(p_label, 80))
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform,
        label = coalesce(excluded.label, push_tokens.label), updated_at = now();
end;
$$;

revoke execute on function public.register_push_token(text, text, text) from public, anon;
grant execute on function public.register_push_token(text, text, text) to authenticated;

-- ====================================================== the sender's queue
-- Called by worker/push.py with the service role. Returns what to send now
-- and marks it sent; anything held by quiet hours or the daily cap, or for a
-- reader with no device, is dropped from the queue (it stays in the bell).
create or replace function public.push_take(p_limit int default 200)
returns table (
  id uuid, user_id uuid, type text, category text, title text, body text,
  data jsonb, count int, actor_name text, language text, group_key text, tokens text[]
)
language plpgsql security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  r        record;
  s        public.notification_settings%rowtype;
  v_now    time := (now() at time zone 'Asia/Kuala_Lumpur')::time;
  v_day    timestamptz := date_trunc('day', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_quiet  boolean;
  v_exempt boolean;
  v_tokens text[];
  v_sent   int;
begin
  for r in
    select n.* from public.notifications n
    where n.push_due_at is not null and n.push_due_at <= now()
    order by n.push_due_at
    limit greatest(1, least(p_limit, 500))
    for update skip locked
  loop
    select * into s from public.notification_settings ns where ns.user_id = r.user_id;
    if not found then
      s.quiet_enabled := true; s.quiet_start := '23:00'; s.quiet_end := '07:00'; s.language := 'en';
    end if;

    v_exempt := r.category in ('reminders', 'account');
    v_quiet := s.quiet_enabled and case
      when s.quiet_start = s.quiet_end then false
      when s.quiet_start < s.quiet_end then v_now >= s.quiet_start and v_now < s.quiet_end
      else v_now >= s.quiet_start or v_now < s.quiet_end
    end;

    select count(*) into v_sent from public.notifications n2
    where n2.user_id = r.user_id and n2.pushed_at >= v_day
      and n2.category not in ('reminders', 'account');

    select array_agg(t.token order by t.updated_at desc) into v_tokens
    from public.push_tokens t where t.user_id = r.user_id;

    if (v_quiet and not v_exempt) or (v_sent >= 8 and not v_exempt) or v_tokens is null then
      update public.notifications set push_due_at = null where notifications.id = r.id;
      continue;
    end if;

    update public.notifications set push_due_at = null, pushed_at = now() where notifications.id = r.id;

    id := r.id; user_id := r.user_id; type := r.type; category := r.category;
    title := r.title; body := coalesce(r.body, r.message); data := coalesce(r.data, '{}'::jsonb);
    count := r.count; language := s.language; group_key := r.group_key; tokens := v_tokens;
    select coalesce(nullif(p.display_name, ''), nullif(p.full_name, ''), p.username)
      into actor_name from public.profiles p where p.id = r.actor_id;
    return next;
  end loop;
end;
$$;

revoke execute on function public.push_take(int) from public, anon, authenticated;

-- ====================================================== comments
create or replace function public.notify_comment()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_actor   uuid := case when coalesce(new.is_anonymous, false) then null else new.user_id end;
  v_snippet text := left(regexp_replace(coalesce(new.body, ''), '\s+', ' ', 'g'), 100);
  v_owner   uuid;
  v_title   text;
  v_data    jsonb;
begin
  if new.post_id is not null then
    select p.user_id, left(coalesce(nullif(p.title, ''), regexp_replace(coalesce(p.body, ''), '\s+', ' ', 'g')), 60)
      into v_owner, v_title
    from public.posts p where p.id = new.post_id and not coalesce(p.is_hidden, false);
    if not found then return new; end if;

    v_data := jsonb_build_object('post_id', new.post_id, 'comment_id', new.id,
                                 'snippet', v_snippet, 'post_title', v_title);

    if v_owner is not null and v_owner <> new.user_id then
      insert into public.notifications (user_id, actor_id, type, title, body, data, group_key)
      values (v_owner, v_actor, 'comment', 'New comment on your post', v_snippet, v_data,
              'comment:post:' || new.post_id);
    end if;

    insert into public.notifications (user_id, actor_id, type, title, body, data, group_key)
    select distinct c.user_id, v_actor, 'also_commented',
           'New comment on a post you commented on', v_snippet, v_data,
           'also:post:' || new.post_id
    from (select distinct user_id from public.comments
          where post_id = new.post_id and id <> new.id and user_id is not null
          limit 100) c
    where c.user_id <> new.user_id and c.user_id is distinct from v_owner;

  elsif new.event_id is not null then
    select e.organizer_id, e.title into v_owner, v_title
    from public.events e where e.id = new.event_id;
    if v_owner is not null and v_owner <> new.user_id then
      insert into public.notifications (user_id, actor_id, type, title, body, data, group_key)
      values (v_owner, v_actor, 'comment', 'New comment on your event', v_snippet,
              jsonb_build_object('event_id', new.event_id, 'comment_id', new.id,
                                 'snippet', v_snippet, 'event_title', v_title),
              'comment:event:' || new.event_id);
    end if;
  end if;
  return new;
exception when others then
  return new; -- never block the comment itself
end;
$$;

drop trigger if exists trg_notify_comment on public.comments;
create trigger trg_notify_comment
after insert on public.comments
for each row execute function public.notify_comment();

-- ====================================================== form answers
create or replace function public.notify_form_answer()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_title text;
  v_event uuid;
begin
  -- Entered by the organiser on someone's behalf: nothing new to them.
  if new.entered_by is not null then return new; end if;

  select coalesce(f.owner_id, e.organizer_id), f.title, f.event_id
    into v_owner, v_title, v_event
  from public.event_forms f
  left join public.events e on e.id = f.event_id
  where f.id = new.form_id;

  if v_owner is null or v_owner is not distinct from new.user_id then return new; end if;

  insert into public.notifications (user_id, actor_id, type, title, body, data, group_key)
  values (v_owner, null, 'form_answer', 'New answer to your form', v_title,
          jsonb_build_object('form_id', new.form_id, 'event_id', v_event,
                             'form_title', v_title,
                             'who', coalesce((select coalesce(nullif(p.display_name, ''), p.username)
                                              from public.profiles p where p.id = new.user_id),
                                             new.guest_name)),
          'form:' || new.form_id);
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_form_answer on public.form_responses;
create trigger trg_notify_form_answer
after insert on public.form_responses
for each row execute function public.notify_form_answer();

-- ====================================================== event joins
create or replace function public.notify_event_join()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_title text;
begin
  select e.organizer_id, e.title into v_owner, v_title
  from public.events e where e.id = new.event_id;
  if v_owner is null or v_owner = new.user_id then return new; end if;

  insert into public.notifications (user_id, actor_id, type, title, body, data, group_key)
  values (v_owner, new.user_id, 'event_join', 'Someone joined your event', v_title,
          jsonb_build_object('event_id', new.event_id, 'event_title', v_title),
          'join:' || new.event_id);
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_event_join on public.event_participants;
create trigger trg_notify_event_join
after insert on public.event_participants
for each row execute function public.notify_event_join();

-- ====================================================== event changed / cancelled
create or replace function public.notify_event_changed()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.cancelled_at is not null then return new; end if;
  if new.start_datetime is not distinct from old.start_datetime
     and new.location is not distinct from old.location then
    return new;
  end if;
  -- Past events: nobody needs to know.
  if coalesce(new.start_datetime, old.start_datetime) < now() then return new; end if;

  insert into public.notifications (user_id, actor_id, type, title, body, data, group_key)
  select ep.user_id, new.organizer_id, 'event_changed', 'Event changed: ' || new.title,
         case when new.start_datetime is distinct from old.start_datetime
              then 'New time' else 'New place: ' || coalesce(new.location, '') end,
         jsonb_build_object('event_id', new.id, 'event_title', new.title,
                            'start', new.start_datetime, 'old_start', old.start_datetime,
                            'location', new.location, 'old_location', old.location),
         'changed:' || new.id
  from public.event_participants ep
  where ep.event_id = new.id and ep.user_id is distinct from new.organizer_id;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_event_changed on public.events;
create trigger trg_notify_event_changed
after update of start_datetime, location on public.events
for each row execute function public.notify_event_changed();

create or replace function public.notify_event_cancelled()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if old.cancelled_at is null and new.cancelled_at is not null then
    insert into public.notifications (user_id, actor_id, type, title, body, data)
    select ep.user_id,
           new.organizer_id,
           'event_cancelled',
           'Event cancelled',
           format('"%s" has been cancelled by the organiser.', new.title),
           jsonb_build_object('event_id', new.id, 'event_title', new.title)
    from public.event_participants ep
    where ep.event_id = new.id
      and ep.user_id is distinct from new.organizer_id;
  end if;
  return new;
end;
$$;

-- ====================================================== new events (opt-in)
create or replace function public.notify_new_event()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, actor_id, type, title, body, data)
  select p.id, new.organizer_id, 'new_event',
         'New event: ' || new.title,
         coalesce(new.location, ''),
         jsonb_build_object('event_id', new.id, 'event_title', new.title,
                            'start', new.start_datetime, 'location', new.location)
  from public.notification_settings s
  join public.profiles p on p.id = s.user_id
  where p.id is distinct from new.organizer_id
    and s.prefs ->> 'new_events' in ('push', 'bell');
  return new;
exception when others then
  return new; -- never block creating an event
end;
$$;

-- ====================================================== reminders
create table if not exists public.event_reminders_sent (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  sent_at  timestamptz not null default now(),
  primary key (event_id, user_id)
);
alter table public.event_reminders_sent enable row level security;
revoke all on public.event_reminders_sent from public, anon, authenticated;

-- Everyone who joined an event starting within the next 65 minutes, once.
-- (The sender runs every few minutes, sometimes late; 65 covers that.)
create or replace function public.make_event_reminders()
returns int
language plpgsql security definer
set search_path = public
as $$
declare v int;
begin
  with due as (
    insert into public.event_reminders_sent (event_id, user_id)
    select ep.event_id, ep.user_id
    from public.events e
    join public.event_participants ep on ep.event_id = e.id
    where e.start_datetime > now()
      and e.start_datetime <= now() + interval '65 minutes'
      and e.cancelled_at is null
      and ep.user_id is not null
    on conflict do nothing
    returning event_id, user_id
  )
  insert into public.notifications (user_id, actor_id, type, title, body, data)
  select d.user_id, null, 'event_reminder', 'Starting soon: ' || e.title,
         coalesce(e.location, ''),
         jsonb_build_object('event_id', e.id, 'event_title', e.title,
                            'start', e.start_datetime, 'location', e.location)
  from due d join public.events e on e.id = d.event_id;
  get diagnostics v = row_count;
  return v;
end;
$$;

revoke execute on function public.make_event_reminders() from public, anon, authenticated;

-- Service role (the sender) keeps execute; on a real project these exist.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.push_take(int) to service_role;
    grant execute on function public.make_event_reminders() to service_role;
    grant select, delete on public.push_tokens to service_role;
  end if;
end $$;
