// Notifications v2 (20261114000100): preferences, grouping, the new kinds,
// event reminders and the push queue.
//
//   cd supabase/tests
//   node notifications/notifications_v2_test.mjs ../..

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
const mine = (uid, type) =>
  q(`select * from notifications where user_id = $1 and ($2::text is null or type = $2) order by created_at`, [uid, type ?? null]);
const token = (n) => 'tok_' + n + '_' + 'x'.repeat(30);

const author = await user('author');
const aina = await user('aina');
const hafiz = await user('hafiz');
const mei = await user('mei');
const organiser = await user('organiser');

// ---------------------------------------------------------------- comments
const post = (await q(`insert into posts (user_id, title, body) values ($1,'Futsal petang ni?','Siapa nak join') returning id`, [author]))[0].id;
let r = await as(aina, `insert into comments (post_id, user_id, body) values ($1,$2,'Saya!') returning id`, [post, aina]);
ok(Array.isArray(r), 'a member can comment (the trigger never blocks it)');
let n = await mine(author, 'comment');
ok(n.length === 1 && n[0].actor_id === aina && n[0].category === 'comments', 'post owner told about the comment, with the commenter as actor');
ok(n[0].data.comment_id === r[0].id && n[0].data.post_id === post, 'the notification points at the exact comment');
ok(n[0].push_due_at !== null, 'comments default to phone push');

await as(hafiz, `insert into comments (post_id, user_id, body) values ($1,$2,'Join')`, [post, hafiz]);
n = await mine(author, 'comment');
ok(n.length === 1 && n[0].count === 2, 'a second comment merges into the unread row (count 2)');
ok(n[0].actor_id === hafiz && n[0].actor_ids[0] === hafiz && n[0].actor_ids.includes(aina), 'latest actor first, earlier kept');
const also = await mine(aina, 'also_commented');
ok(also.length === 1 && also[0].actor_id === hafiz, 'earlier commenter told about the new comment');
ok((await mine(hafiz)).length === 0, 'nobody is told about their own comment');

await as(mei, `insert into comments (post_id, user_id, body, is_anonymous) values ($1,$2,'anon',true)`, [post, mei]);
n = await mine(author, 'comment');
ok(n[0].count === 3 && n[0].actor_id === null, 'anonymous comment merges without revealing the commenter');

await q(`update notifications set is_read = true where user_id = $1`, [author]);
await as(aina, `insert into comments (post_id, user_id, body) values ($1,$2,'lagi')`, [post, aina]);
n = await mine(author, 'comment');
ok(n.length === 2 && n[1].count === 1, 'after reading, a new comment starts a fresh row');

// event comment -> organiser
const ev = (await q(
  `insert into events (organizer_id, title, location, start_datetime) values ($1,'Gotong-royong','Dewan', now() + interval '3 days') returning id`,
  [organiser]))[0].id;
await as(aina, `insert into comments (event_id, user_id, body) values ($1,$2,'Pukul berapa?')`, [ev, aina]);
n = await mine(organiser, 'comment');
ok(n.length === 1 && n[0].data.event_id === ev && n[0].data.comment_id, 'event organiser told about a comment on the event');

// ---------------------------------------------------------------- preferences
r = await as(author, `insert into notification_settings (user_id, prefs) values ($1, '{"comments":"off"}')`, [author]);
ok(Array.isArray(r), 'a member saves their own settings');
r = await as(aina, `insert into notification_settings (user_id) values ($1)`, [author]);
ok(!Array.isArray(r), "nobody can write someone else's settings");
const before = JSON.stringify((await mine(author, 'comment')).map((x) => [x.id, x.count]));
await as(hafiz, `insert into comments (post_id, user_id, body) values ($1,$2,'x')`, [post, hafiz]);
ok(JSON.stringify((await mine(author, 'comment')).map((x) => [x.id, x.count])) === before,
  "'off' drops the notification (no new row, no merge)");

await as(author, `update notification_settings set prefs = '{"comments":"bell"}' where user_id = $1`, [author]);
await q(`update notifications set is_read = true where user_id = $1`, [author]);
await as(mei, `insert into comments (post_id, user_id, body) values ($1,$2,'y')`, [post, mei]);
n = (await mine(author, 'comment')).at(-1);
ok(n.is_read === false && n.push_due_at === null, "'bell' keeps it in the list but never pushes");

// account & safety cannot be switched off
await as(author, `update notification_settings set prefs = '{"account":"off"}' where user_id = $1`, [author]);
await q(`select mod_notify($1, 'Your post was hidden', 'x', '{}')`, [author]);
n = await mine(author, 'moderation');
ok(n.length === 1 && n[0].category === 'account' && n[0].push_due_at !== null, 'safety notices ignore "off" and push');

