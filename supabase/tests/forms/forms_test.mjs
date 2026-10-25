// Event forms (KI report survey): applies every migration twice against the
// moderation stub schema in PGlite, then exercises the seeded template, the
// editor's write, submission and the S1/S2/S3 means.
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node ../forms/forms_test.mjs ../../..

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
const admin = (await q('select gen_random_uuid() id'))[0].id;
async function user(name, role = 'student') {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '10 days')`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)`,
    [id, name, role]);
  return id;
}
await q(`insert into auth.users (id) values ($1)`, [admin]);
await q(`insert into public.profiles (id, username, display_name, role) values ($1,'root','root','admin')`, [admin]);

const pres = await user('president');
const officer = await user('officer');
const s1 = await user('student1');
const s2 = await user('student2');
const s3 = await user('student3');
const otherPres = await user('otherpres');

const club = (await q(
  `insert into clubs (name, handle, status, category) values ('Bahasa Arab','bahasa_arab','active','academic') returning id`))[0].id;
const club2 = (await q(
  `insert into clubs (name, handle, status, category) values ('Debate','debate','active','academic') returning id`))[0].id;
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'president')`, [club, pres]);
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'officer')`, [club, officer]);
await q(`insert into club_members (club_id, user_id, role) values ($1,$2,'president')`, [club2, otherPres]);

const ev = (await q(
  `insert into events (organizer_id, title, club_id, start_datetime) values ($1,'Quiz Bahasa Arab',$2, now() - interval '2 days') returning id`,
  [pres, club]))[0].id;
const ev2 = (await q(
  `insert into events (organizer_id, title, club_id, start_datetime) values ($1,'Debate night',$2, now()) returning id`,
  [otherPres, club2]))[0].id;

// ---------------------------------------------------------- the template
const tpl = (await q(`select * from form_templates where slug='ki'`))[0];
ok(!!tpl && tpl.active, 'KI template seeded and active');

const counts = Object.fromEntries((await q(
  `select coalesce(analysis,'(none)') a, count(*)::int n from form_template_fields
   where template_id=$1 group by 1 order by 1`, [tpl.id])).map((r) => [r.a, r.n]));
ok(counts['ki_pre'] === 7 && counts['ki_post'] === 7 && counts['feedback'] === 6,
  `template carries 7 pre / 7 post / 6 feedback (got ${JSON.stringify(counts)})`);
ok(counts['(none)'] === 8, 'template carries identity + headings');
const codes = (await q(
  `select distinct ki_code from form_template_fields where template_id=$1 and ki_code is not null order by 1`,
  [tpl.id])).map((r) => r.ki_code);
ok(codes.length === 7 && codes[0] === 1 && codes[6] === 7, 'every KI code 1..7 is tagged');
ok((await as(pres, `select count(*)::int n from form_templates_list()`))[0].n === 1,
  'template list is readable by a signed-in user');

// ---------------------------------------------------------- creating
ok((await as(pres, `select event_form_summary($1) j`, [ev]))[0].j === null,
  'no form yet → the event summary is null');
ok((await as(s1, `select event_form_summary($1) j`, [ev]))[0].j === null,
  'a student gets no event summary');

let e = await err(s1, `select create_form_from_template($1,'ki')`, [ev]);
ok(e?.includes('FORM:not_allowed'), 'a student cannot create a form');
e = await err(null, `select create_form_from_template($1,'ki')`, [ev], 'anon');
ok(e !== null, 'a guest cannot create a form');
e = await err(otherPres, `select create_form_from_template($1,'ki')`, [ev]);
ok(e?.includes('FORM:not_allowed'), "another club's president cannot create this form");

const form = (await as(officer, `select create_form_from_template($1,'ki') f`, [ev]))[0].f;
ok(!!form, "an officer of the event's club creates the form");
ok((await q(`select count(*)::int n from form_fields where form_id=$1`, [form]))[0].n === 28,
  'the fields are copied (28)');
ok((await q(`select template_id from event_forms where id=$1`, [form]))[0].template_id === tpl.id,
  'the form remembers which template it came from');

