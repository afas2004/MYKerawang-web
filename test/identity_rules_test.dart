import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A small "slop lint" for the visual identity (docs/visual-identity-plan.md):
/// source checks that keep the generic defaults from creeping back. Each
/// rule has an allow-list; add to it only with a reason in the comment.
void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => (path: f.path.replaceAll(r'\', '/'), text: f.readAsStringSync()))
      .toList();

  List<String> offenders(RegExp pattern, Set<String> allowed) => [
        for (final s in sources)
          if (pattern.hasMatch(s.text) && !allowed.contains(s.path)) s.path,
      ];

  test('colours come from the theme or the brand palette', () {
    expect(
      offenders(RegExp(r'Color\(0x'), {
        // Palettes live here.
        'lib/widgets/brand/brand_cover.dart',
        // Google's four brand colours in the sign-in button's "G".
        'lib/screens/login_screen.dart',
      }).where((p) => !p.startsWith('lib/theme/')),
      isEmpty,
    );
  });

  test('no gradient placeholders', () {
    expect(
      offenders(RegExp(r'(Linear|Radial)Gradient\('), {
        // Legibility scrim under text on a cover photo.
        'lib/screens/announcements/announcements_screen.dart',
        // The skeleton shimmer sweep.
        'lib/widgets/brand/k_skeleton.dart',
        // The pin bar's ground: the owner's choice, to set it apart from the
        // plum header.
        'lib/widgets/pin_bar.dart',
      }),
      isEmpty,
    );
  });

  test('no stock unDraw art left in the bundle', () {
    final svgs = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'));
    for (final f in svgs) {
      expect(f.readAsStringSync().toLowerCase(), isNot(contains('#6c63ff')), reason: f.path);
    }
  });

  test('no songket pattern strips (removed by design, 2026-10-29)', () {
    expect(offenders(RegExp(r'songket_perseri|SongketHem'), {}), isEmpty);
    expect(File('web/index.html').readAsStringSync(), isNot(contains('songket')));
  });
}
