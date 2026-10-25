/// Pure rules for announcements (no Flutter, no Supabase) so they can be
/// unit-tested and shared by the composer, the detail view and the card.
///
/// Announcements are `posts` rows with `is_announcement = true` plus the
/// v1.4 columns: cover_url, action_links (≤2 {label, url}),
/// linked_event_id, publish_at, feature_until, comments_enabled,
/// show_in_feed, announcement_category, club_id.
library;

// ---------------------------------------------------------------- categories

/// Stored values of posts.announcement_category (DB check constraint).
const kAnnouncementCategories = ['kolej', 'jpk', 'club', 'event', 'general'];

/// What a club officer may pick; admins get all of [kAnnouncementCategories].
const kClubAnnouncementCategories = ['club', 'event', 'general'];

// ---------------------------------------------------------------- limits

const kAnnouncementTitleMax = 120;
const kAnnouncementBodyMax = 5000;
const kAnnouncementExtraImagesMax = 4;
const kActionLinksMax = 2;
const kActionLabelMax = 24;

// ---------------------------------------------------------------- links

/// App routes an internal action link may point at (patterns over the
/// path only; query strings are ignored). Keep in sync with router.dart.
final List<RegExp> kInternalRoutePatterns = [
  for (final p in [
    r'/home',
    r'/announcements',
    r'/search',
    r'/market',
    r'/events',
    r'/clubs',
    r'/clubs/register',
    r'/post/[^/]+',
    r'/event/[^/]+',
    r'/item/[^/]+',
    r'/u/[^/]+',
    r'/c/[^/]+',
    r'/tag/[^/]+',
    r'/create/post',
    r'/create/event',
    r'/create/listing',
  ])
    RegExp('^$p/?\$'),
];

/// Whether [path] (e.g. "/event/abc?x=1") is a route of this app.
bool isKnownInternalRoute(String path) {
  final p = path.split('?').first.split('#').first;
  return kInternalRoutePatterns.any((r) => r.hasMatch(p));
}

enum ActionLinkIssue { emptyLabel, labelTooLong, emptyUrl, notHttps, unknownRoute, badUrl }

/// A call-to-action button on an announcement.
class ActionLink {
  final String label;
  final String url;

  const ActionLink(this.label, this.url);

  bool get isInternal => url.startsWith('/');

  Map<String, dynamic> toJson() => {'label': label.trim(), 'url': url.trim()};

  static ActionLink? fromJson(Object? j) {
    if (j is! Map) return null;
    final label = '${j['label'] ?? ''}'.trim();
    final url = '${j['url'] ?? ''}'.trim();
    if (label.isEmpty || url.isEmpty) return null;
    return ActionLink(label, url);
  }

  /// Parses posts.action_links (jsonb array); bad entries are dropped and
  /// at most [kActionLinksMax] kept.
  static List<ActionLink> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(fromJson)
        .whereType<ActionLink>()
        .where((l) => validateActionLink(l.label, l.url) == null)
        .take(kActionLinksMax)
        .toList();
  }
}

/// Validates one action button: label 1–24 chars; URL either an app
/// route ("/event/…") or an absolute https:// URL.
ActionLinkIssue? validateActionLink(String label, String url) {
  final l = label.trim();
  final u = url.trim();
  if (l.isEmpty) return ActionLinkIssue.emptyLabel;
  if (l.length > kActionLabelMax) return ActionLinkIssue.labelTooLong;
  if (u.isEmpty) return ActionLinkIssue.emptyUrl;
  if (u.startsWith('/')) {
    return isKnownInternalRoute(u) ? null : ActionLinkIssue.unknownRoute;
  }
  return validateHttpsUrl(u);
}

/// The URL half of [validateActionLink], for fields that only hold a link —
/// an event's registration page, which is launched the same way.
///
/// https only: a `javascript:` or `data:` URL in a saved event is code that
/// runs when a student taps the button.
ActionLinkIssue? validateHttpsUrl(String url) {
  final u = url.trim();
  if (u.isEmpty) return ActionLinkIssue.emptyUrl;
  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return ActionLinkIssue.badUrl;
  if (uri.scheme != 'https') return ActionLinkIssue.notHttps;
  return null;
}

// ---------------------------------------------------------------- draft

enum AnnouncementIssue {
  titleRequired,
  titleTooLong,
  bodyTooLong,
  categoryNotAllowed,
  tooManyImages,
  tooManyActions,
  badAction,
  featureBeforePublish,
}

