import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../l10n/app_strings.dart';
import '../language_cubit.dart';

/// Single source for how prices and dates look anywhere in the app —
/// grid, detail, right rail, embeds, share/WhatsApp text, create forms.
/// Don't hand-roll `DateFormat(...)`, `toStringAsFixed` or `"RM ..."`
/// in screens; add a function here instead.

/// Prefix for price input fields.
const String kCurrencyPrefix = 'RM ';

/// `RM 12.50`. Null (missing price) renders as `RM 0.00`.
String formatPrice(num? price) =>
    '$kCurrencyPrefix${(price ?? 0).toStringAsFixed(2)}';

/// Parses a Supabase timestamp (or passes a DateTime through) and always
/// converts to the viewer's local time. Null when missing/unparseable.
DateTime? parseLocal(dynamic raw) {
  if (raw is DateTime) return raw.toLocal();
  if (raw is String) return DateTime.tryParse(raw)?.toLocal();
  return null;
}

final _day = DateFormat('d MMM yyyy');
final _time = DateFormat('h:mm a');

/// `12 Oct 2026`
String formatDate(DateTime date) => _day.format(date.toLocal());

/// `12 Oct 2026, 8:00 PM`
String formatEventDate(DateTime start) {
  final s = start.toLocal();
  return '${_day.format(s)}, ${_time.format(s)}';
}

/// One event's time span:
///  - no end:      `12 Oct 2026, 8:00 PM`
///  - same day:    `12 Oct 2026, 8:00 PM – 10:00 PM`
///  - multi-day:   `12 Oct 2026, 8:00 PM – 13 Oct 2026, 2:00 AM`
String formatEventRange(DateTime start, DateTime? end) {
  if (end == null) return formatEventDate(start);
  final s = start.toLocal();
  final e = end.toLocal();
  final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
  return sameDay
      ? '${formatEventDate(s)} – ${_time.format(e)}'
      : '${formatEventDate(s)} – ${formatEventDate(e)}';
}

/// Short "time ago" (`5m`, `2h`…) in the current app language.
/// Call from build — it listens to [LanguageCubit].
String formatRelative(BuildContext context, DateTime date) {
  _registerTimeagoLocales();
  final locale = switch (context.appLanguage) {
    AppLanguage.en => 'en_short',
    AppLanguage.ms => 'ms_short',
    AppLanguage.ja => 'ja',
  };
  return timeago.format(date.toLocal(), locale: locale);
}

bool _timeagoReady = false;
void _registerTimeagoLocales() {
  if (_timeagoReady) return;
  timeago.setLocaleMessages('ms_short', timeago.MsMyShortMessages());
  timeago.setLocaleMessages('ja', timeago.JaMessages());
  _timeagoReady = true;
}
