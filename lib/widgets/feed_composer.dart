import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../l10n/feed_strings.dart';
import '../language_cubit.dart';
import '../screens/create_post_screen.dart';
import '../screens/profile_cubit.dart';
import '../widgets/brand/brand.dart';

/// Composer launcher at the top of the feed, on every size
/// (Threads-style). Compact (<600): a slim row — avatar, hint, photo
/// shortcut — that opens the full-screen editor. Wider: a card that opens
/// the editor as a dialog over the feed.
class FeedComposer extends StatelessWidget {
  final VoidCallback onPosted;

  /// Avatar to show; read from [ProfileCubit] when not given.
  final String? avatarUrl;

  const FeedComposer({super.key, required this.onPosted, this.avatarUrl});

  Future<void> _open(BuildContext context) async {
    if (await openPostComposer(context)) onPosted();
  }

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
    final fs = context.feedL10n;
    final compact =
        MediaQuery.sizeOf(context).width < kComposerDialogBreakpoint;
    final avatar = _avatar(context);

    final hint = compact ? fs.composerHintCompact : context.l10n.composerHint;

    return Padding(
      padding: EdgeInsets.fromLTRB(KSpace.gutter, compact ? KSpace.s : KSpace.m, KSpace.gutter, KSpace.xs),
      child: Semantics(
        button: true,
        label: hint,
        excludeSemantics: true,
        onTap: () => _open(context),
        child: Material(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: KRadius.card,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(context),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: KSpace.m, vertical: compact ? KSpace.xs : KSpace.s),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null
                        ? Icon(AppIcons.person,
                            size: 18, color: scheme.onPrimaryContainer)
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
                  // Visual shortcut only — the whole row opens the editor.
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(AppIcons.photo,
                          size: 20, color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
