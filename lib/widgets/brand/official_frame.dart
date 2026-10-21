import 'package:flutter/material.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';

/// Marks official / pinned / verified content: a 1px accent border and,
/// when there's a [label] (or [semanticLabel]), a small accent label row
/// at the top — e.g. "📌 Pinned", "✓ Official club".
///
/// The accent is the app's one special colour; use this only for content
/// that is genuinely official or pinned.
///
///   OfficialFrame(label: s.pinned, child: PostCard(...))
///   OfficialFrame(enabled: isClub, semanticLabel: roleLabel(...), child: ...)
class OfficialFrame extends StatelessWidget {
  final Widget child;

  /// When false the child is returned untouched (saves call-site ternaries).
  final bool enabled;

  final BorderRadius borderRadius;

  /// Text for the label row. Defaults to [semanticLabel]; no row when both
  /// are null.
  final String? label;

  /// Icon before the label (pin for pinned, [AppIcons.verified] for official).
  final IconData icon;

  /// Read by screen readers; also the default [label].
  final String? semanticLabel;

  /// Unused since the corner ornament was retired; kept for compatibility.
  final Alignment corner;
  final double cornerExtent;

  const OfficialFrame({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = KRadius.card,
    this.label,
    this.icon = AppIcons.verified,
    this.semanticLabel,
    this.corner = Alignment.topRight,
    this.cornerExtent = 36,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final theme = Theme.of(context);
    final k = KTokens.of(context);
    final text = label ?? semanticLabel;

    final framed = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: k.accent.withValues(alpha: 0.7)),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text != null)
              Container(
                color: k.accent.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(
                    horizontal: KSpace.m, vertical: KSpace.xs + 2),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: theme.colorScheme.tertiary),
                    const SizedBox(width: KSpace.xs + 2),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.tertiary),
                      ),
                    ),
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );

    if (semanticLabel == null) return framed;
    return Semantics(label: semanticLabel, container: true, child: framed);
  }
}
