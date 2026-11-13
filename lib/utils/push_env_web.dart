import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

String get _ua => web.window.navigator.userAgent;

/// iPhone/iPad Safari (iPadOS also reports "Macintosh" with touch).
bool isIosBrowser() =>
    RegExp(r'iPhone|iPad|iPod').hasMatch(_ua) ||
    (_ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);

/// Opened from the Home Screen (installed), not in a browser tab.
bool isInstalledApp() {
  if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
  final standalone = (web.window.navigator as JSObject)['standalone'];
  return standalone.isA<JSBoolean>() && (standalone as JSBoolean).toDart;
}

/// 'granted', 'denied', 'default' or 'unsupported'.
String notificationPermission() {
  if (!web.window.has('Notification')) return 'unsupported';
  return web.Notification.permission;
}

/// Asks the browser for permission. Must start inside a tap: iPhone in
/// particular ignores a request that comes after an await.
Future<String> requestPermission() async {
  if (!web.window.has('Notification')) return 'unsupported';
  final r = await web.Notification.requestPermission().toDart;
  return r.toDart;
}

/// A short name for this device, shown in Settings → Notifications.
String deviceLabel() {
  final ua = _ua;
  final device = RegExp(r'iPhone|iPad').firstMatch(ua)?.group(0) ??
      (ua.contains('Android')
          ? 'Android'
          : ua.contains('Windows')
              ? 'Windows'
              : ua.contains('Mac')
                  ? 'Mac'
                  : ua.contains('Linux')
                      ? 'Linux'
                      : 'Device');
  final browser = ua.contains('Edg/')
      ? 'Edge'
      : ua.contains('SamsungBrowser')
          ? 'Samsung Internet'
          : ua.contains('Firefox')
              ? 'Firefox'
              : ua.contains('Chrome')
                  ? 'Chrome'
                  : ua.contains('Safari')
                      ? 'Safari'
                      : 'Browser';
  return '$browser · $device';
}
