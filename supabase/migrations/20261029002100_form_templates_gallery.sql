-- The form template gallery.
--
-- 20261029001100 let anyone make a form, but the only starting points were a
-- blank page and the KI report survey. This adds a catalogue students actually
-- reach for â€” registration, RSVP, sign-ups, orders, feedback, campus reports â€”
-- shown as a searchable grid (/forms/new), each template in English and Malay.
--
-- Shape:
--   form_templates        + intro_ms, description(_ms), category
--   form_template_fields  + label_ms, help_ms, options_ms
--   form_template_gallery()   the catalogue with every question, for the grid
--                             and the preview (questions are not secret, so
--                             guests may read it too)
--   create_standalone_form(title, club, template, lang)
--                             copies the questions in the caller's language
--
-- Categories: events Â· signups Â· feedback Â· orders Â· campus Â· academic. The
-- client owns their names and colours.
--
-- Templates seeded here are owned by this file: their questions are replaced
-- on every run. Forms already made from them are copies and never change.
--
-- Re-runnable: the test harness applies every migration twice.

-- ====================================================== columns

alter table public.form_templates
  add column if not exists intro_ms       text,
  add column if not exists description    text,
  add column if not exists description_ms text,
  add column if not exists category       text not null default 'events';

alter table public.form_templates drop constraint if exists form_templates_category_valid;
alter table public.form_templates add constraint form_templates_category_valid
  check (category in ('events','signups','feedback','orders','campus','academic'));

alter table public.form_template_fields
  add column if not exists label_ms   text,
  add column if not exists help_ms    text,
  add column if not exists options_ms jsonb;

-- ====================================================== the KI survey

update public.form_templates set
  category       = 'events',
  sort           = 10,
  description    = 'The HEP report survey: 7 KI elements before and after, plus programme feedback. Gives S1, S2 and S3.',
  description_ms = 'Borang laporan HEP: 7 elemen KI sebelum dan selepas, serta maklum balas program. Menghasilkan S1, S2 dan S3.'
where slug = 'ki';

-- ====================================================== the catalogue

insert into public.form_templates
  (slug, name, name_ms, intro, intro_ms, description, description_ms, category, source, sort)
