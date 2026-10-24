-- Beta seed: official club content plus a handful of sample student rows.
--
-- Run once against a clean-ish beta database (see the hide step below).
-- Idempotent: it refuses to run twice.
--
--   * KMI (Kelab Minda Islam) authors three announcements and hosts three
--     upcoming events; one event carries merit and turns attendance on.
--   * A password-less "Demo Pelajar" account authors the sample student
--     posts and market listings. It cannot be logged into (no password,
--     unroutable address).
--
-- Old development content is NOT deleted here: everything existing is
-- expected to be flagged is_hidden = true beforehand, so it stays
-- restorable. That statement lives in the companion cleanup script.

do $$
declare
  v_kmi   uuid;
  v_club  uuid;
  v_demo  uuid;
  v_event uuid;
begin
  if exists (select 1 from public.posts
             where title = 'Pendaftaran ahli KMI sesi 2026/2027 dibuka') then
    raise notice 'beta seed already applied — nothing to do';
    return;
  end if;

  select id into v_kmi  from public.profiles where username = 'kelabmindaislam';
  select id into v_club from public.clubs    where handle   = 'kelabmindaislam';
  if v_kmi is null or v_club is null then
    raise exception 'Seed needs the KMI profile (username kelabmindaislam) and club page';
  end if;

  -- ---------------------------------------------------------------- demo author
  select id into v_demo from auth.users where email = 'demo@mykerawang.local';
  if v_demo is null then
    v_demo := gen_random_uuid();
    insert into auth.users
      (id, instance_id, aud, role, email, email_confirmed_at,
       created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
    values
      (v_demo, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'demo@mykerawang.local', now(), now(), now(),
       '{"provider":"email","providers":["email"],"allow_non_student":true}'::jsonb,
       '{"display_name":"Demo Pelajar"}'::jsonb);
  end if;

  insert into public.profiles (id, username, display_name, role, bio)
  values (v_demo, 'demo', 'Demo Pelajar', 'student',
          'Akaun contoh untuk kandungan demo beta. Bukan orang sebenar.')
  on conflict (id) do update
    set username = excluded.username,
        display_name = excluded.display_name,
        bio = excluded.bio;

  -- ---------------------------------------------------------------- announcements
  insert into public.posts
    (user_id, club_id, is_announcement, announcement_category, title, body,
     publish_at, cover_aspect)
  values
    (v_kmi, v_club, true, 'club',
     'Pendaftaran ahli KMI sesi 2026/2027 dibuka',
     E'Assalamualaikum warga kolej,\n\nKelab Minda Islam (KMI) membuka pendaftaran ahli untuk sesi 2026/2027. Sertai program mingguan, kelas mengaji dan aktiviti khidmat masyarakat kami.\n\nPendaftaran dibuka sehingga 15 November. Sebarang pertanyaan boleh diajukan kepada AJK melalui butang hubungi di halaman kelab.',
     now(), '16:9'),
    (v_kmi, v_club, true, 'club',
     'Jadual program KMI bulan November',
     E'Berikut adalah jadual program KMI untuk bulan November:\n\n• 8 Nov — Kelas mengaji mingguan (Surau Kolej, 8.00 malam)\n• 14 Nov — Malam Apresiasi KMI 2026 (Dewan Kuliah 1)\n• 21 Nov — Bengkel Pengurusan Jenazah (Bilik Seminar 2)\n\nSertai mana-mana program yang terbuka. Kehadiran direkodkan untuk merit.',
     now(), '16:9'),
    (v_kmi, v_club, true, 'club',
     'Kelas mengaji mingguan kembali',
     E'Kelas mengaji KMI kembali setiap malam Rabu, 8.00 malam di Surau Kolej Kediaman. Terbuka kepada semua pelajar — tiada syarat kelayakan.\n\nBawa al-Quran sendiri. Kelas dikendalikan oleh AJK KMI.',
     now(), '16:9');

  -- ---------------------------------------------------------------- events
  insert into public.events
    (organizer_id, club_id, title, description, location,
     start_datetime, end_datetime, categories, audience,
     capacity, fee, merit_offered, merit_note, join_deadline,
     attendance_enabled, is_public)
  values
    (v_kmi, v_club, 'Malam Apresiasi KMI 2026',
     E'Malam apresiasi tahunan KMI: persembahan nasyid, tayangan ringkas aktiviti sepanjang tahun, dan jamuan ringan.\n\nTerbuka kepada semua pelajar kolej. Sila daftar awal kerana tempat terhad.',
     'Dewan Kuliah 1, UiTM Kuala Pilah',
     timestamptz '2026-11-14 20:00+08', timestamptz '2026-11-14 22:30+08',
     array['culture','religious','music'], 'kolej',
     120, 0, true, '2 merit (kokurikulum)',
     timestamptz '2026-11-13 23:59+08', true, true)
  returning id into v_event;
  insert into public.event_contacts (event_id, email)
  values (v_event, 'kmiuitmctkkt2024@gmail.com');

  insert into public.events
    (organizer_id, club_id, title, description, location,
     start_datetime, end_datetime, categories, audience,
     capacity, fee, merit_offered, merit_note, join_deadline,
     attendance_enabled, is_public)
  values
    (v_kmi, v_club, 'Bengkel Pengurusan Jenazah',
     E'Bengkel praktikal pengurusan jenazah: memandikan, mengkafankan, solat dan pengebumian.\n\nDikendalikan bersama AJK KMI. Sijil penyertaan disediakan. Tempat terhad kepada 40 peserta.',
     'Bilik Seminar 2, UiTM Kuala Pilah',
     timestamptz '2026-11-21 09:00+08', timestamptz '2026-11-21 16:00+08',
     array['religious','training'], 'kolej',
     40, 0, true, '2 merit (kokurikulum)',
     timestamptz '2026-11-20 23:59+08', true, true)
  returning id into v_event;
  insert into public.event_contacts (event_id, email)
  values (v_event, 'kmiuitmctkkt2024@gmail.com');

  insert into public.events
    (organizer_id, club_id, title, description, location,
     start_datetime, end_datetime, categories, audience,
     merit_offered, join_deadline, attendance_enabled, is_public)
  values
    (v_kmi, v_club, 'Program Jom Ke Masjid',
     E'Jom solat Subuh berjemaah di Masjid UiTM Kuala Pilah, diikuti tazkirah ringkas dan sarapan bersama.\n\nTerbuka kepada semua pelajar. Tiada pendaftaran diperlukan selain daftar di aplikasi.',
     'Masjid UiTM Kuala Pilah',
     timestamptz '2026-12-05 06:00+08', timestamptz '2026-12-05 08:30+08',
     array['religious','community-service'], 'uitm',
     false, timestamptz '2026-12-04 23:59+08', false, true);

  -- ---------------------------------------------------------------- sample student content
  insert into public.posts (user_id, title, body, is_anonymous, tags)
  values
    (v_demo, 'Mana tempat makan malam paling murah dekat kolej?',
     'Biasa makan di kafe kolej tapi rasa nak try tempat lain. Ada cadangan yang murah dan dekat?', false, '{}'),
    (v_demo, 'Ada sesiapa ambil CSC661 semester ni?',
     'Nak tanya pasal projek akhir. Boleh kongsi idea atau buat study group sekali?', false, '{}'),
    (v_demo, 'Tips study week?',
     'First time nak hadap study week dengan empat paper. Korang study macam mana?', false, '{}'),
    (v_demo, 'Jumpa kad matrik dekat surau',
     'Jumpa sekeping kad matrik di luar surau selepas solat Maghrib. Pemilik boleh hubungi saya untuk ambil semula.', false,
     array['lostfound']);

  insert into public.listings
    (seller_id, title, price, description, condition, categories, meetup, fulfillment_type, is_sold)
  values
    (v_demo, 'Buku Kalkulus Edisi ke-9', 25,
     'Dah habis guna untuk semester lepas. Ada sedikit nota pensel di dalam, muka surat lengkap.',
     'used', array['books'], 'Kolej Kediaman', 'Pickup', false),
    (v_demo, 'Kipas meja (macam baru)', 35,
     'Beli awal semester, jarang guna sebab bilik ada aircond. Ada kotak asal.',
     'like_new', array['room','furniture'], 'Blok B', 'Pickup', false),
    (v_demo, 'Baju kurung labuh saiz M', 45,
     'Pakai sekali untuk majlis keluarga. Warna hitam, tak ada koyak atau kesan.',
     'used', array['traditional-wear','clothing'], 'Kafe kolej', 'Pickup', false);
end $$;