// copying, not referencing: a later template edit must not reach the form
await q(`update form_template_fields set label='CHANGED' where template_id=$1 and sort=60`, [tpl.id]);
ok((await q(`select label from form_fields where form_id=$1 and sort=60`, [form]))[0].label ===
  'KI1 Kemahiran Berkomunikasi', 'template edits do not rewrite a created form');

const summ = (await as(officer, `select event_form_summary($1) j`, [ev]))[0].j;
ok(summ !== null && summ.id === form && summ.status === 'draft' && summ.responses === 0,
  'the summary points at the draft');
ok((await as(s1, `select event_open_form($1) f`, [ev]))[0].f === null,
  'a draft is not offered as the form to answer');

e = await err(officer, `select create_form_from_template($1,'ki')`, [ev]);
ok(e === null, 'a draft form may be created alongside');

// blank start — the editor's "from nothing" and "from a pasted list" paths
const blank = (await as(officer, `select create_blank_form($1,'Borang saya') f`, [ev]))[0].f;
ok(!!blank, 'an officer creates a blank form');
ok((await q(`select count(*)::int n from form_fields where form_id=$1`, [blank]))[0].n === 0,
  'a blank form starts with no fields');
e = await err(s1, `select create_blank_form($1,null)`, [ev]);
ok(e?.includes('FORM:not_allowed'), 'a student cannot create a blank form');

// ---------------------------------------------------------- the editor
const fields = await q(`select * from form_fields where form_id=$1 order by sort`, [form]);
const bySort = (n) => fields.find((f) => f.sort === n);

// relabel one, drop the "Cadangan" long text, keep the rest
const edited = fields
  .filter((f) => f.sort !== 280)
  .map((f) => ({
    id: f.id, kind: f.kind,
    label: f.sort === 60 ? 'KI1 Komunikasi (edited)' : f.label,
    help: f.help, required: f.required, options: f.options,
    analysis: f.analysis, ki_code: f.ki_code,
  }));
let n = (await as(officer, `select save_event_form($1,$2,$3)`,
  [form, JSON.stringify({ title: 'Laporan KI — Quiz' }), JSON.stringify(edited)]));
ok(true, 'the editor saves a whole field list');
ok((await q(`select label from form_fields where id=$1`, [bySort(60).id]))[0].label ===
  'KI1 Komunikasi (edited)', 'a relabel lands');
ok((await q(`select count(*)::int n from form_fields where form_id=$1`, [form]))[0].n === 27,
  'a dropped field is deleted');

// bad definitions are refused
const heading = edited.find((f) => f.kind === 'heading');
const headingBad = JSON.parse(JSON.stringify(edited));
headingBad.find((f) => f.id === heading.id).analysis = 'feedback';
e = await err(officer, `select save_event_form($1,'{}'::jsonb,$2)`, [form, JSON.stringify(headingBad)]);
ok(e?.includes('FORM:analysis_needs_rating'), 'only ratings may carry an analysis tag');

const ratingField = edited.find((f) => f.analysis === 'feedback');
const bad = JSON.parse(JSON.stringify(edited));
const badRating = bad.find((f) => f.id === ratingField.id);
badRating.analysis = 'feedback';
badRating.ki_code = 3;
e = await err(officer, `select save_event_form($1,'{}'::jsonb,$2)`, [form, JSON.stringify(bad)]);
ok(e?.includes('FORM:bad_ki_code'), 'feedback may not carry a KI code');

const bad2 = JSON.parse(JSON.stringify(edited));
bad2.push({ kind: 'rating', label: 'Extra A', required: false, options: { min: 1, max: 5 }, analysis: 'ki_pre', ki_code: 1 });
bad2.push({ kind: 'rating', label: 'Extra B', required: false, options: { min: 1, max: 5 }, analysis: 'ki_pre', ki_code: 2 });
e = await err(officer, `select save_event_form($1,'{}'::jsonb,$2)`, [form, JSON.stringify(bad2)]);
ok(e?.includes('FORM:too_many_ki'), 'more than seven KI fields per phase is refused');

// ---------------------------------------------------------- publishing
await as(pres, `select publish_form($1)`, [form]);
ok((await q(`select status from event_forms where id=$1`, [form]))[0].status === 'open', 'publish opens the form');
ok((await as(s1, `select event_open_form($1) f`, [ev]))[0].f === form,
  'a student finds the open form to answer');
