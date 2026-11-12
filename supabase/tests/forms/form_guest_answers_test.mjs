// Public forms (20261112000100): the per-form switch that lets guests answer.
// Applies every migration twice against the moderation stub schema in PGlite,
// then checks what a guest sees and may do with the switch off and on, the
// guest limits, and how guest answers reach the organiser.
//
//   cd supabase/tests
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node forms/form_guest_answers_test.mjs ../..

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
const guest = (sql, params = []) => as(null, sql, params, 'anon');
const guestErr = (sql, params = []) => err(null, sql, params, 'anon');

// ---------------------------------------------------------- migrations
for (const f of files) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied twice OK');

// ---------------------------------------------------------- fixtures
async function user(name) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '10 days')`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,'student')`,
    [id, name]);
  return id;
}
const alice = await user('alice');
const bob = await user('bob');

const form = (await as(alice, `select create_standalone_form('Bake sale') f`))[0].f;
await as(alice, `select save_event_form($1,'{"intro":"Pick a cake"}'::jsonb,$2::jsonb)`, [form, JSON.stringify([
  { kind: 'short_text', label: 'Cake', required: true },
  { kind: 'single_choice', label: 'Size', options: { choices: ['Small', 'Big'] } },
])]);
await as(alice, `select publish_form($1)`, [form]);
const fields = await q(`select id from form_fields where form_id=$1 order by sort`, [form]);
const ans = (cake, size = 'Small') => JSON.stringify({ [fields[0].id]: cake, [fields[1].id]: size });
const guestSubmit = (name, email, answers, id = form) =>
  guest(`select submit_guest_form_response($1,$2,$3,$4::jsonb) r`, [id, name, email, answers]);
const guestSubmitErr = (name, email, answers, id = form) =>
  guestErr(`select submit_guest_form_response($1,$2,$3,$4::jsonb)`, [id, name, email, answers]);

// ---------------------------------------------------------- default: private
ok((await q(`select is_public from event_forms where id=$1`, [form]))[0].is_public === false,
  'a new form is not public');
let pub = (await guest(`select form_public($1) j`, [form]))[0].j;
ok(pub.reason === 'signed_out' && pub.can_answer === false && pub.guest === true,
  'a guest on a private form is asked to sign in');
ok(pub.fields.length === 0 && pub.form.intro === null,
  'a guest on a private form does not get the questions or intro');
ok(pub.form.title === 'Bake sale' && pub.form.owner?.username === 'alice',
  'a guest still sees the title and who made it');
let e = await guestSubmitErr('Guest', null, ans('Brownie'));
ok(e?.includes('FORM:login_required'), 'a guest cannot answer a private form');

pub = (await as(bob, `select form_public($1) j`, [form]))[0].j;
ok(pub.can_answer === true && pub.fields.length === 2 && pub.form.is_public === false,
  'a signed-in user still sees and answers a private form');

// ---------------------------------------------------------- the switch
e = await err(bob, `select set_form_public($1, true)`, [form]);
ok(e?.includes('FORM:not_allowed'), 'only the form maker can make it public');
e = await guestErr(`select set_form_public($1, true)`, [form]);
ok(e !== null, 'a guest cannot flip the switch');
await as(alice, `select set_form_public($1, true)`, [form]);
ok((await q(`select is_public from event_forms where id=$1`, [form]))[0].is_public === true,
  'the maker turns public on');

pub = (await guest(`select form_public($1) j`, [form]))[0].j;
ok(pub.can_answer === true && pub.reason === null && pub.fields.length === 2
   && pub.form.intro === 'Pick a cake' && pub.form.is_public === true,
  'a guest on a public form sees the questions and may answer');

// ---------------------------------------------------------- guest answers
ok((await guestSubmit('  Siti   Aminah ', 'Siti@Example.com', ans('Brownie')))[0].r === 'ok',
  'a guest answers with a name and email');
ok((await guestSubmit('Ali', null, ans('Tart', 'Big')))[0].r === 'ok',
  'the email is optional');
let rows = await q(`select user_id, guest_name, guest_email from form_responses where form_id=$1 and user_id is null order by guest_name`, [form]);
ok(rows.length === 2 && rows[1].guest_name === 'Siti Aminah' && rows[1].guest_email === 'siti@example.com',
  'the name is tidied and the email lower-cased');

e = await guestSubmitErr('   ', null, ans('Cookie'));
ok(e?.includes('FORM:guest_name'), 'a name is required');
e = await guestSubmitErr('x'.repeat(81), null, ans('Cookie'));
ok(e?.includes('FORM:guest_name'), 'a very long name is refused');
e = await guestSubmitErr('Ali', 'not-an-email', ans('Cookie'));
ok(e?.includes('FORM:guest_email'), 'a malformed email is refused');
e = await guestSubmitErr('Ali', null, JSON.stringify({ [fields[1].id]: 'Small' }));
ok(e?.includes('FORM:required:'), 'required questions apply to guests');
e = await guestSubmitErr('Ali', null, ans('Cookie', 'Huge'));
ok(e?.includes('FORM:bad_choice:'), 'choice checks apply to guests');
e = await err(bob, `select submit_guest_form_response($1,'Bob',null,$2::jsonb)`, [form, ans('Pie')]);
ok(e !== null, 'a signed-in user cannot use the guest path');
e = await guestErr(`select form_clean_answers($1,'{}'::jsonb)`, [form]);
ok(e?.includes('permission denied'), 'guests cannot call the answer checker directly');

