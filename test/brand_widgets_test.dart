import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/theme/app_themes.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every brand widget at phone / tablet / desktop widths in all three
/// themes: must lay out without overflow or exceptions.
void main() {
  debugUseSystemFonts = true;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const widths = [320.0, 375.0, 768.0, 1280.0];

  Widget gallery() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LatticeBand(),
            const SizedBox(height: 120, child: KerawangLattice()),
            const Align(
              alignment: Alignment.centerLeft,
              child: KerawangLattice.corner(extent: 48),
            ),
            SectionHeader(title: 'Jangan Terlepas', onSeeAll: () {}),
            const SectionHeader(
                title: 'A very long section title that has to ellipsize nicely',
                trailing: Icon(Icons.tune)),
            Padding(
              padding: const EdgeInsets.all(KSpace.l),
              child: KCard(
                onTap: () {},
                child: const Text('Regular card'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(KSpace.l),
              child: KCard(
                official: true,
                semanticLabel: 'Official',
                onTap: () {},
                child: const Padding(
                  padding: EdgeInsets.only(right: 36),
                  child: Text('Official / pinned card with longer text that wraps'),
                ),
              ),
            ),
            const OfficialFrame(
              child: SizedBox(height: 80, width: double.infinity),
            ),
            const Padding(
              padding: EdgeInsets.all(KSpace.l),
              child: Row(children: [
                KSkeleton.circle(),
                SizedBox(width: KSpace.m),
                Expanded(child: KSkeleton(height: 16)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(KSpace.l),
              child: KSkeleton.lines(3),
            ),
            SizedBox(
              height: 360,
              child: BrandEmptyState(
                icon: Icons.event_outlined,
                illo: AppIllo.noEvents,
                title: 'Belum ada acara',
                message: 'Jom buat acara pertama untuk kolej anda.',
                actionLabel: 'Buat acara',
                onAction: () {},
              ),
            ),
            const SizedBox(
              height: 200,
              child: BrandEmptyState(title: 'Compact', compact: true),
            ),
            // Patterns, hems and covers fill whatever box they get: very
            // short, very wide, and with a motif that must stay inside.
            const SongketHem(height: 8),
            const SizedBox(height: 60, child: KPattern(kind: KPatternKind.star8, color: Colors.black12)),
            const SizedBox(height: 24, child: KPattern(kind: KPatternKind.pucuk, color: Colors.black12, angle: 45)),
            const SizedBox(height: 140, child: BrandCover(seed: 'kebudayaan', motif: AppMotif.wauBulan, hem: true)),
            const SizedBox(height: 40, child: BrandCover(seed: 'robotik', motif: AppMotif.sape, hem: true)),
            for (final i in AppIllo.values) AppIllustration(i, size: 160),
            SizedBox(
              height: 240,
              child: AdaptiveScaffoldBody(
                primary: Container(height: 200, color: Colors.black12),
                secondary: const Text('Details'),
              ),
            ),
          ],
        ),
      );

  for (final theme in AppTheme.values) {
    for (final width in widths) {
      testWidgets('${theme.name} @ ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(BlocProvider(
          create: (_) => LanguageCubit(),
          child: MaterialApp(
            theme: buildAppTheme(theme),
            home: Scaffold(body: gallery()),
          ),
        ));
        // Skeleton shimmer repeats forever, so pump frames, not settle.
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(KCard), findsNWidgets(2));

        // Split only where there's room (pane is the full window here).
        final split = find.byType(Row).evaluate().any((e) =>
            (e.widget as Row).children.length == 3 &&
            e.findAncestorWidgetOfExactType<AdaptiveScaffoldBody>() != null);
        expect(split, width >= Responsive.desktopBreakpoint);
      });
    }
  }

  testWidgets('reduced motion: skeleton is static, KMotion is zero',
      (tester) async {
    late Duration medium;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: buildAppTheme(AppTheme.kampus),
        home: Builder(builder: (context) {
          medium = KMotion.of(context).medium;
          return const Scaffold(body: KSkeleton(width: 100));
        }),
      ),
    ));
    expect(medium, Duration.zero);
    // No running animation → settles immediately.
    await tester.pumpAndSettle();
  });

  for (final size in [48.0, 200.0, 420.0]) {
    testWidgets('every illustration loads and renders at ${size.toInt()}px',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(AppTheme.noir),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(children: [
              for (final i in AppIllo.values) AppIllustration(i, size: size),
            ]),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final i in AppIllo.values) {
        expect(tester.getSize(find.byWidgetPredicate((w) => w is AppIllustration && w.illo == i)),
            Size(size, size * 0.75));
      }
    });
  }

  test('every scene asset is bundled', () {
    final assets = {for (final i in AppIllo.values) ...AppIllustration.assetsOf(i)};
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
    for (final m in AppMotif.values) {
      expect(File(m.asset).existsSync(), isTrue, reason: m.asset);
    }
  });

  test('illustration recolour follows the theme (ink, fill, accent)', () {
    const svg = '<path fill="#000000"/><path fill="#FFFFFF"/><path fill="#FF5678"/><path fill="#a0616a"/>';
    final light = buildAppTheme(AppTheme.kampus).colorScheme;
    final dark = buildAppTheme(AppTheme.noir).colorScheme;
    final l = AppIllustration.recolor(svg, light).toLowerCase();
    final d = AppIllustration.recolor(svg, dark).toLowerCase();
    expect(l, isNot(contains('#000000'))); // ink takes the text colour
    expect(l, contains('#ffffff')); // fill stays white on light themes
    expect(d, isNot(contains('#ffffff'))); // and darkens on Noir
    expect(l, isNot(contains('#ff5678'))); // doodle pink becomes the accent
    expect(d, contains('#a0616a')); // anything else is left alone
  });

  test('generated covers are stable and spread over the palette', () {
    expect(KPalette.forKey('robotik'), KPalette.forKey('robotik'));
    expect(stableHash('robotik'), stableHash('robotik'));
    final used = {for (final h in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']) KPalette.forKey(h)};
    expect(used.length, greaterThan(2));
    for (final c in KPalette.all) {
      expect(contrastRatio(Colors.white, c), greaterThanOrEqualTo(4.5));
    }
  });

  test('size classes and grid columns', () {
    expect(Responsive.sizeFor(375), WindowSize.compact);
    expect(Responsive.sizeFor(768), WindowSize.medium);
    expect(Responsive.sizeFor(1000), WindowSize.expanded);
    expect(Responsive.sizeFor(1280), WindowSize.large);
    expect(<double>[375, 768, 1000, 1400].map(Responsive.gridColumnsFor),
        [2, 3, 4, 5]);
  });
}
