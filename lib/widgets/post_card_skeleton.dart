import 'package:flutter/material.dart';

import '../l10n/post_strings.dart';
import 'brand/brand.dart';

/// Placeholder with the shape of a [PostCard] while posts load, so the
/// feed doesn't jump from a spinner to content. Built from [KSkeleton]
/// (shimmer, static under reduced motion) inside a [KCard].
///
/// Use [PostCardSkeleton.list] for a whole loading feed.
class PostCardSkeleton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KSpace.gutter, vertical: KSpace.m / 2),
      child: KCard(
        padding: const EdgeInsets.all(KSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                KSkeleton.circle(size: 40),
                SizedBox(width: KSpace.m),
                KSkeleton(width: 120, height: 12),
                SizedBox(width: KSpace.s),
                KSkeleton(width: 72, height: 10),
              ],
            ),
            const SizedBox(height: KSpace.m),
            const KSkeleton(width: 200, height: 16),
            const SizedBox(height: KSpace.m),
            KSkeleton.lines(2),
            if (withPhoto) ...[
              const SizedBox(height: KSpace.m),
              const AspectRatio(
                aspectRatio: 4 / 3,
                child: KSkeleton(height: double.infinity, borderRadius: KRadius.card),
              ),
            ],
            const SizedBox(height: KSpace.l),
            const Row(
              children: [
                KSkeleton(width: 40, height: 20),
                SizedBox(width: KSpace.xl),
                KSkeleton(width: 20, height: 20),
                SizedBox(width: KSpace.xl),
                KSkeleton(width: 20, height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