values
  ('event_registration', 'Event registration', 'Pendaftaran acara', 'Register for the event below. We only use your details for this event.', 'Daftar untuk acara di bawah. Butiran anda hanya digunakan untuk acara ini.',
   'Names, matric numbers and contacts of everyone joining.', 'Nama, nombor matrik dan nombor telefon semua peserta.', 'events', 'official', 20),
  ('rsvp', 'RSVP', 'RSVP', 'Let us know if you can make it.', 'Beritahu kami jika anda boleh hadir.',
   'Find out who is coming, and how many.', 'Ketahui siapa yang akan hadir, dan berapa ramai.', 'events', 'official', 30),
  ('competition_team', 'Competition team registration', 'Pendaftaran pasukan pertandingan', 'One form per team. The leader fills it in.', 'Satu borang bagi setiap pasukan. Ketua pasukan yang mengisi.',
   'Team name, leader and members for a contest.', 'Nama pasukan, ketua dan ahli untuk pertandingan.', 'events', 'official', 40),
  ('club_membership', 'Club membership application', 'Permohonan keahlian kelab', 'Thanks for your interest in joining us!', 'Terima kasih kerana berminat menyertai kami!',
   'Recruit new members and see what they want to do.', 'Rekrut ahli baharu dan ketahui minat mereka.', 'signups', 'official', 10),
  ('volunteer_signup', 'Volunteer sign-up', 'Pendaftaran sukarelawan', 'Thank you for volunteering!', 'Terima kasih kerana menjadi sukarelawan!',
   'Who can help, when, and with what.', 'Siapa boleh membantu, bila, dan dalam apa.', 'signups', 'official', 20),
  ('contact_info', 'Contact information', 'Maklumat hubungan', null, null,
   'A simple list of names and ways to reach people.', 'Senarai ringkas nama dan cara untuk dihubungi.', 'signups', 'official', 30),
  ('study_group', 'Study group sign-up', 'Pendaftaran kumpulan belajar', null, null,
   'Match people by course, time and place.', 'Padankan pelajar mengikut kursus, masa dan tempat.', 'academic', 'official', 10),
  ('class_feedback', 'Class feedback', 'Maklum balas kelas', 'Your answers help make the class better.', 'Jawapan anda membantu memperbaik kelas ini.',
   'Ratings and comments on a class or tutorial.', 'Penilaian dan komen tentang kelas atau tutorial.', 'academic', 'official', 20),
  ('event_feedback', 'Event feedback', 'Maklum balas acara', 'Thanks for coming! Tell us how it went.', 'Terima kasih kerana hadir! Kongsi pendapat anda.',
   'How did it go? Ratings for content, venue and food.', 'Bagaimana acara itu? Penilaian pengisian, tempat dan makanan.', 'feedback', 'official', 10),
  ('suggestion_box', 'Suggestion box', 'Peti cadangan', null, null,
   'Ideas and complaints, sorted by topic.', 'Idea dan aduan, mengikut topik.', 'feedback', 'official', 20),
  ('quick_poll', 'Quick poll', 'Undian pantas', null, null,
   'One question, a few options. Done.', 'Satu soalan, beberapa pilihan. Siap.', 'feedback', 'official', 30),
  ('merch_order', 'T-shirt & merch order', 'Tempahan baju & cenderamata', 'Order closes when stock runs out.', 'Tempahan ditutup apabila stok habis.',
   'Sizes, quantities, collection and payment.', 'Saiz, kuantiti, cara ambil dan bayaran.', 'orders', 'official', 10),
  ('food_preorder', 'Food pre-order', 'Tempahan awal makanan', null, null,
   'Take orders before you cook or buy.', 'Ambil tempahan sebelum memasak atau membeli.', 'orders', 'official', 20),
  ('lost_found', 'Lost & found report', 'Laporan barang hilang & dijumpai', null, null,
   'Report something lost or found on campus.', 'Laporkan barang yang hilang atau dijumpai di kampus.', 'campus', 'official', 10),
  ('facility_report', 'Facility problem report', 'Laporan kerosakan kemudahan', null, null,
   'Broken lights, leaks, Wi-Fi — where and how urgent.', 'Lampu rosak, paip bocor, Wi-Fi — di mana dan tahap kecemasan.', 'campus', 'official', 20)
on conflict (slug) do update set
  name = excluded.name, name_ms = excluded.name_ms,
  intro = excluded.intro, intro_ms = excluded.intro_ms,
  description = excluded.description, description_ms = excluded.description_ms,
  category = excluded.category, sort = excluded.sort, active = true;

-- These templates are owned by this migration: their questions are replaced
-- on every run, so a correction here reaches the gallery. Forms already made
-- from them are copies and do not change.
delete from public.form_template_fields
where template_id in (select id from public.form_templates where slug in ('event_registration', 'rsvp', 'competition_team', 'club_membership', 'volunteer_signup', 'contact_info', 'study_group', 'class_feedback', 'event_feedback', 'suggestion_box', 'quick_poll', 'merch_order', 'food_preorder', 'lost_found', 'facility_report'));

insert into public.form_template_fields
  (template_id, kind, label, label_ms, help, help_ms, required, options, options_ms, sort)
