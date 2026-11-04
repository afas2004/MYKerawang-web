import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/licenses_strings.dart';
import 'package:mykerawang/screens/licenses_screen.dart';

import 'helpers/feed_fixtures.dart';

/// Settings → Open-source credits: the artwork that must be credited comes
/// first, packages are grouped by licence rather than listed flat, and the
/// filter searches both.
void main() {
  final s = AppStrings.en;

  setUp(() {
    LicenseRegistry.reset();
    LicenseRegistry.addLicense(() async* {
      // Named entries, as services/art_credits.dart registers them.
      yield const LicenseEntryWithLineBreaks(
        ['Malaysian stitch illustrations (WP25 Malaysia)'],
        'Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).',
      );
      // pub packages: lowercase_with_underscores.
      yield const LicenseEntryWithLineBreaks(
        ['go_router'],
        'MIT License\n\nPermission is hereby granted, free of charge, to any person.',
      );
      yield const LicenseEntryWithLineBreaks(
        ['supabase_flutter'],
        'MIT License\n\nPermission is hereby granted, free of charge, to any person.',
      );
      yield const LicenseEntryWithLineBreaks(
        ['vector_math'],
        'Apache License, Version 2.0',
      );
      // The engine bundles C++ libraries whose names are neither pub-style
      // nor artwork. These belong with the packages, not in the credits.
      yield const LicenseEntryWithLineBreaks(
        ['abseil-cpp'],
        'Redistribution and use in source and binary forms are permitted.',
      );
    });
  });

  tearDown(LicenseRegistry.reset);

  testWidgets('artwork is credited first, packages are grouped by licence',
      (tester) async {
    await pumpAt(tester, kCompact, const LicensesScreen());
    await tester.pumpAndSettle();

    // The page says what it is, instead of opening with raw licence text.
    expect(find.text(s.licIntro), findsOneWidget);

    // The CC BY artwork is named, not buried among the packages.
    expect(find.text(s.licArt), findsOneWidget);
    expect(find.text('Malaysian stitch illustrations (WP25 Malaysia)'),
        findsOneWidget);
    expect(find.text('Creative Commons'), findsOneWidget);

    // Packages are behind licence groups, so the list is short to scan.
    expect(find.text('MIT'), findsOneWidget);
    expect(find.text('Apache 2.0'), findsOneWidget);
    expect(find.text(s.licItems(2)), findsOneWidget); // the two MIT packages
    expect(find.text('go_router'), findsNothing); // collapsed until opened

    // An engine library is a package, however its name is spelled: it must
    // not land in the artwork section, which is the attribution list.
    expect(find.text('BSD'), findsOneWidget);
    await tester.tap(find.text('BSD'));
    await tester.pumpAndSettle();
    expect(find.text('abseil-cpp'), findsOneWidget);
  });

  testWidgets('opening a licence group reveals its packages', (tester) async {
    await pumpAt(tester, kCompact, const LicensesScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('MIT'));
    await tester.pumpAndSettle();

    expect(find.text('go_router'), findsOneWidget);
    expect(find.text('supabase_flutter'), findsOneWidget);
    expect(find.text('vector_math'), findsNothing); // Apache group still shut
  });

  testWidgets('the filter searches packages and artwork, and expands hits',
      (tester) async {
    await pumpAt(tester, kCompact, const LicensesScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'supabase');
    await tester.pumpAndSettle();

    // A deliberate search shows its hits without a second tap.
    expect(find.text('supabase_flutter'), findsOneWidget);
    expect(find.text('Apache 2.0'), findsNothing);
    expect(find.text(s.licArt), findsNothing);

    await tester.enterText(find.byType(TextField), 'stitch');
    await tester.pumpAndSettle();
    expect(find.text('Malaysian stitch illustrations (WP25 Malaysia)'),
        findsOneWidget);
    expect(find.text('MIT'), findsNothing);
  });

  testWidgets('a search with no hits explains itself', (tester) async {
    await pumpAt(tester, kCompact, const LicensesScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text(s.licNoneTitle), findsOneWidget);
    expect(find.text(s.licNoneBody), findsOneWidget);
  });

  testWidgets('tapping a credit opens its full licence text', (tester) async {
    await pumpAt(tester, kCompact, const LicensesScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Malaysian stitch illustrations (WP25 Malaysia)'));
    await tester.pumpAndSettle();

    expect(find.text(s.licFullText), findsOneWidget);
    expect(
      find.textContaining('Creative Commons Attribution 4.0'),
      findsOneWidget,
    );
  });
}
