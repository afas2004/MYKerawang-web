// Runs every migration twice (idempotency) against a stub schema in
// PGlite (Postgres compiled to WASM), then exercises the moderation
// rules as real roles under RLS. No database or Docker needed:
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node moderation_test.mjs ../../..
//
// stub.sql approximates the tables the app uses; it is not the real schema.

import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const db = new PGlite();
const read = (f) => fs.readFileSync(f, 'utf8');

await db.exec(read(path.join(path.dirname(process.argv[1]), 'stub.sql')));
const files = fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort();
for (const pass of [1, 2]) {
  for (const f of files) {
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
const q = async (sql, p = []) => (await db.query(sql, p)).rows;

// users
const ids = {};
for (const n of ['owner', 'admin', 'alice', 'bob', 'carol', 'dave', 'erin', 'club', 'pending', 'newbie']) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  ids[n] = id;
  const old = n === 'newbie' ? 'now()' : "now() - interval '10 days'";
  await q(`insert into auth.users (id, created_at) values ($1, ${old})`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)`,
    [id, n, n === 'owner' ? 'owner' : n === 'admin' ? 'admin' : n === 'club' ? 'club' : n === 'pending' ? 'club_pending' : 'student']);
}

// alice posts
const post = (await as(ids.alice, `insert into posts (user_id, title, body) values ($1,'hi','body') returning id`, [ids.alice]))[0].id;
const anonPost = (await as(ids.alice, `insert into posts (user_id, title, body, is_anonymous) values ($1,'anon','x', true) returning id`, [ids.alice]))[0].id;

// report flow
await as(ids.bob, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Hate Speech or Harassment')`, [ids.bob, post]);
let e = await err(ids.bob, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.bob, post]);
ok(e && /reports_one_per_reporter|duplicate/.test(e), 'duplicate report rejected: ' + e);
e = await err(ids.alice, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.alice, post]);
ok(e && e.includes('MOD:self_report'), 'self report rejected');
await as(ids.carol, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.carol, post]);
let cases = await q(`select * from moderation_cases where target_id = $1`, [post]);
ok(cases.length === 1 && cases[0].status === 'open', 'two reports → one open case');
await as(ids.dave, `insert into reports (reporter_id, target_id, target_type, reason, category) values ($1,$2,'post','Spam or Scam','spam')`, [ids.dave, post]);
cases = await q(`select * from moderation_cases where target_id = $1`, [post]);
ok(cases[0].status === 'hidden' && cases[0].auto_hidden, '3rd distinct reporter → auto-hidden');
ok((await q(`select is_hidden from posts where id=$1`, [post]))[0].is_hidden === true, 'post is_hidden set');
let notes = await q(`select * from notifications where user_id=$1`, [ids.alice]);
ok(notes.some((n) => n.data.kind === 'content_hidden'), 'author notified of auto-hide');
ok((await as(ids.bob, `select count(*)::int n from posts_public where id=$1`, [post]))[0].n === 0, 'hidden post gone from posts_public');

// priority category on anonymous post: hide on first report
await as(ids.bob, `insert into reports (reporter_id, target_id, target_type, reason, category) values ($1,$2,'post','Scam or fraud','scam')`, [ids.bob, anonPost]);
cases = await q(`select * from moderation_cases where target_id = $1`, [anonPost]);
ok(cases[0].status === 'hidden' && cases[0].priority === 2 && cases[0].target_anonymous, 'priority category hidden on first report');

// admin views
ok((await err(ids.bob, `select * from moderation_queue`)) === null && (await as(ids.bob, `select * from moderation_queue`)).length === 0, 'non-admin sees empty queue');
const queue = await as(ids.admin, `select * from moderation_queue order by priority desc, first_reported_at`);
ok(queue.length === 2, 'admin sees 2 cases');
const anonRow = queue.find((r) => r.target_id === anonPost);
ok(anonRow.target_owner_id === null && anonRow.owner === null, 'anonymous owner masked in queue');
ok(anonRow.preview && anonRow.preview.title === 'anon', 'preview present');
const summary = (await as(ids.admin, `select admin_queue_summary() s`))[0].s;
ok(summary.open_cases === 2 && summary.oldest_open_at, 'summary works');
ok((await err(ids.bob, `select admin_queue_summary()`))?.includes('MOD:not_admin'), 'summary admin-only');

