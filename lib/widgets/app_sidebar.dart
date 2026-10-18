import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../screens/create_post_screen.dart';
import '../utils/responsive.dart';
import 'kerawang_motif.dart';

/// Sidebar navigation, shared by the tab shell and by pushed pages
/// (detail/profile/settings) so the chrome never disappears mid-session
/// — UI_UX_AUDIT H1.2.
class AppSidebar extends StatelessWidget {
  /// Index of the highlighted tab, or -1 when a pushed page is showing.
  final int selectedIndex;

  /// Tab switching. Pushed pages pass null and navigate by route instead.
  final void Function(int index)? onSelect;

  const AppSidebar({super.key, required this.selectedIndex, this.onSelect});

  static const routes = ['/home', '/search', '/market', '/events', '/profile'];

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
    final items = navItems(context);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 20),
            child: InkWell(
              onTap: () => context.go('/home'),
              child: Text(
                AppStrings.appName,
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
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
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
            ),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.createPost),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const Spacer(),
          const KerawangDivider(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class SideNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SideNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? scheme.secondaryContainer : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a pushed page so that on desktop it keeps the sidebar and stays
/// inside the content column, instead of unmounting the chrome and
/// sprawling across the window (H1.2). No-op on phones.
class DesktopChrome extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const DesktopChrome({super.key, required this.child, this.maxWidth = 680});

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
