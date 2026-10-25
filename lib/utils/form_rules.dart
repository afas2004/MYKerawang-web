/// Pure rules for event forms (no Flutter, no Supabase), shared by the editor
/// and its tests so the client and the server agree on what a valid field is.
///
/// The server re-checks everything — see
/// `supabase/migrations/20261026007100_event_forms.sql` (`form_check_field`).
/// Anything accepted here but not there comes back as a `FORM:` error code.
library;

/// The field kinds the database accepts; keep in sync with `form_kind_ok()`.
const List<String> kFormKinds = [
  'short_text',
  'long_text',
  'rating',
  'single_choice',
  'multi_choice',
  'number',
  'date',
  'email',
  'phone',
  'student_id',
  'consent',
  'heading',
];

const Set<String> kChoiceKinds = {'single_choice', 'multi_choice'};
const Set<String> kAnalysisTags = {'ki_pre', 'ki_post', 'feedback'};
const Set<String> _kiTags = {'ki_pre', 'ki_post'};

const int kMaxFormFields = 40;
const int kMaxKiPerPhase = 7;
const int kLabelMax = 200;

/// Problem codes, so the UI owns the wording.
abstract final class FormIssue {
  static const labelRequired = 'label_required';
  static const labelTooLong = 'label_too_long';
  static const choicesNeeded = 'choices_needed';
  static const badScale = 'bad_scale';
  static const analysisNeedsRating = 'analysis_needs_rating';
  static const kiCodeNeeded = 'ki_code_needed';
  static const tooManyFields = 'too_many_fields';
  static const tooManyKi = 'too_many_ki';
  static const emptyForm = 'empty_form';
  static const headingRequired = 'heading_required';
}

/// One question, as the editor holds it. [id] is null for a field that has not
/// been saved yet; everything else mirrors the database row plus the flattened
/// `options`.
class FormFieldSpec {
  final String? id;
  final String kind;
  final String label;
  final String? help;
  final bool required;

  /// Choices for [kChoiceKinds]; ignored otherwise.
  final List<String> choices;

  /// Scale for [kind] == 'rating'.
  final int min;
  final int max;

  /// `ki_pre` / `ki_post` / `feedback`, or null. The server refuses an analysis
  /// tag on anything but a rating, and a KI tag without a code.
  final String? analysis;
  final int? kiCode;

  const FormFieldSpec({
    this.id,
    required this.kind,
    required this.label,
    this.help,
    this.required = false,
    this.choices = const [],
    this.min = 1,
    this.max = 5,
    this.analysis,
    this.kiCode,
  });

  bool get isAnswerable => kind != 'heading';
  bool get isRating => kind == 'rating';
  bool get isChoice => kChoiceKinds.contains(kind);

  FormFieldSpec copyWith({
    String? id,
    String? kind,
    String? label,
    String? help,
    bool? required,
    List<String>? choices,
    int? min,
    int? max,
    String? analysis,
    int? kiCode,
    bool clearAnalysis = false,
  }) =>
      FormFieldSpec(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        help: help ?? this.help,
        required: required ?? this.required,
        choices: choices ?? this.choices,
        min: min ?? this.min,
        max: max ?? this.max,
        analysis: clearAnalysis ? null : (analysis ?? this.analysis),
        kiCode: clearAnalysis ? null : (kiCode ?? this.kiCode),
      );

  /// The shape `save_event_form()` takes.
  Map<String, dynamic> toRpc() => {
        if (id != null) 'id': id,
        'kind': kind,
        'label': label,
        if (help != null && help!.isNotEmpty) 'help': help,
        'required': required,
        if (isChoice) 'options': {'choices': choices},
        if (isRating) 'options': {'min': min, 'max': max},
        if (analysis != null) 'analysis': analysis,
        if (kiCode != null) 'ki_code': kiCode,
      };

