// Import from Google Form (20261114001100). Applies every migration twice
// against the moderation stub schema in PGlite, then checks the link rules,
// who may call import_google_form(), redirects, sign-in detection, data
// extraction, the size cap and the rate limit.
//
// PGlite has no `http` extension, so google_form_http_get() (the one function
// that touches the network) is replaced by a stub that answers from a table
// of fake responses. What this cannot test: the real fetch from Google
// (timeouts, Google's real redirects and headers) — that needs the live
// database.
//
//   cd supabase/tests
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node forms/google_form_import_test.mjs ../..

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
console.log('migrations applied twice OK (no http extension here: the migration still applies)');

// Before the stub: the real fetcher says "unavailable" when the extension is
// missing, and the RPC passes that on.
async function user(name) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '10 days')`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,'student')`,
    [id, name]);
  return id;
}
const alice = await user('alice');
const bob = await user('bob');
const carol = await user('carol');

const imp = async (uid, url) => (await as(uid, `select import_google_form($1) r`, [url]))[0].r;
{
  const r = await imp(carol, 'https://forms.gle/abcd1234');
  ok(r.ok === false && r.reason === 'unavailable', 'without the http extension: "unavailable"');
}

// ---------------------------------------------------------- the stub
await db.exec(`
  create table public.test_fake_http (url text primary key, resp jsonb);
  create or replace function public.google_form_http_get(p_url text)
  returns jsonb language plpgsql as $$
  declare r jsonb;
  begin
    insert into public.test_fake_http_calls(url) values (p_url);
    select resp into r from public.test_fake_http where url = p_url;
    if r is null then raise exception 'no fake for %', p_url; end if;
    return r;
  end $$;
  create table public.test_fake_http_calls (n serial, url text);
  revoke execute on function public.google_form_http_get(text) from public, anon, authenticated;
`);
const fake = (url, resp) =>
  q(`insert into public.test_fake_http values ($1, $2::jsonb)
     on conflict (url) do update set resp = excluded.resp`, [url, JSON.stringify(resp)]);
const calls = async () => (await q(`select url from public.test_fake_http_calls order by n`)).map((r) => r.url);
const clearCalls = () => q(`truncate public.test_fake_http_calls`);

const formJson = read(path.join(repo, 'test', 'fixtures', 'google_forms', 'upi_recruitment.json')).trim();
const page = read(path.join(repo, 'test', 'fixtures', 'google_forms', 'upi_recruitment.html'));
const signInPage = read(path.join(repo, 'test', 'fixtures', 'google_forms', 'sign_in.html'));
const brokenPage = read(path.join(repo, 'test', 'fixtures', 'google_forms', 'broken.html'));
const page200 = (body) => ({ status: 200, location: null, size: body.length, body });
const redirect = (to) => ({ status: 302, location: to, size: 0, body: '' });

const viewform = (id) => `https://docs.google.com/forms/d/e/${id}/viewform`;

// ---------------------------------------------------------- link rules
const norm = async (u) => (await q(`select google_form_url($1) u`, [u]))[0].u;
ok(await norm('https://forms.gle/qphAyf6jEiWHK45o6') === 'https://forms.gle/qphAyf6jEiWHK45o6', 'short link kept');
ok(await norm('https://forms.gle/qphAyf6jEiWHK45o6?x=1') === 'https://forms.gle/qphAyf6jEiWHK45o6', 'short link query dropped');
ok(await norm('https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC-Dh9A/viewform?usp=send_form')
  === 'https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC-Dh9A/viewform', 'long link rebuilt');
ok(await norm('https://docs.google.com/forms/u/0/d/1AbCdEfGhIjKlMn/edit')
  === 'https://docs.google.com/forms/d/1AbCdEfGhIjKlMn/viewform', 'edit link becomes the viewform');
