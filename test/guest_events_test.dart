import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/announcements/hub_strings.dart';
import 'package:mykerawang/screens/events_cubit.dart';
import 'package:mykerawang/screens/events_screen.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/widgets/profile_avatar_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guests read events once and never hold a realtime connection; the
/// Events app bar shows Sign in (no bell) to guests.
void main() {
  final soon = DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String();
  final rows = [
    {'id': 'e1', 'title': 'Futsal night', 'start_datetime': soon, 'tags': <String>[]},
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EventsCubit.debugStreamOpened = false;
    EventsCubit.debugFetchOnce = () async => rows;
    EventsCubit.debugStream = () => Stream.value(rows);
  });
  tearDown(() {
    ShellAuth.debugLoggedIn = null;
    EventsCubit.debugFetchOnce = null;
    EventsCubit.debugStream = null;
  });

  test('guest: one-shot read, no realtime stream', () async {
    ShellAuth.debugLoggedIn = false;
    final cubit = EventsCubit();
    await cubit.stream.firstWhere((s) => s.allEvents.isNotEmpty);
    expect(cubit.state.allEvents.single['title'], 'Futsal night');
    expect(EventsCubit.debugStreamOpened, isFalse);
    await cubit.close();
  });

  test('signed in: live stream', () async {
    ShellAuth.debugLoggedIn = true;
    final cubit = EventsCubit();
    await cubit.stream.firstWhere((s) => s.allEvents.isNotEmpty);
    expect(EventsCubit.debugStreamOpened, isTrue);
    await cubit.close();
  });

  testWidgets('guest app bar: Sign in, no notifications bell', (tester) async {
    ShellAuth.debugLoggedIn = false;
    await tester.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: const MaterialApp(home: EventsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.en.hub.signIn), findsOneWidget);
    expect(find.byIcon(AppIcons.notifications), findsNothing);
    expect(find.text('Futsal night'), findsOneWidget);
  });
}
