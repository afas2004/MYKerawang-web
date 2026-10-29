import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/form_rules.dart';

/// One shipped starting point ("template" in the UI).
class FormTemplate {
  final String slug;
  final String name;
  final String? nameMs;
  final int fieldCount;

  const FormTemplate({
    required this.slug,
    required this.name,
    this.nameMs,
    this.fieldCount = 0,
  });

  String label(bool malay) => (malay ? nameMs : null) ?? name;
}

/// What the event page needs to label its button.
class FormSummary {
  final String id;
  final String title;
  final String status;
  final int responses;

  const FormSummary({
    required this.id,
    required this.title,
    required this.status,
    this.responses = 0,
  });

  bool get isDraft => status == 'draft';
}

/// A form as the editor holds it.
class FormDoc {
  final String id;
  final String title;
  final String status;
  final String? intro;
  final bool requireRsvp;
  final bool afterCheckin;
  final bool canEdit;
  final List<FormFieldSpec> fields;

  /// Not tied to an event: made by a student or a club (`/f/:id`).
  final bool standalone;

  /// Taken down by moderation: no answers, and its answers cannot be read.
  final bool isHidden;

  /// Who made a standalone form, shown on its answer page.
  final String? ownerUsername;
  final String? ownerName;

  /// The club a standalone form belongs to, if any.
  final String? clubName;
  final String? clubHandle;

  /// The event an event form belongs to.
  final String? eventId;

  const FormDoc({
    required this.id,
    required this.title,
    required this.status,
    this.intro,
    this.requireRsvp = false,
    this.afterCheckin = false,
    this.canEdit = true,
    this.fields = const [],
    this.standalone = false,
    this.isHidden = false,
    this.ownerUsername,
    this.ownerName,
    this.clubName,
    this.clubHandle,
    this.eventId,
  });

  /// Where the editor, the answer page and the responses page live.
  String get answerPath =>
      standalone || eventId == null ? '/f/$id' : '/event/$eventId/form?f=$id';
  String get editPath =>
      standalone || eventId == null ? '/f/$id/edit' : '/event/$eventId/form/edit?f=$id';
  String get responsesPath => standalone || eventId == null
      ? '/f/$id/responses'
      : '/event/$eventId/form/responses?f=$id';

  bool get isDraft => status == 'draft';

  /// The caller may fill this form in.
  bool get isOpen => status == 'open';

  /// The `p_form` half of `save_event_form`.
  Map<String, dynamic> get header => {
        'title': title,
        'intro': intro,
        'require_rsvp': requireRsvp,
        'after_checkin': afterCheckin,
      };

  FormDoc copyWith({
    String? title,
    String? status,
    String? intro,
    bool? requireRsvp,
    bool? afterCheckin,
    List<FormFieldSpec>? fields,
  }) =>
      FormDoc(
        id: id,
        title: title ?? this.title,
        status: status ?? this.status,
        intro: intro ?? this.intro,
        requireRsvp: requireRsvp ?? this.requireRsvp,
        afterCheckin: afterCheckin ?? this.afterCheckin,
        canEdit: canEdit,
        fields: fields ?? this.fields,
        standalone: standalone,
        isHidden: isHidden,
        ownerUsername: ownerUsername,
        ownerName: ownerName,
        clubName: clubName,
        clubHandle: clubHandle,
        eventId: eventId,
      );
}

/// `form_public()` as a whole: the form, whether the caller may answer it, and
/// the answer they already gave (if any).
class FormView {
  final FormDoc doc;

  /// False with a [reason] when the caller cannot answer.
  final bool canAnswer;

  /// `signed_out` · `closed` · `not_joined` · `full` · `removed`.
  final String? reason;

  /// The caller may read the answers (owner, club officers; organisers).
  final bool canRead;

  /// The caller's own answers, keyed by field id, and the role they picked.
  final Map<String, dynamic>? mine;
  final String? myRole;

  const FormView({
    required this.doc,
    this.canAnswer = false,
    this.reason,
    this.canRead = false,
    this.mine,
    this.myRole,
  });

  bool get answered => mine != null;
}

/// One KI element in S1 or S2.
class KiMean {
  final int kiCode;
  final String label;
  final int nBefore;
  final double? meanBefore;
  final int nAfter;
  final double? meanAfter;
  final double? delta;

  const KiMean({
    required this.kiCode,
    required this.label,
    this.nBefore = 0,
    this.meanBefore,
    this.nAfter = 0,
    this.meanAfter,
    this.delta,
  });
}

