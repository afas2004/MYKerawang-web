import 'package:flutter/material.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/pinned_posts.dart';
import '../../utils/app_nav.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import '../../widgets/pin_controls.dart';
import 'admin_screen.dart';

/// Every live pin, in one place.
///
/// Home's pin bar is the only other handle on a pin, and it is a poor one
/// for an admin: closing a pin hides it on that device, and the feed sorts
/// by date, so an older pinned post is buried. This tab reads the pins
/// straight from `posts_public` and never minds what was closed.
class PinsTab extends StatefulWidget {
  const PinsTab({super.key});

  @override
  State<PinsTab> createState() => _PinsTabState();
}

class _PinsTabState extends State<PinsTab> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future = PinnedPosts.allForAdmin();

  @override
  bool get wantKeepAlive => true;

  void _reload() => setState(() => _future = PinnedPosts.allForAdmin());

  /// The pin's headline: its title, or the start of the body for a post
  /// that has none.
  String _title(Map<String, dynamic> post, AppStrings s) {
    final title = (post['title'] as String? ?? '').trim();
    if (title.isNotEmpty) return title;
    final body = (post['body'] as String? ?? '').trim();
    return body.isEmpty ? s.untitled : body;
  }

  /// Mandatory, or the date it ends by itself.
  String _subtitle(Map<String, dynamic> post, AppStrings s) {
    if (post['pin_mandatory'] == true) return s.pinMandatory;
    final until = DateTime.tryParse('${post['pinned_until'] ?? ''}');
    return until == null ? s.pinNoEnd : s.pinUntil.fill([formatDate(until)]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.l10n;
    final theme = Theme.of(context);
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      empty: ModEmptyState(
          icon: ModIcons.pin, title: s.pinsEmpty, body: s.pinsEmptyBody),
      itemBuilder: (context, post) {
        final mandatory = post['pin_mandatory'] == true;
        return Card(
          margin: const EdgeInsets.only(bottom: KSpace.s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                KSpace.m, KSpace.s, KSpace.s, KSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title(post, s),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_subtitle(post, s),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                Row(children: [
                  // Unpin and the mandatory switch both reload the list:
                  // an unpinned post leaves it.
                  TextButton(
                    onPressed: () async {
                      await PinActions.toggle(context, post, pinned: true);
                      if (mounted) _reload();
                    },
                    child: Text(s.mod.unpin),
                  ),
                  TextButton(
                    onPressed: () async {
                      await PinActions.setMandatory(context, post, !mandatory);
                      if (mounted) _reload();
                    },
                    child:
                        Text(mandatory ? s.pinMakeNormal : s.pinMakeMandatory),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.goPost(post),
                    child: Text(s.pinOpen),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
