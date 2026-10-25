import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_reload_stub.dart'
    if (dart.library.js_interop) 'update_reload_web.dart' as impl;

/// Detects when a newer web build has been deployed and reloads into it.
///
/// `deploy_web.bat` stamps every build with a timestamp: it is compiled in
/// via `--dart-define=BUILD_ID=...` and also written to `build.json` next to
/// `index.html`. The running app polls that file (bypassing every cache) and
/// flags an update when the IDs differ.
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  /// Keep in sync with the `version:` name in pubspec.yaml.
  static const appVersion = '1.8.3';
  static const buildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');

  /// Only release web builds made by the deploy script can be checked.
  static bool get isSupported => kIsWeb && buildId != 'dev';

  final updateAvailable = ValueNotifier<bool>(false);
  String? latestBuildId;
  Timer? _timer;

  /// Check now, then every [interval] while the app is open.
  void start({Duration interval = const Duration(minutes: 15)}) {
    if (!isSupported || _timer != null) return;
    check();
    _timer = Timer.periodic(interval, (_) => check());
    impl.onPageVisible(check); // phones resume tabs rather than reopening them
  }

  /// Returns true if a newer build is live. Never throws.
  Future<bool> check() async {
    if (!isSupported) return false;
    try {
      // Root-relative: with path URLs a relative lookup from /events/123
      // would hit the SPA rewrite and get index.html back.
      final uri = Uri.base.resolve(
          '/build.json?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http
          .get(uri, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final id = (jsonDecode(res.body) as Map<String, dynamic>)['build_id'] as String?;
      if (id == null) return false;
      latestBuildId = id;
      final newer = id != buildId;
      if (newer) updateAvailable.value = true;
      return newer;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return false;
    }
  }

  /// Drops service workers + Cache Storage left by older builds, then reloads.
  Future<void> applyUpdate() => impl.hardReload();
}