select t.id, v.kind, v.label, v.label_ms, v.help, v.help_ms, v.required, v.options, v.options_ms, v.sort
from (values
  ('event_registration', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('event_registration', 'student_id', 'Matric number', 'Nombor matrik', null, null, true, null, null, 20),
  ('event_registration', 'phone', 'Phone number', 'Nombor telefon', null, null, true, null, null, 30),
  ('event_registration', 'short_text', 'Programme & semester', 'Program & semester', null, null, true, null, null, 40),
  ('event_registration', 'single_choice', 'Dietary needs', 'Keperluan pemakanan', null, null, false, '{"choices": ["None", "Vegetarian", "Allergy (tell us below)"]}'::jsonb, '{"choices": ["Tiada", "Vegetarian", "Alahan (nyatakan di bawah)"]}'::jsonb, 50),
  ('event_registration', 'long_text', 'Anything we should know?', 'Ada apa-apa yang perlu kami tahu?', null, null, false, null, null, 60),
  ('event_registration', 'consent', 'I agree my details are used only for this event.', 'Saya bersetuju butiran saya digunakan untuk acara ini sahaja.', null, null, true, null, null, 70),
  ('rsvp', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('rsvp', 'single_choice', 'Will you attend?', 'Adakah anda akan hadir?', null, null, true, '{"choices": ["Yes", "No", "Maybe"]}'::jsonb, '{"choices": ["Ya", "Tidak", "Mungkin"]}'::jsonb, 20),
  ('rsvp', 'number', 'How many people, including you?', 'Berapa orang, termasuk anda?', null, null, false, null, null, 30),
  ('rsvp', 'long_text', 'Message for the organiser', 'Mesej kepada penganjur', null, null, false, null, null, 40),
  ('competition_team', 'short_text', 'Team name', 'Nama pasukan', null, null, true, null, null, 10),
  ('competition_team', 'short_text', 'Team leader', 'Ketua pasukan', null, null, true, null, null, 20),
  ('competition_team', 'student_id', 'Leader''s matric number', 'Nombor matrik ketua', null, null, true, null, null, 30),
  ('competition_team', 'phone', 'Leader''s phone number', 'Nombor telefon ketua', null, null, true, null, null, 40),
  ('competition_team', 'long_text', 'Team members (name and matric, one per line)', 'Ahli pasukan (nama dan matrik, satu setiap baris)', null, null, true, null, null, 50),
  ('competition_team', 'single_choice', 'Category', 'Kategori', null, null, true, '{"choices": ["Beginner", "Open"]}'::jsonb, '{"choices": ["Pemula", "Terbuka"]}'::jsonb, 60),
  ('competition_team', 'consent', 'We have read the competition rules.', 'Kami telah membaca peraturan pertandingan.', null, null, true, null, null, 70),
  ('club_membership', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('club_membership', 'student_id', 'Matric number', 'Nombor matrik', null, null, true, null, null, 20),
  ('club_membership', 'phone', 'Phone number', 'Nombor telefon', null, null, true, null, null, 30),
  ('club_membership', 'email', 'Email', 'E-mel', null, null, false, null, null, 40),
  ('club_membership', 'short_text', 'Programme & semester', 'Program & semester', null, null, true, null, null, 50),
  ('club_membership', 'multi_choice', 'Which areas interest you?', 'Bidang yang anda minati?', null, null, false, '{"choices": ["Events", "Publicity & design", "Logistics", "Finance", "Technical"]}'::jsonb, '{"choices": ["Acara", "Publisiti & reka bentuk", "Logistik", "Kewangan", "Teknikal"]}'::jsonb, 60),
  ('club_membership', 'long_text', 'Why do you want to join?', 'Mengapa anda mahu menyertai?', null, null, false, null, null, 70),
  ('volunteer_signup', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('volunteer_signup', 'phone', 'Phone number', 'Nombor telefon', null, null, true, null, null, 20),
  ('volunteer_signup', 'multi_choice', 'When are you free?', 'Bila anda lapang?', null, null, true, '{"choices": ["Weekday mornings", "Weekday evenings", "Weekends"]}'::jsonb, '{"choices": ["Pagi hari bekerja", "Petang hari bekerja", "Hujung minggu"]}'::jsonb, 30),
  ('volunteer_signup', 'multi_choice', 'What can you help with?', 'Apa yang anda boleh bantu?', null, null, false, '{"choices": ["Setting up", "Registration desk", "Photography", "Clean-up"]}'::jsonb, '{"choices": ["Persiapan tempat", "Kaunter pendaftaran", "Fotografi", "Pembersihan"]}'::jsonb, 40),
  ('volunteer_signup', 'single_choice', 'T-shirt size', 'Saiz baju', null, null, false, '{"choices": ["XS", "S", "M", "L", "XL", "XXL"]}'::jsonb, '{"choices": ["XS", "S", "M", "L", "XL", "XXL"]}'::jsonb, 50),
  ('contact_info', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('contact_info', 'student_id', 'Matric number', 'Nombor matrik', null, null, false, null, null, 20),
  ('contact_info', 'phone', 'Phone number', 'Nombor telefon', null, null, true, null, null, 30),
  ('contact_info', 'email', 'Email', 'E-mel', null, null, false, null, null, 40),
  ('contact_info', 'short_text', 'Block & room', 'Blok & bilik', null, null, false, null, null, 50),
  ('study_group', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('study_group', 'short_text', 'Course code', 'Kod kursus', null, null, true, null, null, 20),
  ('study_group', 'multi_choice', 'Preferred times', 'Masa pilihan', null, null, true, '{"choices": ["Weekday evenings", "Weekend mornings", "Weekend evenings"]}'::jsonb, '{"choices": ["Petang hari bekerja", "Pagi hujung minggu", "Petang hujung minggu"]}'::jsonb, 30),
  ('study_group', 'single_choice', 'Where?', 'Di mana?', null, null, false, '{"choices": ["Library", "Online", "Residential college"]}'::jsonb, '{"choices": ["Perpustakaan", "Dalam talian", "Kolej kediaman"]}'::jsonb, 40),
  ('study_group', 'rating', 'How confident are you with this course?', 'Sejauh mana anda yakin dengan kursus ini?', null, null, false, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 50),
  ('class_feedback', 'short_text', 'Course code', 'Kod kursus', null, null, true, null, null, 10),
  ('class_feedback', 'rating', 'The lessons were clear', 'Pengajaran jelas', null, null, true, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 20),
  ('class_feedback', 'rating', 'The pace was right', 'Kadar pengajaran sesuai', null, null, true, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 30),
  ('class_feedback', 'rating', 'I would recommend this class', 'Saya mengesyorkan kelas ini', null, null, true, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 40),
  ('class_feedback', 'long_text', 'What worked well?', 'Apa yang baik?', null, null, false, null, null, 50),
  ('class_feedback', 'long_text', 'What could be better?', 'Apa yang boleh diperbaik?', null, null, false, null, null, 60),
  ('event_feedback', 'rating', 'Overall, how was the event?', 'Secara keseluruhan, bagaimana acara ini?', null, null, true, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 10),
  ('event_feedback', 'rating', 'Content', 'Pengisian', null, null, false, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 20),
  ('event_feedback', 'rating', 'Venue', 'Tempat', null, null, false, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 30),
  ('event_feedback', 'rating', 'Food', 'Makanan', null, null, false, '{"min": 1, "max": 5}'::jsonb, '{"min": 1, "max": 5}'::jsonb, 40),
  ('event_feedback', 'single_choice', 'Would you come again?', 'Adakah anda akan datang lagi?', null, null, false, '{"choices": ["Yes", "No", "Maybe"]}'::jsonb, '{"choices": ["Ya", "Tidak", "Mungkin"]}'::jsonb, 50),
  ('event_feedback', 'long_text', 'Suggestions', 'Cadangan', null, null, false, null, null, 60),
  ('suggestion_box', 'single_choice', 'About', 'Berkenaan', null, null, true, '{"choices": ["Facilities", "Activities", "Food", "Safety", "Other"]}'::jsonb, '{"choices": ["Kemudahan", "Aktiviti", "Makanan", "Keselamatan", "Lain-lain"]}'::jsonb, 10),
  ('suggestion_box', 'long_text', 'Your suggestion', 'Cadangan anda', null, null, true, null, null, 20),
  ('suggestion_box', 'email', 'Email (only if you want a reply)', 'E-mel (jika mahu balasan)', null, null, false, null, null, 30),
  ('quick_poll', 'single_choice', 'Your question here', 'Soalan anda di sini', null, null, true, '{"choices": ["Option 1", "Option 2", "Option 3"]}'::jsonb, '{"choices": ["Pilihan 1", "Pilihan 2", "Pilihan 3"]}'::jsonb, 10),
  ('quick_poll', 'long_text', 'Anything to add?', 'Ada apa-apa untuk ditambah?', null, null, false, null, null, 20),
  ('merch_order', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('merch_order', 'phone', 'Phone number', 'Nombor telefon', null, null, true, null, null, 20),
  ('merch_order', 'single_choice', 'Size', 'Saiz', null, null, true, '{"choices": ["XS", "S", "M", "L", "XL", "XXL"]}'::jsonb, '{"choices": ["XS", "S", "M", "L", "XL", "XXL"]}'::jsonb, 30),
  ('merch_order', 'number', 'Quantity', 'Kuantiti', null, null, true, null, null, 40),
  ('merch_order', 'single_choice', 'Collection', 'Cara ambil', null, null, true, '{"choices": ["Pick up at the club booth", "Deliver to my college"]}'::jsonb, '{"choices": ["Ambil di gerai kelab", "Hantar ke kolej saya"]}'::jsonb, 50),
  ('merch_order', 'single_choice', 'Payment', 'Bayaran', null, null, true, '{"choices": ["Cash on pick-up", "Online transfer (we''ll send details)"]}'::jsonb, '{"choices": ["Tunai semasa ambil", "Pindahan dalam talian (butiran akan dihantar)"]}'::jsonb, 60),
  ('food_preorder', 'short_text', 'Full name', 'Nama penuh', null, null, true, null, null, 10),
  ('food_preorder', 'phone', 'Phone number', 'Nombor telefon', null, null, true, null, null, 20),
  ('food_preorder', 'short_text', 'Block & room', 'Blok & bilik', null, null, true, null, null, 30),
  ('food_preorder', 'multi_choice', 'What would you like?', 'Apa yang anda mahu?', null, null, true, '{"choices": ["Item 1", "Item 2", "Item 3"]}'::jsonb, '{"choices": ["Item 1", "Item 2", "Item 3"]}'::jsonb, 40),
  ('food_preorder', 'number', 'Quantity', 'Kuantiti', null, null, true, null, null, 50),
  ('food_preorder', 'date', 'Delivery date', 'Tarikh penghantaran', null, null, true, null, null, 60),
  ('food_preorder', 'long_text', 'Notes (spicy, no onion…)', 'Nota (pedas, tanpa bawang…)', null, null, false, null, null, 70),
  ('lost_found', 'single_choice', 'I have…', 'Saya telah…', null, null, true, '{"choices": ["Lost something", "Found something"]}'::jsonb, '{"choices": ["Kehilangan barang", "Menjumpai barang"]}'::jsonb, 10),
  ('lost_found', 'short_text', 'What is it?', 'Apa barangnya?', null, null, true, null, null, 20),
  ('lost_found', 'short_text', 'Where?', 'Di mana?', null, null, true, null, null, 30),
  ('lost_found', 'date', 'When?', 'Bila?', null, null, false, null, null, 40),
  ('lost_found', 'long_text', 'Description (colour, brand, marks)', 'Penerangan (warna, jenama, tanda)', null, null, false, null, null, 50),
  ('lost_found', 'phone', 'Contact number', 'Nombor untuk dihubungi', null, null, true, null, null, 60),
  ('facility_report', 'short_text', 'Block & room, or place', 'Blok & bilik, atau tempat', null, null, true, null, null, 10),
  ('facility_report', 'single_choice', 'Problem', 'Masalah', null, null, true, '{"choices": ["Electrical", "Plumbing", "Furniture", "Wi-Fi", "Cleanliness", "Other"]}'::jsonb, '{"choices": ["Elektrik", "Paip", "Perabot", "Wi-Fi", "Kebersihan", "Lain-lain"]}'::jsonb, 20),
  ('facility_report', 'long_text', 'What happened?', 'Apa yang berlaku?', null, null, true, null, null, 30),
  ('facility_report', 'single_choice', 'How urgent?', 'Tahap kecemasan?', null, null, true, '{"choices": ["Can wait", "Soon", "Urgent"]}'::jsonb, '{"choices": ["Boleh tunggu", "Segera", "Sangat segera"]}'::jsonb, 40),
  ('facility_report', 'phone', 'Contact number', 'Nombor untuk dihubungi', null, null, false, null, null, 50)
) as v(slug, kind, label, label_ms, help, help_ms, required, options, options_ms, sort)
join public.form_templates t on t.slug = v.slug;


-- ====================================================== reading the gallery

create or replace function public.form_template_gallery()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'slug', t.slug,
           'name', t.name,
           'name_ms', t.name_ms,
           'description', t.description,
           'description_ms', t.description_ms,
           'category', t.category,
           'fields', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'kind', f.kind, 'label', f.label, 'label_ms', f.label_ms,
                      'required', f.required,
                      'choices', f.options -> 'choices',
                      'choices_ms', f.options_ms -> 'choices')
                    order by f.sort)
             from public.form_template_fields f where f.template_id = t.id), '[]'::jsonb))
         order by t.sort, t.name), '[]'::jsonb)
  from public.form_templates t
  where t.active;
