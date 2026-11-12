// Form short links and link previews (20261112001100). Applies every
// migration twice against the moderation stub schema in PGlite, then checks
// the short-name rules, who may set one, the /f/<key> lookup and what the
// link card may reveal.
//
//   cd supabase/tests
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node forms/form_short_links_test.mjs ../..

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

const form = (await as(alice, `select create_standalone_form('SUS survey') f`))[0].f;
await as(alice, `select save_event_form($1,'{"intro":"Tell us how the app feels"}'::jsonb,$2::jsonb)`,
  [form, JSON.stringify([{ kind: 'short_text', label: 'Q', required: false }])]);
await as(alice, `select publish_form($1)`, [form]);
const form2 = (await as(bob, `select create_standalone_form('Other') f`))[0].f;
const setSlug = (uid, id, slug) => as(uid, `select set_form_slug($1,$2) s`, [id, slug]);
const setSlugErr = (uid, id, slug) => err(uid, `select set_form_slug($1,$2)`, [id, slug]);

// ---------------------------------------------------------- rules
for (const bad of ['ab', 'a'.repeat(41), '-start', 'end-', 'two--dashes', 'has space', 'émoji', 'UP_per']) {
  const e = await setSlugErr(alice, form, bad);
  ok(e?.includes('FORM:slug_bad'), `"${bad}" is refused as malformed`);
}
for (const bad of ['uitm-survey', 'official-form', 'borang-rasmi', 'login-here', 'mykerawang-team',
                   'reset-password', 'bank-refund', 'get-otp', 'your-pin', 'edit', 'new']) {
  const e = await setSlugErr(alice, form, bad);
  ok(e?.includes('FORM:slug_blocked'), `"${bad}" is refused as misleading or reserved`);
}
for (const fine of ['pinjam-buku', 'hepi-day', 'abc', 'a'.repeat(40)]) {
  const e = await setSlugErr(alice, form, fine);
  ok(e === null, `"${fine}" is allowed`);
}

// ---------------------------------------------------------- setting
ok((await setSlug(alice, form, '  SUS-Survey '))[0].s === 'sus-survey', 'the maker sets a name; it is tidied');
ok((await q(`select slug from event_forms where id=$1`, [form]))[0].slug === 'sus-survey', 'it is stored');
let e = await setSlugErr(bob, form, 'mine-now');
ok(e?.includes('FORM:not_allowed'), "someone else cannot set alice's short name");
e = await err(null, `select set_form_slug($1,'x-guest')`, [form], 'anon');
ok(e !== null, 'a guest cannot set one');
e = await setSlugErr(bob, form2, 'sus-survey');
ok(e?.includes('FORM:slug_taken'), 'a name in use is refused');
e = await setSlugErr(bob, form2, 'SUS-SURVEY');
ok(e?.includes('FORM:slug_taken'), 'names are case-insensitive');
ok((await setSlug(alice, form, 'sus-survey'))[0].s === 'sus-survey', 'setting the same name again is fine');

const ev = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Talk',now()) returning id`, [alice]))[0].id;
const fEv = (await as(alice, `select create_blank_form($1,'Event form') f`, [ev]))[0].f;
e = await setSlugErr(alice, fEv, 'talk-form');
ok(e?.includes('FORM:event_form'), 'event forms keep their event link');

// ---------------------------------------------------------- lookup
ok((await guest(`select form_id_for_key('sus-survey') id`))[0].id === form, 'a guest resolves the short name');
ok((await guest(`select form_id_for_key('SUS-Survey') id`))[0].id === form, 'in any case');
ok((await guest(`select form_id_for_key($1) id`, [form]))[0].id === form, 'the long id still resolves');
ok((await guest(`select form_id_for_key('no-such-form') id`))[0].id === null, 'an unknown name is null');
ok((await guest(`select form_id_for_key('00000000-0000-0000-0000-000000000000') id`))[0].id === null,
  'an unknown id is null');
let pub = (await guest(`select form_public($1) j`, [form]))[0].j;
ok(pub.form.slug === 'sus-survey', 'the answer page knows the short name');

// ---------------------------------------------------------- the link card
let card = (await guest(`select form_preview('sus-survey') c`))[0].c;
ok(card?.title === 'SUS survey' && card.slug === 'sus-survey' && card.id === form,
  'the card has the title');
ok(card.description === null, 'a private form keeps its description off the card');
await as(alice, `select set_form_public($1, true)`, [form]);
card = (await guest(`select form_preview($1) c`, [form]))[0].c;
ok(card.description === 'Tell us how the app feels', 'a public form shows its description');
await as(alice, `select save_event_form($1,'{"intro":"  "}'::jsonb,$2::jsonb)`,
  [form, JSON.stringify([{ id: (await q(`select id from form_fields where form_id=$1`, [form]))[0].id,
    kind: 'short_text', label: 'Q', required: false }])]);
card = (await guest(`select form_preview($1) c`, [form]))[0].c;
ok(card.description === null, 'a blank description stays blank');
await q(`update event_forms set is_hidden = true where id=$1`, [form]);
ok((await guest(`select form_preview('sus-survey') c`))[0].c === null, 'a removed form gets no card');
e = await setSlugErr(alice, form, 'new-name');
ok(e?.includes('FORM:removed'), 'a removed form cannot change its name');
await q(`update event_forms set is_hidden = false where id=$1`, [form]);
ok((await guest(`select form_preview('no-such-form') c`))[0].c === null, 'an unknown name gets no card');

// ---------------------------------------------------------- clearing
ok((await setSlug(alice, form, ''))[0].s === null, 'clearing removes the name');
ok((await guest(`select form_id_for_key('sus-survey') id`))[0].id === null, 'and the short link stops working');
ok((await setSlug(bob, form2, 'sus-survey'))[0].s === 'sus-survey', 'a freed name can be taken by someone else');
e = await err(null, `update event_forms set slug = 'Bad Name' where id = '${form}'`, [], 'postgres');
ok(e !== null, 'the table refuses a malformed name even without the function');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
