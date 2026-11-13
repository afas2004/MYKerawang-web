import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/push_config.dart';
import '../utils/push_env_stub.dart'
    if (dart.library.js_interop) '../utils/push_env_web.dart' as env;

/// Can phone notifications (push) reach this device?
enum PushState {
  /// The Web Push key isn't filled in yet (lib/config/push_config.dart).
  notConfigured,

  /// This browser can't receive push at all.
  unsupported,

  /// iPhone Safari in a tab: push only works once added to the Home Screen.
  iosNeedsInstall,

  /// The person blocked notifications for kerawang.my in the browser.
  blocked,

  /// Allowed, but this device isn't registered (never turned on, or off).
  off,

  /// Registered: pushes arrive here.
  on,
}

enum EnableResult { enabled, denied, unsupported, failed }

/// Registers this device for phone notifications. The notifications
/// themselves are sent by worker/push.py (GitHub Actions); this stores the
/// device's FCM token through register_push_token().
///
/// Firebase is only started when push is actually used, so people who
/// never turn it on don't download the Firebase SDK.
class PushService {
  PushService._();
  static final instance = PushService._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Changes whenever this device's push state may have changed, so the
  /// bell banner and Settings refresh.
  final changed = ValueNotifier<int>(0);

  String? _token;
  StreamSubscription<String>? _refreshSub;
  Future<FirebaseMessaging>? _messaging;

  static const _tokenKey = 'pushToken';
  static const _snoozeKey = 'pushAskSnoozedUntil';

  bool get configured => kIsWeb && kWebPushVapidKey.isNotEmpty;

  Future<FirebaseMessaging> _fm() => _messaging ??= () async {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: kFirebaseWebOptions);
        }
        return FirebaseMessaging.instance;
      }();

  /// Never prompts.
  Future<PushState> state() async {
    if (!configured) return PushState.notConfigured;
    if (env.isIosBrowser() && !env.isInstalledApp()) return PushState.iosNeedsInstall;
    final perm = env.notificationPermission();
    if (perm == 'unsupported') return PushState.unsupported;
    if (perm == 'denied') return PushState.blocked;
    try {
      if (!await (await _fm()).isSupported()) return PushState.unsupported;
    } catch (_) {
      return PushState.unsupported;
    }
    if (perm != 'granted') return PushState.off;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null ? PushState.on : PushState.off;
  }

  /// Asks for permission and registers this device. Call from a tap:
  /// browsers only show their prompt in response to one.
  Future<EnableResult> enable() async {
    if (_db.auth.currentUser == null || !configured) return EnableResult.failed;
    try {
      // First, while still inside the tap: the browser's own prompt.
      final perm = await env.requestPermission();
      if (perm == 'unsupported') return EnableResult.unsupported;
      if (perm != 'granted') return EnableResult.denied;
      final fm = await _fm();
      if (!await fm.isSupported()) return EnableResult.unsupported;
      final settings = await fm.requestPermission();
      final s = settings.authorizationStatus;
      if (s != AuthorizationStatus.authorized && s != AuthorizationStatus.provisional) {
        return EnableResult.denied;
      }
      final token = await _tokenWithRetry(fm);
      if (token == null) return EnableResult.failed;
      await _save(token);
      _listenForRefresh(fm);
      return EnableResult.enabled;
    } catch (e) {
      debugPrint('Push enable failed: $e');
      return EnableResult.failed;
    } finally {
      changed.value++;
    }
  }

  /// Stops pushes to this device (the bell keeps working).
  Future<void> disableThisDevice() async {
    final token = _token ?? (await SharedPreferences.getInstance()).getString(_tokenKey);
    await _forget(token);
    try {
      // ignore: deprecated_member_use
      if (Firebase.apps.isNotEmpty) await (await _fm()).deleteToken();
    } catch (e) {
      debugPrint('Push deleteToken failed: $e');
    }
    changed.value++;
  }

  /// On sign-in / app start: tokens rotate, so quietly re-register when this
  /// device was on and permission still stands. Never prompts.
  Future<void> syncOnLaunch() async {
    if (!configured || _db.auth.currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_tokenKey) == null) return;
    if (env.notificationPermission() != 'granted') return;
    try {
      final fm = await _fm();
      final token = await _tokenWithRetry(fm);
      if (token != null) await _save(token);
      _listenForRefresh(fm);
    } catch (e) {
      debugPrint('Push sync failed: $e');
    }
  }

  /// Before sign-out: stop sending this account's notifications here.
  Future<void> forgetThisDevice() async {
    _refreshSub?.cancel();
    _refreshSub = null;
    final prefs = await SharedPreferences.getInstance();
    // The next account on this device turns it on for itself.
    await _forget(_token ?? prefs.getString(_tokenKey));
  }

  /// This device's registered token, to mark it in the device list.
  Future<String?> currentToken() async =>
      _token ?? (await SharedPreferences.getInstance()).getString(_tokenKey);

  // ------------------------------------------------------------ asking

  /// Whether to offer the "turn on" sheet/banner now: push is possible here
  /// but off, and the person didn't say "Not now" in the last two weeks.
  Future<bool> shouldOffer() async {
    if (_db.auth.currentUser == null) return false;
    final st = await state();
    if (st != PushState.off && st != PushState.iosNeedsInstall) return false;
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_snoozeKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch > until;
  }

  Future<void> snooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozeKey,
        DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch);
    changed.value++;
  }

  // ------------------------------------------------------------ internals

  Future<String?> _tokenWithRetry(FirebaseMessaging fm) async {
    // The push worker can still be starting on the first try.
    for (var attempt = 1;; attempt++) {
      try {
        // ignore: deprecated_member_use
        return await fm.getToken(vapidKey: kWebPushVapidKey);
      } catch (e) {
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 1500 * attempt));
      }
    }
  }

  Future<void> _save(String token) async {
    _token = token;
    await _db.rpc('register_push_token', params: {
      'p_token': token,
      'p_platform': 'web',
      'p_label': env.deviceLabel(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _forget(String? token, {bool keepLocal = false}) async {
    if (!keepLocal) {
      _token = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    }
    if (token == null) return;
    try {
      await _db.from('push_tokens').delete().eq('token', token);
    } catch (e) {
      debugPrint('Push forget failed: $e');
    }
  }

  void _listenForRefresh(FirebaseMessaging fm) {
    // ignore: deprecated_member_use
    _refreshSub ??= fm.onTokenRefresh.listen((t) {
      _save(t).catchError((Object e) => debugPrint('Push token refresh: $e'));
    });
  }
}
