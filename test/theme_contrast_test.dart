import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/theme/app_themes.dart';

/// WCAG AA for every text/background pairing the app relies on, in all
/// three themes. If a palette change breaks this, fix the palette (or the
/// `_ensureContrast` floor in buildAppTheme), don't lower the bar.
void main() {
  debugUseSystemFonts = true; // before buildAppTheme runs below

  for (final theme in AppTheme.values) {
    group(kThemeSpecs[theme]!.displayName, () {
      final data = buildAppTheme(theme);
      final c = data.colorScheme;
      final k = data.extension<KTokens>()!;
      final card = data.cardColor;

      final text = <String, (Color, Color)>{
        'onSurface / background': (c.onSurface, c.surface),
        'onSurface / card': (c.onSurface, card),
        'onSurfaceVariant / background': (c.onSurfaceVariant, c.surface),
        'onSurfaceVariant / card': (c.onSurfaceVariant, card),
        'onSurfaceVariant / containerHighest':
            (c.onSurfaceVariant, c.surfaceContainerHighest),
        'primary / background': (c.primary, c.surface),
        'primary / card': (c.primary, card),
        'onPrimary / primary': (c.onPrimary, c.primary),
        'tertiary (gold text) / card': (c.tertiary, card),
        'onTertiary / tertiary': (c.onTertiary, c.tertiary),
        'onPrimaryContainer / primaryContainer':
            (c.onPrimaryContainer, c.primaryContainer),
        'onSecondaryContainer / secondaryContainer':
            (c.onSecondaryContainer, c.secondaryContainer),
        'error / background': (c.error, c.surface),
        'onError / error': (c.onError, c.error),
      };
      text.forEach((name, pair) {
        test('$name ≥ 4.5', () {
          expect(contrastRatio(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        });
      });

      final ui = <String, (Color, Color)>{
        'focus ring / card': (k.focusRing, card),
        'focus ring / background': (k.focusRing, c.surface),
        'outline / background': (c.outline, c.surface),
      };
      ui.forEach((name, pair) {
        test('$name ≥ 3', () {
          expect(contrastRatio(pair.$1, pair.$2), greaterThanOrEqualTo(3));
        });
      });
    });
  }
}
