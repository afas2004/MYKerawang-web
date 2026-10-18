import 'package:flutter/foundation.dart' show kIsWeb;

/// Public origin of the deployed web app, used when there is no browser
/// origin to read (mobile builds).
const kAppBaseUrl = 'https://mykerawang-app.web.app';

/// Origin links should point at: the current site on web (so staging and
/// localhost links stay on their own host), [kAppBaseUrl] elsewhere.
String get appOrigin => kIsWeb ? Uri.base.origin : kAppBaseUrl;

/// Shareable https link to a profile — opens in any phone camera/browser.
String profileUrl(String userId) => '$appOrigin/u/$userId';

/// User id from a scanned profile code. Accepts the https form
/// (`…/u/<id>`, any host) and the legacy `mykerawang://user/<id>`.
String? userIdFromProfileCode(String code) {
  final uri = Uri.tryParse(code.trim());
  if (uri == null) return null;
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (uri.scheme == 'mykerawang') {
    // mykerawang://user/<id> parses with host "user".
    if (uri.host == 'user' && segs.isNotEmpty) return segs.last;
    if (segs.length >= 2 && segs.first == 'user') return segs[1];
    return null;
  }
  if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      segs.length == 2 &&
      segs.first == 'u') {
    return segs[1];
  }
  return null;
}
