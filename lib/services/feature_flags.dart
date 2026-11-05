import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The parts of the app the owner can switch off.
///
/// [key] is the name `set_feature_enabled()` takes; [policyKey] is the
/// key `access_policy()` returns.
enum AppFeature {
  announcements('announcements'),
  clubs('clubs'),
  studentFeatures('student_features');

  const AppFeature(this.key);
  final String key;
  String get policyKey => '${key}_enabled';
}

/// Owner on/off switches for whole areas of the app (announcements,
/// clubs, student-specific features).
///
/// Read once through `access_policy()` (granted to `anon`, so it works
/// signed out) and cached for the session. Fails OPEN: until the first
/// read lands, or if it fails, every feature counts as on, so a network
/// blip never hides a feature.
///
/// To rebuild when a switch changes:
/// ```dart
/// ValueListenableBuilder<FeatureFlagsState>(
///   valueListenable: FeatureFlags.listenable,
///   builder: (context, flags, _) => flags.clubsOn ? ... : ...,
/// )
/// ```
class FeatureFlags {
  FeatureFlags._();

  static final ValueNotifier<FeatureFlagsState> _state =
      ValueNotifier(const FeatureFlagsState());
  static bool _loaded = false;
  static Future<FeatureFlagsState>? _inFlight;

  /// Notifies whenever the switches change (a refresh, or the owner
  /// flipping one in this session).
  static ValueListenable<FeatureFlagsState> get listenable => _state;

  /// Last known switches.
  static FeatureFlagsState get current => _state.value;

  static bool get announcementsOn => _state.value.announcementsOn;
  static bool get clubsOn => _state.value.clubsOn;
  static bool get studentFeaturesOn => _state.value.studentFeaturesOn;

  static bool isOn(AppFeature f) => _state.value.isOn(f);

  /// Tests: set the switches without a database.
  @visibleForTesting
  static void debugSet(FeatureFlagsState s) => _state.value = s;

  /// Reads the switches again. Never throws; on error the last known
  /// (or all-on) state stays.
  static Future<FeatureFlagsState> refresh() =>
      _inFlight ??= _read().whenComplete(() => _inFlight = null);

  /// Reads once per session; later calls return the cached state.
  static Future<FeatureFlagsState> ensureLoaded() async =>
      _loaded ? _state.value : refresh();

  /// Forgets the cache; the next [ensureLoaded] reads again.
  static void invalidate() => _loaded = false;

  /// Owner only (the database raises MOD:not_owner for anyone else).
  /// Updates the local state on success so open screens rebuild.
  static Future<void> setEnabled(AppFeature f, bool enabled) async {
    await Supabase.instance.client.rpc('set_feature_enabled',
        params: {'p_feature': f.key, 'p_enabled': enabled});
    _state.value = _state.value.copyWith(f, enabled);
  }

  static Future<FeatureFlagsState> _read() async {
    try {
      final p = await Supabase.instance.client.rpc('access_policy') as Map;
      _state.value = FeatureFlagsState.fromPolicy(p);
      _loaded = true;
    } catch (e) {
      debugPrint('FeatureFlags: read failed, keeping last state: $e');
    }
    return _state.value;
  }
}

/// A snapshot of the switches. Missing keys count as on.
@immutable
class FeatureFlagsState {
  final bool announcementsOn;
  final bool clubsOn;
  final bool studentFeaturesOn;

  const FeatureFlagsState({
    this.announcementsOn = true,
    this.clubsOn = true,
    this.studentFeaturesOn = true,
  });

  factory FeatureFlagsState.fromPolicy(Map policy) {
    bool on(AppFeature f) => policy[f.policyKey] != false;
    return FeatureFlagsState(
      announcementsOn: on(AppFeature.announcements),
      clubsOn: on(AppFeature.clubs),
      studentFeaturesOn: on(AppFeature.studentFeatures),
    );
  }

  bool isOn(AppFeature f) => switch (f) {
        AppFeature.announcements => announcementsOn,
        AppFeature.clubs => clubsOn,
        AppFeature.studentFeatures => studentFeaturesOn,
      };

  FeatureFlagsState copyWith(AppFeature f, bool on) => FeatureFlagsState(
        announcementsOn: f == AppFeature.announcements ? on : announcementsOn,
        clubsOn: f == AppFeature.clubs ? on : clubsOn,
        studentFeaturesOn:
            f == AppFeature.studentFeatures ? on : studentFeaturesOn,
      );

  @override
  bool operator ==(Object other) =>
      other is FeatureFlagsState &&
      other.announcementsOn == announcementsOn &&
      other.clubsOn == clubsOn &&
      other.studentFeaturesOn == studentFeaturesOn;

  @override
  int get hashCode => Object.hash(announcementsOn, clubsOn, studentFeaturesOn);
}
