// Owner choice of the Create event layout: access_policy() key and
// set_create_event_layout() (20261113000100_create_event_layout.sql).
//
//   node supabase/tests/features/event_layout_test.mjs .

import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const db = new PGlite({ extensions: { citext } });
const read = (f) => fs.readFileSync(f, 'utf8');

await db.exec(read(path.join(repo, 'supabase', 'tests', 'moderation', 'stub.sql')));
const files = fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort();
for (const f of files) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied twice OK');

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
async function err(uid, sql, params = [], role) {
  try { await as(uid, sql, params, role); return null; } catch (e) { return e.message; }
}
async function user(name, role = 'student') {
  const id = (await db.query('select gen_random_uuid() id')).rows[0].id;
  await db.query('insert into auth.users (id) values ($1)', [id]);
  await db.query('insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)',
    [id, name, role]);
  return id;
}
const policy = async (uid = null, role) =>
  (await as(uid, 'select public.access_policy() p', [], role))[0].p;
const setLayout = (uid, layout) => as(uid, 'select public.set_create_event_layout($1)', [layout]);

const owner = await user('owner', 'owner');
const admin = await user('admin', 'admin');
const student = await user('ali');

// ---- default, readable signed out, older keys kept
const p0 = await policy(null, 'anon');
ok(p0.create_event_layout === 'folded', 'the layout defaults to folded (read as anon)');
ok(p0.announcements_enabled === true && p0.clubs_enabled === true &&
   p0.student_features_enabled === true && 'registration_mode' in p0 && 'verification_enabled' in p0,
  'access_policy() still returns every older key');

// ---- the owner can switch both ways
await setLayout(owner, 'steps');
ok((await policy(student)).create_event_layout === 'steps', 'owner switches to steps');
await setLayout(owner, ' folded ');
ok((await policy(student)).create_event_layout === 'folded', 'owner switches back (spaces trimmed)');

// ---- the feature switches are untouched by it
await setLayout(owner, 'steps');
const p1 = await policy(student);
ok(p1.clubs_enabled === true && p1.announcements_enabled === true, 'changing the layout leaves the switches alone');

// ---- nobody else can
const byAdmin = await err(admin, 'select public.set_create_event_layout($1)', ['folded']);
ok(byAdmin?.includes('MOD:not_owner'), `an admin is refused (${byAdmin})`);
const byStudent = await err(student, 'select public.set_create_event_layout($1)', ['folded']);
ok(byStudent?.includes('MOD:not_owner'), 'a student is refused');
const byAnon = await err(null, 'select public.set_create_event_layout($1)', ['folded'], 'anon');
ok(byAnon !== null, `anon cannot call it (${byAnon})`);
ok((await policy(student)).create_event_layout === 'steps', 'refused calls changed nothing');

// ---- unknown layouts are refused, even for the owner
for (const bad of ['wizard', 'STEPS', '', null]) {
  const e = await err(owner, 'select public.set_create_event_layout($1)', [bad]);
  ok(e?.includes('ACCESS:bad_layout'), `layout ${JSON.stringify(bad)} is refused`);
}
const direct = await db.query(`update public.access_settings set create_event_layout = 'grid' where id`)
  .then(() => null, (e) => e.message);
ok(direct?.includes('access_settings_event_layout_valid'), 'the column itself only takes folded or steps');

// ---- every change is logged with before and after
const logs = (await db.query(
  `select metadata from public.moderation_log where action = 'layout_switch' order by id`)).rows;
ok(logs.length === 3, `each owner change is logged (${logs.length})`);
ok(logs[0]?.metadata.from === 'folded' && logs[0]?.metadata.to === 'steps',
  'the log records the layout before and after');

if (failures) { console.error(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nALL PASSED');