// signed-in path is unchanged
ok((await as(bob, `select submit_form_response($1,null,'peserta',$2::jsonb) r`, [form, ans('Pie')]))[0].r === 'ok',
  'a signed-in user answers a public form as before');
ok((await as(bob, `select submit_form_response($1,null,'peserta',$2::jsonb) r`, [form, ans('Pie', 'Big')]))[0].r === 'updated',
  'and can still change their answer');
e = await err(bob, `select submit_form_response($1,null,'peserta',$2::jsonb)`, [form, JSON.stringify({})]);
ok(e?.includes('FORM:required:'), 'the signed-in path still checks required questions');

// ---------------------------------------------------------- the organiser's view
let list = await as(alice, `select * from form_response_list($1)`, [form]);
ok(list.length === 3, 'the organiser sees guest and member answers together');
const siti = list.find((r) => r.display_name === 'Siti Aminah');
ok(siti?.is_guest === true && siti.user_id === null && siti.guest_email === 'siti@example.com' && !!siti.response_id,
  'a guest answer is marked as a guest, with their email');
const bobRow = list.find((r) => r.username === 'bob');
ok(bobRow?.is_guest === false && bobRow.guest_email === null, 'a member answer is not marked as a guest');
e = await err(bob, `select * from form_response_list($1)`, [form]);
ok(e?.includes('FORM:not_allowed'), 'others still cannot read the answers');
pub = (await as(bob, `select form_public($1) j`, [form]))[0].j;
ok(pub.mine && !('guest_name' in pub.mine), "a member's own answer carries no guest fields");

// ---------------------------------------------------------- limits
await q(`update event_forms set max_responses = 3 where id=$1`, [form]);
pub = (await guest(`select form_public($1) j`, [form]))[0].j;
ok(pub.reason === 'full' && pub.can_answer === false, 'a full form tells guests so');
e = await guestSubmitErr('Late', null, ans('Cake'));
ok(e?.includes('FORM:full'), 'a full form takes no more guest answers');
await q(`update event_forms set max_responses = null where id=$1`, [form]);

// 50 guest answers an hour per form
await q(`insert into form_responses (form_id, user_id, guest_name, answers)
         select $1, null, 'bot' || g, '{}'::jsonb from generate_series(1, 48) g`, [form]);
e = await guestSubmitErr('One more', null, ans('Cake'));
ok(e?.includes('FORM:rate_limited'), 'the 51st guest answer in an hour is refused');
ok((await as(bob, `select submit_form_response($1,null,'peserta',$2::jsonb) r`, [form, ans('Pie')]))[0].r === 'updated',
  'members are not caught by the guest cap');
await q(`update form_responses set submitted_at = now() - interval '2 hours' where form_id=$1 and user_id is null`, [form]);
ok((await guestSubmit('Later', null, ans('Cake')))[0].r === 'ok', 'the cap is per hour');

// closed, hidden, private again
await as(alice, `select close_form($1)`, [form]);
e = await guestSubmitErr('Closed', null, ans('Cake'));
ok(e?.includes('FORM:closed'), 'a closed form takes no guest answers');
pub = (await guest(`select form_public($1) j`, [form]))[0].j;
ok(pub.reason === 'closed', 'a guest sees that a public form is closed');

const form2 = (await as(alice, `select create_standalone_form('Second') f`))[0].f;
await as(alice, `select save_event_form($1,'{}'::jsonb,$2::jsonb)`,
  [form2, JSON.stringify([{ kind: 'short_text', label: 'Q', required: false }])]);
await as(alice, `select publish_form($1)`, [form2]);
await as(alice, `select set_form_public($1, true)`, [form2]);
ok((await guestSubmit('Ok', null, '{}', form2))[0].r === 'ok', 'a second public form takes guests');
await q(`update event_forms set is_hidden = true where id=$1`, [form2]);
e = await guestSubmitErr('Hidden', null, '{}', form2);
ok(e?.includes('FORM:removed'), 'a form hidden by moderation takes no guest answers');
pub = (await guest(`select form_public($1) j`, [form2]))[0].j;
ok(pub.reason === 'removed' && pub.fields.length === 0, 'and shows guests nothing');
await q(`update event_forms set is_hidden = false where id=$1`, [form2]);
await as(alice, `select set_form_public($1, false)`, [form2]);
e = await guestSubmitErr('Off', null, '{}', form2);
ok(e?.includes('FORM:login_required'), 'turning public off stops guest answers again');

// event forms that need an RSVP never take guests
const ev = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Talk',now()) returning id`, [alice]))[0].id;
const fEv = (await as(alice, `select create_blank_form($1,'Event form') f`, [ev]))[0].f;
await as(alice, `select save_event_form($1,'{"require_rsvp":true}'::jsonb,$2::jsonb)`,
  [fEv, JSON.stringify([{ kind: 'short_text', label: 'Q', required: false }])]);
await as(alice, `select publish_form($1)`, [fEv]);
await as(alice, `select set_form_public($1, true)`, [fEv]);
pub = (await guest(`select form_public($1) j`, [fEv]))[0].j;
ok(pub.reason === 'signed_out' && pub.can_answer === false,
  'a public event form that needs an RSVP still asks guests to sign in');
e = await guestSubmitErr('Rsvp', null, '{}', fEv);
ok(e?.includes('FORM:login_required'), 'and refuses a guest answer');

// a row must belong to someone
e = await err(null, `insert into form_responses (form_id, user_id, answers) values ('${form}', null, '{}')`, [], 'postgres');
ok(e !== null, 'an answer with neither an account nor a name is refused by the table');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
