import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../services/unread_notifications.dart';
import '../utils/app_nav.dart';
import '../widgets/brand/brand.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/right_rail.dart';
import '../widgets/shell_actions.dart';

// Layout per Responsive size class (WindowSize):
//  * compact  < 600   bottom bar (Home, Market, Create, Events, Profile);
//                     Search lives in the tab app bars ([ShellSearchButton])
//  * medium   600–899 navigation rail + one 680 column
//  * expanded 900–1199 240 sidebar + 680 feed
//  * large    ≥ 1200  sidebar + feed + right rail

/// Branch order in the router's StatefulShellRoute.
abstract final class ShellBranch {
  static const home = 0;
  static const search = 1;
  static const market = 2;
  static const events = 3;
  static const profile = 4;
}

/// Shell around the five main tabs. The tab bodies and their state are
/// owned by go_router's StatefulShellRoute, so each tab keeps its scroll
/// position and the browser URL always matches the visible tab.
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return ShellFrame(
      currentIndex: navigationShell.currentIndex,
      onSelect: (index) => navigationShell.goBranch(
        index,
        // Tapping the active tab returns it to its root.
        initialLocation: index == navigationShell.currentIndex,
      ),
      child: navigationShell,
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
    const branches = [
      ShellBranch.home,
      ShellBranch.market,
      ShellBranch.events,
      ShellBranch.profile,
    ];
    final railIndex = branches.indexOf(currentIndex);
    final items = AppSidebar.navItems(context);
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
            indicatorColor: scheme.secondaryContainer,
            groupAlignment: -0.6,
            leading: Column(
              children: [
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'shell-create',
                  tooltip: s.shell.create,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: KRadius.cut),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  onPressed: () => showCreateSheet(context),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 12),
                IconButton(
                  tooltip: s.navSearch,
                  isSelected: currentIndex == ShellBranch.search,
                  icon: const Icon(Icons.search),
                  selectedIcon: const Icon(Icons.saved_search),
                  onPressed: () => onSelect(ShellBranch.search),
                ),
              ],
            ),
            trailing: Column(
              children: [
                const SizedBox(height: 16),
                IconButton(
                  tooltip: s.notifications,
                  icon: const UnreadBadge(
                      child: Icon(Icons.notifications_outlined)),
                  onPressed: () => context.goNotifications(),
                ),
                IconButton(
                  tooltip: s.settings,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.goSettings(),
                ),
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

/// Phone bottom bar: Home, Market, a raised centre Create, Events,
/// Profile. Search has no slot here — it is in the tab app bars.
class CompactNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const CompactNavBar(
      {super.key, required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final items = AppSidebar.navItems(context);

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
        color: scheme.surfaceContainer,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  tab(ShellBranch.home),
                  tab(ShellBranch.market),
                  Expanded(child: _CreateBarButton(label: s.shell.create)),
                  tab(ShellBranch.events),
                  tab(ShellBranch.profile),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: KMotion.of(context).medium,
              curve: KMotion.curve,
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(selected ? selectedIcon : icon, color: fg, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The prominent centre action: a primary, kerawang-cut tile.
class _CreateBarButton extends StatelessWidget {
  final String label;
  const _CreateBarButton({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: scheme.primary,
            elevation: 2,
            shape: const RoundedRectangleBorder(borderRadius: KRadius.cut),
            child: InkWell(
              customBorder:
                  const RoundedRectangleBorder(borderRadius: KRadius.cut),
              onTap: () => showCreateSheet(context),
              child: SizedBox(
                width: 56,
                height: 48,
                child: Icon(Icons.add, color: scheme.onPrimary, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
