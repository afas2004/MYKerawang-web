-- Hardens get_listing_contact() (20261019002300_profile_contacts.sql).
-- Without a limit it could be called in a loop over every listing id to
-- harvest every seller's phone number. Now:
--   * at most 20 distinct sellers per viewer per rolling hour (looking a
--     seller up again inside the hour is free);
--   * sold listings reveal nothing (listings.status from 2500).
-- Errors carry a stable code at the start of the message so the app can
-- show a friendly text: 'rate_limited' / 'listing_sold'.

create index if not exists contact_reveals_viewer_time_idx
  on public.contact_reveals (viewer_id, revealed_at desc);

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
  v_status text;
  v_recent int;
begin
  if auth.uid() is null then
    raise exception 'Login required' using errcode = '42501';
  end if;

  select l.seller_id, l.status into v_seller, v_status
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    return; -- no such listing: nothing to reveal
  end if;

  if v_seller <> auth.uid() then
    if v_status = 'sold' then
      raise exception 'listing_sold: this listing has been sold'
        using errcode = 'P0001';
    end if;

    -- Serialise this viewer's lookups so parallel calls can't all pass
    -- the check before any of them is logged.
    perform pg_advisory_xact_lock(hashtext('contact_reveal:' || auth.uid()::text));

    select count(distinct r.seller_id) into v_recent
    from public.contact_reveals r
    where r.viewer_id = auth.uid()
      and r.revealed_at > now() - interval '1 hour'
      and r.seller_id <> v_seller;

    if v_recent >= 20 then
      raise exception 'rate_limited: too many contact requests, try again later'
        using errcode = 'P0001';
    end if;

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
