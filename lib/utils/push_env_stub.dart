/// Non-web builds (tests): no browser to ask.
bool isIosBrowser() => false;
bool isInstalledApp() => false;

/// 'granted', 'denied', 'default' or 'unsupported'.
String notificationPermission() => 'unsupported';

/// A short name for this device, shown in Settings → Notifications.
String deviceLabel() => 'This device';

/// Asks the browser for permission. Must start inside a tap.
Future<String> requestPermission() async => 'unsupported';
