// v1.3 posts: tag normalisation (20261022003100) and comment pins
// (20261022003200), against every migration in PGlite — same harness as
// ../moderation (stub schema, real roles under RLS):
//
//   cd supabase/tests/posts_v13
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node posts_v13_test.mjs ../../..

import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const stub = path.join(repo, 'supabase', 'tests', 'moderation', 'stub.sql');
const db = new PGlite();
const read = (f) => fs.readFileSync(f, 'utf8');

let failures = 0;
const ok = (cond, msg) => { console.log((cond ? 'ok   ' : 'FAIL ') + msg); if (!cond) failures++; };
const q = async (sql, p = []) => (await db.query(sql, p)).rows;

async function as(uid, sql, params = []) {
  await db.exec('begin');
  try {
    await db.exec(`set local role authenticated; select set_config('request.jwt.claim.sub', '${uid ?? ''}', true);`);
    const r = await db.query(sql, params);
    await db.exec('commit');
    return r.rows;
  } catch (e) { await db.exec('rollback'); throw e; }
}
async function err(uid, sql, params = []) {
  try { await as(uid, sql, params); return null; } catch (e) { return e.message; }
}

await db.exec(read(stub));
const files = fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort();
const before = files.filter((f) => f < '20261022003100');
const after = files.filter((f) => f >= '20261022003100');

// Apply everything up to (not incl.) the tag migration, seed legacy rows
// the way the first editors saved them, then apply the rest twice.
for (const f of before) {
  try { await db.exec(read(path.join(mig, f))); }
  catch (e) { console.error(`FAIL ${f}: ${e.message}`); process.exit(1); }
}

const ids = {};
for (const n of ['alice', 'bob', 'admin', 'org']) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  ids[n] = id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '10 days')`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)`,
    [id, n, n === 'admin' ? 'admin' : 'student']);
}
const legacy = (await q(
  `insert into posts (user_id, title, body, tags) values ($1,'old','x', array['Rant','#rant',' Lost&Found ','Academic','']) returning id`,
  [ids.alice]))[0].id;

for (const pass of [1, 2]) {
  for (const f of after) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied (new ones twice) OK');

// ---------------------------------------------------------------- tags
const tags = (await q('select tags from posts where id = $1', [legacy]))[0].tags;
ok(JSON.stringify(tags) === JSON.stringify(['rant', 'lostfound', 'academic']),
  `backfill normalises legacy tags (got ${JSON.stringify(tags)})`);

const viaView = await q(`select id from posts_public where tags && '{rant}'`);
ok(viaView.some((r) => r.id === legacy), 'posts_public finds the legacy post by #rant');

const fresh = (await as(ids.bob,
  `insert into posts (user_id, title, body, tags) values ($1,'new','y', array['#Question','question','LOST-FOUND']) returning tags`,
  [ids.bob]))[0].tags;
ok(JSON.stringify(fresh) === JSON.stringify(['question', 'lostfound']), `trigger normalises new rows (got ${JSON.stringify(fresh)})`);

const cnt = (await q(`select count(*)::int c from posts_public where tags && '{lostfound}'`))[0].c;
ok(cnt === 2, `tag count for #lostfound is 2 (got ${cnt})`);

// ---------------------------------------------------------------- pins
const post = (await as(ids.alice, `insert into posts (user_id, title, body) values ($1,'p','b') returning id`, [ids.alice]))[0].id;
const cs = [];
for (let i = 0; i < 5; i++) {
  cs.push((await as(ids.bob, `insert into comments (post_id, user_id, body) values ($1,$2,'c${i}') returning id`, [post, ids.bob]))[0].id);
}

ok((await err(ids.bob, 'select pin_comment($1, true)', [cs[0]]))?.includes('MOD:forbidden'),
  'commenter (not the post author) cannot pin');
for (let i = 0; i < 3; i++) await as(ids.alice, 'select pin_comment($1, true)', [cs[i]]);
ok((await q('select count(*)::int c from comments_public where post_id = $1 and pinned_at is not null', [post]))[0].c === 3,
  'author pins 3; comments_public exposes pinned_at');
ok((await err(ids.alice, 'select pin_comment($1, true)', [cs[3]]))?.includes('MOD:comment_pin_limit'),
  'a 4th pin is refused with comment_pin_limit');
ok((await err(ids.alice, 'select pin_comment($1, true)', [cs[0]])) === null, 're-pinning a pinned comment is a no-op');
await as(ids.alice, 'select pin_comment($1, false)', [cs[0]]);
ok((await err(ids.alice, 'select pin_comment($1, true)', [cs[3]])) === null, 'after an unpin there is room again');
ok((await err(ids.admin, 'select pin_comment($1, false)', [cs[1]])) === null, 'admin can unpin on any post');
ok((await err(null, 'select pin_comment($1, true)', [cs[4]])) !== null, 'signed-out callers are refused');

const ev = (await as(ids.org, `insert into events (organizer_id, title) values ($1,'e') returning id`, [ids.org]))[0].id;
const ec = (await as(ids.bob, `insert into comments (event_id, user_id, body) values ($1,$2,'hi') returning id`, [ev, ids.bob]))[0].id;
ok((await err(ids.alice, 'select pin_comment($1, true)', [ec]))?.includes('MOD:forbidden'), 'non-organiser cannot pin on an event');
ok((await err(ids.org, 'select pin_comment($1, true)', [ec])) === null, 'organiser pins on their event');

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
