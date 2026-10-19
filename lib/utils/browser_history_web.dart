import 'package:web/web.dart' as web;

/// Steps the browser back one entry. go_router then restores that entry's
/// page stack, so the in-app back and the browser's back stay in step.
bool browserHistoryBack() {
  web.window.history.back();
  return true;
}
