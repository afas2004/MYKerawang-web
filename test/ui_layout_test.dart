import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/events_screen.dart';
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
}
