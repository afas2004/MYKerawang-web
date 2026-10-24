import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/services/category_service.dart';
import 'package:mykerawang/utils/categories.dart';

void main() {
  test('seed slugs are unique and well formed', () {
    for (final seeds in [kEventCategorySeeds, kListingCategorySeeds]) {
      final slugs = seeds.map((s) => s.slug).toList();
      expect(slugs.toSet().length, slugs.length, reason: 'duplicate slug');
      for (final s in slugs) {
        expect(RegExp(r'^[a-z0-9][a-z0-9-]{1,29}$').hasMatch(s), isTrue,
            reason: 'bad slug: $s');
      }
    }
  });

  test('the bundled lists are big enough to be useful', () {
    expect(kEventCategorySeeds.length, greaterThan(40));
    expect(kListingCategorySeeds.length, greaterThan(20));
  });

  test('every seed has both names', () {
    for (final s in [...kEventCategorySeeds, ...kListingCategorySeeds]) {
      expect(s.en.trim(), isNotEmpty);
      expect(s.ms.trim(), isNotEmpty);
    }
  });

  test('labels follow the language, and unknown slugs fall back', () {
    const c = ContentCategory(
        id: '1', kind: 'event', slug: 'workshop', nameEn: 'Workshop', nameMs: 'Bengkel');
    expect(c.label(AppStrings.en), 'Workshop');
    expect(c.label(AppStrings.ms), 'Bengkel');

    const noMs = ContentCategory(
        id: '2', kind: 'event', slug: 'x', nameEn: 'Only English');
    expect(noMs.label(AppStrings.ms), 'Only English');

    // Before any load, cached() serves the seeds — so a filter chip can
    // always resolve a label.
    expect(CategoryService.labelOf('event', 'workshop', AppStrings.en), 'Workshop');
    expect(CategoryService.labelOf('event', 'not-a-category', AppStrings.en),
        'not-a-category');
  });
}
