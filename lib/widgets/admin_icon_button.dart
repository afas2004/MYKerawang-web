import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import 'brand/brand.dart';

/// Shield shortcut to /admin, rendered only for admins and the owner.
/// Used by the navigation rail and the profile app bar.
class AdminIconButton extends StatelessWidget {
  const AdminIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ModerationService.isAdmin(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return IconButton(
          tooltip: context.l10n.mod.moderation,
          icon: const Icon(AppIcons.moderation),
          onPressed: () => context.push('/admin'),
        );
      },
    );
  }
}
