import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'marketplace_screen.dart';
import 'events_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'create_post_screen.dart';
import '../utils/responsive.dart';
import '../widgets/kerawang_motif.dart';
import '../widgets/right_rail.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  // This function allows children (like Home) to switch tabs
  void _switchTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  static const _navItems = [
    (Icons.home_outlined, Icons.home, 'Utama'),
    (Icons.search, Icons.saved_search, 'Cari'),
    (Icons.storefront_outlined, Icons.storefront, 'Pasar'),
    (Icons.calendar_today_outlined, Icons.calendar_month, 'Acara'),
    (Icons.person_outline, Icons.person, 'Profil'),
  ];

  List<Widget> get _pages => [
    HomeScreen(onTabChange: _switchTab),
    const SearchScreen(),
    const MarketplaceScreen(),
    const EventsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final isDesktop = width >= 900;
      final showRail = width >= 1150;

      if (!isDesktop) return _buildMobile(context);
      return _buildDesktop(context, showRail);
    });
  }

  // ---------- MOBILE: bottom tabs (unchanged behavior) ----------
  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
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
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          indicatorColor: scheme.secondaryContainer,
          destinations: _navItems
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- SIDEBAR ---
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                right: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 20),
                  child: Text(
                    "MYKerawang",
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
                for (int i = 0; i < _navItems.length; i++)
                  _SideNavTile(
                    icon: _selectedIndex == i ? _navItems[i].$2 : _navItems[i].$1,
                    label: _navItems[i].$3,
                    selected: _selectedIndex == i,
                    onTap: () => setState(() => _selectedIndex = i),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text("Jom post"),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const Spacer(),
                const KerawangDivider(),
                const SizedBox(height: 4),
              ],
            ),
          ),

          // --- MAIN CONTENT ---
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: Responsive.feedMaxWidth),
                child: IndexedStack(index: _selectedIndex, children: _pages),
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

class _SideNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavTile({
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
