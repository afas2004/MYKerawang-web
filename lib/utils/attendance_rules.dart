/// Pure helpers for the attendance flow: the names shown while people check in,
/// the CSV the organiser exports, and the organiser's contact links.
///
/// Kept out of the widgets so the rules are testable without a browser.
library;

/// The part of a name worth showing on a door screen.
///
/// "NURUL ARISSA BINTI AZIZ" → "Nurul Arissa". Everything from `bin` / `binti`
/// (or `a/l`, `a/p`) onwards is the father's name, and a full name on a screen
/// other students can see is more than the organiser needs.
String shortAttendeeName(String full) {
  var name = full.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return '';

  final cut = RegExp(r'\b(bin|binti|bte|bt|a/l|a/p)\b', caseSensitive: false)
      .firstMatch(name);
  if (cut != null && cut.start > 0) {
    name = name.substring(0, cut.start).trim();
  }

  final words = name.split(' ').where((w) => w.isNotEmpty).toList();
  final kept = words.take(2).join(' ');
  return _titleCase(kept);
}

String _titleCase(String value) => value
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

/// The attendance export, one row per person.
///
/// Columns match what the eMerit application asks for and what the checklist
/// says to keep: full name, student id, verified, when they checked in.
String attendanceCsv(List<Map<String, dynamic>> rows) {
  final out = StringBuffer()..writeln('name,student_id,verified,checked_in_at');
  for (final r in rows) {
    out.writeln([
      _cell(r['display_name'] ?? r['username']),
      _cell(r['student_id']),
      _cell(r['verified'] == true ? 'yes' : 'no'),
      _cell(r['checked_in_at']),
    ].join(','));
  }
  return out.toString();
}

String _cell(Object? value) {
  final s = value == null ? '' : '$value';
  final needsQuotes =
      s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
  return needsQuotes ? '"${s.replaceAll('"', '""')}"' : s;
}

/// `attendance-malam-ujian-ki-20261025.csv`
String flowFileName(String prefix, String title, {DateTime? now}) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final d = now ?? DateTime.now();
  final stamp =
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  return '$prefix-${slug.isEmpty ? 'event' : slug}-$stamp.csv';
}

/// One tappable contact channel for the event page.
class ContactLink {
  final String label;
  final String url;

  /// Channel key (`whatsapp`, `telegram`, `instagram`, `email`, `link`); the UI
  /// maps it to an icon.
  final String channel;

  const ContactLink(this.channel, this.label, this.url);
}

/// Turns an `event_contact()` row into links, skipping the blank channels.
///
/// The organiser publishes these on purpose; the sheet used to make you read a
/// list, so they are buttons now.
List<ContactLink> contactLinks(Map<String, dynamic> row) {
  final out = <ContactLink>[];
  String value(String key) => '${row[key] ?? ''}'.trim();

  final wa = value('whatsapp');
  if (wa.isNotEmpty) {
    final digits = wa.replaceAll(RegExp(r'[^0-9]'), '');
    out.add(ContactLink('whatsapp', 'WhatsApp', 'https://wa.me/$digits'));
  }

  final tg = value('telegram');
  if (tg.isNotEmpty) {
    final handle = tg.replaceFirst(RegExp(r'^@'), '');
    out.add(ContactLink(
        'telegram', 'Telegram', handle.contains('/') ? handle : 'https://t.me/$handle'));
  }

  final ig = value('instagram');
  if (ig.isNotEmpty) {
    final handle = ig.replaceFirst(RegExp(r'^@'), '');
    out.add(ContactLink('instagram', 'Instagram',
        handle.contains('/') ? handle : 'https://instagram.com/$handle'));
  }

  final email = value('email');
  if (email.isNotEmpty) {
    out.add(ContactLink('email', 'Email', 'mailto:$email'));
  }

  final link = value('link');
  if (link.isNotEmpty) {
    out.add(ContactLink('link', 'Link', link));
  }

  return out;
}
