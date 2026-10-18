-- Phone number and payment QR leave public.profiles. Any authenticated
-- user could read them from there (RLS is per row, not per column).
-- They now live in profile_contacts, which only the owner can read. A
-- buyer gets a seller's contact through get_listing_contact(), and only
-- when they tap Contact on a listing.
--
-- APP CONTRACT: clients must stop reading/writing profiles.phone_number
-- and profiles.payment_qr_url before (or together with) this migration.
-- The owner edits their own row in profile_contacts (upsert on user_id).

-- ---------------------------------------------------------- table
create table if not exists public.profile_contacts (
  user_id        uuid primary key references public.profiles(id) on delete cascade,
  phone_number   text,
  payment_qr_url text,
  updated_at     timestamptz not null default now()
);

alter table public.profile_contacts enable row level security;

drop policy if exists "profile_contacts_select_own" on public.profile_contacts;
create policy "profile_contacts_select_own" on public.profile_contacts
for select to authenticated using (user_id = auth.uid());

drop policy if exists "profile_contacts_insert_own" on public.profile_contacts;
create policy "profile_contacts_insert_own" on public.profile_contacts
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "profile_contacts_update_own" on public.profile_contacts;
create policy "profile_contacts_update_own" on public.profile_contacts
for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.profile_contacts from anon;
grant select, insert, update on public.profile_contacts to authenticated;

create or replace function public.touch_profile_contacts()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_profile_contacts on public.profile_contacts;
create trigger trg_touch_profile_contacts
before update on public.profile_contacts
for each row execute function public.touch_profile_contacts();

-- ---------------------------------------------------------- move data
-- Guarded so re-running after the columns are gone is harmless.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'profiles'
               and column_name = 'phone_number') then
    execute $q$
      insert into public.profile_contacts (user_id, phone_number, payment_qr_url)
      select id, nullif(trim(phone_number), ''), payment_qr_url
      from public.profiles
      where nullif(trim(phone_number), '') is not null
         or payment_qr_url is not null
      on conflict (user_id) do update
        set phone_number   = excluded.phone_number,
            payment_qr_url = excluded.payment_qr_url
    $q$;
  end if;
end;
$$;

alter table public.profiles drop column if exists phone_number;
alter table public.profiles drop column if exists payment_qr_url;

-- ---------------------------------------------------------- reveal log
-- Who looked up which seller's contact, for abuse reports. Not readable
-- by clients; admins query it from the dashboard.
create table if not exists public.contact_reveals (
  id          bigint generated always as identity primary key,
  listing_id  uuid not null,
  seller_id   uuid not null,
  viewer_id   uuid not null,
  revealed_at timestamptz not null default now()
);

alter table public.contact_reveals enable row level security;
revoke all on public.contact_reveals from anon, authenticated;

-- ---------------------------------------------------------- RPC
create or replace function public.get_listing_contact(p_listing_id uuid)
returns table (
  phone_number   text,
  payment_qr_url text,
  username       text,
  display_name   text
)
language plpgsql security definer
set search_path = public
as $$
declare
  v_seller uuid;
begin
  if auth.uid() is null then
    raise exception 'Login required' using errcode = '42501';
  end if;

  select l.seller_id into v_seller
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    return; -- no such listing: nothing to reveal
  end if;

  if v_seller <> auth.uid() then
    insert into public.contact_reveals (listing_id, seller_id, viewer_id)
    values (p_listing_id, v_seller, auth.uid());
  end if;

  return query
  select c.phone_number, c.payment_qr_url, p.username, p.display_name
  from public.profiles p
  left join public.profile_contacts c on c.user_id = p.id
  where p.id = v_seller;
end;
$$;

revoke execute on function public.get_listing_contact(uuid) from public, anon;
grant  execute on function public.get_listing_contact(uuid) to authenticated;
