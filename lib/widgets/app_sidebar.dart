import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../screens/announcements/hub_strings.dart';
import '../services/unread_notifications.dart';
import '../utils/app_nav.dart';
import 'admin_nav_entry.dart';
import 'clubs_nav_entry.dart';
import 'brand/brand.dart';
import 'profile_avatar_action.dart';
import 'shell_actions.dart';

/// Desktop sidebar (≥ 900), shared by the tab shell and by pushed pages
/// (detail/profile/settings) so the chrome never disappears mid-session
/// — UI_UX_AUDIT H1.2.
///
/// Top to bottom: wordmark, the tabs (Home, Announcements, Search, Market,
/// Events), then for members notifications (unread badge), settings,
/// admin (admins only), profile and Create; for guests Create (asks to log
/// in) and Sign in / Join with student email.
class AppSidebar extends StatelessWidget {
  static const double width = Responsive.sidebarWidth;

  /// Index of the highlighted tab, or -1 when a pushed page is showing.
  final int selectedIndex;

  /// Tab switching. Pushed pages pass null and navigate by route instead.
  final void Function(int index)? onSelect;

  const AppSidebar({super.key, required this.selectedIndex, this.onSelect});

  /// Tab routes in branch order (see ShellBranch in main_scaffold.dart).
  static const routes = [
    '/home',
    '/announcements',
    '/search',
    '/market',
    '/events',
  ];

  /// (icon, selected icon, label) per tab, in branch order. Single source
  /// for the bottom bar, the rail and this sidebar. [short] gives the
  /// compact Announcements label for the five-slot bottom bar / rail.
  static List<(IconData, IconData, String)> navItems(BuildContext context,
      {bool short = false}) {
    final s = context.l10n;
    return [
      (AppIcons.home, AppIcons.homeFilled, s.navHome),
      (
        AppIcons.announcement,
        AppIcons.announcement,
        short ? s.hub.navLabel : s.hub.title,
      ),
      (AppIcons.search, AppIcons.searchFilled, s.navSearch),
      (AppIcons.market, AppIcons.marketFilled, s.navMarket),
      (AppIcons.events, AppIcons.eventsFilled, s.navEvents),
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
    final loggedIn = ShellAuth.of(context);

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
                          padding: EdgeInsets.symmetric(horizontal: KSpace.s, vertical: KSpace.xs),
                          child: Wordmark(fontSize: 20),
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
                  const ClubsNavEntry(),
                  const SizedBox(height: KSpace.s),
                  Divider(height: 16, color: scheme.outlineVariant),
                  if (loggedIn) ...[
                    SideNavTile(
                      icon: onNotifications
                          ? AppIcons.notificationsActive
                          : AppIcons.notifications,
                      label: s.notifications,
                      selected: onNotifications,
                      showUnread: true,
                      onTap: () {
                        if (!onNotifications) context.goNotifications();
                      },
                    ),
                    SideNavTile(
                      icon: AppIcons.settings,
                      label: s.settings,
                      selected: onSettings,
                      onTap: () {
                        if (!onSettings) context.goSettings();
                      },
                    ),
                    const AdminNavEntry(),
                    const ProfileAvatarAction(extended: true),
                  ],
                  const SizedBox(height: KSpace.l),
                  FilledButton.icon(
                    onPressed: () => showCreateSheet(context),
                    icon: const Icon(AppIcons.create),
                    label: Text(s.shell.create),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  if (!loggedIn) ...[
                    const SizedBox(height: KSpace.xl),
                    const ProfileAvatarAction(extended: true),
                  ],
                ],
              ),
            ),
            const SizedBox(height: KSpace.l),
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
        widget.selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
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
            padding: const EdgeInsets.symmetric(horizontal: KSpace.m),
            decoration: BoxDecoration(
              color: widget.selected ? scheme.primaryContainer : null,
              borderRadius: radius,
              border: Border.all(
                color: _focused ? KTokens.of(context).focusRing : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                widget.showUnread ? UnreadBadge(child: icon) : icon,
                const SizedBox(width: KSpace.m),
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