// resolve: restore + undo + remove
const c1 = queue.find((r) => r.target_id === post).id;
e = await err(ids.admin, `select admin_resolve_case($1,'restore','')`, [c1]);
ok(e?.includes('MOD:reason_required'), 'reason required');
let res = (await as(ids.admin, `select admin_resolve_case($1,'restore','fine') r`, [c1]))[0].r;
ok(res.decision === 'restored' && res.undoable, 'restore → restored, undoable');
ok((await q(`select is_hidden from posts where id=$1`, [post]))[0].is_hidden === false, 'post visible again');
ok((await q(`select count(*)::int n from reports where case_id=$1 and status='dismissed'`, [c1]))[0].n === 3, 'reports dismissed');
ok((await q(`select count(*)::int n from notifications where user_id=$1 and data->>'kind'='report_dismissed'`, [ids.bob]))[0].n === 1, 'reporter notified (dismissed)');
await as(ids.admin, `select admin_undo_case($1)`, [c1]);
ok((await q(`select status from moderation_cases where id=$1`, [c1]))[0].status === 'hidden', 'undo → back to hidden');
ok((await q(`select is_hidden from posts where id=$1`, [post]))[0].is_hidden === true, 'undo re-hid post');
res = (await as(ids.admin, `select admin_resolve_case($1,'remove','harassment') r`, [c1]))[0].r;
ok(res.decision === 'removed', 'remove');
ok((await q(`select strike from moderation_cases where id=$1`, [c1]))[0].strike === true, 'strike recorded');

// restrict anonymous author through case (owner hidden from admin)
const c2 = anonRow.id;
const rids = (await as(ids.admin, `select admin_restrict_user(null, $1, array['post','comment'], now() + interval '2 days', 'scam') r`, [c2]))[0].r;
ok(rids.length === 2, 'restrict via case creates 2 restrictions');
ok((await q(`select status from moderation_cases where id=$1`, [c2]))[0].status === 'actioned', 'case upheld by restrict');
const rv = await as(ids.admin, `select * from moderation_restrictions where active`);
ok(rv.length === 2 && rv.every((r) => r.user_id === null && r.anonymous_source), 'restriction view masks anonymous author');
const logs = await as(ids.admin, `select * from moderation_log`);
ok(!logs.some((l) => JSON.stringify(l).includes(ids.alice)), 'log never contains anonymous author id');

// enforcement
e = await err(ids.alice, `insert into posts (user_id, title, body) values ($1,'x','y')`, [ids.alice]);
ok(e?.includes('MOD:restricted:post'), 'restricted user cannot post: ' + e);
e = await err(ids.alice, `insert into listings (seller_id, title, price) values ($1,'x',1)`, [ids.alice]);
ok(e === null, 'post restriction does not block market');
const visible = (await q(`insert into posts (user_id, title) values ($1,'v') returning id`, [ids.alice]))[0].id;
e = await err(ids.alice, `update posts set title='edit' where id=$1`, [visible]);
ok(e?.includes('MOD:restricted:post'), 'restricted user cannot edit post');
e = await err(ids.bob, `update posts set comment_count = comment_count + 1 where id=$1`, [anonPost]);
ok(e === null, 'others can still bump counters');
const st = (await as(ids.alice, `select my_moderation_status() s`))[0].s;
ok(st.restrictions.length === 2 && st.cases.length >= 2, 'my status lists restrictions and cases');
ok((await as(ids.alice, `select is_restricted('comment') r`))[0].r === true, 'is_restricted works');