ok((await as(null, `select event_open_form($1) f`, [ev], 'anon'))[0].f === form,
  'a guest can find it too — it reveals only that a form exists');
e = await err(officer, `select publish_form($1)`, [form]);
ok(e?.includes('FORM:not_draft'), 'publishing twice is refused');

// ---------------------------------------------------------- answering
const live = await q(`select * from form_fields where form_id=$1 order by sort`, [form]);
const answerable = live.filter((f) => f.kind !== 'heading');

function answersFor(ratings = {}) {
  const out = {};
  for (const f of answerable) {
    if (f.kind === 'rating') {
      out[f.id] = ratings[f.ki_code] ?? 4;
    } else if (f.kind === 'single_choice') {
      out[f.id] = f.options.choices[0];
    } else if (f.kind === 'student_id') {
      out[f.id] = '2023837334';
    } else if (f.kind === 'short_text') {
      out[f.id] = 'AHMAD DANEIL';
    } else if (f.kind === 'long_text') {
      out[f.id] = 'Tiada';
    }
  }
  return out;
}

const r1 = await as(s1, `select submit_form_response($1,null,$2,$3) r`,
  [form, 'peserta', JSON.stringify(answersFor())]);
ok(r1[0].r === 'ok', 'a student submits');

// KI2 = 4 for s1. A second participant sends 5, so S1's KI2 mean must be 4.5.
const a2 = answersFor({ 2: 5 });
const r2 = await as(s2, `select submit_form_response($1,null,$2,$3) r`,
  [form, 'peserta', JSON.stringify(a2)]);
ok(r2[0].r === 'ok', 'a second student submits');

// An organiser answers too: after-only, and must not enter S1.
const a3 = answersFor({ 2: 1 });
const r3 = await as(pres, `select submit_form_response($1,null,$2,$3) r`,
  [form, 'penganjur', JSON.stringify(a3)]);
ok(r3[0].r === 'ok', 'an organiser submits as penganjur');

const an = (await as(pres, `select form_analysis($1) a`, [form]))[0].a;
ok(an.responses.peserta === 2 && an.responses.penganjur === 1, 'response counts split by role');
const ki2 = an.s1.find((x) => x.ki_code === 2);
ok(ki2.n_before === 2 && Number(ki2.mean_before) === 4.5,
  `S1 KI2 before = 4.5 over 2 (got ${ki2.mean_before} over ${ki2.n_before})`);
ok(ki2.n_after === 2, 'S1 counts only peserta answers');
const ki2org = an.s2.find((x) => x.ki_code === 2);
ok(ki2org.n_after === 1 && Number(ki2org.mean_after) === 1,
  'S2 sees the organiser only, not the students');
ok(an.s3.length === 6 && Number(an.s3[0].mean) === 4, 'S3 lists the six feedback items');

// ---------------------------------------------------------- refusals
e = await err(s3, `select submit_form_response($1,null,'peserta','{}'::jsonb)`, [form]);
ok(e?.includes('FORM:required'), 'a missing required answer is refused');

const over = answersFor();
over[live.find((f) => f.analysis === 'ki_post' && f.ki_code === 3).id] = 9;
e = await err(s3, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(over)]);
ok(e?.includes('FORM:bad_rating'), 'a rating above the scale is refused');

const frac = answersFor();
frac[live.find((f) => f.analysis === 'ki_post' && f.ki_code === 3).id] = 3.5;
e = await err(s3, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(frac)]);
ok(e?.includes('FORM:bad_rating'), 'a fractional rating is refused');

const pick = live.find((f) => f.kind === 'single_choice');
const badChoice = answersFor();
badChoice[pick.id] = 'Bukan peserta';
e = await err(s3, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(badChoice)]);
ok(e?.includes('FORM:bad_choice'), 'an option outside the list is refused');

e = await err(null, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(answersFor())], 'anon');
ok(e !== null, 'a guest cannot submit');

