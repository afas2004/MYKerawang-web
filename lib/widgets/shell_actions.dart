import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../screens/create_event_screen.dart';
import '../screens/create_listing_screen.dart';
import '../screens/create_post_screen.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/guest_access.dart';

/// The one "Create" entry point, shared by the bottom bar's centre button,
/// the navigation rail and the desktop sidebar. Guests are asked to log in
/// first. Bottom sheet on phones, dialog on wide screens.
Future<void> showCreateSheet(BuildContext context) async {
  if (!requireLogin(context)) return;
  final s = context.l10nRead;

  void open(BuildContext ctx, Widget screen) {
    Navigator.pop(ctx);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  await showAdaptiveSheet<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(s.shell.createWhat,
                    style: theme.textTheme.titleLarge),
              ),
              _CreateOption(
                icon: Icons.chat_bubble_outline,
                title: s.createPostTitle,
                subtitle: s.shell.createPostSub,
                onTap: () => open(ctx, const CreatePostScreen()),
              ),
              _CreateOption(
                icon: Icons.event_outlined,
                title: s.createEvent,
                subtitle: s.shell.createEventSub,
                onTap: () => open(ctx, const CreateEventScreen()),
              ),
              _CreateOption(
                icon: Icons.storefront_outlined,
                title: s.sellItem,
                subtitle: s.shell.sellItemSub,
                onTap: () => open(ctx, const CreateListingScreen()),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 64,
      shape: const RoundedRectangleBorder(borderRadius: kerawangCut),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: kerawangCut,
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

/// App-bar search action for compact and medium layouts, where Search is
/// not in the bottom bar. Opens the Search tab (its state is kept).
///
/// Tab screens drop it into their AppBar `actions`:
/// `actions: [const ShellSearchButton(), ...]`. Hidden on desktop, where
/// the sidebar has Search.
class ShellSearchButton extends StatelessWidget {
  const ShellSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (isWide(context)) return const SizedBox.shrink();
    final s = context.l10n;
    return IconButton(
      tooltip: s.navSearch,
      icon: const Icon(Icons.search),
      onPressed: () => context.go('/search'),
    );
  }
}

/// Brand name in Fraunces, the wordmark used by the sidebar and onboarding.
class Wordmark extends StatelessWidget {
  final double? fontSize;
  const Wordmark({super.key, this.fontSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      AppStrings.appName,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
