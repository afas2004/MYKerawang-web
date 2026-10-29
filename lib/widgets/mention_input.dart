import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../utils/club_mentions.dart';
import '../utils/filter_rules.dart';
import 'mention_text.dart';

/// A text controller that marks mentions as you type: `@people` in bold
/// primary, club mentions (`@[handle]`) as a tinted highlight, so it is
/// clear the composer understood them. Only styling — the text is the
/// same characters the reader's page turns into links and chips.
class MentionEditingController extends TextEditingController {
  MentionEditingController({super.text});

  static final _any =
      RegExp('${clubMentionPattern.pattern}|${MentionText.mentionPattern.pattern}');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Leave IME composition (CJK input) to the default rendering.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final scheme = Theme.of(context).colorScheme;
    final children = <TextSpan>[];
    var i = 0;
    for (final m in _any.allMatches(text)) {
      if (m.start > i) children.add(TextSpan(text: text.substring(i, m.start)));
      final club = m.group(1) != null;
      children.add(TextSpan(
        text: m.group(0),
        style: club
            ? TextStyle(
                color: scheme.onSecondaryContainer,
                backgroundColor: scheme.secondaryContainer,
                fontWeight: FontWeight.w600,
              )
            : TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
      ));
      i = m.end;
    }
    if (i < text.length) children.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: style, children: children);
  }
}

class MentionInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isMultiLine;
  final bool reverseDirection; 

  /// Also suggest **clubs** while typing, not just `@people`.
  ///
  /// A club has a handle but no profile, so `@kerawang` would mention nobody
  /// (or the wrong person). A picked club inserts a club mention,
  /// `@[handle]`, which the page shows as a chip (see club_mentions.dart).
  final bool suggestClubs;

  /// Suggest `@people`. Off where a mention would notify nobody and only
  /// clubs make sense (the announcement body).
  final bool suggestPeople;

  /// Replaces the bare, borderless look (for a field with its own frame,
  /// helper text and counter).
  final InputDecoration? decoration;
  final int? maxLength;

  const MentionInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.isMultiLine = false,
    this.reverseDirection = false,
    this.style,
    this.minLines,
    this.maxLines,
    this.autofocus = false,
    this.focusNode,
    this.suggestClubs = false,
    this.suggestPeople = true,
    this.decoration,
    this.maxLength,
  });

  /// Lets callers focus the field (e.g. "Comment" on a post).
  final FocusNode? focusNode;

  /// Optional look overrides for full editors (create post).
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<Map<String, dynamic>>(
      // CONNECT YOUR CONTROLLER HERE
      controller: controller,
      focusNode: focusNode,

      // Force direction UP if we are at the bottom of the screen
      direction: reverseDirection ? VerticalDirection.up : VerticalDirection.down,
      
      hideOnEmpty: true,
      hideOnLoading: true,
      
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller, // Use the controller TypeAhead gives us
          focusNode: focusNode,
          autofocus: autofocus,
          style: style,
          minLines: minLines ?? 1,
          maxLines: maxLines ?? (isMultiLine ? 8 : 1),
          maxLength: maxLength,
          keyboardType: isMultiLine ? TextInputType.multiline : null,
          decoration: decoration ?? InputDecoration(
            hintText: hintText,
            hintStyle: style?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            filled: false,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        );
      },

      suggestionsCallback: (pattern) async {
        // 1. Get exact cursor position text
        final text = controller.text;
        final selection = controller.selection;
        
        // Safety check: If no cursor, don't search
        if (selection.baseOffset < 0) return null;

        // 2. Backtrack to find the start of the current word
        int start = selection.baseOffset - 1;
        while (start >= 0 && text[start] != ' ' && text[start] != '\n') {
          start--;
        }
        start++; // Move forward to the first character of the word

        // 3. Extract the word
        final currentWord = text.substring(start, selection.baseOffset);
        final isMention = currentWord.startsWith('@');

        // A bare "@" is too broad to search on.
        if (isMention && currentWord.length < 2) return null;
        // Bare words find clubs only in a one-line field (the co-organiser,
        // where the whole entry is a name); in a body that would pop up on
        // every word, so there it takes an "@".
        if (!isMention && (!suggestClubs || isMultiLine)) return null;
        if (!isMention && currentWord.length < 2) return null;

        final query = isMention ? currentWord.substring(1) : currentWord;
        // The club query goes into a `.or(...)` filter *string*, where `,`
        // and `()` mean structure. Strip them before building it.
        final safe = filterSafe(query);
        if (safe.isEmpty) return null;
        final out = <Map<String, dynamic>>[];

        // 4a. People, for an @mention.
        if (isMention && suggestPeople) {
          try {
            final res = await Supabase.instance.client
                .from('profiles')
                .select('id, username, avatar_url')
                .ilike('username', '$safe%')
                .limit(5);
            out.addAll(List<Map<String, dynamic>>.from(res));
          } catch (e) {
            debugPrint("DB Error: $e");
          }
        }

        // 4b. Clubs, by name or handle, typed bare or after "@". These
        //      insert as a club mention, `@[handle]`, never `@handle`:
        //      a club has no profile to notify.
        if (suggestClubs) {
          try {
            final res = await Supabase.instance.client
                .from('clubs')
                .select('name, handle')
                .eq('status', 'active')
                .or('name.ilike.%$safe%,handle.ilike.%$safe%')
                .limit(5);
            out.addAll([
              for (final c in List<Map<String, dynamic>>.from(res))
                {...c, 'kind': 'club'},
            ]);
          } catch (e) {
            debugPrint("Club search failed: $e");
          }
        }

        return out.isEmpty ? null : out;
      },

      itemBuilder: (context, user) {
        final isClub = user['kind'] == 'club';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            backgroundImage:
                !isClub && user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
            radius: 14,
            child: isClub
                ? const Icon(Icons.groups, size: 14)
                : (user['avatar_url'] == null ? const Icon(Icons.person, size: 14) : null),
          ),
          title: Text(isClub ? '${user['name']}' : (user['username'] ?? 'User')),
          subtitle: isClub ? Text('@${user['handle']}') : null,
          dense: true,
        );
      },

      onSelected: (user) {
        final text = controller.text;
        final selection = controller.selection;
        
        // Find start of word again to replace it
        int start = selection.baseOffset - 1;
        while (start >= 0 && text[start] != ' ' && text[start] != '\n') {
          start--;
        }
        start++; 

        // A club becomes "@[handle] " (a chip on the page); a person
        // becomes "@username ".
        final insert = user['kind'] == 'club'
            ? '${clubMentionToken('${user['handle']}')} '
            : "@${user['username']} ";
        final newText = text.replaceRange(start, selection.baseOffset, insert);
        
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start + insert.length),
        );
      },
    );
  }
}