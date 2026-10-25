// Security review regression tests (October 2026).
//
// Applies every migration twice against the moderation stub schema in PGlite,
// with a minimal `storage` schema so the bucket policies in
// 20261026015100_security_review_fixes.sql are exercised too, then asserts the
// properties the review found missing.
//
//   cd supabase/tests/moderation
//   npm i --no-save @electric-sql/pglite@0.2.17
//   node ../security/security_test.mjs ../../..

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

// The real project has a storage schema; the stub does not. Reproduce the
// shape Supabase uses plus the broken dashboard policy the review found
// (one permissive policy for the images bucket), so the migration has
// something to replace.
await db.exec(`
  create schema if not exists storage;
  create table storage.objects (
    id         bigserial primary key,
    bucket_id  text,
    name       text,
    owner      uuid,
    created_at timestamptz not null default now()
  );
  alter table storage.objects enable row level security;
  grant usage on schema storage to anon, authenticated;
  grant select, insert, update, delete on storage.objects to anon, authenticated;
  grant usage, select on sequence storage.objects_id_seq to anon, authenticated;
  create policy "Public Access" on storage.objects
    for all using (bucket_id = 'images');
`);

let failures = 0;
const ok = (cond, msg) => {
  console.log((cond ? 'ok   ' : 'FAIL ') + msg);
  if (!cond) failures++;
};

async function as(uid, sql, params = [], role = 'authenticated') {
  await db.exec('begin');
  try {
    await db.exec(
      `set local role ${role}; select set_config('request.jwt.claim.sub', '${uid ?? ''}', true);`,
    );
    const r = await db.query(sql, params);
    await db.exec('commit');
    return r.rows;
  } catch (e) {
    await db.exec('rollback');
    throw e;
  }
}
const err = async (uid, sql, params = [], role) => {
  try {
    await as(uid, sql, params, role);
    return null;
  } catch (e) {
    return e.message;
  }
};

// ---------------------------------------------------------- migrations
for (const f of files) {
  for (const pass of [1, 2]) {
    try {
      await db.exec(read(path.join(mig, f)));
    } catch (e) {
      console.error(`FAIL pass ${pass} ${f}: ${e.message}`);
      process.exit(1);
    }
  }
}
console.log('migrations applied twice OK');

// ---------------------------------------------------------- fixtures
const me = (await q('select gen_random_uuid() id'))[0].id;
const other = (await q('select gen_random_uuid() id'))[0].id;
for (const [id, name] of [[me, 'me'], [other, 'other']]) {
  await q('insert into auth.users (id) values ($1)', [id]);
  await q('insert into public.profiles (id, username, role) values ($1,$2,$3)', [
    id, name, 'student',
  ]);
}

// ---------------------------------------------------------- 1. execute grants
// `revoke ... from anon` alone leaves the default PUBLIC grant in place.
ok(
  (await q(`select has_function_privilege('anon', 'public.is_admin()', 'execute') p`))[0].p === false,
  'is_admin() is not executable by anon',
);
ok(
  (await q(`select has_function_privilege('anon', 'public.is_owner()', 'execute') p`))[0].p === false,
  'is_owner() is not executable by anon',
);
ok(
  (await q(`select has_function_privilege('authenticated', 'public.is_admin()', 'execute') p`))[0].p === true,
  'is_admin() is still executable by authenticated (RLS needs it)',
);
ok(
  (await q(`select has_function_privilege('anon', 'public.forget_saved_target()', 'execute') p`))[0].p === false,
  'forget_saved_target() is not executable by anon',
);

// ---------------------------------------------------------- 2. hidden events
const hiddenEvent = (await q(
  `insert into events (organizer_id, title, is_public, is_hidden)
   values ($1, 'moderated', true, true) returning id`, [me]))[0].id;
const openEvent = (await q(
  `insert into events (organizer_id, title, is_public, is_hidden)
   values ($1, 'visible', true, false) returning id`, [me]))[0].id;
await q('insert into event_participants (event_id, user_id) values ($1,$2)', [hiddenEvent, me]);
await q('insert into event_participants (event_id, user_id) values ($1,$2)', [openEvent, me]);

const counts = await q(
  `select event_id from event_participant_counts where event_id = any($1)`,
  [[hiddenEvent, openEvent]]);
ok(counts.length === 1 && counts[0].event_id === openEvent,
  'event_participant_counts no longer leaks a hidden event');

// ---------------------------------------------------------- 3. sign-up domain
await q(`update access_settings set registration_mode = 'student_only',
         student_domain = '@student.uitm.edu.my' where id`);

const signupOk = await err(null,
  `insert into auth.users (id, email) values (gen_random_uuid(), 'ali@student.uitm.edu.my')`,
  [], 'postgres');
ok(signupOk === null, 'a real student address still signs up');

// The old check was `like '%student.uitm.edu.my'`, which this address matches.
const signupSuffix = await err(null,
  `insert into auth.users (id, email)
   values (gen_random_uuid(), 'ali@student.uitm.edu.my.attacker.example')`,
  [], 'postgres');
