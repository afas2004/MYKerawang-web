import 'package:flutter/material.dart';

import '../l10n/post_strings.dart';
import '../theme/app_themes.dart';

/// Placeholder with the shape of a [PostCard] while posts load, so the
/// feed doesn't jump from a spinner to content. Pulses gently unless the
/// platform asks for reduced motion.
///
/// Use [PostCardSkeleton.list] for a whole loading feed.
class PostCardSkeleton extends StatefulWidget {
  /// Show a photo block (alternate in lists so it looks like a real feed).
  final bool withPhoto;

  const PostCardSkeleton({super.key, this.withPhoto = false});

  /// [count] skeletons as one list, announced once to screen readers.
  static Widget list(BuildContext context, {int count = 4}) => Semantics(
        label: context.postL10n.loadingPosts,
        liveRegion: true,
        child: ExcludeSemantics(
          child: Column(
            children: [
              for (var i = 0; i < count; i++)
                PostCardSkeleton(withPhoto: i % 3 == 1),
            ],
          ),
        ),
      );

  @override
  State<PostCardSkeleton> createState() => _PostCardSkeletonState();
}

class _PostCardSkeletonState extends State<PostCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _pulse.value = 0.5;
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget bar(double width, double height, {BorderRadius? radius}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: radius ?? BorderRadius.circular(4),
          ),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: kerawangCut,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      color: theme.cardColor,
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  bar(32, 32, radius: BorderRadius.circular(16)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(120, 12),
                      const SizedBox(height: 6),
                      bar(60, 10),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              bar(220, 16),
              const SizedBox(height: 10),
              bar(double.infinity, 12),
              const SizedBox(height: 6),
              bar(180, 12),
              if (widget.withPhoto) ...[
                const SizedBox(height: 12),
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: bar(double.infinity, double.infinity,
                      radius: kerawangCut),
                ),
              ],
              const SizedBox(height: 16),
              bar(90, 12),
            ],
          ),
        ),
      ),
    );
  }
}
