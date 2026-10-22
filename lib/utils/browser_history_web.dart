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
