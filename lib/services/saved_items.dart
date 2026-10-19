import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a saved row points at. [name] is the stored `item_type`.
enum SavedType { post, listing, event }

/// The signed-in user's bookmarks (table `saved_items`).
///
/// Keeps the set of saved keys in memory so every [SaveButton] on screen
/// agrees and updates together. Loaded by SessionWatcher on sign-in,
/// cleared on sign-out.
class SavedItems {
  SavedItems._();
  static final instance = SavedItems._();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Test hook: widget tests run without a Supabase instance.
  static bool Function()? debugSignedIn;

  bool get signedIn =>
      debugSignedIn?.call() ?? _supabase.auth.currentUser != null;

  /// Keys are `"<type>:<id>"`; see [keyOf].
  final keys = ValueNotifier<Set<String>>({});
  String? _userId;

  static String keyOf(SavedType type, Object id) => '${type.name}:$id';

  bool isSaved(SavedType type, Object id) =>
      keys.value.contains(keyOf(type, id));

  Future<void> start(String userId) async {
    if (_userId == userId) return;
    _userId = userId;
    keys.value = {};
    await refresh();
  }

  void stop() {
    _userId = null;
    keys.value = {};
  }

  Future<void> refresh() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final rows = await _supabase
          .from('saved_items')
          .select('item_type, item_id')
          .eq('user_id', uid);
      if (_userId != uid) return;
      keys.value = {for (final r in rows) '${r['item_type']}:${r['item_id']}'};
    } catch (e) {
      debugPrint('Saved items load failed: $e');
    }
  }

  /// Saves or un-saves; returns the new state. Optimistic, rolled back
  /// (and rethrown) on failure so the caller can show an error.
  Future<bool> toggle(SavedType type, Object id) async {
    final uid = _userId ?? _supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('not signed in');
    _userId ??= uid;

    final key = keyOf(type, id);
    final wasSaved = keys.value.contains(key);
    keys.value = wasSaved
        ? ({...keys.value}..remove(key))
        : {...keys.value, key};
    try {
      if (wasSaved) {
        await _supabase.from('saved_items').delete().match({
          'user_id': uid,
          'item_type': type.name,
          'item_id': '$id',
        });
      } else {
        await _supabase.from('saved_items').upsert({
          'user_id': uid,
          'item_type': type.name,
          'item_id': '$id',
        }, onConflict: 'user_id,item_type,item_id', ignoreDuplicates: true);
      }
      return !wasSaved;
    } catch (_) {
      keys.value = wasSaved
          ? {...keys.value, key}
          : ({...keys.value}..remove(key));
      rethrow;
    }
  }

  /// Saved rows, newest first, with each target loaded. A target that
  /// was deleted or hidden comes back with `item: null`.
  Future<List<SavedEntry>> fetchAll() async {
    final uid = _userId ?? _supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _supabase
        .from('saved_items')
        .select('item_type, item_id, created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    List<String> idsOf(SavedType t) => [
          for (final r in rows)
            if (r['item_type'] == t.name) '${r['item_id']}'
        ];

    Future<Map<String, Map<String, dynamic>>> load(
        String table, List<String> ids) async {
      if (ids.isEmpty) return {};
      final found = await _supabase.from(table).select('*').inFilter('id', ids);
      return {for (final f in found) '${f['id']}': f};
    }

    // Posts come from the view so anonymous authors stay hidden.
    final results = await Future.wait([
      load('posts_public', idsOf(SavedType.post)),
      load('listings', idsOf(SavedType.listing)),
      load('events', idsOf(SavedType.event)),
    ]);
    final byType = {
      SavedType.post: results[0],
      SavedType.listing: results[1],
      SavedType.event: results[2],
    };

    keys.value = {for (final r in rows) '${r['item_type']}:${r['item_id']}'};
    return [
      for (final r in rows)
        if (SavedType.values.where((t) => t.name == r['item_type']).firstOrNull
            case final type?)
          SavedEntry(type, '${r['item_id']}', byType[type]!['${r['item_id']}']),
    ];
  }
}

class SavedEntry {
  final SavedType type;
  final String id;

  /// The target row, or null when it no longer exists / isn't visible.
  final Map<String, dynamic>? item;

  const SavedEntry(this.type, this.id, this.item);
}
