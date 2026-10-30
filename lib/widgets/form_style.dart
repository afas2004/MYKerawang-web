import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The three analysis colours of the KI form, and the neutral one for rows
/// that are not counted.
///
/// One definition, used by both the editor (lane tint, tag pill, coverage rail)
/// and the answer page (section tint), so the colour of "KI before" means the
/// same thing on both screens and in every theme.
///
/// | analysis  | accent          | meaning                  |
/// |-----------|-----------------|--------------------------|
/// | `ki_pre`  | `colorScheme.primary`   | before the programme |
/// | `ki_post` | `colorScheme.tertiary`  | after the programme  |
/// | `feedback`| `KTokens.feedback`      | programme feedback   |
/// | null      | `outlineVariant`        | not counted          |
class AnalysisStyle {
  /// The rule, dot and border colour.
  final Color accent;

  /// The pale fill behind a lane head, a tag or a section header.
  final Color soft;

  /// Text/icons on [soft].
  final Color ink;

  const AnalysisStyle(this.accent, this.soft, this.ink);

  static AnalysisStyle of(BuildContext context, String? analysis) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = KTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    Color tint(Color c) => Color.alphaBlend(
          c.withValues(alpha: dark ? 0.22 : 0.12),
          scheme.surfaceContainerLowest,
        );

    return switch (analysis) {
      'ki_pre' => AnalysisStyle(
          scheme.primary, scheme.primaryContainer, scheme.onPrimaryContainer),
      'ki_post' => AnalysisStyle(scheme.tertiary, tint(scheme.tertiary), scheme.tertiary),
      'feedback' => AnalysisStyle(tokens.feedback, tint(tokens.feedback), tokens.feedback),
      _ => AnalysisStyle(
          scheme.outlineVariant, scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
  }
}
