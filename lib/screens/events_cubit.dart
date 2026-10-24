import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database_helper.dart';
import '../utils/guest_access.dart';
import '../widgets/profile_avatar_action.dart' show ShellAuth;

class EventsState {
  final List<Map<String, dynamic>> allEvents;
  final List<Map<String, dynamic>> displayedEvents;
  final String selectedTag;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;

  /// Going count per event id (public `event_participant_counts` view).
  final Map<String, int> goingCounts;

  /// Organiser public profile per user id (`profiles_public`).
  final Map<String, Map<String, dynamic>> organisers;

  EventsState({
    this.goingCounts = const {},
    this.organisers = const {},
    this.allEvents = const [],
    this.displayedEvents = const [],
    this.selectedTag = 'All',
    this.searchQuery = '',
    this.isLoading = true,
    this.errorMessage,
  });

  EventsState copyWith({
    List<Map<String, dynamic>>? allEvents,
    List<Map<String, dynamic>>? displayedEvents,
    String? selectedTag,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    Map<String, int>? goingCounts,
    Map<String, Map<String, dynamic>>? organisers,
  }) {
    return EventsState(
      goingCounts: goingCounts ?? this.goingCounts,
      organisers: organisers ?? this.organisers,
      allEvents: allEvents ?? this.allEvents,
      displayedEvents: displayedEvents ?? this.displayedEvents,
      selectedTag: selectedTag ?? this.selectedTag,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Has this event finished? Ended events stay visible (greyed out) —
/// history is content (DESIGN_SPEC §6).
bool isEventEnded(Map<String, dynamic> event) {
  final raw = event['end_datetime'] ?? event['start_datetime'];
  final end = DateTime.tryParse(raw ?? '');
  if (end == null) return false;
  return end.toUtc().isBefore(DateTime.now().toUtc());
}

/// Cancelled by the organiser (events.cancelled_at, see
/// 20261019002200_event_soft_cancel.sql).
bool isEventCancelled(Map<String, dynamic> event) => event['cancelled_at'] != null;

/// Ended or cancelled: either way it's history, greyed and sorted last.
bool isEventClosed(Map<String, dynamic> event) =>
    isEventEnded(event) || isEventCancelled(event);

class EventsCubit extends Cubit<EventsState> {
  EventsCubit() : super(EventsState()) {
    loadData();
  }

  StreamSubscription? _subscription;

  // Looked up on use, so tests can build the cubit without Supabase.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Tests: replace the network with canned rows. [debugFetchOnce] stands
  /// in for the guest one-shot query, [debugStream] for the realtime
  /// stream; [debugStreamOpened] records whether a stream was opened.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? debugFetchOnce;
  @visibleForTesting
  static Stream<List<Map<String, dynamic>>> Function()? debugStream;
  @visibleForTesting
  static bool debugStreamOpened = false;

  /// Signed in? Guests get a one-shot read: they must not hold a realtime
  /// connection open.
  static bool get _signedIn {
    // Same test switch the shell chrome uses.
    // ignore: invalid_use_of_visible_for_testing_member
    final forced = ShellAuth.debugLoggedIn;
    if (forced != null) return forced;
    try {
      return isLoggedIn;
    } catch (_) {
      return false; // Supabase not initialised
    }
  }

  Future<void> loadData() async {
    emit(state.copyWith(isLoading: true));

    // 1. FAST: the offline cache (best-effort).
    try {
      final cachedData = await DatabaseHelper.instance.getCachedEvents();
      if (cachedData.isNotEmpty && !isClosed) {
        final filtered = _applyFilters(cachedData, state.selectedTag, state.searchQuery);
        emit(state.copyWith(
          allEvents: cachedData,
          displayedEvents: filtered,
          isLoading: false, // UI appears instantly
        ));
      }
    } catch (e) {
      debugPrint('Event cache unavailable: $e');
    }

    _subscription?.cancel(); // drop the previous stream before resubscribing
    _subscription = null;

    // 2a. GUEST: one read, no realtime connection.
    if (!_signedIn) {
      try {
        final rows = await (debugFetchOnce?.call() ??
            _supabase
                .from('events')
                .select()
                .order('created_at', ascending: false)
                .limit(200)
                .then((r) => List<Map<String, dynamic>>.from(r)));
        await _onRows(rows);
      } catch (e) {
        _onError(e);
      }
      return;
    }

    // 2b. SIGNED IN: live updates. Ended events are kept and greyed out in
    // the UI, not hidden.
    debugStreamOpened = true;
    final stream = debugStream?.call() ??
        _supabase
            .from('events')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false)
            .limit(200); // newest 200 — not the whole table over mobile data
    _subscription = stream.listen(
      (data) => _onRows(List<Map<String, dynamic>>.from(data)),
      onError: _onError,
    );
  }

  Future<void> _onRows(List<Map<String, dynamic>> items) async {
    // Update the cache so next time is fast too (best-effort).
    try {
      await DatabaseHelper.instance.cacheEvents(items);
    } catch (_) {}
    if (isClosed) return;
    emit(state.copyWith(
      allEvents: items,
      displayedEvents: _applyFilters(items, state.selectedTag, state.searchQuery),
      isLoading: false,
    ));
    _loadCardExtras(items);
  }

  void _onError(Object error) {
    // Must clear isLoading, otherwise the screen spins forever when
    // offline (UI_UX_AUDIT 15.5).
    if (!isClosed) {
      emit(state.copyWith(isLoading: false, errorMessage: error.toString()));
    }
  }

  /// Going counts and organiser names for the cards. Best-effort: on
  /// failure the cards simply leave those lines out.
  Future<void> _loadCardExtras(List<Map<String, dynamic>> events) async {
    final ids = [for (final e in events) e['id'] as String];
    final organiserIds = {
      for (final e in events)
        if (e['organizer_id'] != null) e['organizer_id'] as String
    }.toList();
    if (ids.isEmpty) return;
    try {
      final results = await Future.wait([
        _supabase
            .from('event_participant_counts')
            .select('event_id, participant_count')
            .inFilter('event_id', ids),
        _supabase
            .from('profiles_public')
            .select('id, username, display_name, avatar_url, role, is_verified')
            .inFilter('id', organiserIds),
      ]);
      if (isClosed) return;
      emit(state.copyWith(
        goingCounts: {
          for (final r in results[0])
            r['event_id'] as String: (r['participant_count'] as num).toInt()
        },
        organisers: {for (final p in results[1]) p['id'] as String: p},
      ));
    } catch (e) {
      debugPrint('Event card extras failed: $e');
    }
  }

  void updateTag(String tag) {
    final filtered = _applyFilters(state.allEvents, tag, state.searchQuery);
    emit(state.copyWith(selectedTag: tag, displayedEvents: filtered));
  }

  void updateSearch(String query) {
    final filtered = _applyFilters(state.allEvents, state.selectedTag, query);
    emit(state.copyWith(searchQuery: query, displayedEvents: filtered));
  }

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> items, String tag, String query) {
    final filtered = items.where((e) {
      final title = (e['title'] as String).toLowerCase();
      final search = query.toLowerCase();
      // New rows carry category slugs; older ones carry free-text tags.
      final eventCats = [
        ...List<String>.from(e['categories'] ?? const []),
        ...List<String>.from(e['tags'] ?? const []),
      ].map((t) => t.toLowerCase()).toList();

      final matchesSearch = title.contains(search);
      final matchesTag = tag == 'All' || eventCats.contains(tag);

      return matchesSearch && matchesTag;
    }).toList();

    // Upcoming first (soonest first), then ended or cancelled (most
    // recent first).
    DateTime start(Map<String, dynamic> e) =>
        DateTime.tryParse(e['start_datetime'] ?? '') ?? DateTime(1970);

    filtered.sort((a, b) {
      final aEnded = isEventClosed(a);
      final bEnded = isEventClosed(b);
      if (aEnded != bEnded) return aEnded ? 1 : -1;
      return aEnded
          ? start(b).compareTo(start(a))
          : start(a).compareTo(start(b));
    });

    return filtered;
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}