import 'dart:async';

import 'package:flutter/foundation.dart';

import 'moderation_service.dart';

/// Client-side lock for the admin console.
///
/// The PIN itself is checked by the database (`admin_check_pin`); this class
/// only remembers the unlock for the current page lifetime and re-locks after
/// [idleTimeout] without interaction. A reload or a new tab asks again.
class AdminUnlock extends ChangeNotifier {
  AdminUnlock._();

  static final AdminUnlock instance = AdminUnlock._();

  static const Duration idleTimeout = Duration(minutes: 15);

  bool _configured = false;
  bool _unlocked = false;
  Timer? _timer;

  /// Whether an owner-set PIN exists.
  bool get configured => _configured;

  /// Whether the console is open for this page lifetime.
  bool get unlocked => _unlocked;

  /// Called when the status loads. With no PIN configured the console stays
  /// open (there is nothing to unlock yet); once a PIN exists it locks.
  void setConfigured(bool value) {
    _configured = value;
    if (!value) {
      _unlocked = true;
      _timer?.cancel();
    }
    notifyListeners();
  }

  /// Checks the PIN with the database and starts the idle timer on success.
  Future<bool> unlock(String pin) async {
    final ok = await ModerationService.checkAdminPin(pin);
    if (!ok) return false;
    startSession();
    return true;
  }

  /// Keeps the console open without rechecking (used right after setting the
  /// first PIN, so the owner isn't immediately kicked out).
  void startSession() {
    _unlocked = true;
    _arm();
    notifyListeners();
  }

  /// Resets the idle countdown on pointer/keyboard activity.
  void touch() {
    if (_unlocked) _arm();
  }

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    _timer?.cancel();
    notifyListeners();
  }

  /// Sign-out / new account: forget everything.
  void reset() {
    _configured = false;
    _unlocked = false;
    _timer?.cancel();
    notifyListeners();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(idleTimeout, lock);
  }
}
