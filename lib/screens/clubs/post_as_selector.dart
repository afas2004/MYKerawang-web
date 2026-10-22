import 'package:flutter/material.dart';

import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../widgets/brand/brand.dart';
import 'club_strings.dart';
import 'club_widgets.dart';

/// "Post as" picker for the create screens (post, event, listing).
///
///     PostAsSelector(
///       selfLabel: myDisplayName,
///       value: _postAs,                       // PostAsOption? (null = yourself)
///       onChanged: (o) => setState(() => _postAs = o),
///     )
///     ...
///     final row = (_postAs ?? const PostAsOption.self('')).applyTo({...});
///
/// Renders nothing until it knows you're an officer of at least one
/// active club, so ordinary students never see it. [options] skips the
/// lookup (tests, or a screen that already loaded them).
class PostAsSelector extends StatefulWidget {
  final String selfLabel;
  final String? selfAvatar;
  final PostAsOption? value;
  final ValueChanged<PostAsOption> onChanged;
  final List<PostAsOption>? options;

  const PostAsSelector({
    super.key,
    required this.selfLabel,
    required this.value,
    required this.onChanged,
    this.selfAvatar,
    this.options,
  });

  @override
  State<PostAsSelector> createState() => _PostAsSelectorState();
}

class _PostAsSelectorState extends State<PostAsSelector> {
  late final Future<List<PostAsOption>> _options = widget.options != null
      ? Future.value(widget.options)
      : ClubService.postAsOptions(widget.selfLabel, selfAvatar: widget.selfAvatar)
          .catchError((_) => <PostAsOption>[PostAsOption.self(widget.selfLabel)]);

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    return FutureBuilder<List<PostAsOption>>(
      future: _options,
      builder: (context, snap) {
        final opts = snap.data ?? const [];
        if (opts.length < 2) return const SizedBox.shrink();
        final selected = opts.firstWhere(
          (o) => o.clubId == widget.value?.clubId,
          orElse: () => opts.first,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.postAs, style: theme.textTheme.labelLarge),
            const SizedBox(height: KSpace.s),
            Wrap(
              spacing: KSpace.s,
              runSpacing: KSpace.s,
              children: [
                for (final o in opts)
                  ChoiceChip(
                    avatar: o.isClub
                        ? ClubLogo(url: o.avatarUrl, name: o.label, size: 22)
                        : const Icon(AppIcons.person, size: 18),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(o.isClub ? o.label : c.yourself),
                        if (o.verified) ...[
                          const SizedBox(width: KSpace.xs),
                          Icon(AppIcons.verified, size: 14, color: theme.colorScheme.tertiary),
                        ],
                      ],
                    ),
                    selected: o.clubId == selected.clubId,
                    onSelected: (_) => widget.onChanged(o),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
