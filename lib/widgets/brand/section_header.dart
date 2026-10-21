import 'package:flutter/material.dart';

import '../../language_cubit.dart';
import '../../theme/tokens.dart';

/// Section title (sans, 18 semibold) with an optional "See all" or a
/// custom trailing widget. Announced as a heading to screen readers.
///
///   SectionHeader(title: s.happeningSoon, onSeeAll: () => context.go('/events'))
class SectionHeader extends StatelessWidget {
  final String title;

  /// Shows a "See all →" button when set.
  final VoidCallback? onSeeAll;

  /// Overrides the default `s.seeAll` label.
  final String? seeAllLabel;

  /// Replaces the See-all button (e.g. a filter chip or count).
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.seeAllLabel,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
        KSpace.l, KSpace.l, KSpace.s, KSpace.s),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(seeAllLabel ?? context.l10n.seeAll),
            ),
        ],
      ),
    );
  }
}
