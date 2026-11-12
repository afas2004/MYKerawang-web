'use strict';

// Pure helpers for per-page link previews: no network, no Firebase, so the
// tests can run with plain `node --test`.
//
// Flutter web is one index.html for every URL, so WhatsApp, Telegram and
// friends (which never run JavaScript) used to see the same generic
// "MYKerawang" card for every shared listing, event, post and form. The function
// in index.js fetches the live index.html, swaps the preview tags for ones
// describing the page, and serves it. People get the normal app; crawlers
// get a real card.

const CANONICAL_ORIGIN = 'https://kerawang.my';
const FALLBACK_IMAGE = `${CANONICAL_ORIGIN}/icons/Icon-512.png`;
const SITE_NAME = 'MYKerawang';

const TITLE_MAX = 90;
const DESCRIPTION_MAX = 200;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// A form's short name (`/f/sus-survey`). Same shape as the database's
// event_forms_slug_shape check and lib/utils/form_rules.dart.
const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/;

// The route shapes the function serves. Must match the rewrite regex in
// firebase.json and the routes in lib/router.dart.
const KINDS = { item: 'listing', event: 'event', post: 'post', f: 'form' };

/**
 * `/item/<uuid>` → `{ kind: 'listing', id }`. A form also takes its short
 * name: `/f/<uuid or short name>`. Anything else (wrong shape, a bad id, a
 * deeper path such as `/item/<id>/edit`) → null, and the caller serves the
 * generic page.
 */
function parsePath(pathname) {
  const m = /^\/(item|event|post|f)\/([^/]+)\/?$/.exec(pathname || '');
  if (!m) return null;
  const id = m[2].toLowerCase();
  const isKey = UUID_RE.test(id) || (m[1] === 'f' && SLUG_RE.test(id) && !id.includes('--'));
  if (!isKey) return null;
  return { kind: KINDS[m[1]], id, path: `/${m[1]}/${id}` };
}

/** One line, trimmed, cut at `max` characters with an ellipsis. */
function clip(text, max) {
  const s = String(text ?? '').replace(/\s+/g, ' ').trim();
  if (s.length <= max) return s;
  return `${s.slice(0, max - 1).trimEnd()}…`;
}

