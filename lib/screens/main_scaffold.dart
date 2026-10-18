import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/responsive.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/right_rail.dart';

/// Shell around the five main tabs. The tab bodies and their state are
/// owned by go_router's StatefulShellRoute, so each tab keeps its scroll
/// position and the browser URL always matches the visible tab.
class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int get _selectedIndex => widget.navigationShell.currentIndex;

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      // Tapping the active tab returns it to its root.
      initialLocation: index == _selectedIndex,
    );
  }

  // Single source of truth, shared with the desktop sidebar.
  List<(IconData, IconData, String)> _navItems(BuildContext context) =>
      AppSidebar.navItems(context);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final isDesktop = width >= Responsive.desktopBreakpoint;
      final showRail = width >= Responsive.railBreakpoint;

      if (!isDesktop) return _buildMobile(context);
      return _buildDesktop(context, showRail);
    });
  }

  // ---------- MOBILE: bottom tabs (unchanged behavior) ----------
  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final navItems = _navItems(context);
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedIndex: _selectedIndex,
          onDestinationSelected: _goBranch,
          indicatorColor: scheme.secondaryContainer,
          destinations: navItems
              .map((item) => NavigationDestination(
                    icon: Icon(item.$1, color: scheme.onSurfaceVariant),
                    selectedIcon:
                        Icon(item.$2, color: scheme.onSecondaryContainer),
                    label: item.$3,
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ---------- DESKTOP: sidebar + content + optional right rail ----------
  Widget _buildDesktop(BuildContext context, bool showRail) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- SIDEBAR (shared with pushed pages — see AppSidebar) ---
          AppSidebar(selectedIndex: _selectedIndex, onSelect: _goBranch),

          // --- MAIN CONTENT ---
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: Responsive.feedMaxWidth),
                child: widget.navigationShell,
              ),
            ),
          ),

          // --- RIGHT RAIL (wide screens only) ---
          if (showRail) const RightRail(),
        ],
      ),
    );
  }
}

