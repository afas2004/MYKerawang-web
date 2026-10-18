import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../services/unread_notifications.dart';
import '../utils/app_nav.dart';
import 'admin_nav_entry.dart';
import 'brand/brand.dart';
import 'kerawang_motif.dart';
import 'shell_actions.dart';

/// Desktop sidebar (≥ 900), shared by the tab shell and by pushed pages
/// (detail/profile/settings) so the chrome never disappears mid-session
/// — UI_UX_AUDIT H1.2.
///
/// Top to bottom: lattice band, wordmark, the five tabs, notifications
/// (with unread badge), settings, admin (admins only), Create, motif.
class AppSidebar extends StatelessWidget {
  static const double width = Responsive.sidebarWidth;

  /// Index of the highlighted tab, or -1 when a pushed page is showing.
  final int selectedIndex;

  /// Tab switching. Pushed pages pass null and navigate by route instead.
  final void Function(int index)? onSelect;

  const AppSidebar({super.key, required this.selectedIndex, this.onSelect});

  static const routes = ['/home', '/search', '/market', '/events', '/profile'];

  /// (icon, selected icon, label) per tab, in branch order. Single source
  /// for the bottom bar, the rail and this sidebar.
  static List<(IconData, IconData, String)> navItems(BuildContext context) {
    final s = context.l10n;
    return [
      (Icons.home_outlined, Icons.home, s.navHome),
      (Icons.search, Icons.saved_search, s.navSearch),
      (Icons.storefront_outlined, Icons.storefront, s.navMarket),
      (Icons.calendar_today_outlined, Icons.calendar_month, s.navEvents),
      (Icons.person_outline, Icons.person, s.navProfile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final items = navItems(context);
    final path = _currentPath(context);
    final onNotifications = path.startsWith('/notifications');
    final onSettings = path.startsWith('/settings');

    return Semantics(
      container: true,
      label: s.shell.mainNavigation,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thin lattice band along the top edge (structure, not
            // wallpaper).
            const LatticeBand(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.l, KSpace.m, KSpace.s),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.go('/home'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Wordmark(fontSize: 24),
                        ),
                      ),
                    ),
                  ),
                  for (int i = 0; i < items.length; i++)
                    SideNavTile(
                      icon: selectedIndex == i ? items[i].$2 : items[i].$1,
                      label: items[i].$3,
                      selected: selectedIndex == i,
                      onTap: () {
                        if (onSelect != null) {
                          onSelect!(i);
                        } else {
                          context.go(routes[i]);
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  Divider(height: 16, color: scheme.outlineVariant),
                  SideNavTile(
                    icon: onNotifications
                        ? Icons.notifications
                        : Icons.notifications_outlined,
                    label: s.notifications,
                    selected: onNotifications,
                    showUnread: true,
                    onTap: () {
                      if (!onNotifications) context.goNotifications();
                    },
                  ),
                  SideNavTile(
                    icon: onSettings ? Icons.settings : Icons.settings_outlined,
                    label: s.settings,
                    selected: onSettings,
                    onTap: () {
                      if (!onSettings) context.goSettings();
                    },
                  ),
                  const AdminNavEntry(),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => showCreateSheet(context),
                    icon: const Icon(Icons.add),
                    label: Text(s.shell.create),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const RoundedRectangleBorder(
                          borderRadius: KRadius.cut),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16, top: 8),
              child: KerawangDivider(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Path of the page this sidebar sits on; '' outside a go_router route.
String _currentPath(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.path;
  } catch (_) {
    return '';
  }
}

/// One sidebar row: ≥ 48 px tall, hover and pressed states, and a visible
/// focus ring for keyboard users on web.
class SideNavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Overlay the live unread-notification count on the icon.
  final bool showUnread;

  const SideNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showUnread = false,
  });

  @override
  State<SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<SideNavTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg =
        widget.selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final icon = Icon(widget.icon, size: 22, color: fg);
    const radius = BorderRadius.all(Radius.circular(12));

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: widget.selected,
        button: true,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          borderRadius: radius,
          hoverColor: scheme.onSurface.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: KMotion.of(context).fast,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.selected ? scheme.secondaryContainer : null,
              borderRadius: radius,
              border: Border.all(
                color: _focused ? KTokens.of(context).focusRing : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                widget.showUnread ? UnreadBadge(child: icon) : icon,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a pushed page so that on desktop it keeps the sidebar and stays
/// inside the content column, instead of unmounting the chrome and
/// sprawling across the window (H1.2). No-op below 900.
///
///   DesktopChrome(child: ...)                       // 680 reading column
///   DesktopChrome(maxWidth: 1000, child: ...)        // custom
///   DesktopChrome.detail(child: ...)                 // 1200, two-column details
class DesktopChrome extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const DesktopChrome({
    super.key,
    required this.child,
    this.maxWidth = Responsive.feedMaxWidth,
  });

  /// Detail pages (item / event / post) that lay out media and details
  /// side by side at ≥ 900: [Responsive.detailMaxWidth] wide.
  const DesktopChrome.detail({super.key, required this.child})
      : maxWidth = Responsive.detailMaxWidth;

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isDesktop(context)) return child;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSidebar(selectedIndex: -1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
