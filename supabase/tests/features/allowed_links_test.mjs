// Safe links: allowed_link_domains and its RLS
// (20261114000200_allowed_link_domains.sql).
//
//   node supabase/tests/features/allowed_links_test.mjs .

import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import fs from 'fs';
import path from 'path';

const repo = process.argv[2];
const mig = path.join(repo, 'supabase', 'migrations');
const db = new PGlite({ extensions: { citext } });
const read = (f) => fs.readFileSync(f, 'utf8');

await db.exec(read(path.join(repo, 'supabase', 'tests', 'moderation', 'stub.sql')));
const files = fs.readdirSync(mig).filter((f) => f.endsWith('.sql')).sort();
for (const f of files) {
  for (const pass of [1, 2]) {
    try { await db.exec(read(path.join(mig, f))); }
    catch (e) { console.error(`FAIL pass ${pass} ${f}: ${e.message}`); process.exit(1); }
  }
}
console.log('migrations applied twice OK');

let failures = 0;
const ok = (cond, msg) => { console.log((cond ? 'ok   ' : 'FAIL ') + msg); if (!cond) failures++; };

async function as(uid, sql, params = [], role = 'authenticated') {
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}; select set_config('request.jwt.claim.sub', '${uid ?? ''}', true);`);
    const r = await db.query(sql, params);
    await db.exec('commit');
    return r;
  } catch (e) { await db.exec('rollback'); throw e; }
}
async function err(uid, sql, params = [], role) {
  try { await as(uid, sql, params, role); return null; } catch (e) { return e.message; }
}
async function user(name, role = 'student') {
  const id = (await db.query('select gen_random_uuid() id')).rows[0].id;
  await db.query('insert into auth.users (id) values ($1)', [id]);
  await db.query('insert into public.profiles (id, username, display_name, role) values ($1,$2,$2,$3)',
    [id, name, role]);
  return id;
}
const domains = async (uid = null, role) =>
  (await as(uid, 'select domain from public.allowed_link_domains order by domain', [], role))
    .rows.map((r) => r.domain);
const add = (uid, d) =>
  as(uid, 'insert into public.allowed_link_domains (domain, note) values ($1, $2)', [d, 'test']);
const remove = (uid, d) =>
  as(uid, 'delete from public.allowed_link_domains where domain = $1', [d]);

const owner = await user('owner', 'owner');
const admin = await user('admin', 'admin');
const student = await user('ali');

// ---- the starter list, readable signed out
const seed = ['kerawang.my', 'forms.gle', 'docs.google.com', 'chat.whatsapp.com', 'wa.me',
  'whatsapp.com', 'instagram.com', 'tiktok.com', 'youtube.com', 'youtu.be', 'facebook.com',
  'fb.me', 't.me', 'uitm.edu.my', 'maps.google.com', 'maps.app.goo.gl', 'goo.gl', 'drive.google.com'];
const anonList = await domains(null, 'anon');
ok(seed.every((d) => anonList.includes(d)) && anonList.length === seed.length,
  `anon reads the 18-domain starter list (${anonList.length})`);
ok((await domains(student)).length === seed.length, 'a student reads it too');

// ---- nobody but admins can write
const anonAdd = await err(null, 'insert into public.allowed_link_domains (domain) values ($1)', ['evil.com'], 'anon');
ok(anonAdd !== null, `anon cannot add (${anonAdd})`);
const studentAdd = await err(student, 'insert into public.allowed_link_domains (domain) values ($1)', ['evil.com']);
ok(studentAdd !== null, `a student cannot add (${studentAdd})`);
await as(student, 'delete from public.allowed_link_domains where domain = $1', ['wa.me']);
ok((await domains(student)).includes('wa.me'), 'a student delete removes nothing');
const anonDel = await err(null, 'delete from public.allowed_link_domains where domain = $1', ['wa.me'], 'anon');
ok(anonDel !== null || (await domains()).includes('wa.me'), 'anon cannot delete');
const studentUpd = await err(student, "update public.allowed_link_domains set note = 'x' where domain = 'wa.me'");
ok(studentUpd !== null, 'a student cannot edit a row');

// ---- admins and the owner can
await add(admin, 'example.org');
const row = (await db.query("select added_by from public.allowed_link_domains where domain = 'example.org'")).rows[0];
ok((await domains(student)).includes('example.org'), 'an admin adds a domain everyone then sees');
ok(row?.added_by === admin, 'added_by is filled in with the admin');
await remove(admin, 'example.org');
ok(!(await domains()).includes('example.org'), 'an admin removes it');
await add(owner, 'example.net');
await remove(owner, 'example.net');
ok(!(await domains()).includes('example.net'), 'the owner adds and removes');

// ---- duplicates and junk refused
const dup = await err(admin, 'insert into public.allowed_link_domains (domain) values ($1)', ['wa.me']);
ok(dup !== null, 'a duplicate is refused');
for (const bad of ['WA.ME', 'https://evil.com', 'evil.com/path', 'evil', 'ev il.com', '.com', 'a..com', '']) {
  const e = await err(admin, 'insert into public.allowed_link_domains (domain) values ($1)', [bad]);
  ok(e !== null, `refused: "${bad}"`);
}

// ---- starter domains are ordinary rows
await remove(admin, 'tiktok.com');
ok(!(await domains()).includes('tiktok.com'), 'an admin can remove a starter domain');

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
