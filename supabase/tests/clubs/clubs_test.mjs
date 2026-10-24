// Clubs: runs every migration twice against the moderation stub schema in
// PGlite, then exercises registration, approval, officers, publishing as
// a club, RLS for guests, pins and the role='club' backfill.
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node ../clubs/clubs_test.mjs ../../..

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

// Legacy accounts exist BEFORE the clubs migrations, so the backfill runs on them.
const legacy = {};
async function user(name, role = 'student', bio = null) {
  const id = (await q('select gen_random_uuid() id'))[0].id;
  await q(`insert into auth.users (id, created_at) values ($1, now() - interval '10 days')`, [id]);
  await q(`insert into public.profiles (id, username, display_name, role, bio) values ($1,$2,$2,$3,$4)`,
    [id, name, role, bio]);
  return id;
}

const before = files.filter((f) => f < '20261022002100');
const clubFiles = files.filter((f) => f >= '20261022002100');
for (const f of before) await db.exec(read(path.join(mig, f)));
legacy.robotics = await user('robotics', 'club');
legacy.pending = await user('chess', 'club_pending', 'Club Verification: Registered with HEP, ref 123');
await db.exec(`insert into public.posts (user_id, title) values ('${legacy.robotics}', 'Old club post')`);
for (const f of clubFiles) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('club migrations applied twice OK');

let failures = 0;
const ok = (cond, msg) => { console.log((cond ? 'ok   ' : 'FAIL ') + msg); if (!cond) failures++; };

