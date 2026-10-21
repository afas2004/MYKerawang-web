import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../l10n/feed_strings.dart';
import '../screens/profile_cubit.dart';
import '../widgets/brand/brand.dart';

/// "Share something with kolej…" row at the top of the feed: your avatar,
/// the prompt, and a photo icon. The whole row opens the post editor
/// ([onTap], normally `context.goCreatePost()`).
class FeedComposer extends StatelessWidget {
  final VoidCallback onTap;

  /// Avatar to show; read from [ProfileCubit] when not given.
  final String? avatarUrl;

  const FeedComposer({super.key, required this.onTap, this.avatarUrl});

  String? _avatar(BuildContext context) {
    if (avatarUrl != null) return avatarUrl;
    try {
      return context.select<ProfileCubit, String?>(
          (c) => c.state.profile?['avatar_url'] as String?);
    } catch (_) {
      return null; // no ProfileCubit above (tests)
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = context.feedL10n.composerHintCompact;
    final avatar = _avatar(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KSpace.gutter, KSpace.s, KSpace.gutter, KSpace.xs),
      child: Semantics(
        button: true,
        label: hint,
        excludeSemantics: true,
        onTap: onTap,
        child: KCard(
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.xs, KSpace.xs, KSpace.xs),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null
                    ? Icon(AppIcons.person, size: 20, color: scheme.onPrimaryContainer)
                    : null,
              ),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              // Visual cue only — the whole row opens the editor.
              SizedBox(
                width: 48,
                height: 48,
                child: Icon(AppIcons.photo, size: 20, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
