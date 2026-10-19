import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database_helper.dart'; // Import your DB Helper

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
  final _supabase = Supabase.instance.client;

  Future<void> loadData() async {
   
    emit(state.copyWith(isLoading: true));

    final cachedData = await DatabaseHelper.instance.getCachedEvents();

    if (cachedData.isNotEmpty) {
      final filtered = _applyFilters(cachedData, state.selectedTag, state.searchQuery);
      emit(state.copyWith(
        allEvents: cachedData,
        displayedEvents: filtered,
        isLoading: false, // UI appears instantly
      ));
    }

    // 3. SLOW: Subscribe to Supabase (Background Download)
    // Ended events are kept and greyed out in the UI, not hidden.
    _subscription?.cancel(); // drop the previous stream before resubscribing
    _subscription = _supabase
        .from('events')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(200) // newest 200 — not the whole table over mobile data
        .listen((data) async {
          final items = List<Map<String, dynamic>>.from(data);
          
          // 4. Update SQLite so next time is fast too
          await DatabaseHelper.instance.cacheEvents(items);

          // 5. Update UI with fresh data
          final filtered = _applyFilters(items, state.selectedTag, state.searchQuery);
          
          if (!isClosed) {
            emit(state.copyWith(
              allEvents: items,
              displayedEvents: filtered,
              isLoading: false,
            ));
            _loadCardExtras(items);
          }
        }, onError: (error) {
          // Must clear isLoading, otherwise the screen spins forever when
          // offline (UI_UX_AUDIT 15.5).
          if (!isClosed) {
            emit(state.copyWith(
                isLoading: false, errorMessage: error.toString()));
          }
        });
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
      final eventTags = List<String>.from(e['tags'] ?? []);

      final matchesSearch = title.contains(search);
      final matchesTag = tag == 'All' || eventTags.contains(tag);

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