async function as(uid, sql, params = [], role = 'authenticated') {
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}; select set_config('request.jwt.claim.sub', '${uid ?? ''}', true);`);
    const r = await db.query(sql, params);
    await db.exec('commit');
    return r.rows;
  } catch (e) { await db.exec('rollback'); throw e; }
}
const err = async (uid, sql, params = [], role) => {
  try { await as(uid, sql, params, role); return null; } catch (e) { return e.message; }
};

// ---------------------------------------------------------- backfill
const rob = (await q(`select * from clubs where created_by = $1`, [legacy.robotics]))[0];
ok(rob && rob.status === 'active' && rob.is_verified && rob.handle === 'robotics', 'role=club account → active verified club');
ok((await q(`select club_id from posts where user_id=$1`, [legacy.robotics]))[0].club_id === rob.id, 'old club posts attached to the club');
const chess = (await q(`select c.*, p.proof_note from clubs c join club_private p on p.club_id=c.id where created_by=$1`, [legacy.pending]))[0];
ok(chess.status === 'pending' && chess.proof_note === 'Registered with HEP, ref 123', 'club_pending → pending request with proof');
ok((await q(`select bio from profiles where id=$1`, [legacy.pending]))[0].bio === null, 'bio proof hack cleared');
ok((await q(`select count(*)::int n from clubs`))[0].n === 2, 'backfill is idempotent');

// ---------------------------------------------------------- users
const admin = await user('admin1', 'admin');
const alice = await user('alice');
const bob = await user('bob');
const carol = await user('carol');

// ---------------------------------------------------------- register
let e;
const regDebate = (await as(admin, `select admin_save_club_registry(null,'HEP/2024/042','Debate Society','FSKM','academic',true) id`))[0].id;
ok(!!regDebate, 'admin adds a registry entry');
e = await err(alice, `select admin_save_club_registry(null,'HEP/2024/099','Other','',null,true)`);
ok(e?.includes('MOD:not_admin'), 'only admins edit the registry');
e = await err(admin, `select admin_save_club_registry(null,'HEP/2024/042','Duplicate','',null,true)`);
ok(e?.includes('CLUB:registry_code_taken'), 'registry codes are unique');
const open = (await as(alice, `select club_registry_open() j`))[0].j;
ok(open.length === 1 && open[0].code === 'HEP/2024/042', 'open registry lists unclaimed entry');

e = await err(alice, `select register_club($1,'not-an-email','president','[]'::jsonb)`, [regDebate]);
ok(e?.includes('CLUB:email_invalid'), 'official email required');
e = await err(alice, `select register_club($1,'debate@gmail.com','boss','[]'::jsonb)`, [regDebate]);
ok(e?.includes('CLUB:position_invalid'), 'position validated');
e = await err(alice, `select register_club($1,'debate@gmail.com','president','[{"name":"A"}]'::jsonb)`, [regDebate]);
ok(e?.includes('CLUB:council_invalid'), 'council names need 2+ chars');

const reg = (await as(alice, `select register_club($1,'debate@gmail.com','secretary','[{"name":"Aiman","position":"Secretary"},{"name":"Siti","position":"Treasurer"}]'::jsonb) j`, [regDebate]))[0].j;
const debate = reg.id;
ok(!!debate && !!reg.handle, 'register_club returns id + handle');
ok((await as(alice, `select position from club_members where club_id=$1 and user_id=$2`, [debate, alice]))[0].position === 'secretary', 'applicant position stored on the roster');
e = await err(bob, `select register_club($1,'bob@gmail.com','president','[]'::jsonb)`, [regDebate]);
ok(e?.includes('CLUB:registry_claimed'), 'claimed entry cannot be registered again');
ok((await as(alice, `select role from my_clubs()`))[0]?.role === 'president', 'my_clubs shows pending club to its president');
ok((await as(bob, `select count(*)::int n from clubs where id=$1`, [debate]))[0].n === 0, 'pending club hidden from others');
ok((await as(null, `select count(*)::int n from clubs where id=$1`, [debate], 'anon'))[0].n === 0, 'pending club hidden from guests');
ok((await as(bob, `select count(*)::int n from club_private`))[0].n === 0, 'proof private');

// Can't publish as a pending club.
e = await err(alice, `insert into posts (user_id, title, club_id) values ($1,'x',$2)`, [alice, debate]);
ok(e !== null, 'pending club cannot publish');

// ---------------------------------------------------------- approve
e = await err(bob, `select admin_decide_club_request($1, true, null)`, [debate]);
ok(e?.includes('MOD:not_admin'), 'only admins decide');
e = await err(admin, `select admin_decide_club_request($1, false, '')`, [debate]);
ok(e?.includes('MOD:reason_required'), 'rejection needs a reason');
const pend = (await as(admin, `select admin_pending_clubs() j`))[0].j;
const pDebate = pend.find((c) => c.id === debate);
ok(pDebate && pDebate.registry_code === 'HEP/2024/042' && pDebate.official_email === 'debate@gmail.com'
  && pDebate.applicant_position === 'secretary' && pDebate.council_members.length === 2,
  'admin queue shows registry code, email, position, council');
ok(pend.some((c) => c.id === chess.id && c.proof_note === 'Registered with HEP, ref 123'), 'legacy proof still shown');
await as(admin, `select admin_decide_club_request($1, true, null)`, [debate]);
const d = (await q(`select * from clubs where id=$1`, [debate]))[0];
ok(d.status === 'active' && d.is_verified, 'approved → active + verified');
ok(d.registry_id === regDebate, 'club linked to its registry entry');
ok((await as(alice, `select club_registry_open() j`))[0].j.length === 0, 'claimed entry drops out of the picker');
ok((await q(`select count(*)::int n from notifications where user_id=$1 and type='club' and data->>'kind'='club_approved'`, [alice]))[0].n === 1, 'president notified');
await as(admin, `select admin_decide_club_request($1, false, 'No proof attached')`, [chess.id]);
ok((await q(`select role from profiles where id=$1`, [legacy.pending]))[0].role === 'student', 'legacy club_pending → student on rejection');
ok((await q(`select count(*)::int n from moderation_log where action in ('club_approved','club_rejected')`))[0].n === 2, 'decisions logged');

// Guests read active clubs and members.
ok((await as(null, `select count(*)::int n from clubs where id=$1`, [debate], 'anon'))[0].n === 1, 'guest reads active club');
ok((await as(null, `select count(*)::int n from club_members where club_id=$1`, [debate], 'anon'))[0].n === 1, 'guest reads member list');

// ---------------------------------------------------------- officers
e = await err(bob, `select invite_officer($1, 'carol')`, [debate]);
ok(e?.includes('CLUB:not_president'), 'only president invites');
e = await err(alice, `select invite_officer($1, 'nobody')`, [debate]);
ok(e?.includes('CLUB:user_not_found'), 'unknown username');
await as(alice, `select invite_officer($1, '@Bob')`, [debate]);
ok((await as(bob, `select can_act_as_club($1) c`, [debate]))[0].c === true, 'officer can act as club');
ok((await as(carol, `select can_act_as_club($1) c`, [debate]))[0].c === false, 'non-member cannot');
e = await err(alice, `select invite_officer($1, 'bob')`, [debate]);
ok(e?.includes('CLUB:already_officer'), 'no duplicate officers');

// ---------------------------------------------------------- roster
e = await err(bob, `select add_club_member($1,'carol',null)`, [debate]);
ok(e?.includes('CLUB:not_president'), 'only president adds members');
await as(alice, `select add_club_member($1,'carol','treasurer')`, [debate]);
ok((await q(`select role, position from club_members where club_id=$1 and user_id=$2`, [debate, carol]))[0].position === 'treasurer', 'member added with position');
ok((await as(carol, `select can_act_as_club($1) c`, [debate]))[0].c === false, 'member cannot act as club');
e = await err(alice, `select add_club_member($1,'carol',null)`, [debate]);
ok(e?.includes('CLUB:already_member'), 'no duplicate members');
await as(alice, `select set_club_member_position($1,$2,'secretary')`, [debate, carol]);
ok((await q(`select position from club_members where club_id=$1 and user_id=$2`, [debate, carol]))[0].position === 'secretary', 'position updated');
await as(alice, `select set_club_member_role($1,$2,'officer')`, [debate, carol]);
ok((await as(carol, `select can_act_as_club($1) c`, [debate]))[0].c === true, 'promoted member can act');
await as(alice, `select set_club_member_role($1,$2,'member')`, [debate, carol]);
ok((await as(carol, `select can_act_as_club($1) c`, [debate]))[0].c === false, 'demoted member cannot act');
e = await err(alice, `select remove_club_member($1,$2)`, [debate, alice]);
ok(e?.includes('CLUB:president_must_transfer'), 'president cannot be removed');
await as(carol, `select remove_club_member($1,$2)`, [debate, carol]);
ok((await q(`select count(*)::int n from club_members where club_id=$1 and user_id=$2`, [debate, carol]))[0].n === 0, 'member can leave');

// ---------------------------------------------------------- publishing
const cp = (await as(bob, `insert into posts (user_id, title, club_id, is_announcement, announcement_category, is_anonymous) values ($1,'Meeting Friday',$2,true,'club',true) returning id, is_anonymous`, [bob, debate]))[0];
ok(cp && cp.is_anonymous === false, 'officer posts as club; club posts never anonymous');
e = await err(carol, `insert into posts (user_id, title, club_id) values ($1,'fake',$2)`, [carol, debate]);
ok(e !== null, 'non-officer cannot post as club: ' + e?.slice(0, 40));
e = await err(carol, `insert into posts (user_id, title, is_announcement) values ($1,'fake',true)`, [carol]);
ok(e !== null, 'students cannot post announcements');
ok((await err(admin, `insert into posts (user_id, title, is_announcement, announcement_category) values ($1,'Water cut',true,'kolej')`, [admin])) === null, 'admins post kolej announcements');
ok((await err(bob, `insert into events (organizer_id, title, club_id) values ($1,'Workshop',$2)`, [bob, debate])) === null, 'officer creates club event');
ok((await err(bob, `insert into listings (seller_id, title, price, club_id) values ($1,'Club tee',25,$2)`, [bob, debate])) === null, 'club can sell');
e = await err(carol, `insert into listings (seller_id, title, price, club_id) values ($1,'Fake tee',25,$2)`, [carol, debate]);
ok(e !== null, 'non-officer cannot sell as club');
e = await err(carol, `update posts set club_id=$2 where user_id=$1`, [carol, debate]);
const hijack = (await q(`select count(*)::int n from posts where user_id=$1 and club_id is not null`, [carol]))[0].n;
ok(hijack === 0, 'cannot move own post into a club');
const pp = (await as(null, `select club, is_announcement, announcement_category from posts_public where id=$1`, [cp.id], 'anon'))[0];
ok(pp.club?.handle === reg.handle && pp.club.is_verified && pp.is_announcement && pp.announcement_category === 'club', 'posts_public.club exposed');

// ---------------------------------------------------------- pins
e = await err(bob, `select pin_post($1)`, [cp.id]);
ok(e?.includes('MOD:pin_not_allowed'), 'officers cannot pin globally');
await as(admin, `select pin_post($1)`, [cp.id]);
const g = (await as(null, `select is_pinned, is_club_pinned from posts_public where id=$1`, [cp.id], 'anon'))[0];
ok(g.is_pinned === true && g.is_club_pinned === false, 'admin global pin leaves the club pin alone');
await as(admin, `select unpin_post($1)`, [cp.id]);

await as(bob, `select club_pin_post($1)`, [cp.id]);
const cp2 = (await as(alice, `insert into posts (user_id, title, club_id) values ($1,'Second',$2) returning id`, [alice, debate]))[0].id;
e = await err(alice, `select club_pin_post($1)`, [cp2]);
ok(e?.includes('MOD:pin_cap'), 'club pin cap counted per club across officers');
const rep = (await as(alice, `select club_pin_post($1, true) r`, [cp2]))[0].r;
ok(rep.replaced[0] === cp.id, 'replace swaps the club pin');
ok((await err(bob, `select club_unpin_post($1)`, [cp2])) === null, 'another officer can unpin the club pin');
ok((await as(null, `select is_club_pinned from posts_public where id=$1`, [cp2], 'anon'))[0].is_club_pinned === false, 'club unpin clears the club pin');
e = await err(carol, `select club_pin_post($1)`, [cp.id]);
ok(e?.includes('CLUB:not_officer'), 'non-officers cannot club-pin');

// ---------------------------------------------------------- transfer / remove
e = await err(alice, `select remove_officer($1,$2)`, [debate, alice]);
ok(e?.includes('CLUB:president_must_transfer'), 'president cannot just leave');
e = await err(alice, `select transfer_presidency($1,$2)`, [debate, carol]);
ok(e?.includes('CLUB:not_officer'), 'transfer only to an officer');
await as(alice, `select transfer_presidency($1,$2)`, [debate, bob]);
const roles = Object.fromEntries((await q(`select user_id, role from club_members where club_id=$1`, [debate])).map((r) => [r.user_id, r.role]));
ok(roles[bob] === 'president' && roles[alice] === 'officer', 'presidency transferred');
ok((await err(alice, `select remove_officer($1,$2)`, [debate, alice])) === null, 'officer can leave');
ok((await as(alice, `select can_act_as_club($1) c`, [debate]))[0].c === false, 'left officer loses access');

// ---------------------------------------------------------- page edit, follow, suspend
e = await err(carol, `select update_club($1,'Hacked',null,null,null,null,null,null,'{}')`, [debate]);
ok(e?.includes('CLUB:not_officer'), 'only officers edit page');
await as(bob, `select update_club($1,'Debate Society UiTM','Weekly debates',null,null,'Academic','FSKM','debate@example.com','{"instagram":"debate"}')`, [debate]);
ok((await q(`select faculty from clubs where id=$1`, [debate]))[0].faculty === 'FSKM', 'officer edits page');
e = await err(bob, `select update_club($1,'Debate',null,null,null,null,null,'not-an-email','{}')`, [debate]);
ok(e?.includes('CLUB:email_invalid'), 'email validated');
await as(carol, `insert into club_followers (club_id, user_id) values ($1,$2)`, [debate, carol]);
ok((await as(null, `select followers from club_follower_counts where club_id=$1`, [debate], 'anon'))[0].followers === 1, 'follower count public');
await as(admin, `select admin_set_club_status($1,'suspended','Spam')`, [debate]);
ok((await as(bob, `select can_act_as_club($1) c`, [debate]))[0].c === false, 'suspended club cannot publish');
ok((await as(null, `select club from posts_public where id=$1`, [cp.id], 'anon'))[0].club === null, 'suspended club hidden on posts');
ok((await as(admin, `select admin_queue_summary() s`))[0].s.club_requests === 0, 'queue summary counts pending clubs');

console.log(failures ? `\n${failures} FAILURES` : '\nALL PASSED');
process.exit(failures ? 1 : 0);
