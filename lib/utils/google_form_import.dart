/// Turning a Google Form into MYKerawang questions. Pure (no Flutter, no
/// Supabase), so every rule here is unit-tested on saved forms.
///
/// How it works: a Google Form's public page carries its questions as a
/// JavaScript array, `FB_PUBLIC_LOAD_DATA_ = [...]`. The server fetches the
/// page (`import_google_form()` in
/// supabase/migrations/20261114001100_google_form_import.sql) and returns that
/// array; [parseGoogleForm] reads it. Where the array keeps things:
///
///   d[1][0]  description          d[1][8]  title shown on the form
///   d[1][1]  the questions         d[3]     the file name (fallback title)
///
/// Each question `q`: q[1] title, q[2] description, q[3] type code, and for
/// answerable ones q[4][0] = [id, options, required(1/0), scale labels, …].
library;

import 'form_rules.dart';

// --------------------------------------------------------------------- links

final RegExp _shortLink =
    RegExp(r'^https://forms\.gle/([A-Za-z0-9_-]{4,64})/?([?#][A-Za-z0-9_.~=&%+-]*)?$');
final RegExp _longLink = RegExp(
    r'^https://docs\.google\.com/forms(?:/u/[0-9]{1,2})?/d/(e/)?([A-Za-z0-9_-]{10,128})'
    r'(?:/[A-Za-z]{0,20})?/?([?#][A-Za-z0-9_.~=&%+-]*)?$');

/// The one fetchable form of a pasted Google Form link, or null when it is
/// not one. Mirrors `google_form_url()` on the server, plus two kindnesses
/// for people pasting by hand: a missing `https://` and `http://` are fixed.
String? normaliseGoogleFormUrl(String input) {
  var v = input.trim();
  if (v.isEmpty || v.length > 500 || RegExp(r'[\s\\@]').hasMatch(v)) return null;
  if (v.startsWith('http://')) v = 'https://${v.substring(7)}';
  if (!v.startsWith('https://')) v = 'https://$v';
  final s = _shortLink.firstMatch(v);
  if (s != null) return 'https://forms.gle/${s.group(1)}';
  final l = _longLink.firstMatch(v);
  if (l != null) {
    return 'https://docs.google.com/forms/d/${l.group(1) ?? ''}${l.group(2)}/viewform';
  }
  return null;
}

final RegExp _linkInText = RegExp(
    r'(?:https?://)?(?:forms\.gle/[A-Za-z0-9_-]+|docs\.google\.com/forms/[^\s<>()"]+)',
    caseSensitive: false);

/// The first Google Form link in [text] (a post, a button's URL), already
/// normalised, or null. For the composers' "turn this into a form?" hint.
String? findGoogleFormUrl(String text) {
  for (final m in _linkInText.allMatches(text)) {
    // Trailing punctuation from the sentence around it is not part of the link.
    final raw = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
    final url = normaliseGoogleFormUrl(raw);
    if (url != null) return url;
  }
  return null;
}

/// The `FB_PUBLIC_LOAD_DATA_` array's text from a whole form page, or null.
/// The server does the same; this one exists for tests and saved pages.
String? extractGoogleFormJson(String html) {
  final at = html.indexOf('FB_PUBLIC_LOAD_DATA_');
  if (at < 0) return null;
  final eq = html.indexOf('=', at);
  if (eq < 0) return null;
  final end = html.indexOf('</script>', eq);
  if (end < 0) return null;
  return html.substring(eq + 1, end).trim().replaceFirst(RegExp(r';\s*$'), '');
}

// -------------------------------------------------------------------- result

/// Why something was left out or changed. The UI owns the wording.
abstract final class GoogleFormNoteCode {
  // Left out.
  static const grid = 'grid';
  static const file = 'file';
  static const image = 'image';
  static const video = 'video';
  static const blocked = 'blocked';
  static const unknown = 'unknown';
  static const tooMany = 'too_many';

  // Imported, but not quite as it was.
  static const time = 'time';
  static const other = 'other';
  static const scaleAsChoice = 'scale_as_choice';
  static const trimmed = 'trimmed';
  static const oneChoice = 'one_choice';
  static const noChoices = 'no_choices';
  static const pictureChoices = 'picture_choices';
  static const branching = 'branching';

