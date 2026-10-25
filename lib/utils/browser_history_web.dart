import 'package:web/web.dart' as web;

/// Steps the browser back one entry. go_router then restores that entry's
/// page stack, so the in-app back and the browser's back stay in step.
bool browserHistoryBack() {
  web.window.history.back();
  return true;
}

/// Steps the browser forward one entry — used to undo a browser back that
/// only closed a dialog or sheet, so the address bar matches the page.
bool browserHistoryForward() {
  web.window.history.forward();
  return true;
}

/// Sends the page to [url] without leaving the page it came from behind.
///
/// Used for the Google sign-in redirect. `location.assign` (what
/// url_launcher does for `_self`) *pushes*, so the provider's account
/// chooser stays one step behind the app and Back showed it again after
/// signing in. Here the current page is pushed once and the new entry is
/// then *replaced* by [url]: the chooser gets the spare entry, the page
/// that comes back from the flow takes that entry over, and Google is
/// never in the back stack. The spare entry also means cancelling on
/// Google's page still lands on the login page.
bool replaceLocationForOAuth(String url) {
  web.window.history.pushState(null, '', web.window.location.href);
  web.window.location.replace(url);
  return true;
}
