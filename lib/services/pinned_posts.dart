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

  /// How many live pins this device has closed, so Home can offer them
  /// back. Closing the last pin takes the bar away with it, so without
  /// this count there is nothing left to tap.
  static final ValueNotifier<int> closedCount = ValueNotifier(0);

  static List<Map<String, dynamic>> _all = const [];

  /// Every live pin, closed ones included: a closed pin is still pinned.
  static Iterable<dynamic> get activeIds => _all.map((p) => p['id']);
  static Set<String> _dismissed = {};

  /// Tests inject rows here instead of Supabase.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? debugLoad;

  /// Tests inject the admin list here instead of Supabase.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? debugAdminLoad;

  static Future<List<Map<String, dynamic>>> _load() async =>
      List<Map<String, dynamic>>.from(await Supabase.instance.client
          .from('posts_public')
          .select('*')
          .eq('is_pinned', true)
          .order('pinned_until', ascending: false)
          .limit(10));

  /// Every live pin, for the admin console's Pins tab: the same query as
  /// the bar's, without the bar's limit and never filtered by what this
  /// device has closed, so an admin can always find a pin to unpin it.
  static Future<List<Map<String, dynamic>>> allForAdmin() async {
    if (debugAdminLoad != null) return debugAdminLoad!();
    return List<Map<String, dynamic>>.from(await Supabase.instance.client
        .from('posts_public')
        .select('*')
        .eq('is_pinned', true)
        .order('pinned_until', ascending: false)
        .limit(100));
  }

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

  /// Brings every closed pin back on this device.
  static Future<void> restore() async {
    if (_dismissed.isEmpty) return;
    _dismissed = {};
    _publish();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedKey);
  }

  static void _publish() {
    final live = [for (final p in _all) if (showInHomeFeed(p)) p];
    final shown = [
      for (final p in live)
        if (p['pin_mandatory'] == true || !_dismissed.contains('${p['id']}')) p,
    ];
    closedCount.value = live.length - shown.length;
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
    closedCount.value = 0;
    debugLoad = null;
    debugAdminLoad = null;
  }
}
