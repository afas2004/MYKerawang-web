/// Safe links: which web links in user-written text may be tapped.
///
/// Only links to sites on the allowed list (admins manage it, see
/// `allowed_link_domains` in 20261114000200_allowed_link_domains.sql) become
/// tappable. Everything else stays plain text, so a phishing link (a fake
/// login page made to steal passwords) can't be opened with one tap.
///
/// Pure functions only, so they're easy to test; the cached list lives in
/// `services/allowed_links.dart`.
library;

/// Built-in copy of the migration's starter list. Used until the real list
/// loads, and kept if loading fails.
const List<String> kSeedAllowedDomains = [
  'kerawang.my',
  'forms.gle',
  'docs.google.com',
  'drive.google.com',
  'maps.google.com',
  'maps.app.goo.gl',
  'goo.gl',
  'chat.whatsapp.com',
  'wa.me',
  'whatsapp.com',
  't.me',
  'instagram.com',
  'tiktok.com',
  'youtube.com',
  'youtu.be',
  'facebook.com',
  'fb.me',
  'uitm.edu.my',
];

/// This app's own site: its links open inside the app.
const String kAppHost = 'kerawang.my';

/// Longest link label shown; longer ones end in "…" (the tap still opens
/// the whole link).
const int kLinkDisplayMax = 40;

/// A link as written: `http(s)://…` or a bare `www.…`, not glued to a word
/// before it. Stops at spaces, quotes, angle brackets and backslashes (a
/// browser reads `\` as `/`, so `https://evil.com\@forms.gle` must end at
/// the backslash). Trailing punctuation is trimmed by [findLinks].
final RegExp linkPattern = RegExp(
  r'(?<![\w@.\-/])(?:[hH][tT][tT][pP][sS]?://|[wW][wW][wW]\.)[^\s<>"\\`]+',
);

/// Lower-case host name: labels of letters, digits and hyphens, then a
/// top-level part of 2–63 letters. Same rule as the table's CHECK.
final RegExp _domainPattern =
    RegExp(r'^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$');

/// One link found in text.
class FoundLink {
  /// Where it is in the text ([end] is after the trimmed link).
  final int start, end;

  /// The link as written (trailing punctuation removed).
  final String text;

  const FoundLink(this.start, this.end, this.text);

  @override
  String toString() => 'FoundLink($start, $end, $text)';
}

/// [raw] (a match of [linkPattern]) without the punctuation that ends a
/// sentence around it: "see forms.gle/x." or "(forms.gle/x)". A closing
/// bracket stays when the link itself opened one, as in `…/Foo_(bar)`.
String trimLinkEnd(String raw) {
  var s = raw;
  while (s.isNotEmpty) {
    final last = s[s.length - 1];
    if ('.,;:!?\'*'.contains(last)) {
      s = s.substring(0, s.length - 1);
      continue;
    }
    const pairs = {')': '(', ']': '[', '}': '{'};
    final open = pairs[last];
    if (open != null &&
        open.allMatches(s).length < last.allMatches(s).length) {
      s = s.substring(0, s.length - 1);
      continue;
    }
    break;
  }
  return s;
}

/// Every link in [text], in order.
List<FoundLink> findLinks(String text) => [
      for (final m in linkPattern.allMatches(text))
        if (trimLinkEnd(m[0]!) case final t when linkUri(t) != null)
          FoundLink(m.start, m.start + t.length, t),
    ];

/// [link] as a full URL: a bare `www.` link gets `https://`.
Uri? linkUri(String link) {
  final full = link.toLowerCase().startsWith('www.') ? 'https://$link' : link;
  final uri = Uri.tryParse(full);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// The host of [uri] in lower case, without a trailing dot.
String hostOf(Uri uri) {
  var h = uri.host.toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h;
}

/// Whether [host] is one of [allowed] or a subdomain of one:
/// `student.uitm.edu.my` matches `uitm.edu.my`; `evil-forms.gle.com` and
/// `notforms.gle` do not match `forms.gle`.
bool hostAllowed(String host, Iterable<String> allowed) {
  final h = host.toLowerCase();
  if (h.isEmpty) return false;
  for (final d in allowed) {
    if (d.isEmpty) continue;
    if (h == d || h.endsWith('.$d')) return true;
  }
  return false;
}

/// [link] as a URL that may be tapped, or null when it stays plain text:
/// not http(s), no host, a user name before the host (`https://x@evil.com`
/// is a known trick), or a host that isn't allowed.
Uri? allowedLinkUri(String link, Iterable<String> allowed) {
  final uri = linkUri(link);
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  return hostAllowed(hostOf(uri), allowed) ? uri : null;
}

/// Whether [uri] is this app's own site (open it inside the app).
bool isAppLink(Uri uri) => hostAllowed(hostOf(uri), const [kAppHost]);

/// The in-app route for an app link: path plus query, `/home` for the root.
String appRouteOf(Uri uri) {
  final path = uri.path.isEmpty || uri.path == '/' ? '/home' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

/// The label shown for a tappable link: as written, cut to
/// [kLinkDisplayMax] characters with "…".
String linkLabel(String link, {int max = kLinkDisplayMax}) =>
    link.length <= max ? link : '${link.substring(0, max - 1)}…';

/// What an admin typed or pasted (a domain or a whole URL) cleaned to a
/// host for the list, or null when it isn't a valid domain. A leading
/// `www.` is dropped so the entry covers the whole site.
String? normalizeDomainInput(String input) {
  var s = input.trim().toLowerCase();
  if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  var host = hostOf(uri);
  if (host.startsWith('www.')) host = host.substring(4);
  if (host.length > 253 || !_domainPattern.hasMatch(host)) return null;
  return host;
}
