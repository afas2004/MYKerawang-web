// Student verification: the record, the owner switch and the gate.
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node ../verification/verification_test.mjs ../../..
//
// Boots the stub schema, applies every migration twice, then acts as real
// roles under RLS: switch off → anyone may act; switch on → the gate
// refuses until an admin verifies the account.

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
async function user(name, role = 'student') {
  const id = (await db.query('select gen_random_uuid() id')).rows[0].id;
  await db.query('insert into auth.users (id) values ($1)', [id]);
  await db.query('insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)',
    [id, name, role]);
  return id;
}
const switchOn = (v) =>
  db.query('update public.access_settings set verification_enabled = $1 where id', [v]);

const owner = await user('owner', 'owner');
const student = await user('ali');

const makeEvent = (uid) =>
  as(uid, `insert into public.events (organizer_id, title, start_datetime)
           values ($1, 'Jom makan', now() + interval '1 day')`, [uid]);

// ---- switch off: the gate is inert
ok((await makeEvent(student)) !== null, 'switch off: an unverified member can create an event');

// ---- switch on: refused with a capability-specific code
await switchOn(true);
const refused = await err(student, `insert into public.events (organizer_id, title) values ($1, 'X')`, [student]);
ok(refused !== null && refused.includes('VERIFY:required:event_create'),
  `switch on: creating an event is refused (${refused})`);

// ---- joining an event is gated too
const ev = (await db.query(`select id from public.events limit 1`)).rows[0].id;
const joinRefused = await err(student, `insert into public.event_participants (event_id, user_id) values ($1,$2)`, [ev, student]);
ok(joinRefused !== null && joinRefused.includes('VERIFY:required:event_join'),
  'switch on: joining an event is refused');

// ---- staff are exempt
ok((await makeEvent(owner)) !== null, 'switch on: an admin/owner is exempt');

// ---- a student can ask, and cannot ask twice in ten minutes
const asked = await as(student, `select public.request_student_verification($1) as s`,
  ['ali@student.uitm.edu.my']);
ok(asked[0].s === 'pending', 'request lands as pending');
const again = await err(student, `select public.request_student_verification($1)`,
  ['ali@student.uitm.edu.my']);
ok(again !== null && again.includes('VERIFY:wait'), 'a second request within 10 minutes is refused');

// ---- wrong domain is refused
const other = await user('bob');
const badDomain = await err(other, `select public.request_student_verification($1)`, ['bob@gmail.com']);
ok(badDomain !== null && badDomain.includes('VERIFY:domain'), 'a non-student address is refused');

// ---- the queue is admin-only, and shows the request
const asStudent = await err(student, 'select * from public.admin_verification_queue()');
ok(asStudent !== null && asStudent.includes('MOD:not_admin'), 'the queue is admin-only');
const queue = await as(owner, 'select * from public.admin_verification_queue()');
ok(queue.length === 1 && queue[0].email === 'ali@student.uitm.edu.my', 'an admin sees the pending request');

// ---- approving unblocks the student
await as(owner, `select public.admin_set_student_verification($1,$2,'verified')`,
  [student, 'ali@student.uitm.edu.my']);
ok((await makeEvent(student)) !== null, 'after approval the student can create an event');
ok(((await as(student, 'select public.is_verified_student() as v'))[0].v) === true,
  'is_verified_student() is true');

// ---- one address, one account
const stolen = await err(owner, `select public.admin_set_student_verification($1,$2,'verified')`,
  [other, 'ali@student.uitm.edu.my']);
ok(stolen !== null && stolen.includes('VERIFY:email_taken'),
  'a verified address cannot be given to a second account');

// ---- revoking closes the gate again
await as(owner, `select public.admin_set_student_verification($1,'','revoked')`, [student]);
const revoked = await err(student, `insert into public.events (organizer_id, title) values ($1, 'Y')`, [student]);
ok(revoked !== null && revoked.includes('VERIFY:required'), 'a revoked student is gated again');

if (failures) { console.error(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nALL PASSED');