for (const bad of [
  'http://forms.gle/abcd1234',
  'forms.gle/abcd1234',
  'https://forms.gle@evil.com/abcd',
  'https://forms.gle/abcd@evil.com',
  'https://forms.gle.evil.com/abcd',
  'https://docs.google.com.evil.com/forms/d/e/1FAIpQLSfAUqIC/viewform',
  'https://docs.google.com/document/d/1AbCdEfGhIjKlMn/edit',
  'https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC/viewform/../../x',
  'https://localhost/forms/d/e/1FAIpQLSfAUqIC/viewform',
  'https://169.254.169.254/latest/meta-data',
  'https://forms.gle/ab cd',
  'https://forms.gle/abcd\\x',
  `https://forms.gle/${'a'.repeat(600)}`,
  '',
  null,
]) {
  ok(await norm(bad) === null, `refused: ${JSON.stringify(bad)?.slice(0, 60)}`);
}

// ---------------------------------------------------------- who may call
{
  const e = await err(null, `select import_google_form('https://forms.gle/abcd1234')`, [], 'anon');
  ok(e !== null && /permission denied/.test(e), 'guests cannot call it');
  const e2 = await err(null, `select import_google_form('https://forms.gle/abcd1234')`);
  ok(e2?.includes('FORM:login_required'), 'no user id: login_required');
  const e3 = await err(alice, `select google_form_http_get('https://evil.com')`);
  ok(e3 !== null && /permission denied/.test(e3), 'the raw fetcher is not callable by users');
  const e4 = await err(alice, `select count(*) from google_form_imports`);
  ok(e4 !== null && /permission denied/.test(e4), 'the rate-limit log is not readable by users');
}

// ---------------------------------------------------------- happy path
await fake('https://forms.gle/qphAyf6jEiWHK45o6', redirect(viewform('UPI123456789') + '?usp=send_form'));
await fake(viewform('UPI123456789'), page200(page));
await clearCalls();
{
  const r = await imp(alice, '  https://forms.gle/qphAyf6jEiWHK45o6  ');
  ok(r.ok === true, 'forms.gle → viewform → data');
  ok(Array.isArray(r.data) && r.data[1][8].startsWith('PENCARIAN AJK'), 'the data is the form array');
  ok(JSON.stringify(r.data) === JSON.stringify(JSON.parse(formJson)), 'the data matches the fixture exactly');
  const c = await calls();
  ok(c.length === 2 && c[0] === 'https://forms.gle/qphAyf6jEiWHK45o6' && c[1] === viewform('UPI123456789'),
    'fetched only the normalised short link, then the checked redirect');
}

// A relative redirect stays on the same host.
await fake(viewform('REL123456789'), redirect('/forms/d/e/REL2345678901/viewform'));
await fake(viewform('REL2345678901'), page200(page));
ok((await imp(alice, viewform('REL123456789'))).ok === true, 'relative redirect followed on the same host');

// ---------------------------------------------------------- refusals
// Each refusal check starts with an empty log, so the rate limit (tested
// below) does not get in the way.
const reason = async (url, uid = bob) => {
  await q(`delete from google_form_imports`);
  return (await imp(uid, url)).reason;
};

ok(await reason('https://example.com/form') === 'bad_url', 'not a Google Form: bad_url');

await fake('https://forms.gle/evil1234', redirect('https://evil.com/steal'));
await clearCalls();
ok(await reason('https://forms.gle/evil1234') === 'bad_redirect', 'redirect off Google: bad_redirect');
ok((await calls()).length === 1, '…and the off-Google address is never fetched');

await fake('https://forms.gle/meta1234', redirect('http://169.254.169.254/latest/meta-data'));
ok(await reason('https://forms.gle/meta1234') === 'bad_redirect', 'redirect to an internal address: bad_redirect');

await fake(viewform('SIGNIN123456'), redirect('https://accounts.google.com/v3/signin/identifier?continue=x'));
ok(await reason(viewform('SIGNIN123456')) === 'sign_in', 'redirect to Google sign-in: sign_in');