// client-side follow insert still works and is bell-only by default
r = await as(aina, `insert into notifications (user_id, actor_id, type, title, body, data) values ($1,$2,'follow','New follower','aina','{}')`, [hafiz, aina]);
ok(Array.isArray(r), 'client follow insert still accepted');
n = await mine(hafiz, 'follow');
ok(n.length === 1 && n[0].push_due_at === null && n[0].category === 'follows', 'follows default to bell only');
await as(hafiz, `insert into notification_settings (user_id, prefs) values ($1,'{"follows":"push"}')`, [hafiz]);
await as(mei, `insert into notifications (user_id, actor_id, type, title, body, data) values ($1,$2,'follow','New follower','mei','{}')`, [hafiz, mei]);
ok((await mine(hafiz, 'follow')).at(-1).push_due_at === null, 'follows can never be pushed');
r = await as(aina, `insert into notifications (user_id, actor_id, type, title) values ($1,$2,'follow','x')`, [hafiz, mei]);
ok(!Array.isArray(r), 'still cannot forge a notification from someone else');

// ---------------------------------------------------------------- form answers
const form = (await q(
  `insert into event_forms (event_id, owner_id, title, status) values (null,$1,'Borang Sukarelawan','open') returning id`,
  [organiser]))[0].id;
await q(`insert into form_responses (form_id, user_id, answers) values ($1,$2,'{}')`, [form, aina]);
await q(`insert into form_responses (form_id, user_id, answers) values ($1,$2,'{}')`, [form, hafiz]);
await q(`insert into form_responses (form_id, user_id, answers, guest_name) values ($1,null,'{}','Guest Ali')`, [form]);
n = await mine(organiser, 'form_answer');
ok(n.length === 1 && n[0].count === 3 && n[0].data.form_id === form, 'three answers make one grouped row');
ok(n[0].data.who === 'Guest Ali', 'the latest answerer is named (guest name too)');
ok(n[0].push_due_at !== null && new Date(n[0].push_due_at) >= new Date(n[0].created_at) - 1000,
  'grouped rows stay queued for a push');
await q(`insert into form_responses (form_id, user_id, answers) values ($1,$2,'{}')`, [form, organiser]);
ok((await mine(organiser, 'form_answer'))[0].count === 3, "the owner's own answer is not announced");

// ---------------------------------------------------------------- joins & changes
await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [ev, aina]);
await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [ev, mei]);
n = await mine(organiser, 'event_join');
ok(n.length === 1 && n[0].count === 2 && n[0].push_due_at === null, 'joins grouped, bell only by default');

await q(`update events set start_datetime = start_datetime + interval '30 minutes' where id = $1`, [ev]);
n = await mine(aina, 'event_changed');
ok(n.length === 1 && n[0].data.old_start && n[0].data.start && n[0].category === 'event_changes', 'participants told the time changed, old and new kept');
await q(`update events set location = 'Dewan Besar' where id = $1`, [ev]);
n = await mine(aina, 'event_changed');
ok(n.length === 1 && n[0].count === 2 && n[0].data.location === 'Dewan Besar', 'a second change merges');
await q(`update events set title = 'Gotong-royong Kolej' where id = $1`, [ev]);
ok((await mine(aina, 'event_changed'))[0].count === 2, 'a title edit is not a change worth announcing');

await q(`update events set cancelled_at = now() where id = $1`, [ev]);
n = await mine(mei, 'event_cancelled');
ok(n.length === 1 && n[0].data.event_id === ev && n[0].category === 'event_changes', 'cancellation now has its own type');

// ---------------------------------------------------------------- new events (opt-in)
await as(mei, `update notification_settings set prefs = '{"new_events":"bell"}' where user_id = $1`, [mei]);
await as(mei, `insert into notification_settings (user_id, prefs) values ($1,'{"new_events":"bell"}') on conflict (user_id) do update set prefs = excluded.prefs`, [mei]);
const ev2 = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Ceramah', now() + interval '40 minutes') returning id`, [organiser]))[0].id;
ok((await mine(mei, 'new_event')).length === 1, 'opted-in member hears about a new event');
ok((await mine(aina, 'new_event')).length === 0 && (await mine(aina, null)).every((x) => x.title !== 'New Event: Ceramah'),
  'everyone else does not (off by default)');

// ---------------------------------------------------------------- reminders
await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [ev2, hafiz]);
const evC = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Batal', now() + interval '30 minutes') returning id`, [organiser]))[0].id;
await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [evC, hafiz]);
await q(`update events set cancelled_at = now() where id = $1`, [evC]);
const ev3 = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Esok', now() + interval '1 day') returning id`, [organiser]))[0].id;
await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [ev3, hafiz]);
let made = (await q(`select make_event_reminders() n`))[0].n;
n = await mine(hafiz, 'event_reminder');
ok(made === 1 && n.length === 1 && n[0].data.event_id === ev2, 'one reminder: only the event within the hour, not cancelled or tomorrow');
made = (await q(`select make_event_reminders() n`))[0].n;
ok(made === 0, 'a reminder is sent once');
r = await as(hafiz, `select make_event_reminders()`);
ok(!Array.isArray(r), 'members cannot run the reminder job');