function escapeAttr(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/** Same as lib/utils/formatters.dart formatPrice. */
function formatPrice(price) {
  const n = Number(price);
  return `RM${(Number.isFinite(n) ? n : 0).toFixed(2)}`;
}

/** Same rule as lib/utils/listing_status.dart ListingStatus.of. */
function listingStatus(row) {
  if (row.status === 'reserved' || row.status === 'sold' || row.status === 'available') {
    return row.status;
  }
  return row.is_sold === true ? 'sold' : 'available';
}

/** "Sat, 15 Nov, 8:00 pm", in Malaysia time whatever the server's zone. */
function formatEventTime(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kuala_Lumpur',
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(d);
}

function httpsUrl(u) {
  return typeof u === 'string' && /^https:\/\//i.test(u) ? u : null;
}

/** Preview fields for a listing row (from `listings`, read as anon). */
function listingMeta(row) {
  const status = listingStatus(row);
  const tag = status === 'sold' ? 'SOLD · ' : status === 'reserved' ? 'Reserved · ' : '';
  return {
    title: `${tag}${clip(row.title, TITLE_MAX - 20)} · ${formatPrice(row.price)}`,
    description: clip(row.description, DESCRIPTION_MAX) || 'For sale on the MYKerawang Market.',
    image: httpsUrl(row.image_url),
  };
}

/** Preview fields for an event row (from `events`, read as anon). */
function eventMeta(row) {
  const when = formatEventTime(row.start_datetime);
  const where = clip(row.location, 60);
  const lead = [when, where].filter(Boolean).join(' · ');
  const body = clip(row.description, DESCRIPTION_MAX);
  return {
    title: `${row.cancelled_at ? 'CANCELLED · ' : ''}${clip(row.title, TITLE_MAX)}`,
    description: clip([lead, body].filter(Boolean).join(' — '), DESCRIPTION_MAX) || 'An event on MYKerawang.',
    image: httpsUrl(row.image_url),
  };
}

/**
 * Preview fields for a row from `posts_public`. That view already nulls
 * the author of anonymous posts, so nothing here can reveal one; the
 * preview says "Anonymous" and stops there.
 */
function postMeta(row) {
  const author = row.is_anonymous
    ? 'Anonymous'
    : (row.club && row.club.name) ||
      (row.profiles && (row.profiles.display_name || row.profiles.username)) ||
      null;
  const body = String(row.body ?? '');
  const firstLine = body.split('\n').map((l) => l.trim()).find(Boolean) || '';
  const heading = clip(row.title, TITLE_MAX) || clip(firstLine, 70) || 'A post';
  const title = author ? clip(`${heading} — ${author}`, TITLE_MAX) : heading;
  // Skip the line already used as the heading.
  const rest = row.title ? body : body.replace(firstLine, '');
  return {
    title,
    description: clip(rest, DESCRIPTION_MAX) || 'A post on MYKerawang.',
    image: httpsUrl(row.cover_url) || httpsUrl(row.image_url),
  };
}

/**
 * Preview fields for a form, from the `form_preview` RPC: the form's own
 * title, and its description only if the form is public (the RPC returns
 * null otherwise). No description → left blank, nothing made up.
 */
function formMeta(row) {
  return {
    title: clip(row.title, TITLE_MAX) || 'A form',
    description: clip(row.description, DESCRIPTION_MAX),
    image: null,
  };
}

const BUILDERS = { listing: listingMeta, event: eventMeta, post: postMeta, form: formMeta };

function buildMeta(kind, row, path) {
  const meta = BUILDERS[kind](row);
  return { ...meta, url: `${CANONICAL_ORIGIN}${path}` };
}

/** The tag block that replaces index.html's generic one. */
function renderTags(meta) {
  const image = meta.image || FALLBACK_IMAGE;
  const big = Boolean(meta.image);
  const t = escapeAttr(meta.title);
  const d = escapeAttr(meta.description);
  const i = escapeAttr(image);
  const u = escapeAttr(meta.url);
  return [
    `<meta name="description" content="${d}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="${SITE_NAME}">`,
    `<meta property="og:url" content="${u}">`,
    `<meta property="og:title" content="${t}">`,
    `<meta property="og:description" content="${d}">`,
    `<meta property="og:image" content="${i}">`,
    `<meta name="twitter:card" content="${big ? 'summary_large_image' : 'summary'}">`,
    `<meta name="twitter:title" content="${t}">`,
    `<meta name="twitter:description" content="${d}">`,
    `<meta name="twitter:image" content="${i}">`,
  ].join('\n  ');
}

// Every preview tag index.html may carry: description, og:*, twitter:*.
const PREVIEW_TAG_RE =
  /[ \t]*<meta\s+(?:name|property)="(?:description|og:[^"]*|twitter:[^"]*)"[^>]*>[ \t]*\r?\n?/gi;

/**
 * index.html with its generic preview tags removed, the page's own tags
 * inserted right after `<meta charset>` (so they sit in the first few KB,
 * where every crawler looks), and `<title>` set to the page title.
 */
function injectMeta(html, meta) {
  let out = html.replace(PREVIEW_TAG_RE, '');
  const block = renderTags(meta);
  const charset = /<meta\s+charset=[^>]*>/i;
  if (charset.test(out)) {
    out = out.replace(charset, (m) => `${m}\n  ${block}`);
  } else {
    out = out.replace(/<head[^>]*>/i, (m) => `${m}\n  ${block}`);
  }
  out = out.replace(
    /<title>[\s\S]*?<\/title>/i,
    `<title>${escapeAttr(meta.title)} | ${SITE_NAME}</title>`,
  );
  return out;
}

module.exports = {
  CANONICAL_ORIGIN,
  parsePath,
  clip,
  escapeAttr,
  formatPrice,
  formatEventTime,
  listingMeta,
  eventMeta,
  postMeta,
  formMeta,
  buildMeta,
  renderTags,
  injectMeta,
};