await fake(viewform('SIGNIN223456'), page200(signInPage));
ok(await reason(viewform('SIGNIN223456')) === 'sign_in', 'sign-in page (redirect already followed): sign_in');

await fake(viewform('FORBID123456'), { status: 403, location: null, size: 0, body: '' });
ok(await reason(viewform('FORBID123456')) === 'sign_in', '403: sign_in');

await fake(viewform('CLOSED123456'), redirect('https://docs.google.com/forms/d/e/CLOSED123456/closedform'));
ok(await reason(viewform('CLOSED123456')) === 'closed', 'closed form: closed');

await fake(viewform('GONE12345678'), { status: 404, location: null, size: 0, body: '' });
ok(await reason(viewform('GONE12345678')) === 'not_found', '404: not_found');

await fake(viewform('ERR123456789'), { status: 500, location: null, size: 0, body: '' });
ok(await reason(viewform('ERR123456789')) === 'fetch_failed', '500: fetch_failed');

await fake(viewform('BIG123456789'), { status: 200, location: null, size: 2500000, body: 'x' });
ok(await reason(viewform('BIG123456789')) === 'too_big', 'over 2 MB: too_big');

await fake(viewform('BROKEN123456'), page200(brokenPage));
ok(await reason(viewform('BROKEN123456')) === 'no_data', 'cut-off page: no_data');

await fake(viewform('BADJSON12345'), page200('<script>var FB_PUBLIC_LOAD_DATA_ = [1,2,;</script>'));
ok(await reason(viewform('BADJSON12345')) === 'no_data', 'invalid JSON: no_data');

await fake(viewform('NOTARRAY1234'), page200('<script>var FB_PUBLIC_LOAD_DATA_ = {"a":1};</script>'));
ok(await reason(viewform('NOTARRAY1234')) === 'no_data', 'JSON that is not an array: no_data');

await fake(viewform('PLAIN1234567'), page200('<html>hello</html>'));
ok(await reason(viewform('PLAIN1234567')) === 'no_data', 'page without form data: no_data');

await fake(viewform('LOOP12345678'), redirect(viewform('LOOP12345678')));
ok(await reason(viewform('LOOP12345678'), carol) === 'fetch_failed', 'redirect loop gives up: fetch_failed');

// ---------------------------------------------------------- rate limit
{
  await q(`delete from google_form_imports`);
  const results = [];
  for (let i = 0; i < 11; i++) results.push((await imp(alice, viewform('UPI123456789'))).ok);
  ok(results.slice(0, 10).every((x) => x === true), 'ten imports in ten minutes are fine');
  ok((await imp(alice, viewform('UPI123456789'))).reason === 'rate_limited', 'the eleventh is rate_limited');
  ok((await imp(bob, viewform('UPI123456789'))).ok === true, 'another user is not affected');
  // Ten minutes later the short window is clear, but the day still counts.
  await q(`update google_form_imports set created_at = now() - interval '11 minutes' where user_id = $1`, [alice]);
  ok((await imp(alice, viewform('UPI123456789'))).ok === true, 'after ten minutes: allowed again');
  await q(`insert into google_form_imports (user_id, created_at)
           select $1, now() - interval '2 hours' from generate_series(1, 30)`, [alice]);
  ok((await imp(alice, viewform('UPI123456789'))).reason === 'rate_limited', '30 in a day: rate_limited');
  const before = (await q(`select count(*)::int n from google_form_imports where user_id = $1`, [alice]))[0].n;
  await imp(alice, viewform('UPI123456789'));
  const after = (await q(`select count(*)::int n from google_form_imports where user_id = $1`, [alice]))[0].n;
  ok(before === after, 'a refused import is not counted');
  await q(`delete from auth.users where id = $1`, [carol]);
  ok((await q(`select count(*)::int n from google_form_imports where user_id = $1`, [carol]))[0].n === 0,
    "deleting an account deletes its import log");
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
