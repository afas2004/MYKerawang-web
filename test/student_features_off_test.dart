import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/access_strings.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/form_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/login_cubit.dart';
import 'package:mykerawang/screens/login_screen.dart';
import 'package:mykerawang/services/feature_flags.dart';
import 'package:mykerawang/services/registration_policy.dart';
import 'package:mykerawang/services/student_verification.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sets the owner switches without a database.
void setFlags(FeatureFlagsState s) =>
    (FeatureFlags.listenable as ValueNotifier<FeatureFlagsState>).value = s;

const studentOff = FeatureFlagsState(studentFeaturesOn: false);

Future<void> pumpLogin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BlocProvider(
    create: (_) => LanguageCubit(),
    child: const MaterialApp(home: Scaffold(body: LoginScreen())),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    setFlags(const FeatureFlagsState());
    RegistrationPolicy.invalidate();
    pendingLoginError.value = null;
  });

  group('student features off', () {
    test('signup no longer asks for a student email', () {
      // Registration still reads as student-only (unread = closed).
      expect(RegistrationPolicy.isOpen, isFalse);
      expect(RegistrationPolicy.studentEmailRequired, isTrue);
      setFlags(studentOff);
      expect(RegistrationPolicy.studentEmailRequired, isFalse);
    });

    test('verification reads as off without asking the database', () async {
      setFlags(studentOff);
      expect(await StudentVerificationService.isEnabled(), isFalse);
    });

    test('a new Google account with any email is not signed out', () async {
      setFlags(studentOff);
      final now = DateTime.now().toUtc().toIso8601String();
      final user = User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: now,
        lastSignInAt: now,
        email: 'someone@gmail.com',
      );
      // With the switch on this would reach signOut (no client here).
      await enforceStudentEmailForNewAccount(user);
      expect(pendingLoginError.value, isNull);
    });

    test('the student_id question reads as a plain ID number', () {
      expect(AppStrings.en.formKindLabel('student_id'), 'Matric number');
      setFlags(studentOff);
      expect(AppStrings.en.formKindLabel('student_id'), 'ID number');
      expect(AppStrings.en.galleryKind('student_id'), 'ID number');
    });

    testWidgets('login shows the any-email wording and accepts any address',
        (tester) async {
      setFlags(studentOff);
      await pumpLogin(tester);
      expect(find.text(AppStrings.en.anyEmailHint), findsOneWidget);
      expect(find.text(AppStrings.en.studentEmailHint), findsNothing);

      await tester.tap(
          find.textContaining(AppStrings.en.createAccount, findRichText: true));
      await tester.pump();
      expect(find.text(AppStrings.en.anyEmailHint), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'someone@gmail.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text(AppStrings.en.studentEmailOnly), findsNothing);
    });

    testWidgets('login wording follows the switch live', (tester) async {
      await pumpLogin(tester);
      expect(find.text(AppStrings.en.studentEmailHint), findsOneWidget);
      setFlags(studentOff);
      await tester.pump();
      expect(find.text(AppStrings.en.studentEmailHint), findsNothing);
      expect(find.text(AppStrings.en.anyEmailHint), findsOneWidget);
    });
  });
}
