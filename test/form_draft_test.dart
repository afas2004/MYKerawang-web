import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/access_strings.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/create_listing_screen.dart';
import 'package:mykerawang/utils/form_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Create forms autosave their text so a reload (Android discarding the
/// tab while the camera is open, or the GPU-context recovery reload in
/// web/index.html) doesn't lose it.
void main() {
  setUp(() => FormDraft.delay = Duration.zero);

  test('save, load and clear', () async {
    SharedPreferences.setMockInitialValues({});
    final draft = FormDraft('t');
    draft.save({'title': 'Kettle', 'price': '15'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect((await FormDraft('t').load())?['title'], 'Kettle');

    await draft.clear();
    expect(await FormDraft('t').load(), isNull);
  });

  test('an empty form stores nothing', () async {
    SharedPreferences.setMockInitialValues({});
    FormDraft('t').save({'title': '  ', 'tags': <String>[]});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('draft.t'), isNull);
  });

  testWidgets('Sell item restores an autosaved draft', (tester) async {
    SharedPreferences.setMockInitialValues({
      'draft.create_listing': jsonEncode({
        'title': 'Rice cooker',
        'price': '30',
        'description': 'Barely used',
        'category': 'Electronics',
      }),
    });
    await tester.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: const MaterialApp(home: CreateListingScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rice cooker'), findsOneWidget);
    expect(find.text('Barely used'), findsOneWidget);
    expect(find.text(AppStrings.en.draftRestored), findsOneWidget);
  });
}
