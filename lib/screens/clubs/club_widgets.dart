import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../widgets/brand/brand.dart';
import 'club_strings.dart';

/// Rounded-square club logo with an initial when there's no image.
/// A club's colour until officers can choose one (that needs a database
/// column): from its category, else from its handle. Always one of the six
/// brand colours, all safe under white text.
Color clubColor(Club club) => switch (club.category) {
      'academic' => KPalette.plum,
      'arts' => KPalette.jingga,
      'sports' => KPalette.hijauPucuk,
      'religious' => KPalette.hijauPucuk,
      'volunteer' => KPalette.merahSaga,
      'tech' => KPalette.biruLaut,
      'business' => KPalette.kelabuArang,
      _ => KPalette.forKey(club.handle),
    };

/// The stitch motif on a club's generated cover, where its category has an
/// obvious one; otherwise the pattern alone.
AppMotif? clubMotif(Club club) => switch (club.category) {
      'arts' => AppMotif.wauBulan,
      'sports' => AppMotif.wauKucing,
      'business' => AppMotif.nasiLemak,
      _ => null,
    };

/// A club's cover: its photo, or a cover generated from its handle in the
/// club colour, with the category motif.
class ClubCover extends StatelessWidget {
  final Club club;
  const ClubCover({super.key, required this.club});

  @override
  Widget build(BuildContext context) {
    final generated = BrandCover(
      seed: club.handle,
      color: clubColor(club),
      motif: clubMotif(club),
    );
    final url = club.coverUrl;
    if (url == null || url.isEmpty) return generated;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => generated,
      errorWidget: (_, __, ___) => generated,
    );
  }
}

class ClubLogo extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  /// Fill behind the initial when there's no logo (the club colour);
  /// the soft primary tint when null.
  final Color? color;

  const ClubLogo({super.key, required this.url, required this.name, this.size = 48, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.28);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color ?? scheme.primaryContainer, borderRadius: radius),
      child: Text(initial,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: color != null ? Colors.white : scheme.onPrimaryContainer, fontSize: size * 0.42)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => fallback,
        placeholder: (_, __) => fallback,
      ),
    );
  }
}

/// Name + verified tick, ellipsised.
class ClubNameLine extends StatelessWidget {
  final String name;
  final bool verified;
  final TextStyle? style;

  const ClubNameLine({super.key, required this.name, required this.verified, this.style});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
        if (verified) ...[
          const SizedBox(width: KSpace.xs),
          Icon(AppIcons.verified, size: 18, color: scheme.tertiary),
        ],
      ],
    );
  }
}

/// Officer-only banner for pending / rejected / suspended clubs.
class ClubStatusBanner extends StatelessWidget {
  final String status;
  const ClubStatusBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'active') return const SizedBox.shrink();
    final c = context.l10n.club;
    final scheme = Theme.of(context).colorScheme;
    final text = switch (status) {
      'pending' => c.pendingBanner,
      'rejected' => c.rejectedBanner,
      _ => c.suspendedBanner,
    };
    final warn = status != 'pending';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KSpace.m),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(warn ? AppIcons.warning : AppIcons.clock,
              size: 20, color: warn ? scheme.onErrorContainer : scheme.onTertiaryContainer),
          const SizedBox(width: KSpace.s),
          Expanded(
            child: Text(text,
                style: TextStyle(color: warn ? scheme.onErrorContainer : scheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }
}

/// Small pill (role, status, category).
class ClubPill extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;
  const ClubPill(this.label, {super.key, this.background, this.foreground});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s + 2, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: foreground ?? scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
    );
  }
}

/// Copy for a failed club call (`CLUB:<code>`), else [fallback] / generic.
String clubErrorText(ClubStrings c, Object e, {String? fallback}) => switch (clubErrorCode(e)) {
      'handle_invalid' => c.handleBadChars,
      'handle_taken' => c.handleTaken,
      'name_invalid' => c.nameInvalid,
      'proof_required' => c.proofTooShort,
      'too_many_pending' => c.tooManyPending,
      'email_invalid' => c.emailInvalid,
      'user_not_found' => c.userNotFound,
      'already_officer' => c.alreadyOfficer,
      'too_many_officers' => c.tooManyOfficers,
      'president_must_transfer' => c.presidentMustTransfer,
      'not_officer' => c.notOfficer,
      'not_president' => c.notPresident,
      'not_pending' => c.notPending,
      'registry_claimed' => c.registryClaimedError,
      'registry_not_found' => c.registryNotFound,
      'registry_code_taken' => c.registryCodeTaken,
      'registry_code_invalid' => c.registryCodeInvalid,
      'position_invalid' => c.positionInvalid,
      'council_invalid' => c.councilInvalid,
      'council_too_long' => c.councilTooLong,
      'already_member' => c.alreadyMember,
      'not_member' => c.notMember,
      'cannot_change_president' => c.cannotChangePresident,
      'role_invalid' => c.roleInvalid,
      'not_active' => c.clubNotActive,
      'already_requested' => c.alreadyRequested,
      'request_not_found' => c.requestNotFound,
      _ => fallback ?? c.genericError,
    };

String? handleIssueText(ClubStrings c, HandleIssue? issue) => switch (issue) {
      null => null,
      HandleIssue.empty || HandleIssue.tooShort => c.handleTooShort,
      HandleIssue.tooLong => c.handleTooLong,
      HandleIssue.badChars => c.handleBadChars,
    };

void showClubSnack(BuildContext context, String text, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? scheme.errorContainer : null,
      showCloseIcon: error,
      closeIconColor: error ? scheme.onErrorContainer : null,
    ));
}

/// Plain yes/no confirmation.
Future<bool> confirmClubAction(BuildContext context,
    {required String title, required String body, required String confirmLabel, bool destructive = false}) async {
  final c = context.l10nRead.club;
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(c.cancel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
