import 'package:flutter/material.dart';

import 'form_rules.dart' show kLabelMax;

/// Caps and cleaning for the text a form is made of.
///
/// The database is the authority on what is *accepted*: `form_check_field`
/// refuses a label that is blank or longer than 200, `submit_form_response`
/// caps short answers at 200 and long ones at 2000, and the check-in/matric
/// rules live in SQL too. These are the client's half of the same contract —
/// the caps the inputs enforce while typing, so nobody types 3,000 characters
/// only to be told at the end that it was too long.
///
/// One place for both screens and the tests.

/// A question's label. Mirrors `form_check_field`'s 200.
const int kFormLabelMax = kLabelMax;

/// The form's own title and introduction.
const int kFormTitleMax = 120;
const int kFormIntroMax = 500;

/// The grey line under a question.
const int kFormHelpMax = 300;

/// One choice of a choice question, and how many a question may have
/// (the server refuses more than 40).
const int kChoiceMax = 60;
const int kChoiceCountMax = 40;

/// Answer lengths, matching `submit_form_response`.
const int kShortAnswerMax = 200;
const int kLongAnswerMax = 2000;

/// C0/C1 control characters, minus tab and newline. These have no business in
/// a form and can break layout or copy-paste into the Word report.
final RegExp _control = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');

/// One line of user text: control characters dropped, runs of whitespace
/// collapsed to a single space, trimmed.
///
/// Used for labels, help text, titles, choices and short answers — anything
/// that is rendered as one line. Newlines are collapsed, so a pasted
/// multi-line label cannot quietly become a three-line heading.
String cleanLine(String raw) =>
    raw.replaceAll(_control, '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Multi-line text (the form's introduction): line endings normalised,
/// control characters dropped, trimmed at the ends only.
String cleanBlock(String raw) {
  final normalised = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalised.replaceAll(_control, '').trim();
}

/// Choices as the form should store them: cleaned, blanks dropped,
/// duplicates dropped (case-insensitively), each capped at [kChoiceMax],
/// and at most [kChoiceCountMax] of them.
///
/// The editor caps typing as well; this also covers pasted and imported
/// lists, which do not go through a text field.
List<String> cleanChoices(Iterable<String> raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final entry in raw) {
    var choice = cleanLine(entry);
    if (choice.isEmpty) continue;
    if (choice.length > kChoiceMax) choice = choice.substring(0, kChoiceMax).trim();
    if (!seen.add(choice.toLowerCase())) continue;
    out.add(choice);
    if (out.length == kChoiceCountMax) break;
  }
  return out;
}

/// A spreadsheet treats a cell starting with `=`, `+`, `-`, `@`, a tab or a
/// carriage return as a formula. Answers are typed by students and end up in a
/// CSV a treasurer opens in Excel, so a leading apostrophe forces text (the
/// usual CSV-injection guard, CWE-1236).
///
/// A plain number keeps its number: `-5` and `+60123456789` are data, not
/// formulas.
String csvSafe(String value) {
  if (value.isEmpty) return value;
  final first = value.codeUnitAt(0);
  final risky = first == 0x3D || // =
      first == 0x2B || // +
      first == 0x2D || // -
      first == 0x40 || // @
      first == 0x09 || // tab
      first == 0x0D; // CR
  if (!risky) return value;
  if (double.tryParse(value) != null) return value;
  return "'$value";
}

/// One cell of a tab-separated table: no tabs or newlines (they would break
/// the columns), and no formula prefix.
String tsvCell(String value) =>
    csvSafe(value.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim());

/// A character counter that stays out of the way until the field is focused.
///
/// Flutter's default counter is always on and adds a line under every field;
/// on a list of 28 questions that is noise. The cap itself is still enforced
/// while typing — this only decides when the number is shown.
Widget? quietCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) {
  if (!isFocused || maxLength == null) return null;
  return Text(
    '$currentLength / $maxLength',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
  );
}
