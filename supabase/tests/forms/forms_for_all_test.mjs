// Forms for everyone (20261029001100): standalone forms owned by a user or a
// club. Applies every migration twice against the moderation stub schema in
// PGlite, then exercises ownership, the answer rules, the abuse limits, the
// moderation hooks and what account deletion leaves behind.
//
//   cd supabase/tests
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node forms/forms_for_all_test.mjs ../..

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

async function as(uid, sql, params = [], role = 'authenticated') {
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}; select set_config('request.jwt.claim.sub', '${uid ?? ''}', true);`);
    const r = await db.query(sql, params);
    await db.exec('commit');
    return r.rows;
  } catch (e) {
    await db.exec('rollback');
    throw e;
  }
}
const err = async (uid, sql, params = [], role) => {
  try { await as(uid, sql, params, role); return null; } catch (e) { return e.message; }
};

// ---------------------------------------------------------- migrations
for (const f of files) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied twice OK');

// ---------------------------------------------------------- fixtures
async function user(name, { role = 'student', age = '10 days' } = {}) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - $2::interval)`, [id, age]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)`,
    [id, name, role]);
  return id;
}
const admin = await user('root', { role: 'admin' });
const alice = await user('alice');
const bob = await user('bob');
const carol = await user('carol');
const pres = await user('president');
const officer = await user('officer');
const fresh = await user('fresh', { age: '1 hour' });

const club = (await q(
  `insert into clubs (name, handle, status, category) values ('Robotics','robotics','active','academic') returning id`))[0].id;
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'president')`, [club, pres]);
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'officer')`, [club, officer]);

const field = (label, extra = {}) => ({ kind: 'short_text', label, required: false, ...extra });
const save = (uid, form, fields, header = {}) =>
  as(uid, `select save_event_form($1, $2::jsonb, $3::jsonb)`,
    [form, JSON.stringify(header), JSON.stringify(fields)]);

// ---------------------------------------------------------- tables stay closed
for (const t of ['event_forms', 'form_fields', 'form_responses']) {
  ok((await err(alice, `select * from ${t}`))?.includes('permission denied'),
    `${t} is not readable directly`);
}

// ---------------------------------------------------------- creating
let e = await err(null, `select create_standalone_form('x')`, [], 'anon');
ok(e !== null, 'a guest cannot create a form');

const fA = (await as(alice, `select create_standalone_form('Lost & found survey') f`))[0].f;
ok(!!fA, 'any signed-in student creates a personal form');
let row = (await q(`select * from event_forms where id=$1`, [fA]))[0];
ok(row.event_id === null && row.owner_id === alice && row.club_id === null && row.status === 'draft',
  'it is standalone, owned by its maker, a draft');

e = await err(alice, `select create_standalone_form('club', $1)`, [club]);
ok(e?.includes('FORM:not_allowed'), 'a non-officer cannot make a club form');
const fClub = (await as(pres, `select create_standalone_form('Robot sign-up', $1) f`, [club]))[0].f;
ok(!!fClub, 'a club president makes a club form');

const fTpl = (await as(bob, `select create_standalone_form(null, null, 'ki') f`))[0].f;
ok((await q(`select count(*)::int n from form_fields where form_id=$1`, [fTpl]))[0].n === 28,
  'a standalone form can start from the KI template');

// ---------------------------------------------------------- editing
e = await err(bob, `select save_event_form($1,'{}'::jsonb,'[]'::jsonb)`, [fA]);
ok(e?.includes('FORM:not_allowed'), "someone else cannot edit alice's form");
await save(alice, fA, [field('What did you lose?', { required: true }),
  { kind: 'single_choice', label: 'Where', options: { choices: ['Library', 'Cafe'] } }]);
ok((await q(`select count(*)::int n from form_fields where form_id=$1`, [fA]))[0].n === 2,
  'the owner saves fields');
await save(officer, fClub, [field('Name', { required: true })]);
ok(true, 'a club officer edits the club form');

// ---------------------------------------------------------- blocked labels
for (const bad of ['Password', 'Kata laluan UiTM', 'OTP code', 'Your PIN', 'Credit card number',
                   'CVV', 'No. kad kredit']) {
  e = await err(alice, `select save_event_form($1,'{}'::jsonb,$2::jsonb)`,
    [fA, JSON.stringify([field(bad)])]);
  ok(e?.includes('FORM:blocked_label'), `"${bad}" is refused on a standalone form`);
}
e = await err(alice, `select save_event_form($1,'{}'::jsonb,$2::jsonb)`,
  [fA, JSON.stringify([field('Name', { help: 'and your password' })])]);
ok(e?.includes('FORM:blocked_label'), 'help text is checked too');
for (const fine of ['Pinjam buku?', 'Opinion', 'IC number', 'Bank account for refund', 'Shipping address']) {
  e = await err(alice, `select save_event_form($1,'{}'::jsonb,$2::jsonb)`,
    [fA, JSON.stringify([field('What did you lose?', { required: true }), field(fine)])]);
  ok(e === null, `"${fine}" is allowed (warning only, in the editor)`);
}
const ev = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Talk',now()) returning id`, [carol]))[0].id;
const fEv = (await as(carol, `select create_blank_form($1,'Event form') f`, [ev]))[0].f;
e = await err(carol, `select save_event_form($1,'{}'::jsonb,$2::jsonb)`, [fEv, JSON.stringify([field('PIN')])]);
ok(e === null, 'event forms are unchanged (no label rule)');
ok((await q(`select owner_id from event_forms where id=$1`, [fEv]))[0].owner_id === null,
  'event forms have no owner_id');

