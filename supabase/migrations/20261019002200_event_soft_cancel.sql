-- "Cancel event" used to hard-delete the row, taking its comments and
-- participant list with it and leaving people who joined with nothing.
-- Cancelling now stamps cancelled_at; the row stays readable, marked
-- cancelled. Deleting remains a separate, explicit owner action.

alter table public.events
  add column if not exists cancelled_at timestamptz null;

comment on column public.events.cancelled_at is
  'Set when the organiser cancels. Null = running. Lists should treat a non-null value like an ended event.';

-- Notify everyone who joined when an event is cancelled. Done here, not
-- in the client, so it happens once and doesn't depend on the organiser
-- being allowed to read event_participants or write others' notifications.
-- Written in English: the recipient reads it, and notifications are
-- stored in one language (see the AppStrings.en convention in the app).
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
           'event',
           'Event cancelled',
           format('"%s" has been cancelled by the organiser.', new.title),
           jsonb_build_object('event_id', new.id)
    from public.event_participants ep
    where ep.event_id = new.id
      and ep.user_id is distinct from new.organizer_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_event_cancelled on public.events;
create trigger trg_notify_event_cancelled
after update of cancelled_at on public.events
for each row execute function public.notify_event_cancelled();

-- Nobody can join a cancelled event, whatever the client does.
create or replace function public.block_join_cancelled_event()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.events
             where id = new.event_id and cancelled_at is not null) then
    raise exception 'This event has been cancelled';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_join_cancelled_event on public.event_participants;
create trigger trg_block_join_cancelled_event
before insert on public.event_participants
for each row execute function public.block_join_cancelled_event();
