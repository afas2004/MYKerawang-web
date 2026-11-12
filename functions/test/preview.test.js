'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  parsePath,
  clip,
  formatPrice,
  formatEventTime,
  listingMeta,
  eventMeta,
  postMeta,
  formMeta,
  buildMeta,
  injectMeta,
} = require('../preview');
const { makeHandler, requestHost } = require('../handler');

const ID = '0f8fad5b-d9cb-469f-a165-70867728950e';
const INDEX = fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'index.html'), 'utf8');

// ------------------------------------------------------------ parsePath

test('parsePath accepts the three shared routes', () => {
  assert.deepEqual(parsePath(`/item/${ID}`), { kind: 'listing', id: ID, path: `/item/${ID}` });
  assert.equal(parsePath(`/event/${ID}`).kind, 'event');
  assert.equal(parsePath(`/post/${ID}/`).kind, 'post');
});

test('parsePath rejects deeper paths, other routes and non-uuid ids', () => {
  assert.equal(parsePath(`/item/${ID}/edit`), null);
  assert.equal(parsePath(`/event/${ID}/checkin`), null);
  assert.equal(parsePath(`/u/${ID}`), null);
  assert.equal(parsePath('/item/abc'), null);
  assert.equal(parsePath('/item/1;drop'), null);
  assert.equal(parsePath(`/item/${ID}&select=*`), null);
  assert.equal(parsePath(''), null);
  assert.equal(parsePath(undefined), null);
});

// --------------------------------------------------------- formatting

test('clip collapses whitespace and cuts with an ellipsis', () => {
  assert.equal(clip('  a\n\n b  ', 10), 'a b');
  assert.equal(clip('abcdefghij', 5), 'abcd…');
  assert.equal(clip(null, 5), '');
});

test('formatPrice matches the app', () => {
  assert.equal(formatPrice(5.5), 'RM5.50');
  assert.equal(formatPrice('12'), 'RM12.00');
  assert.equal(formatPrice(null), 'RM0.00');
});

test('formatEventTime is in Malaysia time', () => {
  // 12:00 UTC = 8:00 pm in Kuala Lumpur.
  const s = formatEventTime('2026-11-15T12:00:00+00:00');
  assert.match(s, /15 Nov/);
  assert.match(s, /8:00\s?pm/i);
  assert.equal(formatEventTime('not a date'), '');
});

// --------------------------------------------------------- meta builders

test('listing: title carries price and status, description falls back', () => {
  const m = listingMeta({
    title: 'Samyang ramen', price: 5.5, description: 'Pickup K018\nCOD +RM0.50',
    image_url: 'https://x.supabase.co/storage/v1/object/public/a.jpg', status: 'available',
  });
  assert.equal(m.title, 'Samyang ramen · RM5.50');
  assert.equal(m.description, 'Pickup K018 COD +RM0.50');
  assert.equal(m.image, 'https://x.supabase.co/storage/v1/object/public/a.jpg');

  assert.match(listingMeta({ title: 'Kettle', price: 10, status: 'sold' }).title, /^SOLD · /);
  assert.match(listingMeta({ title: 'Kettle', price: 10, is_sold: true }).title, /^SOLD · /);
  assert.match(listingMeta({ title: 'Kettle', price: 10, status: 'reserved' }).title, /^Reserved · /);
  assert.equal(listingMeta({ title: 'Kettle', price: 10 }).description, 'For sale on the MYKerawang Market.');
});

test('only https images are used', () => {
  assert.equal(listingMeta({ title: 'a', price: 1, image_url: 'http://insecure/a.jpg' }).image, null);
  assert.equal(listingMeta({ title: 'a', price: 1, image_url: 'javascript:alert(1)' }).image, null);
});

test('event: time and place lead the description; cancelled is flagged', () => {
  const m = eventMeta({
    title: 'Futsal night', start_datetime: '2026-11-15T12:00:00Z',
    location: 'Gelanggang', description: 'Bring your own water.',
  });
  assert.equal(m.title, 'Futsal night');
  assert.match(m.description, /15 Nov.*Gelanggang — Bring your own water\./);
  assert.match(eventMeta({ title: 'X', cancelled_at: '2026-11-01T00:00:00Z' }).title, /^CANCELLED · /);
});

test('post: anonymous posts never name anyone', () => {
  const m = postMeta({
    title: null, body: 'Who left the iron on?\nLevel 3 again.', is_anonymous: true,
    profiles: null, club: null,
  });
  assert.equal(m.title, 'Who left the iron on? — Anonymous');
  assert.equal(m.description, 'Level 3 again.');
});

test('post: club name, then display name, then username', () => {
  assert.match(postMeta({ title: 'Meeting', body: 'x', club: { name: 'Robotics Club' } }).title, /— Robotics Club$/);
  assert.match(postMeta({ title: 'Hi', body: 'x', profiles: { display_name: 'Aina', username: 'aina' } }).title, /— Aina$/);
  assert.match(postMeta({ title: 'Hi', body: 'x', profiles: { username: 'aina' } }).title, /— aina$/);
  assert.equal(postMeta({ title: null, body: '', image_url: null }).title, 'A post');
});

