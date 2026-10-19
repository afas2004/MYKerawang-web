import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 1. The State
class ProfileState {
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> listings; // Items you sell
  final List<Map<String, dynamic>> events;   // Events you organized
  final bool isLoading;
  final String? errorMessage;

  ProfileState({
    this.profile,
    this.listings = const [],
    this.events = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  ProfileState copyWith({
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>>? listings,
    List<Map<String, dynamic>>? events,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      listings: listings ?? this.listings,
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

// 2. The Cubit
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit() : super(ProfileState()) {
    loadProfile();
    // Created once at app start, so follow the session: load on sign-in
    // (no reload needed), clear on sign-out, swap on account switch.
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final uid = data.session?.user.id;
      if (uid == null) {
        _loadedFor = null;
        emit(ProfileState(isLoading: false));
      } else if (uid != _loadedFor ||
          data.event == AuthChangeEvent.userUpdated) {
        loadProfile();
      }
    });
  }

  final _supabase = Supabase.instance.client;
  late final StreamSubscription<AuthState> _authSub;

  /// User whose data is in [state]; guards against a slow load for the
  /// previous account landing after a switch.
  String? _loadedFor;

  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }

  Future<void> loadProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        emit(ProfileState(isLoading: false));
        return;
      }

      if (state.profile == null || _loadedFor != user.id) {
        // Never show the previous account's data while loading.
        emit(ProfileState(isLoading: true));
      }
      _loadedFor = user.id;

      // 1. Fetch Profile
      final profileData = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      // 2. Fetch Listings
      final listingsData = await _supabase
          .from('listings')
          .select()
          .eq('seller_id', user.id);

      // 3. Fetch Events (Check if your column is 'organizer_id' or 'created_by')
      final eventsData = await _supabase
          .from('events')
          .select()
          .eq('organizer_id', user.id); 

      // Signed out or switched while we were fetching.
      if (_supabase.auth.currentUser?.id != user.id) return;

      emit(state.copyWith(
          isLoading: false, // Done!
          profile: profileData,
          listings: listingsData,
          events: eventsData,
        ));
      } catch (e) {
        emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      }
  }

  Future<void> uploadAvatar(XFile imageFile) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      emit(state.copyWith(isLoading: true));
      final fileExt = imageFile.name.split('.').last;
      final fileName = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final bytes = await imageFile.readAsBytes();
      await _supabase.storage.from('avatars').uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));
      final imageUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      await _supabase.from('profiles').update({'avatar_url': imageUrl}).eq('id', user.id);
      await loadProfile();
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: "Upload failed: $e"));
    }
  }
}