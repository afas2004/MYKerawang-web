import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/social_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/privacy_policy_screen.dart';
import 'package:mykerawang/services/account_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke tests for screens that don't need a live Supabase client.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<LanguageCubit> pumpPolicy(WidgetTester tester) async {
    final cubit = LanguageCubit();
    await tester.pumpWidget(BlocProvider.value(
      value: cubit,
      child: const MaterialApp(home: PrivacyPolicyScreen()),
    ));
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('privacy policy renders in English', (tester) async {
    await pumpPolicy(tester);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('What we store'), findsOneWidget);
    expect(find.text('Who we are'), findsOneWidget);
  });

  testWidgets('privacy policy follows the language setting', (tester) async {
    final cubit = await pumpPolicy(tester);
    cubit.changeLanguage(AppLanguage.ms);
    await tester.pumpAndSettle();
    expect(find.text('Dasar privasi'), findsOneWidget);
    expect(find.text('Apa yang kami simpan'), findsOneWidget);
  });

  test('Japanese is no longer offered and falls back to English', () async {
    expect(kSupportedLanguages, isNot(contains(AppLanguage.ja)));
    expect(AppStrings.ja.social, same(SocialStrings.en));

    SharedPreferences.setMockInitialValues({'appLanguage': 'ja'});
    final cubit = LanguageCubit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.language, AppLanguage.en);
  });

  test('delete confirmation needs the exact username', () {
    expect(AccountData.confirms('ali_99', 'ali_99'), isTrue);
    expect(AccountData.confirms(' @Ali_99 ', 'ali_99'), isTrue);
    expect(AccountData.confirms('ali', 'ali_99'), isFalse);
    expect(AccountData.confirms('', 'ali_99'), isFalse);
    expect(AccountData.confirms('x', null), isFalse);
  });
}
