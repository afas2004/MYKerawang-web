import 'package:flutter/material.dart';

import '../../l10n/feature_off_strings.dart';
import '../../language_cubit.dart';
import '../../services/feature_flags.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/profile_avatar_action.dart';
import '../../widgets/shell_actions.dart';
import 'announcements_screen.dart';
import 'hub_strings.dart';

/// The News tab. While the owner has Announcements switched off the tab
/// stays in the bar (so the bar keeps its shape) but shows "Coming soon"
/// instead of the hub. Flipping the switch swaps it live.
class AnnouncementsTab extends StatelessWidget {
  const AnnouncementsTab({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FeatureFlagsState>(
        valueListenable: FeatureFlags.listenable,
        builder: (context, flags, _) => flags.announcementsOn
            ? const AnnouncementsScreen()
            : const AnnouncementsComingSoon(),
      );
}

/// "Coming soon" body for the News tab, under the same header band.
class AnnouncementsComingSoon extends StatelessWidget {
  const AnnouncementsComingSoon({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: KBand.appBar(
        context,
        tone: KBand.news,
        title: Text(s.hub.title),
        actions: const [
          ShellSearchButton(),
          ProfileAvatarAction(),
          SizedBox(width: KSpace.s),
        ],
      ),
      body: Center(
        child: BrandEmptyState(
          icon: AppIcons.announcement,
          title: s.comingSoonTitle,
          message: s.comingSoonNewsBody,
        ),
      ),
    );
  }
}
