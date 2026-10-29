-- Fewer, broader categories.
--
-- The first seed (20261026001100) had 56 event and 26 listing categories,
-- many overlapping (lecture / seminar / forum / conference) and missing
-- whole areas (games, entertainment). This folds them into 17 event and
-- 13 listing categories:
--
--   1. upserts the new list (reusing a slug where one fits, so content
--      already on it needs no change; names are overwritten)
--   2. rewrites events.categories and listings.categories through the map
--      below — deduplicated, first-seen order kept, max 5
--   3. keeps each folded event slug as a hashtag in events.tags, so
--      "hackathon" is not lost when the event moves to Tech
--   4. deactivates (never deletes) the old slugs
--
-- Slugs not in the map — anything an admin added live — are left alone,
-- on content and in the table. listings.category follows categories[1]
-- through trg_sync_listing_category.
--
-- Re-runnable: a second run finds no old slugs on content and changes
-- nothing.

-- ====================================================== the new list
insert into public.content_categories (kind, slug, name_en, name_ms, sort, active) values
  ('event','academic','Talks & academic','Akademik & seminar',10,true),
  ('event','workshop','Workshops & training','Bengkel & latihan',20,true),
  ('event','career','Career & networking','Kerjaya & jaringan',30,true),
  ('event','business','Business & entrepreneurship','Perniagaan & keusahawanan',40,true),
  ('event','technology','Tech','Teknologi',50,true),
  ('event','arts','Arts & creative','Seni & kreatif',60,true),
  ('event','culture','Culture & heritage','Budaya & warisan',70,true),
  ('event','entertainment','Entertainment','Hiburan',80,true),
  ('event','games','Games & e-sports','Permainan & e-sukan',90,true),
  ('event','sports','Sports & outdoor','Sukan & aktiviti luar',100,true),
  ('event','competition','Competitions','Pertandingan',110,true),
  ('event','self-development','Self-development','Pembangunan diri',120,true),
  ('event','volunteering','Volunteering & charity','Sukarelawan & amal',130,true),
  ('event','health','Health & wellbeing','Kesihatan & kesejahteraan',140,true),
  ('event','religious','Religious','Keagamaan',150,true),
  ('event','festivals','Festivals, bazaars & food','Festival, bazar & makanan',160,true),
  ('event','kolej-life','Kolej life','Kehidupan kolej',170,true),

  ('listing','electronics','Electronics','Elektronik',10,true),
  ('listing','books','Books & stationery','Buku & alat tulis',20,true),
  ('listing','room','Room & kitchen','Bilik & dapur',30,true),
  ('listing','clothing','Fashion','Fesyen',40,true),
  ('listing','beauty','Beauty & personal care','Kecantikan & penjagaan diri',50,true),
  ('listing','food','Food & drinks','Makanan & minuman',60,true),
  ('listing','sports-gear','Sports & bicycles','Sukan & basikal',70,true),
  ('listing','vehicles','Vehicles','Kenderaan',80,true),
  ('listing','gaming','Gaming','Permainan video',90,true),
  ('listing','hobbies','Hobbies','Hobi',100,true),
  ('listing','services','Services','Perkhidmatan',110,true),
  ('listing','tickets','Tickets','Tiket',120,true),
  ('listing','others','Others','Lain-lain',130,true)
on conflict (kind, lower(slug)) do update
  set name_en = excluded.name_en,
      name_ms = excluded.name_ms,
      sort    = excluded.sort,
      active  = true;

-- ====================================================== old -> new
drop table if exists pg_temp.category_map;
create temp table category_map (
  kind     text not null,
  old_slug text not null,
  new_slug text not null,
  primary key (kind, old_slug)
);

