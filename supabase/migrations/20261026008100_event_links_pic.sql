-- Events gain the two composer fields they were missing:
--
--   action_links  the same {label,url} buttons an announcement can carry, so an
--                 event can point at a form, a map or a registration page as a
--                 button rather than a bare link in the description
--   pic           the person in charge, a name (the queue also wants tagging
--                 people; that is a later, bigger change)
--
-- Shape is guarded here rather than trusted from the client: at most two
-- buttons, a label that fits, and a url that is either https or an app route.
--
-- Re-runnable.

alter table public.events
  add column if not exists action_links jsonb not null default '[]'::jsonb,
  add column if not exists pic          text;

create or replace function public.events_guard_links()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  link jsonb;
begin
  if new.action_links is null or jsonb_typeof(new.action_links) <> 'array' then
    raise exception 'EVENT:bad_links' using errcode = 'P0001';
  end if;
  if jsonb_array_length(new.action_links) > 2 then
    raise exception 'EVENT:too_many_links' using errcode = 'P0001';
  end if;

  for link in select * from jsonb_array_elements(new.action_links) loop
    if jsonb_typeof(link) <> 'object'
       or coalesce(length(trim(link ->> 'label')), 0) = 0
       or length(link ->> 'label') > 24
       or coalesce(length(trim(link ->> 'url')), 0) = 0
       or length(link ->> 'url') > 500 then
      raise exception 'EVENT:bad_link' using errcode = 'P0001';
    end if;
    if (link ->> 'url') not like 'https://%'
       and (link ->> 'url') not like '/%' then
      raise exception 'EVENT:link_not_https' using errcode = 'P0001';
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_events_guard_links on public.events;
create trigger trg_events_guard_links
before insert or update of action_links on public.events
for each row execute function public.events_guard_links();
