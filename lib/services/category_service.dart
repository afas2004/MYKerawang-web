import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../utils/categories.dart';

/// One row of `content_categories`.
///
/// Slugs are what content stores; [label] is what people read. The Malay
/// name is optional — most rows have one, and it falls back to English.
class ContentCategory {
  final String id;
  final String kind;
  final String slug;
  final String nameEn;
  final String? nameMs;
  final int sort;
  final bool active;

  const ContentCategory({
    required this.id,
    required this.kind,
    required this.slug,
    required this.nameEn,
    this.nameMs,
    this.sort = 0,
    this.active = true,
  });

  String label(AppStrings s) {
    final ms = nameMs?.trim();
    if (identical(s, AppStrings.ms) && ms != null && ms.isNotEmpty) return ms;
    return nameEn;
  }

  static ContentCategory fromRow(Map<String, dynamic> r) => ContentCategory(
        id: '${r['id']}',
        kind: '${r['kind']}',
        slug: '${r['slug']}',
        nameEn: '${r['name_en']}',
        nameMs: r['name_ms'] as String?,
        sort: (r['sort'] as num?)?.toInt() ?? 0,
        active: r['active'] == true,
      );
}

/// Reads the category table, caches it, and falls back to the bundled
/// seeds when the table cannot be read (offline, tests, first paint).
///
/// Screens that need a label synchronously use [cached] — it returns the
/// last loaded list, or the seeds, both of which carry the same slugs.
class CategoryService {
  static final Map<String, List<ContentCategory>> _cache = {};
  static final Map<String, Future<List<ContentCategory>>> _inflight = {};

  static List<ContentCategory> cached(String kind) =>
      _cache[kind] ?? _fallback(kind);

  /// Human label for [slug]; the slug itself if the table no longer has it
  /// (a deactivated category on an old post still renders something).
  static String labelOf(String kind, String slug, AppStrings s) {
    for (final c in cached(kind)) {
      if (c.slug == slug) return c.label(s);
    }
    return slug;
  }

  /// A row's category slugs: the `categories` array, or the single old
  /// `category` column on rows written before it existed.
  static List<String> slugsOf(Map<String, dynamic> row) {
    final cats = row['categories'];
    if (cats is List && cats.isNotEmpty) {
      return [for (final c in cats) '$c'.trim()].where((c) => c.isNotEmpty).toList();
    }
    final one = '${row['category'] ?? ''}'.trim();
    return one.isEmpty ? const [] : [one];
  }

  /// [slugsOf] as names, joined for a detail row; null when it has none.
  static String? labelsFor(String kind, Map<String, dynamic> row, AppStrings s) {
    final slugs = slugsOf(row);
    if (slugs.isEmpty) return null;
    return [for (final slug in slugs) labelOf(kind, slug, s)].join(', ');
  }

  /// Best-effort warm-up at start-up, so filters can render labels
  /// synchronously. Never throws.
  static Future<void> warm() async {
    await Future.wait([forKind('event'), forKind('listing')]);
  }

  static Future<List<ContentCategory>> forKind(String kind) {
    final hit = _cache[kind];
    if (hit != null) return Future.value(hit);
    return _inflight[kind] ??= _load(kind).then((v) {
      _cache[kind] = v;
      _inflight.remove(kind);
      return v;
    }).catchError((_) {
      _inflight.remove(kind);
      return _fallback(kind);
    });
  }

  /// Admin listing: includes inactive rows. Throws on a failed read so the
  /// console can say so instead of silently showing seeds it cannot edit.
  static Future<List<ContentCategory>> allForAdmin(String kind) async {
    final rows = await Supabase.instance.client
        .from('content_categories')
        .select()
        .eq('kind', kind)
        .order('sort', ascending: true)
        .order('name_en', ascending: true);
    return [
      for (final r in rows as List)
        ContentCategory.fromRow((r as Map).cast<String, dynamic>())
    ];
  }

  static Future<List<ContentCategory>> _load(String kind) async {
    try {
      final rows = await Supabase.instance.client
          .from('content_categories')
          .select()
          .eq('kind', kind)
          .eq('active', true)
          .order('sort', ascending: true)
          .order('name_en', ascending: true);
      final list = [
        for (final r in rows as List)
          ContentCategory.fromRow((r as Map).cast<String, dynamic>())
      ];
      return list.isEmpty ? _fallback(kind) : list;
    } catch (_) {
      return _fallback(kind);
    }
  }

  static List<ContentCategory> _fallback(String kind) {
    final seeds = kind == 'event' ? kEventCategorySeeds : kListingCategorySeeds;
    return [
      for (var i = 0; i < seeds.length; i++)
        ContentCategory(
          id: 'seed:${seeds[i].slug}',
          kind: kind,
          slug: seeds[i].slug,
          nameEn: seeds[i].en,
          nameMs: seeds[i].ms,
          sort: i,
        ),
    ];
  }

  // ------------------------------------------------------------ admin
  static Future<void> save({
    String? id,
    required String kind,
    required String slug,
    required String nameEn,
    String? nameMs,
    int sort = 0,
    bool active = true,
  }) async {
    await Supabase.instance.client.rpc('admin_upsert_category', params: {
      'p_id': id,
      'p_kind': kind,
      'p_slug': slug,
      'p_name_en': nameEn,
      'p_name_ms': nameMs,
      'p_sort': sort,
      'p_active': active,
    });
    _cache.remove(kind);
    await forKind(kind);
  }

  static Future<void> delete(String id, String kind) async {
    await Supabase.instance.client
        .rpc('admin_delete_category', params: {'p_id': id});
    _cache.remove(kind);
    await forKind(kind);
  }

  static void invalidate() => _cache.clear();
}