/// One programme-feedback item in S3.
class FeedbackMean {
  final String fieldId;
  final String label;
  final int n;
  final double? mean;

  const FeedbackMean({
    required this.fieldId,
    required this.label,
    this.n = 0,
    this.mean,
  });
}

/// `form_analysis()`: the three "analisa Excel" the HEP report asks for.
class FormAnalysis {
  final int peserta;
  final int penganjur;

  /// Peserta, before and after, per KI element.
  final List<KiMean> s1;

  /// Penganjur, after, per KI element.
  final List<KiMean> s2;

  /// Peserta feedback, per item.
  final List<FeedbackMean> s3;

  const FormAnalysis({
    this.peserta = 0,
    this.penganjur = 0,
    this.s1 = const [],
    this.s2 = const [],
    this.s3 = const [],
  });

  bool get isEmpty => peserta == 0 && penganjur == 0;
}

/// One person's answers.
class FormResponse {
  final String userId;
  final String displayName;
  final String? studentId;
  final String role;
  final DateTime? submittedAt;
  final Map<String, dynamic> answers;

  const FormResponse({
    required this.userId,
    required this.displayName,
    this.studentId,
    this.role = 'peserta',
    this.submittedAt,
    this.answers = const {},
  });
}

/// The editor's and answer page's data source. Swappable so widget tests never
/// touch Supabase: `FormService.instance = FakeFormService()`.
abstract class FormService {
  Future<List<FormTemplate>> templates();

  /// The event's newest draft/open form, or null when it has none. Managers
  /// only — a student gets null.
  Future<FormSummary?> summary(String eventId);

  /// The form a student should answer, or null. Available to guests too.
  Future<String?> openFormId(String eventId);

  /// The signed-in user's email, for pre-filling a matric. Null for guests.
  Future<String?> myEmail();

  Future<String> createBlank(String eventId, {String? title});

  Future<String> createFromTemplate(String eventId, String slug);

  Future<FormView> load(String formId);

  Future<void> save(FormDoc doc);

  Future<void> publish(String formId);

  /// Answers land here. [role] is `peserta` or `penganjur`.
  Future<void> submit(
    String formId, {
    required Map<String, dynamic> answers,
    String? role,
  });

  /// S1, S2, S3 — already reduced to means by the server.
  Future<FormAnalysis> analysis(String formId);

  /// Every answer, for the table and the CSV.
  Future<List<FormResponse>> responses(String formId);

  /// The organiser's "ask this form after check-in" switch.
  Future<void> setAfterCheckin(String formId, bool on);

  static FormService instance = const SupabaseFormService();

  @visibleForTesting
  static void debugReset() => instance = const SupabaseFormService();
}

