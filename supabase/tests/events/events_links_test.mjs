// Events: the action_links / pic columns and the shape guard on the buttons.
// Applies every migration twice against the moderation stub, like the others.
//
//   cd supabase/tests
//   node events/events_links_test.mjs ../..

import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const db = new PGlite({ extensions: { citext } });
const read = (f) => fs.readFileSync(f, 'utf8');
const files = fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;

await db.exec(read(path.join(repo, 'supabase', 'tests', 'moderation', 'stub.sql')));

let failures = 0;
const ok = (cond, msg) => {
  console.log((cond ? 'ok   ' : 'FAIL ') + msg);
  if (!cond) failures++;
};

for (const f of files) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied twice OK');

const owner = (await q('select gen_random_uuid() id'))[0].id;
await q(`insert into auth.users (id) values ($1)`, [owner]);
await q(`insert into public.profiles (id, username, display_name) values ($1,'owner1','Owner')`, [owner]);

const cols = await q(`select column_name from information_schema.columns
                      where table_name = 'events' and column_name in ('action_links','pic')`);
ok(cols.length === 2, 'events gained action_links and pic');

async function insert(links, label = 'Event') {
  return q(
    `insert into public.events (organizer_id, title, action_links)
     values ($1, $2, $3::jsonb) returning id`,
    [owner, label, JSON.stringify(links)]);
}
const err = async (links, label) => {
  try { await insert(links, label); return null; } catch (e) { return e.message; }
};

const first = await insert(
  [{ label: 'Borang', url: '/event/x/form' }, { label: 'Peta', url: 'https://maps.example' }],
  'With buttons');
ok(!!first[0]?.id, 'two well-formed buttons are accepted');
ok((await q(`select action_links from events where id=$1`, [first[0].id]))[0].action_links.length === 2,
  'both are stored');

const empty = await insert([], 'No buttons');
ok(!!empty[0]?.id, 'an event with no buttons is fine');

let e = await err(
  [{ label: 'A', url: 'https://a.example' }, { label: 'B', url: 'https://b.example' },
   { label: 'C', url: 'https://c.example' }], 'Three buttons');
ok(e?.includes('EVENT:too_many_links'), 'a third button is refused');

e = await err([{ label: 'Peta', url: 'http://insecure.example' }], 'Http link');
ok(e?.includes('EVENT:link_not_https'), 'a plain http link is refused');

e = await err([{ label: '', url: 'https://a.example' }], 'Empty label');
ok(e?.includes('EVENT:bad_link'), 'an empty label is refused');

e = await err([{ label: 'A label that is far too long to fit', url: 'https://a.example' }],
  'Long label');
ok(e?.includes('EVENT:bad_link'), 'a label over 24 characters is refused');

e = await err([{ label: 'Ok', url: '' }], 'Empty url');
ok(e?.includes('EVENT:bad_link'), 'an empty url is refused');

const pic = await q(
  `update public.events set pic = 'Ahmad · 0123456789' where id=$1 returning pic`, [first[0].id]);
ok(pic[0].pic === 'Ahmad · 0123456789', 'pic stores a name and number');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
