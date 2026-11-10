'use strict';

const { parsePath, buildMeta, injectMeta } = require('./preview');

// Same public project URL and publishable key as lib/main.dart. The key is
// public by design (the "visitor badge" in docs/security-plain-words.md):
// reads go through row-level security as `anon`, so this function can only
// see what a signed-out guest could see in the app. Hidden listings and
// events, private events and anonymous authors stay out.
const SUPABASE_URL = 'https://zxjuqpqzyzmegdjttzyz.supabase.co';
const SUPABASE_KEY = 'sb_publishable_REqYNPrrJEIgmEjZjrJhtg_1JrLn_yO';

// Hosts this site is served from. The live index.html is fetched from the
// same host the request came in on, so a preview of mykerawang-app.web.app
// gets that host's build; anything unexpected falls back to the main domain.
const KNOWN_HOSTS = new Set([
  'kerawang.my',
  'www.kerawang.my',
  'mykerawang-app.web.app',
  'mykerawang-app.firebaseapp.com',
]);
const DEFAULT_HOST = 'kerawang.my';

const LOOKUP_TIMEOUT_MS = 2500;
const INDEX_TIMEOUT_MS = 5000;

// Which table or view, and which columns, per kind. posts_public is the
// view guests read; it already hides anonymous authors.
const QUERIES = {
  listing: {
    from: 'listings',
    select: 'id,title,price,description,image_url,status,is_sold',
  },
  event: {
    from: 'events',
    select: 'id,title,description,start_datetime,location,image_url,cancelled_at',
  },
  post: {
    from: 'posts_public',
    select: 'id,title,body,image_url,cover_url,is_anonymous,profiles,club',
  },
};

// Browsers revalidate every time (like index.html itself); the Hosting CDN
// keeps a copy for 5 minutes so a link shared into a busy group does not
// run the function once per tap. Every Hosting deploy purges the CDN, so a
// new build is never served with an old index.html.
const CACHE_CONTROL = 'public, max-age=0, s-maxage=300';

// firebase.json's headers block covers static files; set the same ones
// here so a rewritten page is not weaker than the plain one.
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'SAMEORIGIN',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

function requestHost(req) {
  const raw = String(req.headers['x-forwarded-host'] || req.hostname || '')
    .split(',')[0]
    .trim()
    .toLowerCase()
    .replace(/:\d+$/, '');
  return KNOWN_HOSTS.has(raw) ? raw : DEFAULT_HOST;
}

async function fetchRow(fetchImpl, kind, id) {
  const q = QUERIES[kind];
  const url =
    `${SUPABASE_URL}/rest/v1/${q.from}` +
    `?id=eq.${encodeURIComponent(id)}&select=${q.select}&limit=1`;
  const res = await fetchImpl(url, {
    headers: { apikey: SUPABASE_KEY, Accept: 'application/json' },
    signal: AbortSignal.timeout(LOOKUP_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`lookup ${kind} ${res.status}`);
  const rows = await res.json();
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

async function fetchIndex(fetchImpl, host) {
  // An exact file path: Hosting serves the static file and never reaches
  // the rewrite, so this cannot loop back into the function.
  const res = await fetchImpl(`https://${host}/index.html`, {
    signal: AbortSignal.timeout(INDEX_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`index.html ${res.status}`);
  return res.text();
}

/**
 * Express-style handler. `fetchImpl` and `log` are injectable for tests.
 *
 * Never worse than before: if the row is missing, hidden, private, or the
 * lookup fails or is slow, the page is served with index.html's own
 * generic tags, exactly as Hosting would have served it.
 */
function makeHandler({ fetchImpl = fetch, log = console } = {}) {
  return async function linkPreview(req, res) {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.set('Allow', 'GET, HEAD').status(405).send('Method not allowed');
      return;
    }

    const host = requestHost(req);
    let html;
    try {
      html = await fetchIndex(fetchImpl, host);
    } catch (e) {
      log.error('link-preview: could not load index.html', e);
      res.set('Cache-Control', 'no-store').status(503).send('Try again in a moment.');
      return;
    }

    const target = parsePath(req.path);
    if (target) {
      try {
        const row = await fetchRow(fetchImpl, target.kind, target.id);
        if (row) html = injectMeta(html, buildMeta(target.kind, row, target.path));
      } catch (e) {
        log.warn('link-preview: lookup failed, serving generic tags', e.message || e);
      }
    }

    res.set({
      ...SECURITY_HEADERS,
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': CACHE_CONTROL,
    });
    res.status(200).send(req.method === 'HEAD' ? '' : html);
  };
}

module.exports = { makeHandler, requestHost, QUERIES };