// ---------------------------------------------------------- the public read model
let pub = (await as(null, `select form_public($1) j`, [fA], 'anon'))[0].j;
ok(pub.form.standalone === true && pub.form.owner?.username === 'alice',
  'the answer page names who made it');
ok(pub.reason === 'signed_out' && pub.can_answer === false, 'a guest sees it but cannot answer');
pub = (await as(pres, `select form_public($1) j`, [fClub]))[0].j;
ok(pub.form.club?.handle === 'robotics' && pub.can_edit === true && pub.can_read === true,
  'a club form names the club; its president can edit and read');
pub = (await as(bob, `select form_public($1) j`, [fA]))[0].j;
ok(pub.reason === 'closed' && pub.can_edit === false, 'a draft is not answerable');

// ---------------------------------------------------------- publishing and answering
await as(alice, `select publish_form($1)`, [fA]);
await as(pres, `select publish_form($1)`, [fClub]);
const fieldsA = (await q(`select id, kind from form_fields where form_id=$1 order by sort`, [fA]));
const ans = (v) => JSON.stringify({ [fieldsA[0].id]: v, [fieldsA[1].id]: 'Library' });

e = await err(null, `select submit_form_response($1,null,'peserta',$2::jsonb)`, [fA, ans('x')], 'anon');
ok(e !== null, 'a guest cannot answer');
ok((await as(bob, `select submit_form_response($1,null,'peserta',$2::jsonb) r`, [fA, ans('Wallet')]))[0].r === 'ok',
  'a signed-in student answers');
ok((await as(bob, `select submit_form_response($1,null,'peserta',$2::jsonb) r`, [fA, ans('Purse')]))[0].r === 'updated',
  'and can change the answer');
await as(carol, `select submit_form_response($1,null,'peserta',$2::jsonb)`, [fA, ans('Keys')]);

// ---------------------------------------------------------- who reads answers
ok((await as(alice, `select count(*)::int n from form_response_list($1)`, [fA]))[0].n === 2,
  'the owner reads the answers');
e = await err(bob, `select * from form_response_list($1)`, [fA]);
ok(e?.includes('FORM:not_allowed'), 'a responder cannot read the others');
e = await err(admin, `select * from form_response_list($1)`, [fA]);
ok(e?.includes('FORM:not_allowed'), 'an admin cannot read standalone answers');
const fieldsClub = await q(`select id from form_fields where form_id=$1`, [fClub]);
await as(bob, `select submit_form_response($1,null,'peserta',$2::jsonb)`,
  [fClub, JSON.stringify({ [fieldsClub[0].id]: 'Bob' })]);
ok((await as(officer, `select count(*)::int n from form_response_list($1)`, [fClub]))[0].n === 1,
  'a club officer reads the club form');
e = await err(alice, `select * from form_response_list($1)`, [fClub]);
ok(e?.includes('FORM:not_allowed'), 'a non-member cannot');
await q(`insert into student_verifications (user_id, email, status) values ($1,'2024123456@student.uitm.edu.my','verified')`, [bob]).catch(() => {});
const listed = (await as(officer, `select student_id from form_response_list($1)`, [fClub]))[0];
ok(listed.student_id === null, 'no matric is filled in from a verified email on a standalone form');