/// Everything wrong with a draft (empty = publishable).
List<AnnouncementIssue> validateAnnouncement({
  required String title,
  required String body,
  required String? category,
  required List<String> allowedCategories,
  int extraImages = 0,
  List<ActionLink> actions = const [],
  DateTime? publishAt,
  DateTime? featureUntil,
}) {
  final issues = <AnnouncementIssue>[];
  final t = title.trim();
  if (t.isEmpty) issues.add(AnnouncementIssue.titleRequired);
  if (t.length > kAnnouncementTitleMax) issues.add(AnnouncementIssue.titleTooLong);
  if (body.length > kAnnouncementBodyMax) issues.add(AnnouncementIssue.bodyTooLong);
  if (category == null || !allowedCategories.contains(category)) {
    issues.add(AnnouncementIssue.categoryNotAllowed);
  }
  if (extraImages > kAnnouncementExtraImagesMax) issues.add(AnnouncementIssue.tooManyImages);
  if (actions.length > kActionLinksMax) issues.add(AnnouncementIssue.tooManyActions);
  if (actions.any((a) => validateActionLink(a.label, a.url) != null)) {
    issues.add(AnnouncementIssue.badAction);
  }
  if (featureUntil != null && !featureUntil.isAfter(publishAt ?? DateTime.now())) {
    issues.add(AnnouncementIssue.featureBeforePublish);
  }
  return issues;
}

// ---------------------------------------------------------------- feed rules

/// Whether a posts row belongs in the Home feed now: announcements can
/// opt out (show_in_feed = false) and scheduled ones wait for publish_at.
bool showInHomeFeed(Map<String, dynamic> post, {DateTime? now}) {
  if (post['show_in_feed'] == false) return false;
  final at = DateTime.tryParse('${post['publish_at'] ?? ''}');
  if (at != null && at.isAfter(now ?? DateTime.now())) return false;
  return true;
}

/// Comments default to on; announcements may turn them off.
bool commentsEnabled(Map<String, dynamic> post) => post['comments_enabled'] != false;

/// The app bar title of a post's page: the post's own headline, or a
/// generic label for one that has none.
///
/// [thread] is the fallback for an ordinary post, [announcement] for an
/// announcement without a headline.
String postPageTitle(
  Map<String, dynamic> post, {
  required String thread,
  required String announcement,
}) {
  final title = '${post['title'] ?? ''}'.trim();
  if (title.isNotEmpty) return title;
  return post['is_announcement'] == true ? announcement : thread;
}

// ---------------------------------------------------------------- formatting

/// Light formatting for announcement bodies: blank-line paragraphs,
/// "- " / "• " / "* " bullets, **bold**; links are detected when shown.
sealed class BodyBlock {
  const BodyBlock();
}

class ParagraphBlock extends BodyBlock {
  final String text;
  const ParagraphBlock(this.text);
}

class BulletsBlock extends BodyBlock {
  final List<String> items;
  const BulletsBlock(this.items);
}

final _bullet = RegExp(r'^\s*[-•*]\s+');

List<BodyBlock> parseBody(String body) {
  final blocks = <BodyBlock>[];
  final para = <String>[];
  final bullets = <String>[];
  void flushPara() {
    if (para.isNotEmpty) blocks.add(ParagraphBlock(para.join('\n')));
    para.clear();
  }

  void flushBullets() {
    if (bullets.isNotEmpty) blocks.add(BulletsBlock(List.of(bullets)));
    bullets.clear();
  }

  for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
    if (raw.trim().isEmpty) {
      flushPara();
      flushBullets();
    } else if (_bullet.hasMatch(raw)) {
      flushPara();
      bullets.add(raw.replaceFirst(_bullet, '').trim());
    } else {
      flushBullets();
      para.add(raw.trimRight());
    }
  }
  flushPara();
  flushBullets();
  return blocks;
}

/// A run of inline text: plain, **bold**, or a detected link.
class InlineSpan {
  final String text;
  final bool bold;
  final String? url;
  const InlineSpan(this.text, {this.bold = false, this.url});

  @override
  bool operator ==(Object other) =>
      other is InlineSpan && other.text == text && other.bold == bold && other.url == url;
  @override
  int get hashCode => Object.hash(text, bold, url);
  @override
  String toString() => 'InlineSpan($text${bold ? ', bold' : ''}${url != null ? ', $url' : ''})';
}

final _inline = RegExp(r'\*\*(.+?)\*\*|(https://[^\s)]+)');

/// Splits a line into plain / bold / link runs. Only https links are
/// linkified (same rule as action buttons).
List<InlineSpan> parseInline(String text) {
  final out = <InlineSpan>[];
  var i = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > i) out.add(InlineSpan(text.substring(i, m.start)));
    if (m.group(1) != null) {
      out.add(InlineSpan(m.group(1)!, bold: true));
    } else {
      var url = m.group(2)!;
      // Trailing punctuation belongs to the sentence, not the link.
      final trail = RegExp(r'[.,;:!?]+$').firstMatch(url)?.group(0) ?? '';
      url = url.substring(0, url.length - trail.length);
      out.add(InlineSpan(url, url: url));
      if (trail.isNotEmpty) out.add(InlineSpan(trail));
    }
    i = m.end;
  }
  if (i < text.length) out.add(InlineSpan(text.substring(i)));
  return out;
}
