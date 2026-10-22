// v1.4 editing announcements (20261023003100 update_my_announcement):
// author / club officer / admin may edit; others can't; category and
// action-link rules still apply. Same PGlite harness as create_test.mjs.
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node ../create/announce_edit_test.mjs ../../..

import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const db = new PGlite({ extensions: { citext } });
const read = (f) => fs.readFileSync(f, 'utf8');
const q = async (sql, p = []) => (await db.query(sql, p)).rows;

await db.exec(read(path.join(repo, 'supabase', 'tests', 'moderation', 'stub.sql')));
for (const f of fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort()) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied (each twice) OK');

let failures = 0;
const ok = (cond, msg) => { console.log((cond ? 'ok   ' : 'FAIL ') + msg); if (!cond) failures++; };

async function as(uid, sql, params = [], role = 'authenticated') {
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}; select set_config('request.jwt.claim.sub', '${uid ?? ''}', true);`);
    const r = await db.query(sql, params);
    await db.exec('commit');
    return r.rows;
  } catch (e) { await db.exec('rollback'); throw e; }
}
const err = async (uid, sql, params = [], role) => {
  try { await as(uid, sql, params, role); return null; } catch (e) { return e.message; }
};
async function user(name, role = 'student') {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '10 days')`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)`, [id, name, role]);
  return id;
}

const admin = await user('admin1', 'admin');
const officer = await user('officer');
const student = await user('student');
const buyer = await user('buyer');

const club = (await as(officer, `select register_club('Debate Society','Debate','We argue.','academic','HEP letter no. 42') id`))[0].id;
await as(admin, `select admin_decide_club_request($1, true, null)`, [club]);

// ---------------------------------------------------------- update_my_announcement
const officer2 = await user('officer2');
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'officer') on conflict do nothing`, [club, officer2]);

const ann = (await as(officer, `insert into posts (user_id, title, club_id, is_announcement, announcement_category) values ($1,'Meeting',$2,true,'event') returning id`, [officer, club]))[0].id;
const plain = (await as(student, `insert into posts (user_id, title) values ($1,'hi') returning id`, [student]))[0].id;

const fields = (o) => JSON.stringify(o);
let e = await err(officer, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({
  title: 'Meeting moved', body: 'Now at 9pm', comments_enabled: false, show_in_feed: false,
  action_links: [{ label: 'Register', url: 'https://forms.gle/x' }], cover_url: 'https://x/c.jpg', image_url: 'https://x/c.jpg',
  gallery_urls: ['https://x/1.jpg'], feature_until: '2030-01-01T00:00:00Z' })]);
ok(e === null, `author edits their announcement (${e})`);
const r = (await q(`select title, body, comments_enabled, show_in_feed, cover_url, gallery_urls, action_links, feature_until from posts where id=$1`, [ann]))[0];
ok(r.title === 'Meeting moved' && r.body === 'Now at 9pm' && r.comments_enabled === false && r.show_in_feed === false
  && r.cover_url === 'https://x/c.jpg' && r.gallery_urls.length === 1 && r.action_links.length === 1 && r.feature_until,
  'fields updated');

ok((await err(officer2, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({ title: 'by officer2' })])) === null,
  'another officer of the club can edit');
ok((await err(admin, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({ title: 'by admin' })])) === null,
  'admin can edit');
ok((await err(student, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({ title: 'hijack' })]))?.includes('POST:forbidden'),
  "a student cannot edit someone else's announcement");
ok((await err(student, `select update_my_announcement($1, $2::jsonb)`, [plain, fields({ title: 'x' })]))?.includes('POST:not_found'),
  'normal posts are not edited through this');
ok((await err(officer, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({ announcement_category: 'kolej' })]))?.includes('category_admin_only'),
  'officers still cannot switch to kolej');
ok((await err(officer, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({ action_links: [{ label: 'x', url: 'http://insecure' }] })])) !== null,
  'bad action links are still rejected');
ok((await err(null, `select update_my_announcement($1, $2::jsonb)`, [ann, fields({ title: 'x' })], 'anon')) !== null,
  'guests cannot call it');

console.log(failures ? `\n${failures} FAILURES` : "\nALL PASSED");
process.exit(failures ? 1 : 0);
