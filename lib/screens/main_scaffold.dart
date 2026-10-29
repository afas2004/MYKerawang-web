import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../services/unread_notifications.dart';
import '../utils/app_nav.dart';
import '../utils/browser_history_stub.dart'
    if (dart.library.js_interop) '../utils/browser_history_web.dart';
import '../widgets/brand/brand.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_logo.dart';
import '../widgets/admin_icon_button.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/profile_avatar_action.dart';
import '../widgets/right_rail.dart';
import '../widgets/shell_actions.dart';

// Layout per Responsive size class (WindowSize):
//  * compact  < 600   bottom bar (Home, Announcements, Create, Market,
//                     Events); Search lives in the tab app bars
//                     ([ShellSearchButton]); Profile is a pushed page
//                     opened from [ProfileAvatarAction]
//  * medium   600–899 navigation rail + one 680 column
//  * expanded 900–1199 240 sidebar + 680 feed
//  * large    ≥ 1200  sidebar + feed + right rail

/// Branch order in the router's StatefulShellRoute.
abstract final class ShellBranch {
  static const home = 0;
  static const announcements = 1;
  static const search = 2;
  static const market = 3;
  static const events = 4;

  /// Tabs in the order the bottom bar and the rail show them (Create sits
  /// between Announcements and Market on the bar). Search has no slot.
  static const navOrder = [home, announcements, market, events];
}

/// Shell around the five main tabs. The tab bodies and their state are
/// owned by go_router's StatefulShellRoute, so each tab keeps its scroll
/// position and the browser URL always matches the visible tab.
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return ShellBackScope(
      currentIndex: navigationShell.currentIndex,
      goHome: () => selectTab(context, navigationShell, ShellBranch.home),
      child: ShellFrame(
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) => selectTab(context, navigationShell, index),
        child: navigationShell,
      ),
    );
  }
}

/// Switches tab without piling up history.
///
/// * Home → another tab adds one history entry, so the browser's back
///   returns to Home.
/// * Between other tabs the entry is replaced (Router.neglect), so back
///   still returns to Home rather than walking through every tab.
/// * Another tab → Home steps the browser back to that Home entry when
///   there is one, otherwise replaces the entry. Back on Home then leaves
///   the app (browser default).
/// * Tapping the active tab returns it to its root, without history.
void selectTab(BuildContext context, StatefulNavigationShell shell, int index) {
  final current = shell.currentIndex;
  void go() => shell.goBranch(index, initialLocation: index == current);

  if (index == current) {
    Router.neglect(context, go);
    return;
  }
  if (current == ShellBranch.home) {
    TabHistory.homeIsBelow = true;
    go();
    return;
  }
  if (index == ShellBranch.home && TabHistory.homeIsBelow && TabHistory.stepBack()) {
    TabHistory.homeIsBelow = false;
    return;
  }
  Router.neglect(context, go);
}

/// Whether the browser entry under the current tab is Home (set when a
/// tab was opened from Home with a new entry).
abstract final class TabHistory {
  static bool homeIsBelow = false;

  /// Web: browser back; elsewhere false (tabs have no history to step).
  static bool Function() stepBack = () => kIsWeb && browserHistoryBack();
}

/// System back (Android, PWA gesture) on a tab: other tabs go to Home;
/// on Home it's let through, which leaves the app.
class ShellBackScope extends StatelessWidget {
  final int currentIndex;
  final VoidCallback goHome;
  final Widget child;

  const ShellBackScope({
    super.key,
    required this.currentIndex,
    required this.goHome,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: currentIndex == ShellBranch.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goHome();
      },
      child: child,
    );
  }
}

