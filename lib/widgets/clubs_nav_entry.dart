import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import 'app_sidebar.dart';
import 'brand/brand.dart';

/// Sidebar link to the club directory (/clubs). Shown to everyone: the
/// directory and club pages are public, unlike the signed-in account rows.
class ClubsNavEntry extends StatelessWidget {
  const ClubsNavEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final path = GoRouter.maybeOf(context)
            ?.routeInformationProvider
            .value
            .uri
            .path ??
        '';
    final selected = path == '/clubs' ||
        path.startsWith('/clubs/') ||
        path.startsWith('/c/');
    return SideNavTile(
      icon: AppIcons.people,
      label: context.l10n.shell.clubs,
      selected: selected,
      // Pushed like Settings, so back returns to where you were.
      onTap: () {
        if (!selected) context.push('/clubs');
      },
    );
  }
}
