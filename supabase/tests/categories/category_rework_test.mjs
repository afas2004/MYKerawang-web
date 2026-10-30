// Categories: the 20261029000100 rework folds old slugs into the new list.
// Applies every earlier migration twice, seeds content on the old slugs,
// then applies the rework twice and checks the result.
//
//   cd supabase/tests
//   node categories/category_rework_test.mjs ../..

import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const db = new PGlite({ extensions: { citext } });
const read = (f) => fs.readFileSync(f, 'utf8');
const rework = '20261029000100_category_rework.sql';
const files = fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;

await db.exec(read(path.join(repo, 'supabase', 'tests', 'moderation', 'stub.sql')));

let failures = 0;
const ok = (cond, msg) => {
  console.log((cond ? 'ok   ' : 'FAIL ') + msg);
  if (!cond) failures++;
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

async function apply(f) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}

for (const f of files.filter((f) => f < rework)) await apply(f);
console.log('earlier migrations applied twice OK');

const owner = (await q('select gen_random_uuid() id'))[0].id;
await q(`insert into auth.users (id) values ($1)`, [owner]);
await q(`insert into public.profiles (id, username, display_name) values ($1,'owner1','Owner')`, [owner]);

// An admin added this one live; the rework must not touch it.
await q(`insert into public.content_categories (kind, slug, name_en) values ('event','film-club','Film club')`);

const event = async (cats, tags = null) => (await q(
  `insert into public.events (organizer_id, title, categories, tags)
   values ($1, 'E', $2, $3) returning id`, [owner, cats, tags]))[0].id;
const listing = async (cats, category = null) => (await q(
  `insert into public.listings (seller_id, title, categories, category)
   values ($1, 'L', $2, $3) returning id`, [owner, cats, category]))[0].id;

const e1 = await event(['lecture', 'seminar', 'academic', 'hackathon', 'coding'], ['Seminar']);
const e2 = await event(['Esports', 'iftar', 'bazaar', 'orientation', 'debate']);
const e3 = await event(['film-club', 'training']);
const e4 = await event(['sports']);
const e5 = await event(['music', 'dance', 'theatre', 'video', 'photography']);
const l1 = await listing(['phones', 'computers', 'bags']);
const l2 = await listing([], 'plants');
const l3 = await listing(['others']);

for (const pass of [1, 2]) {
  try { await db.exec(read(path.join(mig, rework))); }
  catch (e) { console.error(`FAIL pass ${pass} ${rework}: ${e.message}`); process.exit(1); }
}
console.log('rework applied twice OK');

// The rest of the migrations (if any came after) still apply on top.
for (const f of files.filter((f) => f > rework)) await apply(f);

const ev = async (id) => (await q(`select categories, tags from public.events where id=$1`, [id]))[0];
const li = async (id) => (await q(`select categories, category from public.listings where id=$1`, [id]))[0];

let r = await ev(e1);
ok(same(r.categories, ['academic', 'technology']), `old talk slugs fold into academic, coding into technology (${r.categories})`);
ok(same(r.tags, ['Seminar', 'lecture', 'hackathon', 'coding']),
  `folded slugs are kept as hashtags, without repeating an existing tag (${r.tags})`);

r = await ev(e2);
ok(same(r.categories, ['games', 'religious', 'festivals', 'kolej-life', 'competition']),
  `mixed-case slugs map too, order kept (${r.categories})`);

r = await ev(e3);
ok(same(r.categories, ['film-club', 'workshop']), `an admin-added slug passes through (${r.categories})`);

r = await ev(e4);
ok(same(r.categories, ['sports']) && r.tags === null, 'an event already on a new slug is untouched');

r = await ev(e5);
ok(same(r.categories, ['arts']), `five slugs that fold together leave one (${r.categories})`);
ok(r.tags.length === 5, 'and all five are kept as hashtags');

const over = (await q(`select count(*)::int n from public.events where cardinality(categories) > 5`))[0].n
  + (await q(`select count(*)::int n from public.listings where cardinality(categories) > 5`))[0].n;
ok(over === 0, 'nothing carries more than five categories');

r = await li(l1);
ok(same(r.categories, ['electronics', 'clothing']) && r.category === 'electronics',
  `listing slugs fold, and the primary column follows (${r.categories} / ${r.category})`);
r = await li(l2);
ok(r.category === 'hobbies', `a listing with only the old single column is mapped (${r.category})`);
r = await li(l3);
ok(same(r.categories, ['others']), 'a kept listing slug is untouched');

const active = async (kind) => (await q(
  `select slug from public.content_categories where kind=$1 and active order by sort, slug`, [kind])).map((x) => x.slug);
const ae = await active('event');
const al = await active('listing');
ok(ae.length === 18 && ae.includes('film-club'), `17 event categories + the admin one are active (${ae.length})`);
ok(al.length === 13, `13 listing categories are active (${al.length})`);

const stale = await q(
  `select kind, slug from public.content_categories
   where active and slug in ('lecture','seminar','hackathon','esports','iftar','phones','plants','bags')`);
ok(stale.length === 0, 'old slugs are inactive');
const kept = (await q(`select count(*)::int n from public.content_categories where slug in ('lecture','phones')`))[0].n;
ok(kept === 2, 'old slugs are deactivated, not deleted');

const names = await q(
  `select name_en, name_ms from public.content_categories where kind='event' and slug='academic'`);
ok(names[0]?.name_ms === 'Akademik & seminar', 'a reused slug takes its new name');

const noMs = (await q(`select count(*)::int n from public.content_categories
                        where active and slug <> 'film-club' and coalesce(name_ms,'') = ''`))[0].n;
ok(noMs === 0, 'every new category has a Malay name');

console.log(failures ? `\n${failures} failure(s)` : '\nall ok');
process.exit(failures ? 1 : 0);
