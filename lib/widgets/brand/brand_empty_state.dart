import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'kerawang_lattice.dart';

/// Empty / nothing-here-yet state: a lattice medallion with an icon, a
/// Fraunces title, an optional message and an optional call to action.
///
///   BrandEmptyState(
///     icon: Icons.event_outlined,
///     title: s.noEventsYet,
///     message: s.noEventsHint,
///     actionLabel: s.createEvent,
///     onAction: () => context.push('/events/new'),
///   )
class BrandEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Smaller medallion and spacing for panels / rails.
  final bool compact;

  const BrandEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final k = KTokens.of(context);
    final medallion = compact ? 72.0 : 112.0;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? KSpace.l : KSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: medallion,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: KerawangLattice(
                        tileSize: medallion / 6,
                        // A medallion, not a background: more presence
                        // than a field, still well below the content.
                        opacity: k.motifCornerOpacity * 0.5,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: k.gold.withValues(alpha: k.motifBandOpacity)),
                      ),
                      child: const SizedBox.expand(),
                    ),
                    Container(
                      width: medallion * 0.5,
                      height: medallion * 0.5,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Icon(icon,
                          size: medallion * 0.24, color: scheme.primary),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? KSpace.m : KSpace.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: KSpace.s),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: compact ? KSpace.l : KSpace.xl),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