  static const skipped = {grid, file, image, video, blocked, unknown, tooMany};
}

/// One thing the person should know about the import: [label] is the
/// question it is about (as it was in Google Forms).
class GoogleFormNote {
  final String code;
  final String label;
  const GoogleFormNote(this.code, this.label);

  bool get isSkipped => GoogleFormNoteCode.skipped.contains(code);

  @override
  bool operator ==(Object other) =>
      other is GoogleFormNote && other.code == code && other.label == label;
  @override
  int get hashCode => Object.hash(code, label);
  @override
  String toString() => 'GoogleFormNote($code, "$label")';
}

/// What a Google Form becomes, before anything is saved.
class GoogleFormDraft {
  /// The form's title, or '' when it had none worth keeping ([untitled]).
  final String title;
  final String? description;

  /// The title was empty or Google's default ("Untitled form"): ask for one.
  final bool untitled;
  final List<FormFieldSpec> fields;
  final List<GoogleFormNote> notes;

  const GoogleFormDraft({
    required this.title,
    this.description,
    this.untitled = false,
    this.fields = const [],
    this.notes = const [],
  });

  List<GoogleFormNote> get skipped => [for (final n in notes) if (n.isSkipped) n];
  List<GoogleFormNote> get changed => [for (final n in notes) if (!n.isSkipped) n];
  int get questionCount => fields.where((f) => f.isAnswerable).length;
}

/// The data is not a Google Form's (a sign-in page, a broken page).
class GoogleFormParseException implements Exception {
  final String code;
  const GoogleFormParseException([this.code = 'no_data']);
  @override
  String toString() => 'GoogleFormParseException($code)';
}

// -------------------------------------------------------------------- parser

/// Google's default names for a form nobody named.
const Set<String> _untitledNames = {
  'untitled form',
  'borang tidak bertajuk',
  'borang tanpa tajuk',
  '無題のフォーム',
};

final RegExp _matricLabel = RegExp(
    r'\bmatri[ck]s?\b|\bstudent\s*(id|no|number)\b|\bno\.?\s*pelajar\b|\bnombor\s*pelajar\b|\bid\s*pelajar\b',
    caseSensitive: false);
final RegExp _emailLabel = RegExp(r'\be-?mail\b|\be-?mel\b', caseSensitive: false);
final RegExp _phoneLabel = RegExp(
    r'\b(no\.?|nombor|number)\s*(tel|telefon|phone|hp|h/p|handphone)\b|\bphone\b|\btelefon\b',
    caseSensitive: false);

const int _choiceMax = 60;
const int _choicesMax = 40;

String _clean(Object? v) =>
    v is String ? v.replaceAll(RegExp(r'[ \t]+'), ' ').trim() : '';

