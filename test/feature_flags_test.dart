import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/feature_flags.dart';

void main() {
  group('FeatureFlagsState', () {
    test('defaults to everything on (fail open)', () {
      const s = FeatureFlagsState();
      expect(s.announcementsOn && s.clubsOn && s.studentFeaturesOn, isTrue);
    });

    test('reads access_policy() keys; missing or odd values count as on', () {
      final s = FeatureFlagsState.fromPolicy({
        'announcements_enabled': false,
        'clubs_enabled': null,
        'registration_mode': 'open',
      });
      expect(s.announcementsOn, isFalse);
      expect(s.clubsOn, isTrue);
      expect(s.studentFeaturesOn, isTrue);
    });

    test('copyWith changes only the named feature', () {
      final s = const FeatureFlagsState().copyWith(AppFeature.clubs, false);
      expect(s.isOn(AppFeature.clubs), isFalse);
      expect(s.isOn(AppFeature.announcements), isTrue);
      expect(s.isOn(AppFeature.studentFeatures), isTrue);
    });

    test('feature keys match set_feature_enabled() and access_policy()', () {
      expect(AppFeature.values.map((f) => f.key),
          ['announcements', 'clubs', 'student_features']);
      expect(AppFeature.studentFeatures.policyKey, 'student_features_enabled');
    });
  });
}
