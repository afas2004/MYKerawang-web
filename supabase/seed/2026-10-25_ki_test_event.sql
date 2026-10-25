-- One finished event to try the KI report on.
--
-- Paste this into the Supabase SQL editor AFTER 20261026007100_event_forms.sql
-- and 20261026008100_event_links_pic.sql. It is idempotent: running it twice
-- creates one event, not two.
--
-- The event is owned by the owner account (or the oldest admin) so it shows the
-- organiser's buttons. If you log in as someone else, change the `role in (...)`
-- line below to that account's email:
--
--   where id = (select id from auth.users where email = 'you@example.com')
--
-- The date is two days ago: the report exists precisely for an event that has
-- ended, so that is what the test should look like.

do $$
declare
  v_owner uuid;
  v_club  uuid;
  v_id    uuid;
  v_start timestamptz := date_trunc('day', now()) - interval '2 days' + interval '9 hours';
begin
  select id into v_owner
  from public.profiles
  where role in ('owner', 'admin')
  order by (role = 'owner') desc, created_at
  limit 1;

  if v_owner is null then
    raise exception 'No owner/admin profile found — set v_owner by hand.';
  end if;

  select id into v_club
  from public.clubs
  where status = 'active'
  order by created_at
  limit 1;

  if exists (select 1 from public.events
             where title = 'Malam Ujian KI' and organizer_id = v_owner) then
    raise notice 'Test event already exists; nothing to do.';
    return;
  end if;

  insert into public.events (
    organizer_id, club_id, title, description, location,
    start_datetime, end_datetime,
    categories, attendance_enabled, join_deadline, capacity,
    fee, audience, merit_offered, merit_note,
    pic, action_links
  ) values (
    v_owner, v_club,
    'Malam Ujian KI',
    E'Program ujian untuk borang KI.\n\n'
    '- Daftar di kaunter\n'
    '- Sesi soal jawab selepas ceramah\n\n'
    'Rujuk **nota** di pautan butang di bawah.',
    'Dewan Kolej Kerawang',
    v_start, v_start + interval '3 hours',
    array['academic', 'seminar']::text[],
    true,                      -- attendance on, so the QR and check-in exist
    v_start,                   -- registration closed when it started
    60,
    0,
    'kolej',
    true,
    '2 merit kokurikulum',
    'Ahmad Fahmi · 012-3456789',
    '[]'::jsonb
  )
  returning id into v_id;

  -- The buttons need the event's id, so they go in a second statement.
  update public.events set action_links = jsonb_build_array(
    jsonb_build_object('label', 'Borang', 'url', '/event/' || v_id || '/form'),
    jsonb_build_object('label', 'Peta', 'url', 'https://www.google.com/maps')
  ) where id = v_id;

  raise notice 'Seeded event % (Malam Ujian KI), owned by %', v_id, v_owner;
end $$;