// appeal
const ap = (await as(ids.alice, `select submit_appeal(null, $1, 'please reconsider this') id`, [rids[0]]))[0].id;
e = await err(ids.alice, `select submit_appeal(null, $1, 'again please reconsider')`, [rids[0]]);
ok(e?.includes('MOD:already_appealed'), 'one appeal per decision');
e = await err(ids.bob, `select submit_appeal(null, $1, 'not mine at all here')`, [rids[1]]);
ok(e?.includes('MOD:not_appealable'), 'cannot appeal others');
const apv = await as(ids.admin, `select * from moderation_appeals`);
ok(apv.length === 1 && apv[0].profile === null, 'appeal view masks anonymous source');
await as(ids.admin, `select admin_handle_appeal($1, true, 'ok granted')`, [ap]);
ok((await q(`select lifted_at from user_restrictions where id=$1`, [rids[0]]))[0].lifted_at !== null, 'accepted appeal lifts restriction');
ok((await q(`select count(*)::int n from notifications where user_id=$1 and data->>'kind'='appeal_accepted'`, [ids.alice]))[0].n === 1, 'appellant notified');

// lift + reinstate, account ban
await as(ids.admin, `select admin_lift_restriction($1,'early')`, [rids[1]]);
await as(ids.admin, `select admin_reinstate_restriction($1)`, [rids[1]]);
ok((await q(`select lifted_at from user_restrictions where id=$1`, [rids[1]]))[0].lifted_at === null, 'reinstate undoes lift');
const ban = (await as(ids.admin, `select admin_restrict_user($1, null, array['account'], null, 'repeated abuse') r`, [ids.erin]))[0].r;
ok((await q(`select is_banned from profiles where id=$1`, [ids.erin]))[0].is_banned === true, 'permanent account ban sets is_banned');
e = await err(ids.erin, `insert into followers (follower_id, following_id) values ($1,$2)`, [ids.erin, ids.bob]);
ok(e?.includes('MOD:restricted:account'), 'account ban blocks follows');
e = await err(ids.erin, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.erin, post]);
ok(e?.includes('MOD:restricted:account'), 'account ban blocks reports');
await as(ids.admin, `select admin_lift_restriction($1,'served')`, [ban[0]]);
ok((await q(`select is_banned from profiles where id=$1`, [ids.erin]))[0].is_banned === false, 'lifting clears is_banned');
e = await err(ids.admin, `select admin_restrict_user($1, null, array['post'], null, 'nope')`, [ids.owner]);
ok(e?.includes('MOD:protected_user'), 'admin cannot restrict owner');

// expiry: restriction in the past
await q(`insert into user_restrictions (user_id, scope, until, reason) values ($1,'market', now() + interval '1 second','t')`, [ids.dave]);
await q(`update user_restrictions set until = now() - interval '1 minute' where user_id=$1`, [ids.dave]);
e = await err(ids.dave, `insert into listings (seller_id, title, price) values ($1,'x',1)`, [ids.dave]);
ok(e === null, 'expired restriction no longer applies');
await as(ids.dave, `select my_moderation_status()`);
ok((await q(`select count(*)::int n from notifications where user_id=$1 and data->>'kind'='restriction_ended'`, [ids.dave]))[0].n === 1, 'end notice sent lazily once');
await as(ids.dave, `select my_moderation_status()`);
ok((await q(`select count(*)::int n from notifications where user_id=$1 and data->>'kind'='restriction_ended'`, [ids.dave]))[0].n === 1, 'end notice not repeated');

// rate limit for new accounts
for (let i = 0; i < 3; i++) await as(ids.newbie, `insert into posts (user_id, title) values ($1,'n')`, [ids.newbie]);
e = await err(ids.newbie, `insert into posts (user_id, title) values ($1,'n')`, [ids.newbie]);
ok(e?.includes('MOD:rate_limited:post'), 'new account rate limited at 4th post');