test('post: cover beats image', () => {
  const m = postMeta({ title: 't', body: '', cover_url: 'https://a/c.jpg', image_url: 'https://a/i.jpg' });
  assert.equal(m.image, 'https://a/c.jpg');
});

// ------------------------------------------------------------ injectMeta

test('injectMeta replaces every generic tag in the real index.html', () => {
  const meta = buildMeta('listing', { title: 'Samyang ramen', price: 5.5, image_url: 'https://a/b.jpg' }, `/item/${ID}`);
  const out = injectMeta(INDEX, meta);

  const count = (re) => (out.match(re) || []).length;
  assert.equal(count(/property="og:title"/g), 1);
  assert.equal(count(/property="og:image"/g), 1);
  assert.equal(count(/name="description"/g), 1);
  assert.equal(count(/name="twitter:card"/g), 1);
  assert.equal(count(/og:image:width/g), 0);
  assert.match(out, /<meta property="og:title" content="Samyang ramen · RM5\.50">/);
  assert.match(out, new RegExp(`<meta property="og:url" content="https://kerawang\\.my/item/${ID}">`));
  assert.match(out, /<meta name="twitter:card" content="summary_large_image">/);
  assert.match(out, /<title>Samyang ramen · RM5\.50 \| MYKerawang<\/title>/);

  // Tags come right after <meta charset>, near the top of the file.
  assert.ok(out.indexOf('og:title') < out.indexOf('googletagmanager'));
  // Everything else is untouched.
  assert.ok(out.includes('<base href='));
  assert.ok(out.includes("gtag('config'"));
});

test('injectMeta escapes text so a listing title cannot break the page', () => {
  const evil = '"><script>alert(1)</script>';
  const out = injectMeta(INDEX, buildMeta('listing', { title: evil, price: 1, description: evil }, `/item/${ID}`));
  assert.ok(!out.includes('<script>alert(1)</script>'));
  assert.ok(out.includes('&quot;&gt;&lt;script&gt;'));
});

