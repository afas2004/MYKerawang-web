import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../language_cubit.dart';
import '../screens/create_post_screen.dart';
import '../screens/profile_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';

/// Threads-style composer at the top of the web feed (DESIGN_SPEC.md §4).
/// Acts as a launcher: on wide screens the create-post flow opens as a
/// centered dialog so posting feels like it never leaves the feed;
/// on smaller screens it pushes the normal screen.
class FeedComposer extends StatelessWidget {
  final VoidCallback onPosted;

  const FeedComposer({super.key, required this.onPosted});

  Future<void> _open(BuildContext context) async {
    final wide = isWide(context);

    final bool? posted = wide
        ? await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(borderRadius: kerawangCut),
              child: ConstrainedBox(
                // Sized to the form rather than a fixed tall box, so the
                // dialog doesn't trail empty space below the tags (H4/2.1)
                constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
                child: const CreatePostScreen(),
              ),
            ),
          )
        : await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );

    if (posted == true) onPosted();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarUrl =
        context.watch<ProfileCubit>().state.profile?['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: kerawangCut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: kerawangCut,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Icon(Icons.person,
                        size: 20, color: scheme.onPrimaryContainer)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.composerHint,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Icon(Icons.edit_outlined, size: 20, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