  static FormFieldSpec fromRpc(Map<String, dynamic> m) {
    final options = m['options'];
    final choices = <String>[];
    var min = 1;
    var max = 5;
    if (options is Map) {
      final raw = options['choices'];
      if (raw is List) choices.addAll(raw.map((e) => '$e'));
      min = (options['min'] as num?)?.toInt() ?? 1;
      max = (options['max'] as num?)?.toInt() ?? 5;
    }
    return FormFieldSpec(
      id: m['id'] as String?,
      kind: (m['kind'] as String?) ?? 'short_text',
      label: (m['label'] as String?) ?? '',
      help: m['help'] as String?,
      required: m['required'] == true,
      choices: choices,
      min: min,
      max: max,
      analysis: m['analysis'] as String?,
      kiCode: (m['ki_code'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => 'FormFieldSpec($kind, "$label", analysis=$analysis/$kiCode)';
}

/// A field index plus the reason it is not usable yet.
class FieldProblem {
  final int index;
  final String code;
  const FieldProblem(this.index, this.code);
  @override
  String toString() => 'FieldProblem($index, $code)';
}

/// Everything wrong with [fields], in order. Empty means publishable.
List<FieldProblem> checkFields(List<FormFieldSpec> fields) {
  final problems = <FieldProblem>[];
  if (fields.where((f) => f.isAnswerable).isEmpty) {
    return const [FieldProblem(-1, FormIssue.emptyForm)];
  }
  if (fields.length > kMaxFormFields) {
    problems.add(const FieldProblem(-1, FormIssue.tooManyFields));
  }

  var pre = 0;
  var post = 0;

  for (var i = 0; i < fields.length; i++) {
    final f = fields[i];
    final label = f.label.trim();
    if (label.isEmpty) {
      problems.add(FieldProblem(i, FormIssue.labelRequired));
    } else if (label.length > kLabelMax) {
      problems.add(FieldProblem(i, FormIssue.labelTooLong));
    }
    if (f.kind == 'heading' && f.required) {
      problems.add(FieldProblem(i, FormIssue.headingRequired));
    }
    if (f.isChoice && f.choices.where((c) => c.trim().isNotEmpty).length < 2) {
      problems.add(FieldProblem(i, FormIssue.choicesNeeded));
    }
    if (f.isRating && (f.min < 1 || f.max > 10 || f.min >= f.max)) {
      problems.add(FieldProblem(i, FormIssue.badScale));
    }
    if (f.analysis != null) {
      if (!kAnalysisTags.contains(f.analysis)) {
        problems.add(FieldProblem(i, FormIssue.analysisNeedsRating));
      } else if (!f.isRating) {
        problems.add(FieldProblem(i, FormIssue.analysisNeedsRating));
      } else if (_kiTags.contains(f.analysis) != (f.kiCode != null)) {
        problems.add(FieldProblem(i, FormIssue.kiCodeNeeded));
      } else if (f.kiCode != null && (f.kiCode! < 1 || f.kiCode! > 7)) {
        problems.add(FieldProblem(i, FormIssue.kiCodeNeeded));
      }
    }
    if (f.analysis == 'ki_pre') pre++;
    if (f.analysis == 'ki_post') post++;
  }

  if (pre > kMaxKiPerPhase || post > kMaxKiPerPhase) {
    problems.add(const FieldProblem(-1, FormIssue.tooManyKi));
  }
  return problems;
}

/// A new, empty field — what "Add field" creates.
FormFieldSpec blankField({String kind = 'short_text'}) =>
    FormFieldSpec(kind: kind, label: '', required: false);

/// The required fields with no answer, by id, so the page can mark them.
///
/// `false` counts as missing for a consent field: agreeing is the answer.
List<String> missingRequired(
    List<FormFieldSpec> fields, Map<String, dynamic> answers) {
  final missing = <String>[];
  for (final f in fields) {
    if (f.kind == 'heading' || !f.required || f.id == null) continue;
    final v = answers[f.id];
    final empty = v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty) ||
        v == false;
    if (empty) missing.add(f.id!);
  }
  return missing;
}

/// The role a response carries, read from a choice field that offers
/// Peserta / Penganjur — the KI form's first question. The server stores the
/// role on its own column because S1/S2 are split by it; this keeps the two in
/// step without asking the same thing twice.
String roleForAnswers(List<FormFieldSpec> fields, Map<String, dynamic> answers) {
  for (final f in fields) {
    if (f.kind != 'single_choice') continue;
    final v = answers[f.id]?.toString().trim().toLowerCase();
    if (v == 'penganjur') return 'penganjur';
  }
  return 'peserta';
}

/// A field list pasted as text: one question per line, cells separated by a tab
/// or a comma (see `docs/ki-template-fields.csv`).
///
/// Cells: `kind, label, required(yes/no), options, analysis, ki_code`.
/// - options for a choice is `A|B|C`; for a rating it is `1-5`.
/// - a header row starting with `kind` is skipped.
class FieldPaste {
  final List<FormFieldSpec> fields;
  final List<FieldProblem> problems;

  /// Line number (1-based) of each problem, parallel to nothing — kept simple:
  /// a paste either produces fields or a list of complaints.
  final List<int> problemLines;

  const FieldPaste(this.fields, this.problems, this.problemLines);

  bool get ok => problems.isEmpty && fields.isNotEmpty;
}

FieldPaste parseFieldPaste(String text) {
  final fields = <FormFieldSpec>[];
  final problems = <FieldProblem>[];
  final lines = <int>[];

  var lineNo = 0;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    lineNo++;
    final line = raw.trim();
    if (line.isEmpty) continue;

    final cells = _splitCells(line);
    if (cells.isEmpty) continue;
    if (cells.first.toLowerCase() == 'kind') continue; // header

    final kind = cells[0].trim().toLowerCase();
    if (!kFormKinds.contains(kind)) {
      problems.add(FieldProblem(fields.length, 'unknown_kind'));
      lines.add(lineNo);
      continue;
    }
    if (cells.length < 2) {
      problems.add(FieldProblem(fields.length, FormIssue.labelRequired));
      lines.add(lineNo);
      continue;
    }

    final label = cells[1].trim();
    final required = cells.length > 2 &&
        {'yes', 'y', 'true', '1', 'ya'}.contains(cells[2].trim().toLowerCase());
    final optionsCell = cells.length > 3 ? cells[3].trim() : '';
    final analysisCell = cells.length > 4 ? cells[4].trim() : '';
    final kiCell = cells.length > 5 ? cells[5].trim() : '';

    var choices = const <String>[];
    var min = 1;
    var max = 5;
    if (kChoiceKinds.contains(kind) && optionsCell.isNotEmpty) {
      choices = optionsCell.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    }
    if (kind == 'rating' && optionsCell.isNotEmpty) {
      final m = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(optionsCell);
      if (m != null) {
        min = int.parse(m.group(1)!);
        max = int.parse(m.group(2)!);
      }
    }

    final analysis = kAnalysisTags.contains(analysisCell) ? analysisCell : null;
    final kiCode = int.tryParse(kiCell);

    fields.add(FormFieldSpec(
      kind: kind,
      label: label,
      required: required,
      choices: choices,
      min: min,
      max: max,
      analysis: analysis,
      kiCode: analysis == null ? null : kiCode,
    ));
  }

  // Everything pasted is checked by the same rules the editor uses. An empty
  // list is only "empty_form" when the paste itself parsed cleanly — one bad
  // kind should say so, not complain about an empty form.
  final checked = checkFields(fields)
      .where((p) => p.code != FormIssue.emptyForm || fields.isNotEmpty)
      .toList();
  return FieldPaste(fields, [...problems, ...checked], lines);
}

/// Splits one line on tabs or commas, honouring "quoted, cells".
List<String> _splitCells(String line) {
  if (line.contains('\t')) return line.split('\t');

  final cells = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      cells.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString());
  return cells;
}
