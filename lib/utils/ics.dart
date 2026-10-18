import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// iCalendar (RFC 5545) export for "Add to calendar".
///
/// Times are written in UTC (`...Z`), so whatever zone the organiser and
/// the reader are in, the calendar app converts to the right local time.

/// Builds a single-event .ics file. [event] is an `events` row; [url] is
/// the event's public link.
String buildEventIcs(Map<String, dynamic> event, {String? url, DateTime? now}) {
  final start = DateTime.parse(event['start_datetime'].toString()).toUtc();
  final rawEnd = event['end_datetime'];
  final end = rawEnd == null
      ? start.add(const Duration(hours: 2)) // same default as create_event
      : DateTime.parse(rawEnd.toString()).toUtc();

  final description = [
    if ((event['description'] ?? '').toString().trim().isNotEmpty)
      event['description'].toString().trim(),
    if (url != null) url,
  ].join('\n\n');

  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//MYKerawang//Events//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${event['id']}@mykerawang-app.web.app',
    'DTSTAMP:${icsUtc(now ?? DateTime.now())}',
    'DTSTART:${icsUtc(start)}',
    'DTEND:${icsUtc(end)}',
    'SUMMARY:${icsEscape((event['title'] ?? '').toString())}',
    if ((event['location'] ?? '').toString().trim().isNotEmpty)
      'LOCATION:${icsEscape(event['location'].toString().trim())}',
    if (description.isNotEmpty) 'DESCRIPTION:${icsEscape(description)}',
    if (url != null) 'URL:$url',
    if (event['cancelled_at'] != null) 'STATUS:CANCELLED',
    'END:VEVENT',
    'END:VCALENDAR',
  ];

  // RFC 5545: CRLF line endings, lines folded at 75 octets.
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// `20261019T053000Z`
String icsUtc(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// TEXT value escaping: backslash, semicolon, comma, newline.
String icsEscape(String text) => text
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n');

/// Folds a content line into 75-octet chunks (continuations start with a
/// space), without splitting a multi-byte UTF-8 character.
String _fold(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = StringBuffer();
  var count = 0;
  var limit = 75;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final size = utf8.encode(ch).length;
    if (count + size > limit) {
      out.write('\r\n ');
      count = 0;
      limit = 74; // the leading space counts
    }
    out.write(ch);
    count += size;
  }
  return out.toString();
}

/// Web: downloads the file. Mobile: opens the share sheet with it, from
/// which the calendar app can import it.
Future<void> saveIcs(String ics, String filename) async {
  final bytes = Uint8List.fromList(utf8.encode(ics));
  if (kIsWeb) {
    impl.downloadBytes(bytes, filename);
    return;
  }
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, name: filename, mimeType: 'text/calendar')],
    fileNameOverrides: [filename],
  ));
}

/// A file name from the event title: `campus-run.ics`.
String icsFileName(String? title) {
  final slug = (title ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? 'event' : slug}.ics';
}
