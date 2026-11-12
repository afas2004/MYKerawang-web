// Event series + online / hybrid events (20261112001100_event_series.sql).
// Applies every migration twice against the moderation stub, like the others.
//
//   node supabase/tests/events/event_series_test.mjs .

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
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '30 days')`, [id]);
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

const organiser = await user('organiser');
const other = await user('other');

// ---- columns and defaults
const cols = (await q(`select column_name from information_schema.columns
                       where table_name = 'events'
                         and column_name in ('series_id','location_mode','online_url')`))
  .map((r) => r.column_name).sort();
ok(cols.join() === 'location_mode,online_url,series_id', 'events gained series_id, location_mode, online_url');

const plain = (await q(`insert into public.events (organizer_id, title) values ($1,'Plain') returning *`,
  [organiser]))[0];
ok(plain.location_mode === 'in_person' && plain.series_id === null && plain.online_url === null,
  'an existing-style insert defaults to in person, no series');

// ---- location mode and online link
let e = await err(organiser,
  `insert into public.events (organizer_id, title, location_mode) values (auth.uid(),'X','zoom')`);
ok(e?.includes('events_location_mode_valid'), 'an unknown location mode is refused');

e = await err(organiser,
  `insert into public.events (organizer_id, title, location_mode, online_url)
   values (auth.uid(),'X','online','http://meet.example/abc')`);
ok(e?.includes('events_online_url_https'), 'a plain http meeting link is refused');

e = await err(organiser,
  `insert into public.events (organizer_id, title, location_mode, online_url)
   values (auth.uid(),'X','online','javascript:alert(1)')`);
ok(e?.includes('events_online_url_https'), 'a javascript: meeting link is refused');

const online = await as(organiser,
  `insert into public.events (organizer_id, title, location_mode, online_url)
   values (auth.uid(),'Online talk','hybrid','https://meet.google.com/abc-defg-hij') returning id`);
ok(Array.isArray(online) && online.length === 1, 'a hybrid event with an https meeting link is accepted');

// ---- series ownership
const series = await as(organiser,
  `insert into public.event_series (organizer_id, repeat_rule)
   values (auth.uid(), '{"kind":"weekly","every":1,"weekdays":[4]}') returning id`);
ok(Array.isArray(series) && series.length === 1, 'an organiser can create a series');
const sid = series[0].id;

e = await err(other,
  `insert into public.event_series (organizer_id) values ($1)`, [organiser]);
ok(e !== null, 'nobody can create a series in someone else\'s name');

e = await err(organiser,
  `insert into public.event_series (organizer_id, repeat_rule) values (auth.uid(), '{"kind":"monthly"}')`);
ok(e?.includes('event_series_rule_shape'), 'an unknown repeat kind is refused');

// Many sessions in one statement, as the app publishes them.
const made = await as(organiser,
  `insert into public.events (organizer_id, title, series_id, start_datetime, end_datetime, join_deadline)
   select auth.uid(), 'Kelas Quran', $1,
          timestamptz '2026-11-19 20:30+08' + (n * interval '7 days'),
          timestamptz '2026-11-19 22:00+08' + (n * interval '7 days'),
          timestamptz '2026-11-19 20:30+08' + (n * interval '7 days')
   from generate_series(0, 8) n
   returning id`, [sid]);
if (!Array.isArray(made)) console.log(made.error);
ok(Array.isArray(made) && made.length === 9, 'nine weekly sessions are published in one insert');

e = await err(other,
  `insert into public.events (organizer_id, title, series_id) values (auth.uid(),'Hijack',$1)`, [sid]);
ok(e?.includes('EVENT:series_not_yours'), 'another user cannot add a session to your series');

e = await err(other,
  `insert into public.events (organizer_id, title, series_id)
   values (auth.uid(),'Bogus', gen_random_uuid())`);
ok(e !== null, 'a session cannot point at a series that does not exist');

// Moving your own one-off event into the series is fine; moving it into
// someone else's is not.
const mine = (await as(organiser,
  `insert into public.events (organizer_id, title) values (auth.uid(),'Extra date') returning id`))[0].id;
const moved = await as(organiser,
  `update public.events set series_id = $1 where id = $2 returning series_id`, [sid, mine]);
ok(Array.isArray(moved) && moved[0]?.series_id === sid, 'your own event can be added to your series');

const theirSeries = (await as(other,
  `insert into public.event_series (organizer_id) values (auth.uid()) returning id`))[0].id;
e = await err(organiser,
  `update public.events set series_id = $1 where id = $2`, [theirSeries, mine]);
ok(e?.includes('EVENT:series_not_yours'), 'your event cannot be moved into someone else\'s series');

// ---- 26-date cap, counted inside one statement too
const big = (await as(organiser,
  `insert into public.event_series (organizer_id) values (auth.uid()) returning id`))[0].id;
e = await err(organiser,
  `insert into public.events (organizer_id, title, series_id)
   select auth.uid(), 'Too many', $1 from generate_series(1, 27)`, [big]);
ok(e?.includes('EVENT:series_full'), '27 dates in one insert is refused');
const after = await q(`select count(*)::int n from public.events where series_id = $1`, [big]);
ok(after[0].n === 0, '…and nothing from that insert is kept');

const full = await as(organiser,
  `insert into public.events (organizer_id, title, series_id)
   select auth.uid(), 'Exactly 26', $1 from generate_series(1, 26) returning id`, [big]);
ok(Array.isArray(full) && full.length === 26, '26 dates are accepted');
e = await err(organiser,
  `insert into public.events (organizer_id, title, series_id) values (auth.uid(),'27th',$1)`, [big]);
ok(e?.includes('EVENT:series_full'), 'a 27th date is refused later too');

// ---- each session behaves as its own event
const firstId = made[0].id;
await as(organiser, `update public.events set cancelled_at = now() where id = $1`, [firstId]);
const states = await q(
  `select count(*) filter (where cancelled_at is not null)::int c, count(*)::int n
   from public.events where series_id = $1`, [sid]);
ok(states[0].c === 1 && states[0].n === 10, 'cancelling one session leaves the others running');

// ---- the new-account limit still applies per date (documented, not changed)
const fresh = (await q('select gen_random_uuid() id'))[0].id;
await q(`insert into auth.users (id) values ($1)`, [fresh]);
await q(`insert into public.profiles (id, username, display_name) values ($1,'fresh','Fresh')`, [fresh]);
const freshSeries = (await as(fresh,
  `insert into public.event_series (organizer_id) values (auth.uid()) returning id`))[0].id;
e = await err(fresh,
  `insert into public.events (organizer_id, title, series_id)
   select auth.uid(), 'Weekly', $1 from generate_series(1, 3)`, [freshSeries]);
ok(e?.includes('MOD:rate_limited:event'),
  'a day-old account still hits the 2-events-an-hour limit with a 3-date series');

// ---- reading
const anonRead = await as(null, `select id from public.event_series where id = $1`, [sid], 'anon');
ok(Array.isArray(anonRead) && anonRead.length === 1, 'guests can read a series');

// ---- deleting a series keeps its sessions as one-off events
e = await err(other, `delete from public.event_series where id = $1`, [sid]);
const still = await q(`select count(*)::int n from public.event_series where id = $1`, [sid]);
ok(still[0].n === 1, 'another user cannot delete your series');
await as(organiser, `delete from public.event_series where id = $1`, [sid]);
const orphans = await q(`select count(*)::int n from public.events
                         where title = 'Kelas Quran' and series_id is null`);
ok(orphans[0].n === 9, 'deleting the series keeps every session as a normal event');

console.log(failures === 0 ? '\nALL PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
