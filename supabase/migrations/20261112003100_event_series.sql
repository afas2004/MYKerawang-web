-- Event series and online / hybrid events.
--
-- A weekly class or a run of odd dates is published as a *series*: every
-- date is an ordinary `events` row (its own check-in, attendance, joiners,
-- cancel and deadline), and `event_series` only groups them. Nothing that
-- reads `events` today has to change.
--
-- Only adds: one table, three nullable / defaulted columns on events, a
-- guard trigger. No existing column is rewritten.

-- ------------------------------------------------------------ the series
create table if not exists public.event_series (
  id           uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references public.profiles(id) on delete cascade,
  -- How the dates were made, for the event page's summary line:
  --   {"kind":"weekly","every":1,"weekdays":[4]}   (1 = Monday … 7 = Sunday)
  --   {"kind":"dates"}
  repeat_rule  jsonb not null default '{"kind":"dates"}'::jsonb,
  created_at   timestamptz not null default now()
);

alter table public.event_series drop constraint if exists event_series_rule_shape;
alter table public.event_series add constraint event_series_rule_shape
  check (jsonb_typeof(repeat_rule) = 'object'
         and repeat_rule->>'kind' in ('weekly', 'dates'));

alter table public.event_series enable row level security;

-- Readable by anyone who can read events (guests included): the rows say
-- nothing beyond "these dates belong together".
drop policy if exists "event_series_select" on public.event_series;
create policy "event_series_select" on public.event_series
  for select to anon, authenticated using (true);

drop policy if exists "event_series_insert" on public.event_series;
create policy "event_series_insert" on public.event_series
  for insert to authenticated with check (organizer_id = auth.uid());

drop policy if exists "event_series_delete" on public.event_series;
create policy "event_series_delete" on public.event_series
  for delete to authenticated
  using (organizer_id = auth.uid() or public.is_admin());

revoke all on public.event_series from anon, authenticated;
grant select on public.event_series to anon, authenticated;
grant insert, delete on public.event_series to authenticated;

-- ------------------------------------------------------- events columns
alter table public.events
  add column if not exists series_id     uuid references public.event_series(id) on delete set null,
  add column if not exists location_mode text not null default 'in_person',
  add column if not exists online_url    text;

alter table public.events drop constraint if exists events_location_mode_valid;
alter table public.events add constraint events_location_mode_valid
  check (location_mode in ('in_person', 'online', 'hybrid'));

-- Launched from the event page, so https only (same rule as the buttons).
alter table public.events drop constraint if exists events_online_url_https;
alter table public.events add constraint events_online_url_https
  check (online_url is null
         or (online_url ~* '^https://[^\s]+$' and length(online_url) <= 500));

create index if not exists events_series_idx
  on public.events (series_id, start_datetime) where series_id is not null;

-- ------------------------------------------------------------ the guard
-- A session may only join a series its own organiser made, and a series
-- holds at most 26 dates (about one semester).
create or replace function public.event_series_guard()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_count int;
begin
  if new.series_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.series_id is not distinct from old.series_id then
    return new;
  end if;

  select organizer_id into v_owner from public.event_series where id = new.series_id;
  if v_owner is null or v_owner is distinct from new.organizer_id then
    raise exception 'EVENT:series_not_yours' using errcode = 'P0001';
  end if;

  select count(*) into v_count from public.events where series_id = new.series_id;
  if v_count >= 26 then
    raise exception 'EVENT:series_full' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke execute on function public.event_series_guard() from public, anon, authenticated;

drop trigger if exists trg_event_series_guard on public.events;
create trigger trg_event_series_guard
  before insert or update of series_id on public.events
  for each row execute function public.event_series_guard();

comment on column public.events.series_id is
  'Set when the event is one date of a series (event_series). Each date is a full event of its own.';
comment on column public.events.location_mode is
  'in_person | online | hybrid. online_url holds the meeting link for online and hybrid.';
