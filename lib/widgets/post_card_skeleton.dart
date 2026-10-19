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
          horizontal: KSpace.gutter, vertical: KSpace.s - 2),
      child: KCard(
        padding: const EdgeInsets.all(KSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                KSkeleton.circle(size: 40),
                SizedBox(width: KSpace.m),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KSkeleton(width: 140, height: 12),
                    SizedBox(height: KSpace.s - 2),
                    KSkeleton(width: 80, height: 10),
                  ],
                ),
              ],
            ),
            const SizedBox(height: KSpace.l),
            const KSkeleton(width: 220, height: 18),
            const SizedBox(height: KSpace.m),
            KSkeleton.lines(2),
            if (withPhoto) ...[
              const SizedBox(height: KSpace.m),
              const AspectRatio(
                aspectRatio: 4 / 3,
                child: KSkeleton(height: double.infinity, borderRadius: KRadius.cut),
              ),
            ],
            const SizedBox(height: KSpace.l),
            const Row(
              children: [
                KSkeleton(width: 56, height: 20),
                SizedBox(width: KSpace.l),
                KSkeleton(width: 24, height: 20),
                SizedBox(width: KSpace.l),
                KSkeleton(width: 24, height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
