/// What the app is willing to hand to the browser or the OS.
///
/// Links here are written by other people — an event's registration page, the
/// `link` channel of a contact card, a Telegram handle that is really a URL.
/// `launchUrl` passes the string to the platform, and on the web a
/// `javascript:` URL is code: `window.open('javascript:…')` runs it in a
/// context that can still reach the opener. So the scheme is checked here,
/// once, before anything is launched.
library;

/// Schemes we launch. `mailto`/`tel` are dialogs, not pages.
const Set<String> kLaunchableSchemes = {'http', 'https', 'mailto', 'tel'};

/// [raw] as a URI that is safe to launch, or null when it should be refused.
///
/// Accepts absolute http(s) URLs (with a host), `mailto:` and `tel:`. Rejects
/// unparseable text, relative paths, and every other scheme — `javascript:`,
/// `data:`, `file:`, `intent:`, `content:`.
Uri? launchableUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme) return null;
  final scheme = uri.scheme.toLowerCase();
  if (!kLaunchableSchemes.contains(scheme)) return null;
  if ((scheme == 'http' || scheme == 'https') && uri.host.isEmpty) return null;
  return uri;
}
