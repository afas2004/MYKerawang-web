-- Content categories become data instead of three hardcoded lists.
--
--   content_categories   one row per topic, per kind (event | listing)
--   events.categories    text[] of slugs, multi-select, max 5
--   listings.categories  text[] of slugs, multi-select, max 5
--
-- Announcement categories (kolej/jpk/club/event/general) deliberately stay
-- a fixed set: they decide who may announce and which badge the post
-- carries, so an admin must not be able to invent one.
--
-- Slugs are lowercase ASCII and are what content stores; names are what
-- people see. Renaming a slug while it is in use is refused, because it
-- would orphan every post using it.
--
-- Re-runnable.

create table if not exists public.content_categories (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('event','listing')),
  slug       text not null check (slug ~ '^[a-z0-9][a-z0-9-]{1,29}$'),
  name_en    text not null check (length(btrim(name_en)) between 2 and 60),
  name_ms    text,
  sort       int not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists content_categories_kind_slug
  on public.content_categories (kind, lower(slug));

alter table public.content_categories enable row level security;

drop policy if exists "content_categories_select_anon" on public.content_categories;
create policy "content_categories_select_anon" on public.content_categories
for select to anon using (active);

drop policy if exists "content_categories_select" on public.content_categories;
create policy "content_categories_select" on public.content_categories
for select to authenticated using (active or public.is_admin());

revoke all on public.content_categories from anon, authenticated;
grant select on public.content_categories to anon, authenticated;

-- ====================================================== seed: events
insert into public.content_categories (kind, slug, name_en, name_ms, sort) values
  ('event','academic','Academic','Akademik',10),
  ('event','lecture','Lecture','Kuliah',20),
  ('event','seminar','Seminar','Seminar',30),
  ('event','workshop','Workshop','Bengkel',40),
  ('event','training','Training','Latihan',50),
  ('event','forum','Forum','Forum',60),
  ('event','conference','Conference','Konferens',70),
  ('event','career','Career','Kerjaya',80),
  ('event','internship','Internship','Latihan industri',90),
  ('event','entrepreneurship','Entrepreneurship','Keusahawanan',100),
  ('event','business','Business','Perniagaan',110),
  ('event','technology','Technology','Teknologi',120),
  ('event','ai-data','AI & Data','AI & Data',130),
  ('event','coding','Coding','Pengekodan',140),
  ('event','design','Design','Reka bentuk',150),
  ('event','media','Media','Media',160),
  ('event','photography','Photography','Fotografi',170),
  ('event','video','Video','Video',180),
  ('event','music','Music','Muzik',190),
  ('event','theatre','Theatre','Teater',200),
  ('event','dance','Dance','Tarian',210),
  ('event','arts','Arts','Seni',220),
  ('event','culture','Culture','Budaya',230),
  ('event','heritage','Heritage','Warisan',240),
  ('event','language','Language','Bahasa',250),
  ('event','debate','Debate','Debat',260),
  ('event','public-speaking','Public speaking','Pengucapan awam',270),
  ('event','leadership','Leadership','Kepimpinan',280),
  ('event','volunteering','Volunteering','Kesukarelawanan',290),
  ('event','community-service','Community service','Khidmat masyarakat',300),
  ('event','fundraising','Fundraising','Pengumpulan dana',310),
  ('event','charity','Charity','Amal',320),
  ('event','environment','Environment','Alam sekitar',330),
  ('event','sustainability','Sustainability','Kelestarian',340),
  ('event','health','Health','Kesihatan',350),
  ('event','mental-health','Mental health','Kesihatan mental',360),
  ('event','sports','Sports','Sukan',370),
  ('event','tournament','Tournament','Kejohanan',380),
  ('event','esports','E-sports','E-sukan',390),
  ('event','recreation','Recreation','Rekreasi',400),
  ('event','outdoor','Outdoor','Aktiviti luar',410),
  ('event','religious','Religious','Keagamaan',420),
  ('event','quran','Quran','Al-Quran',430),
  ('event','iftar','Iftar','Iftar',440),
  ('event','qurban','Qurban','Korban',450),
  ('event','bazaar','Bazaar','Bazar',460),
  ('event','carnival','Carnival','Karnival',470),
  ('event','exhibition','Exhibition','Pameran',480),
  ('event','networking','Networking','Networking',490),
  ('event','alumni','Alumni','Alumni',500),
  ('event','international','International','Antarabangsa',510),
  ('event','orientation','Orientation','Orientasi',520),
  ('event','club-recruitment','Club recruitment','Recruitment kelab',530),
  ('event','competition','Competition','Pertandingan',540),
  ('event','hackathon','Hackathon','Hackathon',550),
  ('event','cultural-night','Cultural night','Malam kebudayaan',560)
on conflict (kind, lower(slug)) do nothing;

-- ====================================================== seed: listings
insert into public.content_categories (kind, slug, name_en, name_ms, sort) values
  ('listing','electronics','Electronics','Elektronik',10),
  ('listing','phones','Phones & tablets','Telefon & tablet',20),
  ('listing','computers','Computers','Komputer',30),
  ('listing','accessories','Accessories','Aksesori',40),
  ('listing','books','Books & notes','Buku & nota',50),
  ('listing','stationery','Stationery','Alat tulis',60),
  ('listing','furniture','Furniture','Perabot',70),
  ('listing','room','Room & dorm','Bilik & asrama',80),
  ('listing','kitchen','Kitchen','Dapur',90),
  ('listing','clothing','Clothing','Pakaian',100),
  ('listing','traditional-wear','Traditional wear','Pakaian tradisional',110),
  ('listing','shoes','Shoes','Kasut',120),
  ('listing','bags','Bags','Beg',130),
  ('listing','sports-gear','Sports gear','Peralatan sukan',140),
  ('listing','bicycles','Bicycles','Basikal',150),
  ('listing','vehicles','Vehicles','Kenderaan',160),
  ('listing','food','Food & drinks','Makanan & minuman',170),
  ('listing','homemade-food','Homemade food','Makanan buatan sendiri',180),
  ('listing','services','Services','Perkhidmatan',190),
  ('listing','tickets','Tickets','Tiket',200),
  ('listing','instruments','Musical instruments','Alat muzik',210),
  ('listing','arts-crafts','Arts & crafts','Seni & kraf',220),
  ('listing','gaming','Gaming','Permainan',230),
  ('listing','collectibles','Collectibles','Barangan koleksi',240),
  ('listing','plants','Plants','Tumbuhan',250),
  ('listing','others','Others','Lain-lain',260)
