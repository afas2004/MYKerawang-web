import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database_helper.dart';
import '../utils/listing_status.dart';

enum MarketSort { newest, cheapest, priciest }

/// What the market list is showing. Everything here is applied by the
/// database, so the app only ever downloads one page at a time.
class MarketFilters {
  /// null = every category.
  final String? category;
  final double? minPrice;
  final double? maxPrice;
  final Set<ListingStatus> statuses;
  final MarketSort sort;

  /// Sold listings are history; they're hidden until asked for.
  static const defaultStatuses = {ListingStatus.available, ListingStatus.reserved};

  const MarketFilters({
    this.category,
    this.minPrice,
    this.maxPrice,
    this.statuses = defaultStatuses,
    this.sort = MarketSort.newest,
  });

  MarketFilters copyWith({
    String? Function()? category,
    double? Function()? minPrice,
    double? Function()? maxPrice,
    Set<ListingStatus>? statuses,
    MarketSort? sort,
  }) {
    return MarketFilters(
      category: category != null ? category() : this.category,
      minPrice: minPrice != null ? minPrice() : this.minPrice,
      maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
      statuses: statuses ?? this.statuses,
      sort: sort ?? this.sort,
    );
  }

  /// Filters set in the sheet beyond the defaults (the badge count).
  int get activeCount =>
      (category != null ? 1 : 0) +
      (minPrice != null || maxPrice != null ? 1 : 0) +
      (statuses.length != defaultStatuses.length ||
              !statuses.containsAll(defaultStatuses)
          ? 1
          : 0) +
      (sort != MarketSort.newest ? 1 : 0);

  bool get isDefault => activeCount == 0;
}

class MarketplaceState {
  final List<Map<String, dynamic>> items;
  final MarketFilters filters;
  final String searchQuery;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;

  /// Loading the next page failed; the footer offers a retry.
  final bool loadMoreFailed;

  const MarketplaceState({
    this.items = const [],
    this.filters = const MarketFilters(),
    this.searchQuery = '',
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.errorMessage,
    this.loadMoreFailed = false,
  });

  MarketplaceState copyWith({
    List<Map<String, dynamic>>? items,
    MarketFilters? filters,
    String? searchQuery,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool? loadMoreFailed,
  }) {
    return MarketplaceState(
      items: items ?? this.items,
      filters: filters ?? this.filters,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      loadMoreFailed: loadMoreFailed ?? false,
    );
  }
}

class MarketplaceCubit extends Cubit<MarketplaceState> {
  MarketplaceCubit() : super(const MarketplaceState()) {
    loadData();
  }

  static const pageSize = 24;

  final _supabase = Supabase.instance.client;
  Timer? _searchDebounce;

  /// Bumped on every fresh load so a slow, superseded response can't
  /// overwrite newer results.
  int _generation = 0;

  bool get _isUnfiltered => state.filters.isDefault && state.searchQuery.isEmpty;

  /// First page for the current filters (also pull-to-refresh / retry).
  Future<void> loadData() async {
    final gen = ++_generation;
    emit(state.copyWith(isLoading: state.items.isEmpty, hasMore: false));

    // Instant paint from the offline cache, for the default view only.
    if (_isUnfiltered && state.items.isEmpty) {
      final cached = await DatabaseHelper.instance.getCachedListings();
      final visible = cached
          .where((i) => MarketFilters.defaultStatuses.contains(ListingStatus.of(i)))
          .toList();
      if (gen == _generation && visible.isNotEmpty && !isClosed) {
        emit(state.copyWith(items: visible, isLoading: false));
      }
    }

    try {
      final page = await _fetch(offset: 0);
      if (gen != _generation || isClosed) return;
      if (_isUnfiltered) await DatabaseHelper.instance.cacheListings(page);
      emit(state.copyWith(
        items: page,
        isLoading: false,
        hasMore: page.length == pageSize,
      ));
    } catch (e) {
      debugPrint('Market load failed: $e');
      if (gen != _generation || isClosed) return;
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    final gen = _generation;
    emit(state.copyWith(isLoadingMore: true, hasMore: true));
    try {
      final page = await _fetch(offset: state.items.length);
      if (gen != _generation || isClosed) return;
      emit(state.copyWith(
        items: [...state.items, ...page],
        isLoadingMore: false,
        hasMore: page.length == pageSize,
      ));
    } catch (e) {
      debugPrint('Market load more failed: $e');
      if (gen != _generation || isClosed) return;
      emit(state.copyWith(isLoadingMore: false, hasMore: true, loadMoreFailed: true));
    }
  }

  Future<List<Map<String, dynamic>>> _fetch({required int offset}) async {
    final f = state.filters;
    var query = _supabase.from('listings').select();

    if (f.category != null) query = query.eq('category', f.category!);
    if (f.minPrice != null) query = query.gte('price', f.minPrice!);
    if (f.maxPrice != null) query = query.lte('price', f.maxPrice!);
    if (f.statuses.length < ListingStatus.values.length) {
      query = query.inFilter('status', [for (final st in f.statuses) st.dbValue]);
    }
    final q = state.searchQuery.trim();
    if (q.isNotEmpty) {
      // Escape LIKE wildcards so "50%" searches for the literal text.
      final escaped = q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      query = query.ilike('title', '%$escaped%');
    }

    final ordered = switch (f.sort) {
      MarketSort.newest => query.order('created_at', ascending: false),
      MarketSort.cheapest =>
        query.order('price', ascending: true).order('created_at', ascending: false),
      MarketSort.priciest =>
        query.order('price', ascending: false).order('created_at', ascending: false),
    };

    final rows = await ordered.range(offset, offset + pageSize - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  void applyFilters(MarketFilters filters) {
    emit(state.copyWith(filters: filters, items: const []));
    loadData();
  }

  /// Quick category chips above the grid.
  void updateCategory(String? category) =>
      applyFilters(state.filters.copyWith(category: () => category));

  void updateSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (isClosed || query == state.searchQuery) return;
      emit(state.copyWith(searchQuery: query, items: const []));
      loadData();
    });
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }
}
