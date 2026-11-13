import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The reader's notification settings (one notification_settings row; the
/// defaults below match notif_default_level() in the database when there is
/// no row yet).
class NotificationPrefs {
  final Map<String, String> levels;
  final bool quietEnabled;
  final TimeOfDay quietStart;
  final TimeOfDay quietEnd;

  const NotificationPrefs({
    this.levels = const {},
    this.quietEnabled = true,
    this.quietStart = const TimeOfDay(hour: 23, minute: 0),
    this.quietEnd = const TimeOfDay(hour: 7, minute: 0),
  });

  static const defaults = {
    'reminders': 'push',
    'event_changes': 'push',
    'comments': 'push',
    'mentions': 'push',
    'form_answers': 'push',
    'event_joins': 'bell',
    'follows': 'bell',
    'new_events': 'off',
  };

  String level(String category) {
    final v = levels[category] ?? defaults[category] ?? 'push';
    return category == 'follows' && v == 'push' ? 'bell' : v;
  }

  NotificationPrefs withLevel(String category, String value) =>
      copyWith(levels: {...levels, category: value});

  NotificationPrefs copyWith({
    Map<String, String>? levels,
    bool? quietEnabled,
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) =>
      NotificationPrefs(
        levels: levels ?? this.levels,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );

  static SupabaseClient get _db => Supabase.instance.client;

  static TimeOfDay _time(dynamic raw, TimeOfDay fallback) {
    final parts = '${raw ?? ''}'.split(':');
    final h = int.tryParse(parts.first), m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    return h == null ? fallback : TimeOfDay(hour: h, minute: m ?? 0);
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static Future<NotificationPrefs> load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const NotificationPrefs();
    try {
      final row = await _db
          .from('notification_settings')
          .select('prefs, quiet_enabled, quiet_start, quiet_end')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return const NotificationPrefs();
      const d = NotificationPrefs();
      return NotificationPrefs(
        levels: Map<String, String>.from(
            (row['prefs'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'))),
        quietEnabled: row['quiet_enabled'] != false,
        quietStart: _time(row['quiet_start'], d.quietStart),
        quietEnd: _time(row['quiet_end'], d.quietEnd),
      );
    } catch (e) {
      debugPrint('Notification settings load failed: $e');
      return const NotificationPrefs();
    }
  }

  Future<void> save() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('notification_settings').upsert({
      'user_id': uid,
      'prefs': levels,
      'quiet_enabled': quietEnabled,
      'quiet_start': _hhmm(quietStart),
      'quiet_end': _hhmm(quietEnd),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// The push sender writes in this language. Called when the person picks
  /// a language and when they sign in.
  static Future<void> saveLanguage(String code) async {
    try {
      // Throws when Supabase isn't started (widget tests): nothing to save.
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      await _db.from('notification_settings').upsert({
        'user_id': uid,
        'language': code,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Saving notification language failed: $e');
    }
  }
}
