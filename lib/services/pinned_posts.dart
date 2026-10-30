import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/announcement_rules.dart';

/// The Home pin bar's data: global pins, loaded on their own so the feed
/// can page by date alone and a pin change never shifts its offsets.
abstract final class PinnedPosts {
  static const _dismissedKey = 'dismissed_pins';

  /// What the bar shows: mandatory first, closed ones left out.
  static final ValueNotifier<List<Map<String, dynamic>>> pins =
      ValueNotifier(const []);

  static List<Map<String, dynamic>> _all = const [];
  static Set<String> _dismissed = {};

  /// Tests inject rows here instead of Supabase.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? debugLoad;

  static Future<List<Map<String, dynamic>>> _load() async =>
      List<Map<String, dynamic>>.from(await Supabase.instance.client
          .from('posts_public')
          .select('*')
          .eq('is_pinned', true)
          .order('pinned_until', ascending: false)
          .limit(10));

  /// Reloads the bar; on failure it keeps what it has.
  static Future<void> refresh() async {
    try {
      final rows = await (debugLoad ?? _load)();
      final prefs = await SharedPreferences.getInstance();
      _dismissed = (prefs.getStringList(_dismissedKey) ?? const []).toSet();
      _all = rows;
      _publish();
    } catch (e) {
      debugPrint('Pinned posts failed: $e');
    }
  }

  /// Hides a pin on this device. Mandatory pins can't be closed.
  static Future<void> dismiss(Map<String, dynamic> post) async {
    if (post['pin_mandatory'] == true) return;
    _dismissed.add('${post['id']}');
    _publish();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey, _dismissed.toList());
  }

  static void _publish() {
    final shown = [
      for (final p in _all)
        if (showInHomeFeed(p) &&
            (p['pin_mandatory'] == true || !_dismissed.contains('${p['id']}')))
          p,
    ];
    // Sorted here, not in the query: the bar keeps working on a database
    // that doesn't have the pin_mandatory column yet.
    final mandatory = shown.where((p) => p['pin_mandatory'] == true);
    pins.value = [
      ...mandatory,
      ...shown.where((p) => p['pin_mandatory'] != true),
    ];
  }

  @visibleForTesting
  static void debugReset() {
    _all = const [];
    _dismissed = {};
    pins.value = const [];
    debugLoad = null;
  }
}