// ---------------------------------------------------------------- devices & push queue
r = await as(aina, `select register_push_token($1, 'web', 'Chrome on Android')`, [token('a')]);
ok(Array.isArray(r), 'a member registers this device');
r = await as(mei, `select register_push_token($1)`, [token('a')]);
ok(Array.isArray(r), 'the same browser signing in as someone else takes the token over');
ok((await q(`select user_id from push_tokens where token = $1`, [token('a')]))[0].user_id === mei, '...and it now belongs to them');
ok((await as(aina, `select * from push_tokens`)).length === 0, "the old owner can't see it any more");
await as(aina, `select register_push_token($1)`, [token('a2')]);
await as(hafiz, `select register_push_token($1)`, [token('h')]);
r = await as(aina, `select push_take(10)`);
ok(!Array.isArray(r), 'members cannot read the push queue');
r = await as(aina, `insert into push_tokens (token, user_id) values ($1,$2)`, [token('zz'), aina]);
ok(!Array.isArray(r), 'tokens only arrive through register_push_token');

// make everything due now, then take
await q(`update notifications set push_due_at = now() - interval '1 second' where push_due_at is not null`);
// quiet hours: aina's quiet window covers every hour -> held
await as(aina, `insert into notification_settings (user_id, quiet_start, quiet_end) values ($1,'00:00','23:59:59')`, [aina]);
const taken = await q(`select * from push_take(100)`);
const takenFor = (u) => taken.filter((t) => t.user_id === u);
ok(takenFor(aina).length === 0, 'quiet hours hold pushes (they stay in the bell)');
ok(takenFor(hafiz).some((t) => t.type === 'event_reminder' && t.tokens[0] === token('h')), 'reminder taken with the device token');
ok(takenFor(author).length === 0, 'no device, nothing to send');
ok((await q(`select count(*)::int c from notifications where push_due_at is not null`))[0].c === 0, 'the queue is empty afterwards');
ok((await q(`select count(*)::int c from push_take(100)`))[0].c === 0, 'nothing is sent twice');

// reminders still come during quiet hours
await q(`update notifications set push_due_at = now(), pushed_at = null where user_id = $1 and type = 'also_commented'`, [aina]);
const ev4 = (await q(`insert into events (organizer_id, title, start_datetime) values ($1,'Sekarang', now() + interval '20 minutes') returning id`, [organiser]))[0].id;
await q(`insert into event_participants (event_id, user_id) values ($1,$2)`, [ev4, aina]);
await q(`select make_event_reminders()`);
await q(`update notifications set push_due_at = now() - interval '1 second' where push_due_at is not null`);
const t2 = await q(`select * from push_take(100)`);
ok(t2.some((t) => t.user_id === aina && t.type === 'event_reminder') && !t2.some((t) => t.user_id === aina && t.type === 'also_commented'),
  'reminders break quiet hours, comments do not');

// grouping pace: a merge right after a push waits 15 minutes
await as(aina, `update notification_settings set quiet_enabled = false where user_id = $1`, [aina]);
await q(`update notifications set is_read = true where user_id = $1`, [aina]);
const post2 = (await q(`insert into posts (user_id, title) values ($1,'Dua') returning id`, [aina]))[0].id;
await as(hafiz, `insert into comments (post_id, user_id, body) values ($1,$2,'1')`, [post2, hafiz]);
let t3 = await q(`select * from push_take(100)`);
ok(t3.filter((t) => t.user_id === aina && t.type === 'comment').length === 1, 'first comment pushed at once');
await as(mei, `insert into comments (post_id, user_id, body) values ($1,$2,'2')`, [post2, mei]);
n = (await mine(aina, 'comment')).at(-1);
ok(n.count === 2 && new Date(n.push_due_at) - new Date(n.pushed_at) >= 14 * 60 * 1000,
  'second comment merged and its push waits 15 minutes after the last');
t3 = await q(`select * from push_take(100)`);
ok(!t3.some((t) => t.user_id === aina), '...so it is not sent yet');

// daily cap: 8 non-reminder pushes a day
await q(`update notifications set pushed_at = now(), category = 'comments' where user_id = $1`, [aina]);
for (let i = 0; i < 8; i++) {
  await q(`insert into notifications (user_id, type, title, category, pushed_at) values ($1,'comment','x','comments', now())`, [aina]);
}
await q(`update notifications set pushed_at = now() where user_id = $1`, [aina]);
await as(hafiz, `insert into comments (post_id, user_id, body) values ($1,$2,'3')`, [(await q(`insert into posts (user_id, title) values ($1,'Tiga') returning id`, [aina]))[0].id, hafiz]);
t3 = await q(`select * from push_take(100)`);
ok(!t3.some((t) => t.user_id === aina), 'the daily cap holds further pushes');

// a merged notification for a post that is then deleted is cleaned up as before
r = await as(aina, `select delete_my_post($1)`, [post2]);
ok(Array.isArray(r) && (await q(`select count(*)::int c from notifications where data->>'post_id' = $1`, [post2]))[0].c === 0,
  "deleting a post still removes its notifications");

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