// strikes → automatic restriction
const bobPosts = [];
for (let i = 0; i < 3; i++) bobPosts.push((await as(ids.bob, `insert into posts (user_id, title) values ($1,'s') returning id`, [ids.bob]))[0].id);
for (const p of bobPosts) {
  await as(ids.carol, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.carol, p]);
  const cid = (await q(`select id from moderation_cases where target_id=$1`, [p]))[0].id;
  await as(ids.admin, `select admin_resolve_case($1,'warn','rude')`, [cid]);
}
const auto = await q(`select * from user_restrictions where user_id=$1 and created_by is null`, [ids.bob]);
ok(auto.length === 1 && auto[0].scope === 'post', '3 strikes → automatic post restriction');
ok((await q(`select count(*)::int n from moderation_log where action='auto_restrict' and actor='system'`))[0].n === 1, 'auto restriction logged as system');

// reporter quality: carol has 3 actioned; make frank-like reporter with dismissed history
for (let i = 0; i < 5; i++) {
  const p = (await as(ids.club, `insert into posts (user_id, title) values ($1,'c') returning id`, [ids.club]))[0].id;
  await as(ids.dave, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.dave, p]);
  const cid = (await q(`select id from moderation_cases where target_id=$1`, [p]))[0].id;
  await as(ids.admin, `select admin_resolve_case($1,'dismiss','fine')`, [cid]);
}
const p9 = (await as(ids.club, `insert into posts (user_id, title) values ($1,'c') returning id`, [ids.club]))[0].id;
await as(ids.dave, `insert into reports (reporter_id, target_id, target_type, reason) values ($1,$2,'post','Other')`, [ids.dave, p9]);
ok((await q(`select counts_toward_auto_hide c from reports where target_id=$1`, [p9]))[0].c === false, 'low-quality reporter does not count');

// target deleted → auto close
await q(`delete from posts where id=$1`, [p9]);
ok((await q(`select status from moderation_cases where target_id=$1`, [p9]))[0].status === 'closed', 'deleted target closes case');

// pins
const cp1 = (await as(ids.club, `insert into posts (user_id, title) values ($1,'pin1') returning id`, [ids.club]))[0].id;
const cp2 = (await as(ids.club, `insert into posts (user_id, title) values ($1,'pin2') returning id`, [ids.club]))[0].id;
await as(ids.club, `select pin_post($1)`, [cp1]);
e = await err(ids.club, `select pin_post($1)`, [cp2]);
ok(e?.includes('MOD:pin_cap'), 'pin cap enforced');
const rep = (await as(ids.club, `select pin_post($1, true) r`, [cp2]))[0].r;
ok(rep.replaced.length === 1 && rep.replaced[0] === cp1, 'replace swaps the pin');
e = await err(ids.club, `select pin_post($1)`, [bobPosts[1]]);
ok(e?.includes('MOD:pin_not_allowed'), 'club cannot pin others');
e = await err(ids.carol, `select pin_post($1)`, [bobPosts[0]]);
ok(e?.includes('MOD:pin_not_allowed'), 'student cannot pin');
await as(ids.admin, `select pin_post($1)`, [bobPosts[0]]);
await as(ids.club, `update posts set pinned_until = now() + interval '99 days' where id=$1`, [cp1]);
ok((await q(`select pinned_until from posts where id=$1`, [cp1]))[0].pinned_until === null, 'direct pin column write ignored');
const feed = await as(ids.carol, `select id, is_pinned from posts_public order by is_pinned desc, created_at desc limit 2`);
ok(feed.every((r) => r.is_pinned), 'pinned posts first in feed');

// clubs
await as(ids.admin, `select admin_decide_club($1, true, null)`, [ids.pending]);
const pr = (await q(`select role, is_verified from profiles where id=$1`, [ids.pending]))[0];
ok(pr.role === 'club' && pr.is_verified, 'club approved + verified');
ok((await q(`select count(*)::int n from moderation_log where action='club_approved'`))[0].n === 1
  && (await q(`select count(*)::int n from moderation_log where action='role_change'`))[0].n === 0, 'club approval logged once');