test('no image falls back to the app icon with a small card', () => {
  const out = injectMeta(INDEX, buildMeta('event', { title: 'Talk' }, `/event/${ID}`));
  assert.match(out, /og:image" content="https:\/\/kerawang\.my\/icons\/Icon-512\.png"/);
  assert.match(out, /twitter:card" content="summary"/);
});

// --------------------------------------------------------------- handler

function fakeRes() {
  const r = { headers: {}, statusCode: null, body: null };
  r.set = (k, v) => { if (typeof k === 'object') Object.assign(r.headers, k); else r.headers[k] = v; return r; };
  r.status = (c) => { r.statusCode = c; return r; };
  r.send = (b) => { r.body = b; return r; };
  return r;
}

function fakeFetch({ row = null, lookupStatus = 200, indexStatus = 200, calls = [] } = {}) {
  return async (url, opts) => {
    calls.push({ url, opts });
    if (url.endsWith('/index.html')) {
      return { ok: indexStatus === 200, status: indexStatus, text: async () => INDEX };
    }
    return { ok: lookupStatus === 200, status: lookupStatus, json: async () => (row ? [row] : []) };
  };
}

const quiet = { error() {}, warn() {} };
const req = (p, extra = {}) => ({ method: 'GET', path: p, headers: { 'x-forwarded-host': 'kerawang.my' }, ...extra });

test('handler: listing found → page tags, cacheable on the CDN', async () => {
  const calls = [];
  const h = makeHandler({ fetchImpl: fakeFetch({ row: { title: 'Kettle', price: 12 }, calls }), log: quiet });
  const res = fakeRes();
  await h(req(`/item/${ID}`), res);
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /og:title" content="Kettle · RM12\.00"/);
  assert.equal(res.headers['Content-Type'], 'text/html; charset=utf-8');
  assert.match(res.headers['Cache-Control'], /s-maxage=300/);
  assert.equal(res.headers['X-Frame-Options'], 'SAMEORIGIN');

  const lookup = calls.find((c) => c.url.includes('/rest/v1/'));
  assert.match(lookup.url, new RegExp(`/rest/v1/listings\\?id=eq\\.${ID}&select=`));
  assert.ok(lookup.opts.headers.apikey.startsWith('sb_publishable_'));
  assert.equal(lookup.opts.headers.Authorization, undefined);
});

test('handler: posts are read from posts_public, never posts', async () => {
  const calls = [];
  const h = makeHandler({ fetchImpl: fakeFetch({ row: { title: 't', body: 'b' }, calls }), log: quiet });
  await h(req(`/post/${ID}`), fakeRes());
  const lookup = calls.find((c) => c.url.includes('/rest/v1/'));
  assert.match(lookup.url, /\/rest\/v1\/posts_public\?/);
});

test('handler: missing or hidden row → the generic page, unchanged', async () => {
  const h = makeHandler({ fetchImpl: fakeFetch({ row: null }), log: quiet });
  const res = fakeRes();
  await h(req(`/item/${ID}`), res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body, INDEX);
});

test('handler: lookup error → the generic page, not an error', async () => {
  const h = makeHandler({ fetchImpl: fakeFetch({ lookupStatus: 500 }), log: quiet });
  const res = fakeRes();
  await h(req(`/event/${ID}`), res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body, INDEX);
});

test('handler: bad id never reaches the database', async () => {
  const calls = [];
  const h = makeHandler({ fetchImpl: fakeFetch({ calls }), log: quiet });
  const res = fakeRes();
  await h(req('/item/not-a-uuid'), res);
  assert.equal(res.body, INDEX);
  assert.equal(calls.filter((c) => c.url.includes('/rest/v1/')).length, 0);
});

test('handler: index.html unavailable → 503, not cached', async () => {
  const h = makeHandler({ fetchImpl: fakeFetch({ indexStatus: 404 }), log: quiet });
  const res = fakeRes();
  await h(req(`/item/${ID}`), res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.headers['Cache-Control'], 'no-store');
});

test('handler: HEAD gets headers only; POST is refused', async () => {
  const h = makeHandler({ fetchImpl: fakeFetch({ row: { title: 'a', price: 1 } }), log: quiet });
  const head = fakeRes();
  await h(req(`/item/${ID}`, { method: 'HEAD' }), head);
  assert.equal(head.statusCode, 200);
  assert.equal(head.body, '');
  const post = fakeRes();
  await h(req(`/item/${ID}`, { method: 'POST' }), post);
  assert.equal(post.statusCode, 405);
});

test('requestHost only trusts known hosts', () => {
  assert.equal(requestHost({ headers: { 'x-forwarded-host': 'mykerawang-app.web.app' } }), 'mykerawang-app.web.app');
  assert.equal(requestHost({ headers: { 'x-forwarded-host': 'KERAWANG.MY:443' } }), 'kerawang.my');
  assert.equal(requestHost({ headers: { 'x-forwarded-host': 'evil.example' } }), 'kerawang.my');
  assert.equal(requestHost({ headers: {}, hostname: '' }), 'kerawang.my');
});

// ----------------------------------------------------------------- forms

test('parsePath: a form by id or by short name', () => {
  assert.deepEqual(parsePath(`/f/${ID}`), { kind: 'form', id: ID, path: `/f/${ID}` });
  assert.deepEqual(parsePath('/f/SUS-Survey/'), { kind: 'form', id: 'sus-survey', path: '/f/sus-survey' });
  assert.equal(parsePath(`/f/${ID}/edit`), null);
  assert.equal(parsePath('/f/ab'), null, 'too short');
  assert.equal(parsePath('/f/two--dashes'), null);
  assert.equal(parsePath('/f/-x-'), null);
  assert.equal(parsePath('/f/a%27b'), null);
  assert.equal(parsePath('/item/sus-survey'), null, 'short names are for forms only');
});

test('form: the title, and the description only as given', () => {
  assert.deepEqual(formMeta({ title: 'SUS survey', description: 'Tell us' }),
    { title: 'SUS survey', description: 'Tell us', image: null });
  assert.equal(formMeta({ title: 'SUS survey', description: null }).description, '',
    'no description stays blank');
  assert.equal(formMeta({ title: '' }).title, 'A form');
});

function rpcFetch({ row = null, calls = [] } = {}) {
  return async (url, opts) => {
    calls.push({ url, opts });
    if (url.endsWith('/index.html')) return { ok: true, status: 200, text: async () => INDEX };
    return { ok: true, status: 200, json: async () => row };
  };
}

test('handler: a form card comes from the form_preview RPC, as anon', async () => {
  const calls = [];
  const h = makeHandler({
    fetchImpl: rpcFetch({ row: { id: ID, slug: 'sus-survey', title: 'SUS survey', description: null }, calls }),
    log: quiet,
  });
  const res = fakeRes();
  await h(req('/f/sus-survey'), res);
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /og:title" content="SUS survey"/);
  assert.match(res.body, /og:description" content=""/);
  assert.match(res.body, /og:url" content="https:\/\/kerawang\.my\/f\/sus-survey"/);
  assert.doesNotMatch(res.body, /community marketplace/, 'the generic description is gone');

  const lookup = calls.find((c) => c.url.includes('/rest/v1/'));
  assert.match(lookup.url, /\/rest\/v1\/rpc\/form_preview$/);
  assert.equal(lookup.opts.method, 'POST');
  assert.deepEqual(JSON.parse(lookup.opts.body), { p_key: 'sus-survey' });
  assert.equal(lookup.opts.headers.Authorization, undefined);
});

test('handler: a missing or removed form → the generic page', async () => {
  const h = makeHandler({ fetchImpl: rpcFetch({ row: null }), log: quiet });
  const res = fakeRes();
  await h(req(`/f/${ID}`), res);
  assert.equal(res.body, INDEX);
});
