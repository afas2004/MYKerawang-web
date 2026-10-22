// v1.4 create matrix (20261023001100): who may post / announce / sell /
// create events, scheduled posts, action links, comments on/off, club
// listing contact. PGlite, real roles under RLS.
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node ../create/create_test.mjs ../../..

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

// ---------------------------------------------------------- can_post_announcement
let cap = (await as(student, `select can_post_announcement() j`))[0].j;
ok(cap.allowed === false && cap.categories.length === 0, 'students cannot announce');
cap = (await as(officer, `select can_post_announcement() j`))[0].j;
ok(cap.allowed && JSON.stringify(cap.categories) === '["club","event","general"]' && cap.clubs[0].handle === 'Debate',
  'officers: club/event/general + their clubs');
cap = (await as(admin, `select can_post_announcement() j`))[0].j;
ok(cap.allowed && cap.categories.includes('kolej') && cap.categories.includes('jpk'), 'admins: all categories');

// ---------------------------------------------------------- posts
ok((await err(student, `insert into posts (user_id, title, is_anonymous) values ($1,'anon q',true)`, [student])) === null,
  'students post anonymously');
let e = await err(student, `insert into posts (user_id, title, is_announcement, announcement_category) values ($1,'x',true,'general')`, [student]);
ok(e !== null, 'students cannot post announcements');
e = await err(officer, `insert into posts (user_id, title, club_id, is_announcement, announcement_category) values ($1,'x',$2,true,'kolej')`, [officer, club]);
ok(e?.includes('POST:category_admin_only'), 'officers cannot use kolej/jpk');
const ann = (await as(officer, `insert into posts (user_id, title, club_id, is_announcement, announcement_category, is_anonymous, cover_url, action_links, comments_enabled, show_in_feed) values ($1,'Meeting',$2,true,'event',true,'https://x/c.jpg','[{"label":"Register","url":"https://forms.gle/x"},{"label":"Club page","url":"/c/Debate"}]',false,false) returning id, is_anonymous`, [officer, club]))[0];
ok(ann && ann.is_anonymous === false, 'officer announces as club; never anonymous');
ok((await err(admin, `insert into posts (user_id, title, is_announcement, announcement_category) values ($1,'Water cut',true,'jpk')`, [admin])) === null,
  'admins post jpk announcements');

// action links
e = await err(student, `insert into posts (user_id, title, action_links) values ($1,'x','[{"label":"a","url":"http://insecure"}]')`, [student]);
ok(e?.includes('POST:action_links'), 'http links rejected');
e = await err(student, `insert into posts (user_id, title, action_links) values ($1,'x','[{"label":"a","url":"/a"},{"label":"b","url":"/b"},{"label":"c","url":"/c"}]')`, [student]);
ok(e?.includes('POST:action_links'), 'max 2 links');
e = await err(student, `insert into posts (user_id, title, action_links) values ($1,'x','[{"label":"This label is far too long!!","url":"/a"}]')`, [student]);
ok(e?.includes('POST:action_links'), 'label ≤ 24 chars');
ok((await err(student, `insert into posts (user_id, title, action_links) values ($1,'x','[{"label":"Docs","url":"https://uitm.edu.my/a"}]')`, [student])) === null,
  'valid https link accepted');

// comments on/off
e = await err(buyer, `insert into comments (post_id, user_id, body) values ($1,$2,'hi')`, [ann.id, buyer]);
ok(e?.includes('POST:comments_disabled'), 'comments refused when disabled');
const open = (await as(student, `insert into posts (user_id, title) values ($1,'open') returning id`, [student]))[0].id;
ok((await err(buyer, `insert into comments (post_id, user_id, body) values ($1,$2,'hi')`, [open, buyer])) === null, 'comments allowed by default');

// scheduled
const sched = (await as(officer, `insert into posts (user_id, title, club_id, publish_at) values ($1,'Later',$2, now() + interval '2 days') returning id`, [officer, club]))[0].id;
ok((await as(buyer, `select count(*)::int n from posts_public where id=$1`, [sched]))[0].n === 0, 'scheduled post hidden from others');
ok((await as(null, `select count(*)::int n from posts_public where id=$1`, [sched], 'anon'))[0].n === 0, 'scheduled post hidden from guests');
ok((await as(officer, `select count(*)::int n from posts_public where id=$1`, [sched]))[0].n === 1, 'author sees scheduled post');
ok((await as(admin, `select count(*)::int n from posts_public where id=$1`, [sched]))[0].n === 1, 'admin sees scheduled post');
const row = (await as(null, `select cover_url, action_links, comments_enabled, show_in_feed, publish_at, club from posts_public where id=$1`, [ann.id], 'anon'))[0];
ok(row.cover_url && row.action_links.length === 2 && row.comments_enabled === false && row.show_in_feed === false && row.publish_at && row.club.handle === 'Debate',
  'posts_public exposes new columns');
const old = (await q(`select count(*)::int n from posts where publish_at is null`))[0].n;
ok(old === 0, 'publish_at backfilled / not null');

// linked event
const ev = (await as(officer, `insert into events (organizer_id, title, club_id) values ($1,'Workshop',$2) returning id`, [officer, club]))[0].id;
ok((await err(officer, `insert into posts (user_id, title, club_id, linked_event_id) values ($1,'See event',$2,$3)`, [officer, club, ev])) === null, 'linked_event_id accepted');

// ---------------------------------------------------------- listings
e = await err(student, `insert into listings (seller_id, title, price, condition) values ($1,'x',1,'broken')`, [student]);
ok(e !== null, 'condition validated');
e = await err(officer, `insert into listings (seller_id, title, price, club_id, quantity) values ($1,'tee',25,$2,0)`, [officer, club]);
ok(e !== null, 'quantity must be positive');
const lst = (await as(officer, `insert into listings (seller_id, title, price, club_id, condition, meetup, quantity) values ($1,'Club tee',25,$2,'new','Kolej lobby, 8pm',30) returning id`, [officer, club]))[0].id;
ok(!!lst, 'club listing with condition/meetup/quantity');
e = await err(officer, `select set_club_contact($1,'0123','https://qr')`, [club]);
ok(e === null, 'officer sets club contact');
ok((await err(student, `select set_club_contact($1,'999',null)`, [club]))?.includes('CLUB:not_officer'), 'non-officer cannot');
const contact = (await as(buyer, `select * from get_listing_contact($1)`, [lst]))[0];
ok(contact.is_club && contact.phone_number === '0123' && contact.username === 'Debate' && contact.display_name === 'Debate Society',
  'club listing reveals the club contact, not the officer');
const own = (await as(student, `insert into listings (seller_id, title, price) values ($1,'Book',5) returning id`, [student]))[0].id;
const pc = (await as(buyer, `select * from get_listing_contact($1)`, [own]))[0];
ok(pc && pc.is_club === false && pc.username === 'student', 'personal listing reveals the seller');

console.log(failures ? `\n${failures} FAILURES` : '\nALL PASSED');
process.exit(failures ? 1 : 0);