// unmask
e = await err(ids.admin, `select * from admin_unmask('post', $1, 'short')`, [anonPost]);
ok(e?.includes('MOD:reason_required'), 'unmask needs a real reason');
const um = await as(ids.admin, `select * from admin_unmask('post', $1, 'police report filed for scam')`, [anonPost]);
ok(um[0].author_id === ids.alice, 'unmask returns author');
ok((await err(ids.admin, `select * from admin_unmask_post($1)`, [anonPost])) !== null, 'old unmask not callable by clients');

// log append-only
ok((await err(ids.admin, `delete from moderation_log`)) !== null, 'admin cannot delete log');
ok((await err(null, `update moderation_log set reason='x'`)) !== null, 'nobody can update log');
try { await q(`delete from moderation_log`); ok(false, 'superuser delete blocked'); } catch { ok(true, 'superuser delete blocked'); }

// settings
ok((await err(ids.admin, `update moderation_settings set auto_hide_report_count = 5`)) === null
  && (await q(`select auto_hide_report_count n from moderation_settings`))[0].n === 3, 'admin cannot change settings (0 rows)');
await as(ids.owner, `update moderation_settings set auto_hide_report_count = 5`);
ok((await q(`select auto_hide_report_count n from moderation_settings`))[0].n === 5, 'owner changes settings');
ok((await q(`select count(*)::int n from moderation_log where action='settings_change'`))[0].n === 1, 'settings change logged');

// comments: hide + view filter
const cm = (await as(ids.carol, `insert into comments (post_id, user_id, body) values ($1,$2,'c') returning id`, [post, ids.carol]))[0].id;
await q(`select mod_set_hidden('comment', $1, true)`, [cm]);
ok((await as(ids.bob, `select count(*)::int n from comments_public where id=$1`, [cm]))[0].n === 0, 'hidden comment filtered from comments_public');

// bulk spam only
const sp = (await as(ids.carol, `insert into posts (user_id, title) values ($1,'spam') returning id`, [ids.carol]))[0].id;
await as(ids.bob, `insert into reports (reporter_id, target_id, target_type, reason, category) values ($1,$2,'post','Spam','spam')`, [ids.bob, sp]);
const spc = (await q(`select id from moderation_cases where target_id=$1`, [sp]))[0].id;
e = await err(ids.admin, `select admin_bulk_resolve(array[$1::uuid], 'remove', 'spam wave')`, [spc]);
ok(e === null, 'bulk remove spam ok');


// case detail: reports with notes, history masked for anonymous cases
await as(ids.erin, `insert into reports (reporter_id, target_id, target_type, reason, category, note) values ($1,$2,'post','Spam','spam','posted 5 times')`, [ids.erin, bobPosts[2]]);
const dc = (await q(`select id from moderation_cases where target_id=$1 and status in ('open','hidden')`, [bobPosts[2]]))[0].id;
const det = (await as(ids.admin, `select admin_case_detail($1) d`, [dc]))[0].d;
ok(det.reports.some((r) => r.note === 'posted 5 times') && det.history.length >= 3, 'case detail has notes and author history');
ok(!JSON.stringify(det).includes(ids.erin), 'case detail hides reporter ids');
ok((await err(ids.bob, `select admin_case_detail($1)`, [dc]))?.includes('MOD:not_admin'), 'case detail admin-only');
const anonDet = (await as(ids.admin, `select admin_case_detail($1) d`, [c2]))[0].d;
ok(anonDet.history.length === 0 && anonDet.restrictions.length === 0, 'anonymous case detail has no author history');

console.log(failures ? `\n${failures} FAILURES` : '\nALL PASSED');
process.exit(failures ? 1 : 0);