ok(signupSuffix !== null,
  'an address with the student domain as a prefix is refused (suffix attack)');

const signupOther = await err(null,
  `insert into auth.users (id, email) values (gen_random_uuid(), 'ali@gmail.com')`,
  [], 'postgres');
ok(signupOther !== null, 'a non-student address is refused');

// ---------------------------------------------------------- 4. verification domain
const badVerify = await err(null,
  `insert into public.student_verifications (user_id, email, status)
   values ($1, 'ali@gmail.com', 'verified')`, [me], 'postgres');
ok(badVerify !== null && badVerify.includes('VERIFY:domain'),
  'student_verifications cannot be marked verified on a foreign domain');

const goodVerify = await err(null,
  `insert into public.student_verifications (user_id, email, status)
   values ($1, 'ali@student.uitm.edu.my', 'verified')`, [me], 'postgres');
ok(goodVerify === null, 'a student-domain verification is accepted');

// ---------------------------------------------------------- 5. storage
const anonInsert = await err(null,
  `insert into storage.objects (bucket_id, name, owner)
   values ('images', 'posts/anon.jpg', null)`, [], 'anon');
ok(anonInsert !== null, 'anon can no longer insert into the images bucket');

const anonDelete = await as(null,
  `delete from storage.objects where bucket_id = 'images' returning id`, [], 'anon');
ok(anonDelete.length === 0, 'anon can no longer delete images objects');

const ownInsert = await as(me,
  `insert into storage.objects (bucket_id, name, owner)
   values ('images', 'posts/mine.jpg', $1) returning id`, [me]);
ok(ownInsert.length === 1, 'a signed-in user can upload to images');

// The upload must not depend on storage stamping `owner`: if it were null, an
// owner-checked INSERT policy would refuse every upload. Insert is therefore
// bucket-only, and update/delete carry the ownership check.
const nullOwnerInsert = await as(me,
  `insert into storage.objects (bucket_id, name, owner)
   values ('images', 'posts/no-owner.jpg', null) returning id`);
ok(nullOwnerInsert.length === 1,
  'upload still works when owner is not stamped');

const nullOwnerDelete = await as(me,
  `delete from storage.objects where id = $1 returning id`, [nullOwnerInsert[0].id]);
ok(nullOwnerDelete.length === 0,
  'an object with no owner cannot be deleted by a user (cleanup skipped, not broken)');

const foreignUpdate = await as(other,
  `update storage.objects set name = 'stolen.jpg'
   where id = $1 returning id`, [ownInsert[0].id]);
ok(foreignUpdate.length === 0, 'another user cannot overwrite that object');

const foreignDelete = await as(other,
  `delete from storage.objects where id = $1 returning id`, [ownInsert[0].id]);
ok(foreignDelete.length === 0, 'another user cannot delete that object');

const ownRead = await as(null,
  `select id from storage.objects where bucket_id = 'images'`, [], 'anon');
ok(ownRead.length >= 1, 'public reads of the images bucket still work');

const anonAvatar = await err(null,
  `insert into storage.objects (bucket_id, name, owner)
   values ('avatars', 'x.png', null)`, [], 'anon');
ok(anonAvatar !== null, 'avatars stays closed to anon (not loosened by this migration)');

// ---------------------------------------------------------- 6. form text caps
const longTitle = await err(null,
  `insert into event_forms (event_id, title) values ($1, repeat('x', 121))`,
  [openEvent], 'postgres');
ok(longTitle !== null && longTitle.includes('event_forms_title_len'),
  'event_forms.title is capped at 120 server-side');

const longIntro = await err(null,
  `insert into event_forms (event_id, title, intro)
   values ($1, 'ok', repeat('x', 501))`, [openEvent], 'postgres');
ok(longIntro !== null && longIntro.includes('event_forms_intro_len'),
  'event_forms.intro is capped at 500 server-side');

const formId = (await q(
  `insert into event_forms (event_id, title) values ($1, 'ok') returning id`,
  [openEvent]))[0].id;

const longHelp = await err(null,
  `insert into form_fields (form_id, kind, label, help)
   values ($1, 'short_text', 'q', repeat('x', 301))`, [formId], 'postgres');
ok(longHelp !== null && longHelp.includes('form_fields_help_len'),
  'form_fields.help is capped at 300 server-side');

const longChoice = await err(null,
  `select public.form_check_field('single_choice', 'q', false,
     jsonb_build_object('choices', jsonb_build_array('a', repeat('b', 61))), null, null)`,
  [], 'postgres');
ok(longChoice !== null && longChoice.includes('FORM:bad_choice_label'),
  'a choice longer than 60 is refused by the validator');

const goodField = await err(null,
  `select public.form_check_field('single_choice', 'q', false,
     jsonb_build_object('choices', jsonb_build_array('a', 'b')), null, null)`,
  [], 'postgres');
ok(goodField === null, 'a valid choice field still validates');

// ---------------------------------------------------------- result
console.log(failures === 0 ? '\nALL SECURITY TESTS PASSED' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
