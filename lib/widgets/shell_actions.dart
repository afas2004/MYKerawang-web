import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import '../l10n/create_strings.dart';
import '../services/club_service.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/guest_access.dart';
import 'app_logo.dart';
import 'brand/brand.dart';

/// The one "Create" entry point, shared by the bottom bar's centre button,
/// the navigation rail and the desktop sidebar. Guests are asked to log in
/// first. Bottom sheet with a drag handle on phones, dialog on wide screens.
Future<void> showCreateSheet(BuildContext context) async {
  if (!requireLogin(context)) return;
  final s = context.l10nRead;
  // Officers and admins also get Announcement (cached per user).
  final ability = ClubService.canPostAnnouncement();

  // Each form is a route (/create/...), so back and the browser behave.
  void open(BuildContext ctx, void Function() go) {
    Navigator.pop(ctx);
    go();
  }

  Widget sheet(BuildContext ctx, {required bool handle}) {
    final theme = Theme.of(ctx);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            KSpace.s, handle ? 0 : KSpace.l, KSpace.s, KSpace.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KSpace.l, 0, KSpace.l, KSpace.s),
              child: Text(s.shell.createWhat, style: theme.textTheme.titleMedium),
            ),
            CreateOptionsList(
              ability: ability,
              onPost: () => open(ctx, context.goCreatePost),
              onEvent: () => open(ctx, context.goCreateEvent),
              onSell: () => open(ctx, context.goCreateListing),
              onAnnouncement: () => open(ctx, () => context.push('/create/announcement')),
            ),
          ],
        ),
      ),
    );
  }

  if (isWide(context)) {
    await showAdaptiveSheet<void>(
      context: context,
      builder: (ctx) => sheet(ctx, handle: false),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => sheet(ctx, handle: true),
  );
}

/// The create choices by role (v1.4): everyone signed in gets Post, Event
/// and Sell; club officers and admins also get Announcement once
/// [ability] says so.
class CreateOptionsList extends StatelessWidget {
  final Future<AnnouncementAbility> ability;
  final VoidCallback onPost;
  final VoidCallback onEvent;
  final VoidCallback onSell;
  final VoidCallback onAnnouncement;

  const CreateOptionsList({
    super.key,
    required this.ability,
    required this.onPost,
    required this.onEvent,
    required this.onSell,
    required this.onAnnouncement,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreateOption(
          icon: AppIcons.compose,
          title: s.createPostTitle,
          subtitle: s.shell.createPostSub,
          onTap: onPost,
        ),
        FutureBuilder<AnnouncementAbility>(
          future: ability,
          builder: (context, snap) => AnimatedSize(
            duration: KMotion.of(context).fast,
            child: snap.data?.allowed == true
                ? _CreateOption(
                    icon: AppIcons.announcement,
                    title: s.create.announcement,
                    subtitle: s.create.announcementSub,
                    onTap: onAnnouncement,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
        _CreateOption(
          icon: AppIcons.calendarAdd,
          title: s.createEvent,
          subtitle: s.shell.createEventSub,
          onTap: onEvent,
        ),
        _CreateOption(
          icon: AppIcons.price,
          title: s.sellItem,
          subtitle: s.shell.sellItemSub,
          onTap: onSell,
        ),
      ],
    );
  }
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
      shape: const RoundedRectangleBorder(borderRadius: KRadius.input),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(AppIcons.chevronRight, size: 18, color: scheme.onSurfaceVariant),
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
      icon: const Icon(AppIcons.search),
      onPressed: () => context.go('/search'),
    );
  }
}

/// App-bar shortcut to the club directory, for compact and medium layouts
/// where the sidebar (and its Clubs row) is not shown.
///
/// Tab screens put it next to [ShellSearchButton]:
/// `actions: [const ShellSearchButton(), const ShellClubsButton(), ...]`.
class ShellClubsButton extends StatelessWidget {
  const ShellClubsButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (isWide(context)) return const SizedBox.shrink();
    final s = context.l10n;
    return IconButton(
      tooltip: s.shell.clubs,
      icon: const Icon(AppIcons.people),
      onPressed: () => context.push('/clubs'),
    );
  }
}

/// Logo mark + brand name in the app's sans, used by the sidebar, the rail
/// and onboarding. [showLogo] false gives the name alone.
class Wordmark extends StatelessWidget {
  final double? fontSize;
  final bool showLogo;
  const Wordmark({super.key, this.fontSize, this.showLogo = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = fontSize ?? 20;
    final name = Text(
      AppStrings.appName,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: theme.colorScheme.onSurface,
      ),
    );
    if (!showLogo) return name;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: AppLogo(size: size * 1.5)),
        const SizedBox(width: KSpace.s),
        Flexible(child: name),
      ],
    );
  }
}
