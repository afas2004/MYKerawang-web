// Attendance with any form (20261113001100): the organiser picks which form the
// check-in success screen offers, old KI events keep their behaviour, check-in
// asks for verification only when both owner switches are on, and club
// officers may run the door for their club's events.
//
//   cd supabase/tests
//   node events/attendance_any_form_test.mjs ../..

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
    return { error: e.message };
  }
}
const err = async (id, sql, p = []) => {
  const r = await as(id, sql, p);
  return Array.isArray(r) ? null : r.error;
};
const formFor = async (uid, ev) => {
  const r = await as(uid, `select event_checkin_form($1) f`, [ev]);
  return Array.isArray(r) ? r[0].f : r;
};

const organiser = await user('organiser');
const student = await user('student');
const stranger = await user('stranger');
const officer = await user('officer');

const club = (await q(
  `insert into clubs (name, handle, status, category) values ('Robotics','robotics','active','academic') returning id`))[0].id;
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'officer')`, [club, officer]);

const ev = (await q(
  `insert into public.events (organizer_id, title, attendance_enabled, club_id)
   values ($1,'Ujian',true,$2) returning id`, [organiser, club]))[0].id;

// The event's own (KI) form, published with the old "after check-in" flag on.
const own = (await q(
  `insert into event_forms (event_id, title, status, after_checkin)
   values ($1,'Laporan KI','open',true) returning id`, [ev]))[0].id;
// A standalone form the organiser made at /forms.
const mine = (await q(
  `insert into event_forms (event_id, owner_id, title, status)
   values (null,$1,'Feedback','open') returning id`, [organiser]))[0].id;
// Someone else's form.
const theirs = (await q(
  `insert into event_forms (event_id, owner_id, title, status)
   values (null,$1,'Not yours','open') returning id`, [stranger]))[0].id;

// ---------------------------------------------------------- old behaviour
ok(await formFor(student, ev) === own,
  'with nothing chosen, the event\'s own after-check-in form is offered (as before)');

// ---------------------------------------------------------- choosing a form
let e = await err(organiser, `select set_event_checkin_form($1,$2)`, [ev, mine]);
ok(e === null, `the organiser picks one of their own forms (${e ?? 'ok'})`);
ok(await formFor(student, ev) === mine, 'and that is what the success screen offers');

e = await err(organiser, `select set_event_checkin_form($1,$2)`, [ev, theirs]);
ok(e?.includes('CHECKIN:form_not_yours'), 'someone else\'s form is refused');

e = await err(stranger, `select set_event_checkin_form($1,$2)`, [ev, theirs]);
ok(e?.includes('CHECKIN:not_organizer'), 'a stranger cannot choose the form');

await q(`update event_forms set status='closed' where id=$1`, [mine]);
ok(await formFor(student, ev) === null,
  'a closed chosen form offers nothing, and does not bring back the KI form');
await q(`update event_forms set status='open' where id=$1`, [mine]);

e = await err(organiser, `select set_event_checkin_form($1,null)`, [ev]);
ok(e === null, 'clearing the choice works');
await q(`update event_forms set after_checkin=false where id=$1`, [own]);
ok(await formFor(student, ev) === null, '"none" (cleared + flag off) offers nothing');

e = await err(organiser, `select set_event_checkin_form($1,$2)`, [ev, own]);
ok(e === null && await formFor(student, ev) === own, 'the event\'s own form can be chosen explicitly');

// ---------------------------------------------------------- club officers
const issued = await as(officer, `select * from event_checkin_token($1)`, [ev]);
ok(Array.isArray(issued), `a club officer can open the door (${issued.error ?? 'ok'})`);
e = await err(stranger, `select * from event_checkin_token($1)`, [ev]);
ok(e?.includes('CHECKIN:not_organizer'), 'a stranger still cannot');
const token = Array.isArray(issued) ? issued[0].token : null;

// ---------------------------------------------------------- verification
const setSwitches = (verify, student) => q(
  `update access_settings set verification_enabled=$1, student_features_enabled=$2 where id`,
  [verify, student]);

await setSwitches(true, false);
let r = await as(student, `select checkin_with_token($1) r`, [token]);
ok(Array.isArray(r) && r[0].r === 'ok',
  `verification on but student features off: an unverified person checks in (${r.error ?? 'ok'})`);

const student2 = await user('student2');
await setSwitches(true, true);
e = await err(student2, `select checkin_with_token($1)`, [token]);
ok(e?.includes('CHECKIN:verify'), 'both switches on: verification is required');

await setSwitches(false, true);
r = await as(student2, `select checkin_with_token($1) r`, [token]);
ok(Array.isArray(r) && r[0].r === 'ok', 'verification off: anyone checks in');

// ---------------------------------------------------------- the list
const list = await as(officer, `select * from event_attendance_list($1)`, [ev]);
ok(Array.isArray(list) && list.length === 2, `the club officer reads the list (${list.error ?? list.length})`);
const seen = await as(officer, `select count(*)::int n from event_attendance where event_id=$1`, [ev]);
ok(Array.isArray(seen) && seen[0].n === 2, 'and the live count');
const strangerSees = await as(stranger, `select count(*)::int n from event_attendance where event_id=$1`, [ev]);
ok(Array.isArray(strangerSees) && strangerSees[0].n === 0, 'a stranger sees no rows');
e = await err(stranger, `select * from event_attendance_list($1)`, [ev]);
ok(e?.includes('CHECKIN:not_organizer'), 'a stranger cannot read the list');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
