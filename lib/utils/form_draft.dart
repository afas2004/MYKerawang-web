import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Autosaved text of a create form, so a page reload doesn't lose it.
///
/// On Android Chrome the tab can be thrown away while the camera / photo
/// picker is open, and web/index.html reloads as a last resort when the
/// GPU context is lost. Neither runs the form's dispose, so the draft
/// survives exactly those cases; leaving the form on purpose (publish,
/// discard, close) clears it in dispose.
///
/// Photos aren't kept — they can be several MB each.
class FormDraft {
  final String key;
  FormDraft(this.key);

  static const _prefix = 'draft.';

  /// Debounce for saves while typing.
  @visibleForTesting
  static Duration delay = const Duration(milliseconds: 600);

  Timer? _debounce;
  String? _lastSaved;

  Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      _lastSaved = raw;
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('Draft load failed: $e');
      return null;
    }
  }

  /// Saves [data] shortly (debounced); a no-op if nothing changed. Empty
  /// drafts are removed rather than stored.
  void save(Map<String, dynamic> data) {
    final empty = data.values.every((v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty));
    final encoded = empty ? null : jsonEncode(data);
    if (encoded == _lastSaved) return;
    _lastSaved = encoded;
    _debounce?.cancel();
    _debounce = Timer(delay, () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (encoded == null) {
          await prefs.remove('$_prefix$key');
        } else {
          await prefs.setString('$_prefix$key', encoded);
        }
      } catch (e) {
        debugPrint('Draft save failed: $e');
      }
    });
  }

  Future<void> clear() async {
    _debounce?.cancel();
    _lastSaved = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }
}
