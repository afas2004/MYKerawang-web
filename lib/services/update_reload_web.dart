import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Unregisters service workers and clears Cache Storage (older builds used
/// Flutter's offline-first worker, which serves stale app code), then reloads.
Future<void> hardReload() async {
  try {
    final regs = await web.window.navigator.serviceWorker.getRegistrations().toDart;
    for (final r in regs.toDart) {
      await r.unregister().toDart;
    }
  } catch (_) {}
  try {
    final keys = await web.window.caches.keys().toDart;
    for (final k in keys.toDart) {
      await web.window.caches.delete(k.toDart).toDart;
    }
  } catch (_) {}
  web.window.location.reload();
}

void onPageVisible(void Function() callback) {
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.visibilityState == 'visible') callback();
    }).toJS,
  );
}