/// The responsive chrome, independent of go_router so it can be tested
/// with a stand-in [child].
class ShellFrame extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget child;

  /// Right rail content; defaults to [RightRail]. Tests pass a stub.
  final Widget? rightRail;

  const ShellFrame({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.child,
    this.rightRail,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Responsive.sizeFor(constraints.maxWidth);
      return switch (size) {
        WindowSize.compact => _compact(context),
        WindowSize.medium => _medium(context),
        WindowSize.expanded || WindowSize.large =>
          _expanded(context, showRail: size.isLarge),
      };
    });
  }

  // ---------- COMPACT: bottom bar with a centre Create ----------
  Widget _compact(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar:
          CompactNavBar(currentIndex: currentIndex, onSelect: onSelect),
    );
  }

  // ---------- MEDIUM: navigation rail + one column ----------
  Widget _medium(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    // Rail shows the same four tabs as the bottom bar; Search is in the
    // leading area (and the tab app bars), so it maps to no destination.
    const branches = ShellBranch.navOrder;
    final railIndex = branches.indexOf(currentIndex);
    final items = AppSidebar.navItems(context, short: true);
    final loggedIn = ShellAuth.of(context);
    (IconData, IconData, String) itemFor(int branch) => items[branch];

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            backgroundColor: scheme.surfaceContainerLow,
            selectedIndex: railIndex < 0 ? null : railIndex,
            onDestinationSelected: (i) => onSelect(branches[i]),
            labelType: NavigationRailLabelType.all,
            indicatorColor: scheme.primaryContainer,
            groupAlignment: -0.6,
            leading: Column(
              children: [
                const SizedBox(height: KSpace.s),
                Semantics(
                  label: AppStrings.appName,
                  child: const AppLogo(size: 36),
                ),
                const SizedBox(height: KSpace.l),
                FloatingActionButton(
                  heroTag: 'shell-create',
                  tooltip: s.shell.create,
                  elevation: 0,
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  onPressed: () => showCreateSheet(context),
                  child: const Icon(AppIcons.create),
                ),
                const SizedBox(height: KSpace.m),
                IconButton(
                  tooltip: s.navSearch,
                  isSelected: currentIndex == ShellBranch.search,
                  icon: const Icon(AppIcons.search),
                  selectedIcon: const Icon(AppIcons.searchFilled),
                  onPressed: () => onSelect(ShellBranch.search),
                ),
              ],
            ),
            // Guests: one Sign in control instead of bell + settings.
            trailing: Column(
              children: [
                const SizedBox(height: KSpace.l),
                if (loggedIn) ...[
                  IconButton(
                    tooltip: s.notifications,
                    icon: const UnreadBadge(
                        child: Icon(AppIcons.notifications)),
                    onPressed: () => context.goNotifications(),
                  ),
                  IconButton(
                    tooltip: s.settings,
                    icon: const Icon(AppIcons.settings),
                    onPressed: () => context.goSettings(),
                  ),
                  const AdminIconButton(),
                ],
                const ProfileAvatarAction(compactGuest: true),
              ],
            ),
            destinations: [
              for (final b in branches)
                NavigationRailDestination(
                  icon: Icon(itemFor(b).$1),
                  selectedIcon: Icon(itemFor(b).$2),
                  label: Text(itemFor(b).$3),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: scheme.outlineVariant),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- EXPANDED: sidebar + feed + optional right rail ----------
  Widget _expanded(BuildContext context, {required bool showRail}) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shared with pushed pages — see AppSidebar / DesktopChrome.
          AppSidebar(selectedIndex: currentIndex, onSelect: onSelect),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
                child: child,
              ),
            ),
          ),
          if (showRail) rightRail ?? const RightRail(),
        ],
      ),
    );
  }
}

/// Phone bottom bar, the foot to the app bar's head: a white bar with softly
/// rounded top corners. Home, Announcements, Create, Market, Events. The
/// active tab is plum with a small rounded marigold mark above it; Create is
/// the MYKerawang logo, big and rising above the bar in the middle slot (it
/// opens the create sheet; guests are asked to log in first). Search has no slot; it's in the tab app bars. Profile is
/// reached from [ProfileAvatarAction] in the app bars.
class CompactNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const CompactNavBar(
      {super.key, required this.currentIndex, required this.onSelect});

  static const double height = 72;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final items = AppSidebar.navItems(context, short: true);

    Widget tab(int branch) => Expanded(
          child: _BarItem(
            icon: items[branch].$1,
            selectedIcon: items[branch].$2,
            label: items[branch].$3,
            selected: currentIndex == branch,
            onTap: () => onSelect(branch),
          ),
        );

    return Semantics(
      container: true,
      label: s.shell.mainNavigation,
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: 6,
        shadowColor: scheme.primary.withValues(alpha: 0.25),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                tab(ShellBranch.home),
                tab(ShellBranch.announcements),
                Expanded(
                  child: _BarItem(
                    icon: AppIcons.create,
                    selectedIcon: AppIcons.create,
                    label: s.shell.create,
                    selected: false,
                    accent: true,
                    onTap: () => showCreateSheet(context),
                  ),
                ),
                tab(ShellBranch.market),
                tab(ShellBranch.events),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const double _logoSize = 52;

class _BarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;

  /// The Create slot: always-filled primary pill, not a tab.
  final bool accent;
  final VoidCallback onTap;

  const _BarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color fg = accent
        ? scheme.onPrimary
        : (selected ? scheme.primary : scheme.onSurfaceVariant);
    final motion = KMotion.of(context);

    return Semantics(
      button: true,
      selected: accent ? null : selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          // Splash only on the pill area, like NavigationBar.
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (accent)
                // Create: the MYKerawang logo, big, rising above the bar. It
                // keeps the 32 px slot of the tab icons so every label shares
                // one baseline; the extra height paints upward.
                SizedBox(
                  width: 64,
                  height: 32,
                  child: OverflowBox(
                    alignment: Alignment.bottomCenter,
                    maxHeight: _logoSize,
                    // The logo tile itself, with only a soft shadow behind it.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_logoSize * 0.26),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const AppLogo(size: _logoSize),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 64,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Icon(selected ? selectedIcon : icon, color: fg, size: 22),
                      // The active tab's soft marigold mark.
                      Positioned(
                        top: -5,
                        child: AnimatedScale(
                          scale: selected ? 1 : 0,
                          duration: motion.medium,
                          curve: KMotion.curve,
                          child: Container(
                            width: 14,
                            height: 4,
                            decoration: BoxDecoration(
                              color: KTokens.of(context).accent,
                              borderRadius: KRadius.pill,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: KSpace.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? scheme.primary
                      : accent
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                  fontWeight:
                      selected || accent ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