// ---------------------------------------------------------- withdrawing
ok((await as(carol, `select withdraw_form_response($1) w`, [fA]))[0].w === true,
  'a responder withdraws their answer');
ok((await q(`select count(*)::int n from form_responses where form_id=$1`, [fA]))[0].n === 1,
  'and it is gone');
e = await err(carol, `select withdraw_form_response($1)`, [fEv]);
ok(e?.includes('FORM:event_form'), 'event-form answers are not withdrawn this way');

// ---------------------------------------------------------- my forms
const mine = await as(alice, `select * from my_forms()`);
ok(mine.length === 1 && mine[0].id === fA && Number(mine[0].responses) === 1,
  "my_forms lists alice's form with its count");
const offs = await as(officer, `select * from my_forms()`);
ok(offs.some((r) => r.id === fClub && r.club_handle === 'robotics'),
  'a club officer sees the club form');
ok(!(await as(carol, `select id from my_forms()`)).some((r) => r.id === fEv),
  'event forms are not in my_forms');

// ---------------------------------------------------------- caps
for (let i = 0; i < 8; i++) await as(carol, `select create_standalone_form('c${i}')`);
await as(carol, `select create_standalone_form('c8')`);
e = await err(carol, `select create_standalone_form('c10')`);
ok(e === null, 'ten active personal forms are allowed');
e = await err(carol, `select create_standalone_form('c11')`);
ok(e?.includes('FORM:too_many'), 'the eleventh is refused');
const oneC = (await q(`select id from event_forms where owner_id=$1 limit 1`, [carol]))[0].id;
await as(carol, `select close_form($1)`, [oneC]);
ok((await err(carol, `select create_standalone_form('again')`)) === null, 'closing one frees a slot');

await as(fresh, `select create_standalone_form('one')`);
await as(fresh, `select create_standalone_form('two')`);
e = await err(fresh, `select create_standalone_form('three')`);
ok(e?.includes('MOD:rate_limited:form'), 'a new account is held to new_account_forms_per_hour');

// answers: 10 an hour for a new account
const many = [];
for (let i = 0; i < 11; i++) {
  const f = (await as(pres, `select create_standalone_form($2, $1) f`, [club, `r${i}`]).catch(() => [{}]))[0].f
    ?? (await as(officer, `select create_standalone_form($2, $1) f`, [club, `r${i}`]))[0].f;
  await save(officer, f, [field('Name')]);
  await as(officer, `select publish_form($1)`, [f]);
  many.push(f);
}
let done = 0;
for (const f of many) {
  const fid = (await q(`select id from form_fields where form_id=$1`, [f]))[0].id;
  const r = await err(fresh, `select submit_form_response($1,null,'peserta',$2::jsonb)`, [f, JSON.stringify({ [fid]: 'x' })]);
  if (r === null) done++;
  else { ok(r.includes('FORM:rate_limited'), 'the next answer is rate limited'); break; }
}
ok(done === 10, `a new account answers 10 forms an hour (got ${done})`);

// 2000 answers per standalone form (seeded directly, then one more through the RPC)
const fBig = many[0];
await q(`alter table form_responses disable trigger user`);
await q(`insert into form_responses (form_id, user_id) select $1, $2 from generate_series(1,1)`, [fBig, alice]);
await q(`alter table form_responses drop constraint form_responses_form_id_user_id_key`);
await q(`insert into form_responses (form_id, user_id) select $1, $2 from generate_series(1,1999)`, [fBig, admin]);
await q(`alter table form_responses enable trigger user`);
const bigField = (await q(`select id from form_fields where form_id=$1`, [fBig]))[0].id;
e = await err(carol, `select submit_form_response($1,null,'peserta',$2::jsonb)`, [fBig, JSON.stringify({ [bigField]: 'x' })]);
ok(e?.includes('FORM:full'), 'a standalone form stops at 2000 answers');
pub = (await as(carol, `select form_public($1) j`, [fBig]))[0].j;
ok(pub.reason === 'full', 'and the answer page says so');
await q(`delete from form_responses where form_id=$1`, [fBig]);
await q(`delete from form_responses a using form_responses b where a.form_id=b.form_id and a.user_id=b.user_id and a.ctid > b.ctid`);
await q(`alter table form_responses add constraint form_responses_form_id_user_id_key unique (form_id, user_id)`);

