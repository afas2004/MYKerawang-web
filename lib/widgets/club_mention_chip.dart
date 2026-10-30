import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/clubs/club_widgets.dart' show ClubLogo, clubColor;
import '../services/club_service.dart';
import 'brand/brand.dart';

/// Active clubs by lowercase handle, loaded once on the first mention shown,
/// so a page of chips costs one query. Chips rebuild when it arrives.
abstract final class ClubMentionDirectory {
  static final clubs = ValueNotifier<Map<String, Club>>(const {});
  static Future<void>? _loading;

  @visibleForTesting
  static void debugSet(List<Club> list) {
    _loading = Future.value();
    clubs.value = {for (final c in list) c.handle.toLowerCase(): c};
  }

  static void ensureLoaded() {
    _loading ??= () async {
      try {
        debugSet(await ClubService.directory(limit: 500));
      } catch (e) {
        debugPrint('Club mentions: $e');
      }
    }();
  }

  /// Handle → name, for plain-text previews.
  static Map<String, String> get names =>
      {for (final e in clubs.value.entries) e.key: e.value.name};
}

/// A club mention in a live page: a soft pill in the club's colour with its
/// logo and name; tapping opens the club. An unknown handle (no such club,
/// or the list still loading) shows as `@handle`.
class ClubMentionChip extends StatelessWidget {
  final String handle;
  final TextStyle? style;

  const ClubMentionChip(this.handle, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    ClubMentionDirectory.ensureLoaded();
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Map<String, Club>>(
      valueListenable: ClubMentionDirectory.clubs,
      builder: (context, clubs, _) {
        final club = clubs[handle.toLowerCase()];
        final tint = club == null ? scheme.primary : clubColor(club);
        // Club colours are deep; on a dark ground they need more light.
        final dark = Theme.of(context).brightness == Brightness.dark;
        final text = (style ?? DefaultTextStyle.of(context).style).copyWith(
          color: Color.lerp(tint, scheme.onSurface, dark ? 0.7 : 0.25),
          fontWeight: FontWeight.w600,
          height: 1.2,
        );
        final size = (text.fontSize ?? 14) + 4;
        return Semantics(
          link: true,
          label: club?.name ?? '@$handle',
          excludeSemantics: true,
          child: Material(
            color: tint.withValues(alpha: dark ? 0.3 : 0.12),
            shape: StadiumBorder(
                side: BorderSide(color: tint.withValues(alpha: dark ? 0.8 : 0.35))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.push('/c/$handle'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 2, 8, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (club != null)
                      ClubLogo(url: club.logoUrl, name: club.name, size: size, color: tint)
                    else
                      Icon(AppIcons.people, size: size - 4, color: tint),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        club?.name ?? '@$handle',
                        style: text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
