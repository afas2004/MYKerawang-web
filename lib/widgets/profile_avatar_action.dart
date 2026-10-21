import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../language_cubit.dart';
import '../screens/announcements/hub_strings.dart';
import '../screens/profile_cubit.dart';
import '../utils/guest_access.dart';
import 'brand/brand.dart';

/// Signed-in state for the shell chrome. Rebuilds the caller when the
/// session changes (via [ProfileCubit], which reloads on auth events).
abstract final class ShellAuth {
  /// Tests: force signed in / out without Supabase.
  @visibleForTesting
  static bool? debugLoggedIn;

  static bool of(BuildContext context) {
    if (debugLoggedIn != null) return debugLoggedIn!;
    // Subscribe to profile/auth changes when the cubit is available.
    try {
      context.watch<ProfileCubit>();
    } catch (_) {
      // No ProfileCubit above (isolated widget tests).
    }
    try {
      return isLoggedIn;
    } catch (_) {
      return false; // Supabase not initialised (tests)
    }
  }

  /// Avatar URL of the signed-in user, when loaded.
  static String? avatarUrl(BuildContext context) {
    try {
      return context.select<ProfileCubit, String?>(
          (c) => c.state.profile?['avatar_url'] as String?);
    } catch (_) {
      return null;
    }
  }
}

/// The account entry point other screens put in their app bars:
///
/// * signed in → the user's avatar; tap opens their profile (/profile)
/// * guest     → a "Sign in" button that returns here after login
///
///   AppBar(actions: [..., const ProfileAvatarAction()])
///
/// [extended] is the sidebar version: a full-width row with a label
/// ("Your profile") or the sign-in + "Join with student email" pair.
class ProfileAvatarAction extends StatelessWidget {
  final bool extended;

  /// Icon-only sign-in for tight spots (the navigation rail).
  final bool compactGuest;

  const ProfileAvatarAction({super.key, this.extended = false, this.compactGuest = false});

  static void openProfile(BuildContext context) => context.push('/profile');

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final loggedIn = ShellAuth.of(context);

    if (!loggedIn) {
      if (extended) return const _GuestPanel();
      if (compactGuest) {
        return IconButton(
          tooltip: s.hub.signIn,
          icon: const Icon(AppIcons.login),
          onPressed: () => goToLogin(context),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.xs),
        child: FilledButton.tonal(
          onPressed: () => goToLogin(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
          ),
          child: Text(s.hub.signIn),
        ),
      );
    }

    final avatar = _Avatar(url: ShellAuth.avatarUrl(context), radius: extended ? 16 : 15);
    if (extended) {
      final theme = Theme.of(context);
      return InkWell(
        borderRadius: KRadius.input,
        onTap: () => openProfile(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.m),
            child: Row(children: [
              avatar,
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Text(s.hub.yourProfile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: s.hub.yourProfile,
      icon: avatar,
      onPressed: () => openProfile(context),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final double radius;
  const _Avatar({required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: url != null ? CachedNetworkImageProvider(url!) : null,
      child: url == null
          ? Icon(AppIcons.person, size: radius, color: scheme.onPrimaryContainer)
          : null,
    );
  }
}

/// Sidebar block for guests: tagline, Sign in, Join with student email.
class _GuestPanel extends StatelessWidget {
  const _GuestPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.xs),
          child: Text(s.hub.guestTagline,
              style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: KSpace.m),
        FilledButton(
          onPressed: () => goToLogin(context),
          child: Text(s.hub.signIn),
        ),
        const SizedBox(height: KSpace.s),
        OutlinedButton(
          onPressed: () => goToLogin(context),
          child: Text(s.hub.joinWithStudentEmail,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