on conflict (kind, lower(slug)) do nothing;

-- ====================================================== content columns
alter table public.events   add column if not exists categories text[] not null default '{}';
alter table public.listings add column if not exists categories text[] not null default '{}';

alter table public.events   drop constraint if exists events_categories_max;
alter table public.events   add constraint events_categories_max
  check (cardinality(categories) <= 5);
alter table public.listings drop constraint if exists listings_categories_max;
alter table public.listings add constraint listings_categories_max
  check (cardinality(categories) <= 5);

-- Backfill from what the old single-value columns held. Lowercased to
-- agree with the slug format above.
update public.listings
set categories = array[lower(btrim(category))]
where cardinality(categories) = 0
  and nullif(btrim(coalesce(category, '')), '') is not null;

update public.events
set categories = (
  select array_agg(lower(btrim(t)) order by t)
  from unnest(tags) t
  where nullif(btrim(t), '') is not null)
where cardinality(categories) = 0
  and tags is not null
  and cardinality(tags) > 0;

-- listings.category stays as the primary slug for one release, so the old
-- client and any saved query keep working. The array is the truth.
create or replace function public.sync_listing_primary_category()
returns trigger
language plpgsql
as $$
begin
  if new.categories is not null and cardinality(new.categories) > 0 then
    new.category := new.categories[1];
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_listing_category on public.listings;
create trigger trg_sync_listing_category
before insert or update on public.listings
for each row execute function public.sync_listing_primary_category();

-- ====================================================== admin writes
create or replace function public.admin_upsert_category(
  p_id      uuid,
  p_kind    text,
  p_slug    text,
  p_name_en text,
  p_name_ms text default null,
  p_sort    int  default 0,
  p_active  boolean default true
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_id   uuid;
  v_old  public.content_categories;
begin
  if not public.is_admin() then
    raise exception 'MOD:not_admin' using errcode = 'P0001';
  end if;
  if p_kind not in ('event','listing') then
    raise exception 'CAT:bad_kind' using errcode = 'P0001';
  end if;
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,29}$' then
    raise exception 'CAT:bad_slug' using errcode = 'P0001';
  end if;
  if length(btrim(coalesce(p_name_en, ''))) < 2 then
    raise exception 'CAT:name_required' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.content_categories (kind, slug, name_en, name_ms, sort, active)
    values (p_kind, v_slug, btrim(p_name_en), nullif(btrim(coalesce(p_name_ms, '')), ''), p_sort, p_active)
    on conflict (kind, lower(slug)) do update
      set name_en = excluded.name_en,
          name_ms = excluded.name_ms,
          sort    = excluded.sort,
          active  = excluded.active
    returning id into v_id;
  else
    select * into v_old from public.content_categories where id = p_id;
    if not found then
      raise exception 'CAT:not_found' using errcode = 'P0001';
    end if;

    -- A slug that content already uses must not move.
    if v_slug <> v_old.slug and exists (
         select 1 from public.events e
         where v_old.kind = 'event' and v_old.slug = any (e.categories)
         union all
         select 1 from public.listings l
         where v_old.kind = 'listing' and v_old.slug = any (l.categories)) then
      raise exception 'CAT:slug_in_use' using errcode = 'P0001';
    end if;

    update public.content_categories
    set kind = p_kind,
        slug = v_slug,
        name_en = btrim(p_name_en),
        name_ms = nullif(btrim(coalesce(p_name_ms, '')), ''),
        sort = p_sort,
        active = p_active
    where id = p_id
    returning id into v_id;
  end if;

  perform public.mod_log('category_saved', 'category', v_id::text, null,
    jsonb_build_object('kind', p_kind, 'slug', v_slug, 'active', p_active));
  return v_id;
end;
$$;

create or replace function public.admin_delete_category(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  c public.content_categories;
begin
  if not public.is_admin() then
    raise exception 'MOD:not_admin' using errcode = 'P0001';
  end if;
  select * into c from public.content_categories where id = p_id;
  if not found then
    raise exception 'CAT:not_found' using errcode = 'P0001';
  end if;

  if (c.kind = 'event' and exists (select 1 from public.events e where c.slug = any (e.categories)))
     or (c.kind = 'listing' and exists (select 1 from public.listings l where c.slug = any (l.categories))) then
    raise exception 'CAT:in_use' using errcode = 'P0001';
  end if;

  delete from public.content_categories where id = p_id;
  perform public.mod_log('category_deleted', 'category', p_id::text, null,
    jsonb_build_object('kind', c.kind, 'slug', c.slug));
end;
$$;

revoke execute on function public.admin_upsert_category(uuid, text, text, text, text, int, boolean) from public, anon;
revoke execute on function public.admin_delete_category(uuid) from public, anon;
grant  execute on function public.admin_upsert_category(uuid, text, text, text, text, int, boolean) to authenticated;
grant  execute on function public.admin_delete_category(uuid) to authenticated;
