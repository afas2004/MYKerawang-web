import 'package:flutter/material.dart';
import 'package:flutter_parsed_text/flutter_parsed_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../language_cubit.dart';
import '../utils/app_nav.dart';

/// User-written text with tappable `@username` mentions (posts, comments,
/// event descriptions). Mentions use the primary colour; tapping one looks
/// the profile up and opens it.
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const MentionText(this.text, {super.key, this.style});

  static final mentionPattern = RegExp(r"\@(\w+)");

  Future<void> _open(BuildContext context, String mention) async {
    final user = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('username', mention.substring(1)) // drop '@'
        .maybeSingle();

    if (!context.mounted) return;
    if (user != null) {
      context.goUser(user['id']);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10nRead.userNotFound)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? TextStyle(color: scheme.onSurface);
    return ParsedText(
      text: text,
      style: base,
      parse: [
        MatchText(
          pattern: mentionPattern.pattern,
          style: base.copyWith(
              color: scheme.primary, fontWeight: FontWeight.bold),
          onTap: (mention) => _open(context, mention),
        ),
      ],
    );
  }
}
