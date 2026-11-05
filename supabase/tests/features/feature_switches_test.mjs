// Owner feature switches: access_policy() keys and set_feature_enabled().
//
//   cd supabase/tests && npm i --no-save @electric-sql/pglite@0.2.17
//   node supabase/tests/features/feature_switches_test.mjs .
//
// Boots the stub schema, applies every migration twice, then acts as real
// roles: the owner can flip each switch, an admin or student cannot, an
// unknown feature name is refused, and every change is logged.

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
const set = (uid, feature, on) =>
  as(uid, 'select public.set_feature_enabled($1, $2)', [feature, on]);

const owner = await user('owner', 'owner');
const admin = await user('admin', 'admin');
const student = await user('ali');

// ---- defaults: everything on, old keys still there
const p0 = await policy(null, 'anon');
ok(p0.announcements_enabled === true && p0.clubs_enabled === true &&
   p0.student_features_enabled === true, 'all three switches default to on (read as anon)');
ok('verification_enabled' in p0 && 'registration_mode' in p0 && 'student_domain' in p0,
  'access_policy() still returns the older keys');

// ---- the owner can flip each switch
for (const [feature, key] of [['announcements', 'announcements_enabled'],
                              ['clubs', 'clubs_enabled'],
                              ['student_features', 'student_features_enabled']]) {
  await set(owner, feature, false);
  ok((await policy(student))[key] === false, `owner turns ${feature} off`);
  await set(owner, feature, true);
  ok((await policy(student))[key] === true, `owner turns ${feature} back on`);
}

// ---- one switch does not move the others
await set(owner, 'clubs', false);
const p1 = await policy(student);
ok(p1.clubs_enabled === false && p1.announcements_enabled === true &&
   p1.student_features_enabled === true, 'turning clubs off leaves the others on');
await set(owner, 'clubs', true);

// ---- nobody else can
const byAdmin = await err(admin, 'select public.set_feature_enabled($1, $2)', ['clubs', false]);
ok(byAdmin !== null && byAdmin.includes('MOD:not_owner'), `an admin is refused (${byAdmin})`);
const byStudent = await err(student, 'select public.set_feature_enabled($1, $2)', ['clubs', false]);
ok(byStudent !== null && byStudent.includes('MOD:not_owner'), 'a student is refused');
const byAnon = await err(null, 'select public.set_feature_enabled($1, $2)', ['clubs', false], 'anon');
ok(byAnon !== null, `anon cannot call it (${byAnon})`);
ok((await policy(student)).clubs_enabled === true, 'refused calls changed nothing');

// ---- unknown feature names are refused, even for the owner
for (const bad of ['verification', 'clubs_enabled', '', null]) {
  const e = await err(owner, 'select public.set_feature_enabled($1, $2)', [bad, false]);
  ok(e !== null && e.includes('ACCESS:bad_feature'), `unknown feature ${JSON.stringify(bad)} is refused`);
}

// ---- every change is logged
const logged = (await db.query(
  `select count(*)::int n from public.moderation_log where action = 'feature_switch'`)).rows[0].n;
ok(logged === 8, `each owner change is logged (${logged})`);

if (failures) { console.error(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nALL PASSED');