String _cut(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

Object? _at(Object? list, int i) => list is List && i >= 0 && i < list.length ? list[i] : null;

/// [v] when it is a list, else empty: Google's arrays change shape between
/// item types and over time, and a surprise must never crash an import.
List<Object?> _list(Object? v) => v is List ? v : const [];

/// Turns `FB_PUBLIC_LOAD_DATA_` (already JSON-decoded) into a draft form.
///
/// [studentIds]: a "No. matrik" question becomes the student-ID kind (only
/// when student features are on). [standalone]: the questions the server
/// refuses on a student-made form (passwords, PINs, card numbers) are left
/// out instead of failing the save.
GoogleFormDraft parseGoogleForm(
  Object? data, {
  bool studentIds = true,
  bool standalone = true,
}) {
  final info = _at(data, 1);
  final items = _at(info, 1);
  if (data is! List || info is! List || (items != null && items is! List)) {
    throw const GoogleFormParseException();
  }

  final notes = <GoogleFormNote>[];
  final fields = <FormFieldSpec>[];

  for (final q in _list(items)) {
    if (q is! List) continue;
    final title = _clean(_at(q, 1));
    final desc = _clean(_at(q, 2));
    final shown = title.isNotEmpty ? title : desc.split('\n').first.trim();
    // One odd item is listed as "not supported", never the end of the import.
    try {
      final rawType = _at(q, 3);
      final type = rawType is num ? rawType.toInt() : -1;
      final entry = _at(_at(q, 4), 0);
      final required = _at(entry, 2) == 1 || _at(entry, 2) == true;

      FormFieldSpec? field;
      switch (type) {
        case 0: // short answer
          var kind = 'short_text';
          if (studentIds && _matricLabel.hasMatch(title)) {
            kind = 'student_id';
          } else if (_emailLabel.hasMatch(title)) {
            kind = 'email';
          } else if (_phoneLabel.hasMatch(title)) {
            kind = 'phone';
          }
          field = FormFieldSpec(kind: kind, label: title, required: required);
        case 1: // paragraph
          field = FormFieldSpec(kind: 'long_text', label: title, required: required);
        case 2 || 3 || 4: // multiple choice, dropdown, checkboxes
          field = _choiceField(title, type == 4, entry, required, notes);
        case 5 || 18: // linear scale, rating
          field = _scaleField(title, desc, type == 18, entry, required, notes);
        case 9:
          field = FormFieldSpec(kind: 'date', label: title, required: required);
        case 10:
          notes.add(GoogleFormNote(GoogleFormNoteCode.time, title));
          field = FormFieldSpec(kind: 'short_text', label: title, required: required);
        case 6 || 8: // text block, section break
          if (shown.isEmpty) continue;
          field = FormFieldSpec(kind: 'heading', label: shown);
        case 7:
          notes.add(GoogleFormNote(GoogleFormNoteCode.grid, shown));
          continue;
        case 11:
          notes.add(GoogleFormNote(GoogleFormNoteCode.image, shown));
          continue;
        case 12:
          notes.add(GoogleFormNote(GoogleFormNoteCode.video, shown));
          continue;
        case 13:
          notes.add(GoogleFormNote(GoogleFormNoteCode.file, shown));
          continue;
        default:
          notes.add(GoogleFormNote(GoogleFormNoteCode.unknown, shown));
          continue;
      }

      // A question with no title: borrow the first line of its description.
      var label = field.label.isEmpty ? shown : field.label;
      if (label.isEmpty) {
        notes.add(const GoogleFormNote(GoogleFormNoteCode.unknown, ''));
        continue;
      }
      if (label.length > kLabelMax) {
        notes.add(GoogleFormNote(GoogleFormNoteCode.trimmed, label));
        label = _cut(label, kLabelMax);
      }
      // The description becomes help text, unless it is already the label.
      final help = field.help ?? (desc.isEmpty || desc == label ? null : desc);
      field = field.copyWith(label: label, help: help);

      if (standalone && (formLabelBlocked(field.label) || formLabelBlocked(field.help))) {
        notes.add(GoogleFormNote(GoogleFormNoteCode.blocked, label));
        continue;
      }
      fields.add(field);
    } catch (_) {
      notes.add(GoogleFormNote(GoogleFormNoteCode.unknown, shown));
    }
  }

  if (fields.length > kMaxFormFields) {
    for (final f in fields.sublist(kMaxFormFields)) {
      notes.add(GoogleFormNote(GoogleFormNoteCode.tooMany, f.label));
    }
    fields.removeRange(kMaxFormFields, fields.length);
  }

  var formTitle = _clean(_at(info, 8));
  if (formTitle.isEmpty) formTitle = _clean(_at(data, 3));
  final untitled = formTitle.isEmpty || _untitledNames.contains(formTitle.toLowerCase());
  final description = _clean(_at(info, 0));

  return GoogleFormDraft(
    title: untitled ? '' : _cut(formTitle, 120),
    description: description.isEmpty ? null : description,
    untitled: untitled,
    fields: fields,
    notes: notes,
  );
}

FormFieldSpec _choiceField(
  String title,
  bool multi,
  Object? entry,
  bool required,
  List<GoogleFormNote> notes,
) {
  final choices = <String>[];
  var hasOther = false;
  var trimmed = false;
  var pictures = false;
  var branching = false;
  for (final o in _list(_at(entry, 1))) {
    // o[2]: "go to section …" after this answer.
    if (_at(o, 2) != null) branching = true;
    if (_at(o, 4) == 1 || _at(o, 4) == true) {
      hasOther = true;
      continue;
    }
    var c = _clean(_at(o, 0));
    if (c.isEmpty) {
      // An option with no words is a picture: it can't come across.
      if (_at(o, 5) != null) pictures = true;
      continue;
    }
    if (c.length > _choiceMax) {
      c = _cut(c, _choiceMax);
      trimmed = true;
    }
    if (!choices.contains(c)) choices.add(c);
  }
  if (hasOther) {
    notes.add(GoogleFormNote(GoogleFormNoteCode.other, title));
    if (!choices.contains('Other')) choices.add('Other');
  }
  if (choices.length > _choicesMax) {
    choices.removeRange(_choicesMax, choices.length);
    trimmed = true;
  }
  if (trimmed) notes.add(GoogleFormNote(GoogleFormNoteCode.trimmed, title));
  if (pictures) notes.add(GoogleFormNote(GoogleFormNoteCode.pictureChoices, title));
  if (branching) notes.add(GoogleFormNote(GoogleFormNoteCode.branching, title));

  if (choices.isEmpty) {
    notes.add(GoogleFormNote(GoogleFormNoteCode.noChoices, title));
    return FormFieldSpec(kind: 'short_text', label: title, required: required);
  }
  if (choices.length == 1) {
    // One box to tick ("I agree") is a consent question here.
    notes.add(GoogleFormNote(GoogleFormNoteCode.oneChoice, title));
    return FormFieldSpec(
        kind: 'consent', label: title.isEmpty ? choices.first : title, required: required,
        help: title.isEmpty ? null : choices.first);
  }
  return FormFieldSpec(
    kind: multi ? 'multi_choice' : 'single_choice',
    label: title,
    required: required,
    choices: choices,
  );
}

FormFieldSpec _scaleField(
  String title,
  String desc,
  bool isRating,
  Object? entry,
  bool required,
  List<GoogleFormNote> notes,
) {
  // The options are the numbers ("1" … "5"); some forms keep only the bounds.
  final numbers = <int>[
    for (final o in _list(_at(entry, 1)))
      if (int.tryParse(_clean(_at(o, 0))) case final n?) n,
  ];
  final extra = _at(entry, 3);
  String? low;
  String? high;
  if (extra is List && extra.length >= 2) {
    final a = extra[0];
    final b = extra[1];
    if (a is num && b is num) {
      numbers
        ..clear()
        ..addAll([for (var i = a.toInt(); i <= b.toInt(); i++) i]);
    } else {
      low = _clean(a);
      high = _clean(b);
    }
  }
  if (numbers.isEmpty) numbers.addAll(isRating ? [1, 2, 3, 4, 5] : const []);
  if (numbers.isEmpty) {
    notes.add(GoogleFormNote(GoogleFormNoteCode.noChoices, title));
    return FormFieldSpec(kind: 'short_text', label: title, required: required);
  }
  numbers.sort();
  final min = numbers.first;
  final max = numbers.last;

  // "1 = Not at all · 5 = Very much", kept as help so the meaning survives.
  final ends = [
    if (low != null && low.isNotEmpty) '$min = $low',
    if (high != null && high.isNotEmpty) '$max = $high',
  ].join(' · ');
  final help = [if (desc.isNotEmpty) desc, if (ends.isNotEmpty) ends].join('\n');

  if (min >= 1 && max <= 10 && min < max) {
    return FormFieldSpec(
      kind: 'rating',
      label: title,
      required: required,
      min: min,
      max: max,
      help: help.isEmpty ? null : help,
    );
  }
  notes.add(GoogleFormNote(GoogleFormNoteCode.scaleAsChoice, title));
  final choices = [for (final n in numbers.toSet()) '$n'];
  if (choices.length < 2 || choices.length > _choicesMax) {
    notes.add(GoogleFormNote(GoogleFormNoteCode.noChoices, title));
    return FormFieldSpec(kind: 'short_text', label: title, required: required);
  }
  return FormFieldSpec(
    kind: 'single_choice',
    label: title,
    required: required,
    choices: choices,
    help: help.isEmpty ? null : help,
  );
}