class SupabaseFormService implements FormService {
  const SupabaseFormService();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<FormTemplate>> templates() async {
    final rows = await _db.rpc('form_templates_list') as List;
    return rows.map((e) {
      final r = Map<String, dynamic>.from(e as Map);
      return FormTemplate(
        slug: '${r['slug']}',
        name: '${r['name']}',
        nameMs: r['name_ms'] as String?,
        fieldCount: (r['field_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  @override
  Future<FormSummary?> summary(String eventId) async {
    final raw = await _db.rpc('event_form_summary', params: {'p_event_id': eventId});
    if (raw is! Map) return null;
    final r = Map<String, dynamic>.from(raw);
    return FormSummary(
      id: '${r['id']}',
      title: '${r['title']}',
      status: '${r['status']}',
      responses: (r['responses'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<String?> openFormId(String eventId) async {
    final raw = await _db.rpc('event_open_form', params: {'p_event_id': eventId});
    return raw == null ? null : '$raw';
  }

  @override
  Future<String?> myEmail() async => _db.auth.currentUser?.email;

  @override
  Future<String> createBlank(String eventId, {String? title}) async =>
      '${await _db.rpc('create_blank_form',
          params: {'p_event_id': eventId, 'p_title': title})}';

  @override
  Future<String> createFromTemplate(String eventId, String slug) async =>
      '${await _db.rpc('create_form_from_template',
          params: {'p_event_id': eventId, 'p_template_slug': slug})}';

  @override
  Future<FormView> load(String formId) async {
    final raw = await _db.rpc('form_public', params: {'p_form_id': formId});
    final all = Map<String, dynamic>.from(raw as Map);
    final form = Map<String, dynamic>.from((all['form'] as Map?) ?? const {});
    final fields = ((all['fields'] as List?) ?? const [])
        .map((e) => FormFieldSpec.fromRpc(Map<String, dynamic>.from(e as Map)))
        .toList();
    final mine = all['mine'];
    final owner = form['owner'] is Map ? form['owner'] as Map : const {};
    final club = form['club'] is Map ? form['club'] as Map : const {};
    final event = form['event'] is Map ? form['event'] as Map : const {};
    return FormView(
      doc: FormDoc(
        id: '${form['id']}',
        title: '${form['title'] ?? ''}',
        status: '${form['status'] ?? 'draft'}',
        intro: form['intro'] as String?,
        requireRsvp: form['require_rsvp'] == true,
        afterCheckin: form['after_checkin'] == true,
        canEdit: all['can_edit'] == true,
        fields: fields,
        standalone: form['standalone'] == true,
        isHidden: form['is_hidden'] == true,
        ownerUsername: owner['username'] as String?,
        ownerName: owner['display_name'] as String?,
        clubName: club['name'] as String?,
        clubHandle: club['handle'] as String?,
        eventId: event['id'] as String?,
      ),
      canAnswer: all['can_answer'] == true,
      reason: all['reason'] as String?,
      canRead: all['can_read'] == true,
      mine: mine is Map ? Map<String, dynamic>.from(mine) : null,
      myRole: mine is Map ? mine['role'] as String? : null,
    );
  }

  @override
  Future<void> save(FormDoc doc) => _db.rpc('save_event_form', params: {
        'p_form_id': doc.id,
        'p_form': doc.header,
        'p_fields': doc.fields.map((f) => f.toRpc()).toList(),
      });

  @override
  Future<void> publish(String formId) =>
      _db.rpc('publish_form', params: {'p_form_id': formId});

  @override
  Future<void> setAfterCheckin(String formId, bool on) =>
      _db.rpc('set_form_after_checkin',
          params: {'p_form_id': formId, 'p_on': on});

  @override
  Future<void> submit(
    String formId, {
    required Map<String, dynamic> answers,
    String? role,
  }) =>
      _db.rpc('submit_form_response', params: {
        'p_form_id': formId,
        'p_for_user': null,
        'p_role': role ?? 'peserta',
        'p_answers': answers,
      });

  @override
  Future<FormAnalysis> analysis(String formId) async {
    final raw = await _db.rpc('form_analysis', params: {'p_form_id': formId});
    final all = Map<String, dynamic>.from((raw as Map?) ?? const {});
    final counts = Map<String, dynamic>.from((all['responses'] as Map?) ?? const {});

    double? num_(dynamic v) => v == null ? null : (v as num).toDouble();
    int int_(dynamic v) => v == null ? 0 : (v as num).toInt();

    List<KiMean> ki(Object? list) => [
          for (final e in (list as List?) ?? const [])
            if (e is Map)
              KiMean(
                kiCode: int_(e['ki_code']),
                label: '${e['label'] ?? ''}',
                nBefore: int_(e['n_before']),
                meanBefore: num_(e['mean_before']),
                nAfter: int_(e['n_after']),
                meanAfter: num_(e['mean_after']),
                delta: num_(e['delta']),
              ),
        ];

    return FormAnalysis(
      peserta: int_(counts['peserta']),
      penganjur: int_(counts['penganjur']),
      s1: ki(all['s1']),
      s2: ki(all['s2']),
      s3: [
        for (final e in (all['s3'] as List?) ?? const [])
          if (e is Map)
            FeedbackMean(
              fieldId: '${e['field_id'] ?? ''}',
              label: '${e['label'] ?? ''}',
              n: int_(e['n']),
              mean: num_(e['mean']),
            ),
      ],
    );
  }

  @override
  Future<List<FormResponse>> responses(String formId) async {
    final rows = await _db.rpc('form_response_list', params: {'p_form_id': formId}) as List;
    return [
      for (final e in rows)
        if (e is Map)
          FormResponse(
            userId: '${e['user_id']}',
            displayName: '${e['display_name'] ?? e['username'] ?? ''}',
            studentId: e['student_id'] as String?,
            role: '${e['role'] ?? 'peserta'}',
            submittedAt: DateTime.tryParse('${e['submitted_at'] ?? ''}'),
            answers: e['answers'] is Map
                ? Map<String, dynamic>.from(e['answers'] as Map)
                : const {},
          ),
    ];
  }
}
