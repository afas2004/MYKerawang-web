import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/events_screen.dart';
import 'package:mykerawang/screens/login_screen.dart';
import 'package:mykerawang/screens/marketplace_screen.dart';
import 'package:mykerawang/l10n/access_strings.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Redesigned cards and pages render without overflow at phone (375),
/// tablet (768) and desktop (1280) widths.
const widths = [375.0, 768.0, 1280.0];

Future<void> pumpAt(WidgetTester tester, double width, Widget child,
    {double height = 900, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, height), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Column width the events list gives one card at a screen width.
double eventColumnWidth(double width) {
  if (width >= 1000) return (width - 32 - 32) / 3;
  if (width >= 600) return (width - 32 - 16) / 2;
  return width - 32;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final soon = DateTime.now().add(const Duration(days: 2));
  final event = {
    'id': 'e1',
    'title': 'Malam Kebudayaan Kolej Kerawang: persembahan, gerai makanan dan pertandingan',
    'location': 'Dewan Besar, Kolej Kerawang, UiTM Shah Alam (sebelah surau)',
    'start_datetime': soon.toUtc().toIso8601String(),
    'end_datetime': soon.add(const Duration(hours: 3)).toUtc().toIso8601String(),
    'image_url': null,
    'tags': ['Arts'],
  };
  final organiser = {
    'id': 'u1',
    'display_name': 'Kelab Kebudayaan dan Kesenian Melayu UiTM',
    'role': 'club',
    'is_verified': true,
  };

  for (final width in widths) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('EventCard fits at ${width.toInt()}px, text x$scale', (tester) async {
        final columnWidth = eventColumnWidth(width);
        final inGrid = width >= 600;
        await pumpAt(
          tester,
          width,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: columnWidth,
              height: inGrid ? EventCard.gridExtent : null,
              child: EventCard(event: event, goingCount: 42, organiser: organiser),
            ),
          ),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Malam Kebudayaan'), findsOneWidget);
        expect(find.text('42 going'), findsOneWidget);
        expect(find.byIcon(Icons.verified), findsOneWidget);
      });
    }
  }

  testWidgets('cancelled event shows the CANCELLED badge, no countdown', (tester) async {
    await pumpAt(
      tester,
      375,
      SingleChildScrollView(
        child: EventCard(event: {...event, 'cancelled_at': '2026-10-19T00:00:00Z'}),
      ),
    );
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.byType(CountdownChip), findsNothing);
  });

  // ---- market card ----
  /// Width the market grid gives one tile at a screen width (side panel
  /// from 900).
  double marketTileWidth(double width) {
    final grid = (width >= 900 ? width - 281 : width) - 32;
    final cols = marketColumns(grid + 32);
    return (grid - 12 * (cols - 1)) / cols;
  }

  final listing = {
    'id': 'l1',
    'title': 'Kalkulator saintifik Casio fx-570EX hampir baru, lengkap dengan kotak dan manual',
    'price': 12345.5,
    'status': 'reserved',
    'image_url': null,
  };

  for (final width in widths) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('MarketCard fits at ${width.toInt()}px, text x$scale', (tester) async {
        final w = marketTileWidth(width);
        await pumpAt(
          tester,
          width,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: w,
              height: w / MarketCard.aspectRatio,
              child: MarketCard(item: listing),
            ),
          ),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('RESERVED'), findsOneWidget);
        expect(find.textContaining('12345.50'), findsOneWidget);
      });
    }
  }

  test('market columns step 2 / 3 / 4 / 5', () {
    expect(marketColumns(375), 2);
    expect(marketColumns(768), 3);
    expect(marketColumns(1000), 4);
    expect(marketColumns(1400), 5);
  });

  // ---- login ----
  for (final width in widths) {
    testWidgets('Login fits at ${width.toInt()}px', (tester) async {
      await pumpAt(tester, width, const LoginScreen(), height: 800);
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.en.welcomeBack), findsOneWidget);
      // Value proposition is always there: brand panel (wide) or under
      // the form (compact).
      expect(find.text(AppStrings.en.loginValueTitle), findsOneWidget);
    });
  }

  testWidgets('sign-up rejects a non-student email inline', (tester) async {
    await pumpAt(tester, 375, const LoginScreen(), height: 1400);
    await tester.tap(find.textContaining(AppStrings.en.createAccount, findRichText: true));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'someone@gmail.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    // Enter in the password field submits.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text(AppStrings.en.studentEmailOnly), findsOneWidget);
  });

  testWidgets('empty login shows field errors, not a request', (tester) async {
    await pumpAt(tester, 1280, const LoginScreen(), height: 900);
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.en.login));
    await tester.pump();
    expect(find.text(AppStrings.en.fillAllFields), findsNWidgets(2));
  });
}