$$;

revoke execute on function public.form_template_gallery() from public;
grant  execute on function public.form_template_gallery() to anon, authenticated;

-- ====================================================== creating, in a language

-- Same rules as 001100's three-argument version, which this replaces: a
-- fourth argument with a default would make every three-argument call
-- ambiguous between the two.
drop function if exists public.create_standalone_form(text, uuid, text);

create or replace function public.create_standalone_form(
  p_title         text default null,
  p_club_id       uuid default null,
  p_template_slug text default null,
  p_lang          text default 'en'
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_ms   boolean := coalesce(p_lang, 'en') = 'ms';
  v_tpl  public.form_templates;
  v_form uuid;
  v_n    int;
begin
  if v_uid is null then
    raise exception 'FORM:login_required' using errcode = '42501';
  end if;

  if p_club_id is not null and not public.can_act_as_club(p_club_id) then
    raise exception 'FORM:not_allowed' using errcode = '42501';
  end if;

  select count(*) into v_n from public.event_forms
  where owner_id = v_uid and event_id is null and status <> 'closed';
  if v_n >= 10 then
    raise exception 'FORM:too_many' using errcode = 'P0001';
  end if;

  if p_template_slug is not null then
    select * into v_tpl from public.form_templates
    where slug = p_template_slug and active;
    if not found then
      raise exception 'FORM:no_template' using errcode = 'P0001';
    end if;
  end if;

  insert into public.event_forms (event_id, owner_id, club_id, template_id,
                                  title, intro, created_by)
  values (null, v_uid, p_club_id, v_tpl.id,
          left(coalesce(nullif(trim(p_title), ''),
                        case when v_ms then v_tpl.name_ms end,
                        v_tpl.name,
                        case when v_ms then 'Borang tanpa tajuk' else 'Untitled form' end), 120),
          coalesce(case when v_ms then v_tpl.intro_ms end, v_tpl.intro),
          v_uid)
  returning id into v_form;

  if v_tpl.id is not null then
    insert into public.form_fields
      (form_id, kind, label, help, required, options, analysis, ki_code, sort)
    select v_form, f.kind,
           coalesce(case when v_ms then f.label_ms end, f.label),
           coalesce(case when v_ms then f.help_ms end, f.help),
           f.required,
           coalesce(case when v_ms then f.options_ms end, f.options),
           f.analysis, f.ki_code, f.sort
    from public.form_template_fields f
    where f.template_id = v_tpl.id
    order by f.sort;
  end if;

  return v_form;
end;
$$;

revoke execute on function public.create_standalone_form(text, uuid, text, text) from public, anon;
grant  execute on function public.create_standalone_form(text, uuid, text, text) to authenticated;

-- ====================================================== the event editor's list

-- The event form chooser offers report surveys only (templates whose
-- questions feed S1/S2/S3); the general catalogue lives in the gallery.
create or replace function public.form_templates_list()
returns table (slug text, name text, name_ms text, intro text, field_count bigint)
language sql security definer stable
set search_path = public
as $$
  select t.slug, t.name, t.name_ms, t.intro,
         (select count(*) from public.form_template_fields f where f.template_id = t.id)
  from public.form_templates t
  where t.active
    and exists (select 1 from public.form_template_fields f
                where f.template_id = t.id and f.analysis is not null)
  order by t.sort, t.name;
$$;