insert into category_map (kind, old_slug, new_slug) values
  ('event','lecture','academic'),
  ('event','seminar','academic'),
  ('event','forum','academic'),
  ('event','conference','academic'),
  ('event','training','workshop'),
  ('event','internship','career'),
  ('event','networking','career'),
  ('event','alumni','career'),
  ('event','entrepreneurship','business'),
  ('event','ai-data','technology'),
  ('event','coding','technology'),
  ('event','hackathon','technology'),
  ('event','design','arts'),
  ('event','media','arts'),
  ('event','photography','arts'),
  ('event','video','arts'),
  ('event','theatre','arts'),
  ('event','dance','arts'),
  ('event','music','arts'),
  ('event','heritage','culture'),
  ('event','cultural-night','culture'),
  ('event','language','culture'),
  ('event','international','culture'),
  ('event','esports','games'),
  ('event','tournament','sports'),
  ('event','recreation','sports'),
  ('event','outdoor','sports'),
  ('event','debate','competition'),
  ('event','leadership','self-development'),
  ('event','public-speaking','self-development'),
  ('event','community-service','volunteering'),
  ('event','charity','volunteering'),
  ('event','fundraising','volunteering'),
  ('event','environment','volunteering'),
  ('event','sustainability','volunteering'),
  ('event','mental-health','health'),
  ('event','quran','religious'),
  ('event','iftar','religious'),
  ('event','qurban','religious'),
  ('event','bazaar','festivals'),
  ('event','carnival','festivals'),
  ('event','exhibition','festivals'),
  ('event','orientation','kolej-life'),
  ('event','club-recruitment','kolej-life'),

  ('listing','phones','electronics'),
  ('listing','computers','electronics'),
  ('listing','accessories','electronics'),
  ('listing','stationery','books'),
  ('listing','furniture','room'),
  ('listing','kitchen','room'),
  ('listing','traditional-wear','clothing'),
  ('listing','shoes','clothing'),
  ('listing','bags','clothing'),
  ('listing','homemade-food','food'),
  ('listing','bicycles','sports-gear'),
  ('listing','instruments','hobbies'),
  ('listing','arts-crafts','hobbies'),
  ('listing','collectibles','hobbies'),
  ('listing','plants','hobbies');

-- Slugs through the map: lowercased, deduplicated in first-seen order,
-- capped at 5. Unknown slugs pass through unchanged.
create or replace function pg_temp.remap_categories(p_kind text, p_cats text[])
returns text[]
language sql
as $$
  select coalesce(array_agg(slug order by first_pos), '{}')
  from (
    select coalesce(m.new_slug, l.c) as slug, min(u.pos) as first_pos
    from unnest(p_cats) with ordinality as u(raw, pos)
    cross join lateral (select lower(btrim(u.raw)) as c) l
    left join category_map m on m.kind = p_kind and m.old_slug = l.c
    where l.c <> ''
    group by 1
    order by 2
    limit 5
  ) q
$$;

-- The folded event slugs, to keep as hashtags: those not already in tags
-- (case-insensitive), in the order they appeared.
create or replace function pg_temp.folded_tags(p_cats text[], p_tags text[])
returns text[]
language sql
as $$
  select coalesce(array_agg(c order by first_pos), '{}')
  from (
    select l.c, min(u.pos) as first_pos
    from unnest(p_cats) with ordinality as u(raw, pos)
    cross join lateral (select lower(btrim(u.raw)) as c) l
    join category_map m on m.kind = 'event' and m.old_slug = l.c
    where not exists (
      select 1 from unnest(coalesce(p_tags, '{}')) t where lower(btrim(t)) = l.c)
    group by 1
  ) q
$$;

-- ====================================================== rewrite content
update public.events e
set tags       = coalesce(e.tags, '{}') || pg_temp.folded_tags(e.categories, e.tags),
    categories = pg_temp.remap_categories('event', e.categories)
where exists (
  select 1 from unnest(e.categories) c
  join category_map m on m.kind = 'event' and m.old_slug = lower(btrim(c)));

update public.listings l
set categories = pg_temp.remap_categories('listing', l.categories)
where exists (
  select 1 from unnest(l.categories) c
  join category_map m on m.kind = 'listing' and m.old_slug = lower(btrim(c)));

-- A listing with no categories still has the single old column; the sync
-- trigger only writes it from a non-empty array, so map it directly.
update public.listings l
set category = m.new_slug
from category_map m
where m.kind = 'listing'
  and cardinality(l.categories) = 0
  and m.old_slug = lower(btrim(l.category));

-- ====================================================== retire old slugs
update public.content_categories c
set active = false
from category_map m
where m.kind = c.kind
  and m.old_slug = lower(c.slug)
  and c.active;

drop function pg_temp.folded_tags(text[], text[]);
drop function pg_temp.remap_categories(text, text[]);
drop table pg_temp.category_map;
