/// Turning answers and means into the two artefacts the club hands over: a CSV
/// of responses (what they process themselves) and a plain table of the
/// S1/S2/S3 numbers (which get typed into the Word report by hand).
///
/// Pure, so both can be tested without a widget.
library;

import '../services/form_service.dart';
import 'form_rules.dart';
import 'moderation_logic.dart' show toCsv;
import 'text_rules.dart' show tsvCell;

/// One answer as it should read in a spreadsheet.
String answerText(FormFieldSpec field, Object? value) {
  if (value == null) return '';
  if (value is bool) return value ? 'yes' : 'no';
  if (value is List) return value.join('; ');
  return '$value';
}

/// Identity columns, then one per question (headings excluded).
List<String> responseColumns(List<FormFieldSpec> fields) => [
      'display_name',
      'student_id',
      'role',
      'submitted_at',
      for (final f in fields)
        if (f.kind != 'heading' && f.id != null) f.label,
    ];

/// The rows, in the order of [responseColumns].
List<List<String>> responseRows(
        List<FormFieldSpec> fields, List<FormResponse> responses) =>
    [
      for (final r in responses)
        [
          r.displayName,
          r.studentId ?? '',
          r.role,
          r.submittedAt?.toIso8601String() ?? '',
          for (final f in fields)
            if (f.kind != 'heading' && f.id != null)
              answerText(f, r.answers[f.id]),
        ],
    ];

/// The CSV the organiser downloads. One row per person, same identity columns
/// as the attendance export so the two join in a spreadsheet.
String responsesCsv(List<FormFieldSpec> fields, List<FormResponse> responses) {
  final columns = responseColumns(fields);
  final rows = responseRows(fields, responses);
  return toCsv(columns, [
    for (final r in rows)
      {for (var i = 0; i < columns.length; i++) columns[i]: r[i]},
  ]);
}

/// S1 as tab-separated text: pastes into Excel and into the Word report.
String s1Tsv(List<KiMean> rows) => _tsv(
      ['KI', 'n_before', 'mean_before', 'n_after', 'mean_after', 'delta'],
      [
        for (final r in rows)
          [
            'KI${r.kiCode}',
            '${r.nBefore}',
            _num(r.meanBefore),
            '${r.nAfter}',
            _num(r.meanAfter),
            _num(r.delta),
          ],
      ],
    );

/// S2: organisers, after only.
String s2Tsv(List<KiMean> rows) => _tsv(
      ['KI', 'n_after', 'mean_after'],
      [
        for (final r in rows)
          ['KI${r.kiCode}', '${r.nAfter}', _num(r.meanAfter)],
      ],
    );

/// S3: participant feedback items.
String s3Tsv(List<FeedbackMean> rows) => _tsv(
      ['Item', 'n', 'mean'],
      [
        for (final r in rows) [r.label, '${r.n}', _num(r.mean)],
      ],
    );

/// Two decimals, or an empty cell when there is nothing to average.
String _num(double? v) => v == null ? '' : v.toStringAsFixed(2);

String _tsv(List<String> columns, List<List<String>> rows) {
  // No trimRight: a row's trailing empty cells are columns too, and the header
  // is what a spreadsheet aligns against.
  final lines = <String>[
    columns.map(tsvCell).join('\t'),
    for (final r in rows) r.map(tsvCell).join('\t'),
  ];
  return lines.join('\n');
}
