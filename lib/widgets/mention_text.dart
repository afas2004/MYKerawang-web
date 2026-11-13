import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../language_cubit.dart';
import '../services/allowed_links.dart';
import '../utils/app_nav.dart';
import '../utils/club_mentions.dart';
import '../utils/safe_links.dart';
import '../utils/url_rules.dart';
import 'club_mention_chip.dart';
import 'app_toast.dart';

/// One piece of [MentionText]'s text.
sealed class MentionPart {
  const MentionPart();
}

class PlainPart extends MentionPart {
  final String text;
  const PlainPart(this.text);
}

class UserMentionPart extends MentionPart {
  /// As written, with the '@'.
  final String text;
  const UserMentionPart(this.text);
}

class ClubMentionPart extends MentionPart {
  final String handle;
  const ClubMentionPart(this.handle);
}

/// A link to an allowed site. Links to other sites are [PlainPart]s.
class LinkPart extends MentionPart {
  /// As written.
  final String text;
  final Uri uri;
  const LinkPart(this.text, this.uri);

  /// What's shown (long links end in "…").
  String get label => linkLabel(text);
}

/// User-written text with tappable `@username` mentions (posts, comments,
/// event descriptions). Mentions use the primary colour; tapping one looks
/// the profile up and opens it. Club mentions (`@[handle]`) show as chips.
///
/// Web links are tappable only for sites on the allowed list
/// ([AllowedLinks]); they're underlined in the link colour, shortened to
/// about 40 characters, and open in a new tab (links to this app open
/// inside it). Any other link is left as plain, untappable text.
class MentionText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Cap on lines (feed cards); null = unlimited.
  final int? maxLines;

  const MentionText(this.text, {super.key, this.style, this.maxLines});

  static final mentionPattern = RegExp(r"\@(\w+)");

  /// Links first: a link that contains `@name` stays one link.
  static final _tokens = RegExp(
      '(${linkPattern.pattern})|(${clubMentionPattern.pattern})|(${mentionPattern.pattern})');

  /// [text] split into plain text, mentions and allowed links.
  static List<MentionPart> parse(String text, Iterable<String> allowed) {
    final parts = <MentionPart>[];
    final plain = StringBuffer();
    void flush() {
      if (plain.isNotEmpty) parts.add(PlainPart(plain.toString()));
      plain.clear();
    }

    var at = 0;
    for (final m in _tokens.allMatches(text)) {
      plain.write(text.substring(at, m.start));
      at = m.end;
      final raw = m[1];
      if (raw != null) {
        final link = trimLinkEnd(raw);
        final uri = allowedLinkUri(link, allowed);
        if (uri == null) {
          plain.write(raw); // not allowed: plain text, unchanged
        } else {
          flush();
          parts.add(LinkPart(link, uri));
          // Trimmed sentence punctuation stays ordinary text.
          plain.write(raw.substring(link.length));
        }
      } else if (m[2] != null) {
        flush();
        parts.add(ClubMentionPart(clubMentionPattern.firstMatch(m[0]!)!.group(1)!));
      } else {
        flush();
        parts.add(UserMentionPart(m[0]!));
      }
    }
    plain.write(text.substring(at));
    flush();
    return parts;
  }

  /// [text] as it reads on screen (long links shortened), for measuring.
  static String displayText(String text, [Iterable<String>? allowed]) =>
      parse(text, allowed ?? AllowedLinks.current)
          .map((p) => switch (p) {
                PlainPart(:final text) => text,
                UserMentionPart(:final text) => text,
                ClubMentionPart(:final handle) => clubMentionToken(handle),
                LinkPart() => p.label,
              })
          .join();

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  Future<void> _openUser(String mention) async {
    final user = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('username', mention.substring(1)) // drop '@'
        .maybeSingle();

    if (!mounted) return;
    if (user != null) {
      context.goUser(user['id']);
    } else {
      showToast(context.l10nRead.userNotFound);
    }
  }

  Future<void> _openLink(Uri uri) async {
    if (isAppLink(uri)) {
      context.push(appRouteOf(uri));
      return;
    }
    final safe = launchableUri(uri.toString());
    if (safe == null) return;
    try {
      await launchUrl(safe,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (e) {
      debugPrint('MentionText: could not open $safe: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: AllowedLinks.listenable,
      builder: (context, allowed, _) => _build(context, allowed),
    );
  }

  Widget _build(BuildContext context, Set<String> allowed) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = widget.style ?? TextStyle(color: scheme.onSurface);
    final mentionStyle =
        base.copyWith(color: scheme.primary, fontWeight: FontWeight.bold);
    // The theme's link colour (primary in this app's schemes).
    final linkStyle = base.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );

    final spans = <InlineSpan>[
      for (final p in MentionText.parse(widget.text, allowed))
        switch (p) {
          PlainPart(:final text) => TextSpan(text: text),
          UserMentionPart(:final text) => TextSpan(
              text: text,
              style: mentionStyle,
              recognizer: _tap(() => _openUser(text))),
          ClubMentionPart(:final handle) => WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              // The chip opens the club itself.
              child: ClubMentionChip(handle, style: base)),
          LinkPart(:final uri) => TextSpan(
              text: p.label,
              style: linkStyle,
              semanticsLabel: p.text,
              mouseCursor: SystemMouseCursors.click,
              recognizer: _tap(() => _openLink(uri))),
        },
    ];

    return RichText(
      // No text scaling, as before (ParsedText's default).
      textScaler: TextScaler.noScaling,
      maxLines: widget.maxLines,
      overflow:
          widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      text: TextSpan(style: base, children: spans),
    );
  }
}