// unknown keys are dropped rather than stored
const extra = answersFor();
extra['00000000-0000-0000-0000-000000000000'] = 'junk';
await as(s3, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(extra)]);
const saved = (await q(`select answers from form_responses where form_id=$1 and user_id=$2`, [form, s3]))[0].answers;
ok(!('00000000-0000-0000-0000-000000000000' in saved), 'unknown answer keys are dropped');

// ---------------------------------------------------------- edit after answers
const liveFields = await q(`select * from form_fields where form_id=$1 order by sort`, [form]);
const withAnswers = liveFields.map((f) => ({
  id: f.id, kind: f.kind, label: f.label, help: f.help, required: f.required,
  options: f.options, analysis: f.analysis, ki_code: f.ki_code,
}));
const retagged = JSON.parse(JSON.stringify(withAnswers));
const choice = retagged.find((f) => f.kind === 'single_choice');
choice.kind = 'short_text';
choice.options = null;
e = await err(officer, `select save_event_form($1,'{}'::jsonb,$2)`, [form, JSON.stringify(retagged)]);
ok(e?.includes('FORM:kind_has_answers'), 'a field with answers cannot change kind');

const removed = JSON.parse(JSON.stringify(withAnswers)).filter((f) => f.id !== choice.id);
e = await err(officer, `select save_event_form($1,'{}'::jsonb,$2)`, [form, JSON.stringify(removed)]);
ok(e?.includes('FORM:field_has_answers'), 'a field with answers cannot be removed');

// ---------------------------------------------------------- reading answers
e = await err(s1, `select * from form_response_list($1)`, [form]);
ok(e?.includes('FORM:not_allowed'), 'a student cannot read the response list');
const list = await as(officer, `select * from form_response_list($1)`, [form]);
ok(list.length === 4, `the officer sees all four responses (got ${list.length})`);
ok(list.every((r) => r.student_id === null || /^[0-9]{6,12}$/.test(r.student_id)),
  'the matric comes back as digits');
e = await err(otherPres, `select form_analysis($1)`, [form]);
ok(e?.includes('FORM:not_allowed'), "another club's officer cannot read the analysis");

// ---------------------------------------------------------- require_rsvp
const current = (await q(
  `select id, kind, label, help, required, options, analysis, ki_code
   from form_fields where form_id=$1 order by sort`, [form]))
  .map((f) => ({
    id: f.id, kind: f.kind, label: f.label, help: f.help, required: f.required,
    options: f.options, analysis: f.analysis, ki_code: f.ki_code,
  }));
await as(officer, `select save_event_form($1,$2,$3)`,
  [form, JSON.stringify({ require_rsvp: true }), JSON.stringify(current)]);
e = await err(await user('late'), `select submit_form_response($1,null,'peserta',$2)`,
  [form, JSON.stringify(answersFor())]);
ok(e?.includes('FORM:join_first'), 'require_rsvp refuses a non-participant');

await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [ev, s3]);
e = await err(s3, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(answersFor())]);
ok(e === null, 'joining first satisfies require_rsvp');

// ---------------------------------------------------------- closing
await as(officer, `select close_form($1)`, [form]);
ok((await as(s2, `select event_open_form($1) f`, [ev]))[0].f === null,
  'a closed form is no longer offered');
e = await err(s2, `select submit_form_response($1,null,'peserta',$2)`, [form, JSON.stringify(answersFor())]);
ok(e?.includes('FORM:closed'), 'a closed form refuses new answers');
ok((await as(s2, `select form_public($1) p`, [form]))[0].p.form.status === 'closed',
  'the read model still works when closed');
ok((await as(null, `select form_public($1) p`, [form], 'anon'))[0].p.can_answer === false,
  'a guest cannot answer a published form');

// ---------------------------------------------------------- cascade
const before = (await q(`select count(*)::int n from form_responses`))[0].n;
// the stub's event_participants has no ON DELETE CASCADE, so clear it first
await q(`delete from event_participants where event_id=$1`, [ev]);
await q(`delete from events where id=$1`, [ev]);
ok((await q(`select count(*)::int n from form_responses`))[0].n < before, 'deleting the event removes responses');
ok((await q(`select count(*)::int n from form_fields`))[0].n === 0, 'and its fields');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
