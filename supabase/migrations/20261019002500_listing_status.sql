-- Listings move from a sold/not-sold boolean to three states:
--   available → reserved (a buyer is arranging it) → sold.
-- status is the source of truth. is_sold is kept in sync by a trigger
-- so readers that still use it (home, search, right rail, profile tabs,
-- the native cache) keep working until they move to status.

alter table public.listings
  add column if not exists status text not null default 'available';

alter table public.listings drop constraint if exists listings_status_valid;
alter table public.listings add constraint listings_status_valid
  check (status in ('available', 'reserved', 'sold'));

update public.listings
set status = case when coalesce(is_sold, false) then 'sold' else 'available' end
where status is distinct from case when coalesce(is_sold, false) then 'sold' else 'available' end
  and status <> 'reserved';

-- Whichever column a client writes, the other follows. Writing status
-- wins when both change.
create or replace function public.sync_listing_status()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'available' and coalesce(new.is_sold, false) then
      new.status := 'sold';
    end if;
  elsif new.status is distinct from old.status then
    null; -- status changed: is_sold follows below
  elsif new.is_sold is distinct from old.is_sold then
    new.status := case
      when coalesce(new.is_sold, false) then 'sold'
      when old.status = 'sold' then 'available'
      else old.status
    end;
  end if;

  new.is_sold := (new.status = 'sold');
  return new;
end;
$$;

drop trigger if exists trg_sync_listing_status on public.listings;
create trigger trg_sync_listing_status
before insert or update on public.listings
for each row execute function public.sync_listing_status();

-- The market list filters by status and sorts by date or price.
create index if not exists listings_status_created_idx
  on public.listings (status, created_at desc);
create index if not exists listings_price_idx
  on public.listings (price);
