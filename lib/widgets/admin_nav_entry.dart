import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import 'app_sidebar.dart';

/// Sidebar link to /admin, rendered only for admins and the owner.
class AdminNavEntry extends StatelessWidget {
  const AdminNavEntry({super.key});

  @override
  Widget build(BuildContext context) {
    if (Supabase.instance.client.auth.currentUser == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<bool>(
      future: ModerationService.isAdmin(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        final path = GoRouter.maybeOf(context)
                ?.routeInformationProvider
                .value
                .uri
                .path ??
            '';
        final selected = path.startsWith('/admin');
        return SideNavTile(
          icon: selected ? Icons.shield : Icons.shield_outlined,
          label: context.l10n.mod.moderation,
          selected: selected,
          onTap: () => context.go('/admin'),
        );
      },
    );
  }
}
