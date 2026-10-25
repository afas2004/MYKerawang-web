// Attendance: the rotating check-in code, the student's check-in, and the
// organiser's list. This is the flow that reported
//   column reference "expires_at" is ambiguous
// so it asserts the whole loop rather than just the fix.
//
//   cd supabase/tests
//   node events/attendance_flow_test.mjs ../..

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

async function user(name) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id) values ($1)`, [id]);
  await q(`insert into public.profiles (id, username, display_name) values ($1,$2,$2)`, [id, name]);
  return id;
}

async function as(id, sql, p = [], role = 'authenticated') {
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}; select set_config('request.jwt.claim.sub', '${id ?? ''}', true);`);
    const r = await db.query(sql, p);
    await db.exec('commit');
    return r.rows;
  } catch (e) {
    await db.exec('rollback');
    return { error: e.message, where: e.where ?? '' };
  }
}
const err = async (id, sql, p = []) => {
  const r = await as(id, sql, p);
  return Array.isArray(r) ? null : r.error;
};

const organiser = await user('organiser');
const student = await user('student');
const stranger = await user('stranger');

const ev = (await q(
  `insert into public.events (organizer_id, title, attendance_enabled)
   values ($1,'Ujian',true) returning id`, [organiser]))[0].id;

// ---------------------------------------------------------- the code
const issued = await as(organiser, `select * from event_checkin_token($1)`, [ev]);
ok(Array.isArray(issued), `the organiser gets a code (${Array.isArray(issued) ? 'ok' : issued.error})`);
ok(Array.isArray(issued) && typeof issued[0]?.token === 'string' && issued[0].token.length > 10,
  'the code is a token, not empty');
ok(Array.isArray(issued) && new Date(issued[0].expires_at).getTime() > Date.now() + 5 * 1000,
  'it lives for about twenty seconds');

const token = Array.isArray(issued) ? issued[0].token : null;

let e = await err(stranger, `select * from event_checkin_token($1)`, [ev]);
ok(e?.includes('CHECKIN:not_organizer'), 'a stranger cannot mint a code');

// ---------------------------------------------------------- checking in
const first = await as(student, `select checkin_with_token($1) r`, [token]);
ok(Array.isArray(first) && first[0]?.r === 'ok', `a student checks in (${first.error ?? 'ok'})`);
const again = await as(student, `select checkin_with_token($1) r`, [token]);
ok(Array.isArray(again) && again[0]?.r === 'already', 'checking in twice says already');

const attendance = (await q(
  `select count(*)::int n from event_attendance where event_id=$1`, [ev]))[0].n;
ok(attendance === 1, `one attendance row, not two (${attendance})`);

const participants = await q(
  `select event_id, user_id from event_participants where event_id=$1`, [ev]);
ok(participants.length === 1 && participants[0].user_id === student,
  `attending implies going (${participants.length} row(s): ${JSON.stringify(participants)})`);

e = await err(student, `select checkin_with_token('not-a-token')`);
ok(e?.includes('CHECKIN:invalid'), 'a made-up code is refused');

await q(`update event_checkin_tokens set expires_at = now() - interval '1 second' where token=$1`, [token]);
e = await err(stranger, `select checkin_with_token($1)`, [token]);
ok(e?.includes('CHECKIN:expired'), 'an expired code is refused');

// ---------------------------------------------------------- the list
const list = await as(organiser, `select * from event_attendance_list($1)`, [ev]);
ok(Array.isArray(list) && list.length === 1, 'the organiser sees the one check-in');
ok(Array.isArray(list) && list[0].user_id === student, 'and who it was');

e = await err(stranger, `select * from event_attendance_list($1)`, [ev]);
ok(e?.includes('CHECKIN:not_organizer'), 'a stranger cannot read the list');

// ---------------------------------------------------------- cleanup
// The cleanup DELETE runs on every mint; with a stale row present it used to be
// the statement that failed, so minting twice proves the fix.
await q(`update event_checkin_tokens set expires_at = now() - interval '10 minutes'`);
const second = await as(organiser, `select * from event_checkin_token($1)`, [ev]);
ok(Array.isArray(second),
  `minting again after stale rows still works (${Array.isArray(second) ? 'ok' : second.error})`);
ok((await q(`select count(*)::int n from event_checkin_tokens`))[0].n === 1,
  'the stale token was cleaned up');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