// ---------------------------------------------------------- moderation
await as(bob, `insert into reports (reporter_id, target_id, target_type, reason, category) values ($1,$2,'form','Scam','scam')`, [bob, fA]);
const kase = (await q(`select * from moderation_cases where target_type='form' and target_id=$1`, [fA]))[0];
ok(!!kase && kase.target_owner_id === alice, 'a form can be reported; the case knows its owner');
e = await err(alice, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'form','Other')`, [alice, fA]);
ok(e?.includes('MOD:self_report'), 'the owner cannot report their own form');
const preview = (await as(admin, `select mod_preview('form', $1) p`, [fA]))[0].p;
ok(preview?.title === 'Lost & found survey' && preview.body.includes('What did you lose?')
   && !JSON.stringify(preview).includes('Purse'),
  'the moderator preview shows the questions, never the answers');

const res = await err(admin, `select admin_resolve_case($1,'remove','phishing form')`, [kase.id]);
ok(res === null, `an admin removes the form (${res})`);
ok((await q(`select is_hidden from event_forms where id=$1`, [fA]))[0].is_hidden === true, 'it is hidden');
pub = (await as(bob, `select form_public($1) j`, [fA]))[0].j;
ok(pub.reason === 'removed' && pub.fields.length === 0 && pub.can_answer === false,
  'a removed form shows nobody its questions');
e = await err(bob, `select submit_form_response($1,null,'peserta',$2::jsonb)`, [fA, ans('again')]);
ok(e?.includes('FORM:removed'), 'and takes no answers, not even edits');
e = await err(alice, `select * from form_response_list($1)`, [fA]);
ok(e?.includes('FORM:not_allowed'), 'the owner can no longer read or export its answers');
e = await err(alice, `select publish_form($1)`, [fA]);
ok(e !== null, 'and cannot republish it');

// ---------------------------------------------------------- deletion
e = await err(carol, `select delete_form($1)`, [fEv]);
ok(e?.includes('FORM:event_form'), 'delete_form does not touch event forms');
e = await err(bob, `select delete_form($1)`, [fClub]);
ok(e?.includes('FORM:not_allowed'), 'a stranger cannot delete a club form');
const fGone = (await as(bob, `select create_standalone_form('temp') f`))[0].f;
await as(bob, `select delete_form($1)`, [fGone]);
ok((await q(`select count(*)::int n from event_forms where id=$1`, [fGone]))[0].n === 0, 'the owner deletes it');

// the club form's maker leaves: the form stays with the club
const fBob = (await as(bob, `select create_standalone_form('bob personal') f`))[0].f;
await q(`delete from profiles where id=$1`, [pres]);
row = (await q(`select owner_id from event_forms where id=$1`, [fClub]))[0];
ok(row && row.owner_id === null, 'a club form outlives its maker');
ok((await as(officer, `select can_manage_form($1) c`, [fClub]))[0].c === true, 'officers still manage it');
// alice leaves: her personal forms and their answers go
await q(`delete from profiles where id=$1`, [alice]);
ok((await q(`select count(*)::int n from event_forms where id=$1`, [fA]))[0].n === 0,
  "alice's personal form is deleted with her account");
ok((await q(`select count(*)::int n from form_responses where form_id=$1`, [fA]))[0].n === 0,
  'with its answers');
ok((await q(`select status from moderation_cases where id=$1`, [kase.id]))[0].status === 'actioned',
  'the decided case keeps its record');
// bob leaves: his answers go, others' forms stay
await q(`delete from profiles where id=$1`, [bob]);
ok((await q(`select count(*)::int n from form_responses where user_id=$1`, [bob]))[0].n === 0,
  "bob's answers are deleted with his account");
ok((await q(`select count(*)::int n from event_forms where id=$1`, [fBob]))[0].n === 0, 'and his own form');
ok((await q(`select count(*)::int n from event_forms where id=$1`, [fClub]))[0].n === 1, 'the club form remains');
await q(`delete from clubs where id=$1`, [club]);
ok((await q(`select count(*)::int n from event_forms where id=$1`, [fClub]))[0].n === 0,
  'deleting the club deletes its forms');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
