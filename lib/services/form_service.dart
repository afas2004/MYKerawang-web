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

  const FormDoc({
    required this.id,
    required this.title,
    required this.status,
    this.intro,
    this.requireRsvp = false,
    this.afterCheckin = false,
    this.canEdit = true,
    this.fields = const [],
  });

  bool get isDraft => status == 'draft';

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
      );
}

/// The editor's data source. Swappable so widget tests never touch Supabase:
/// `FormService.instance = FakeFormService()`.
abstract class FormService {
  Future<List<FormTemplate>> templates();

  /// The event's newest draft/open form, or null when it has none.
  Future<FormSummary?> summary(String eventId);

  Future<String> createBlank(String eventId, {String? title});

  Future<String> createFromTemplate(String eventId, String slug);

  Future<FormDoc> load(String formId);

  Future<void> save(FormDoc doc);

  Future<void> publish(String formId);

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
  Future<String> createBlank(String eventId, {String? title}) async =>
      '${await _db.rpc('create_blank_form',
          params: {'p_event_id': eventId, 'p_title': title})}';

  @override
  Future<String> createFromTemplate(String eventId, String slug) async =>
      '${await _db.rpc('create_form_from_template',
          params: {'p_event_id': eventId, 'p_template_slug': slug})}';

  @override
  Future<FormDoc> load(String formId) async {
    final raw = await _db.rpc('form_public', params: {'p_form_id': formId});
    final all = Map<String, dynamic>.from(raw as Map);
    final form = Map<String, dynamic>.from((all['form'] as Map?) ?? const {});
    final fields = ((all['fields'] as List?) ?? const [])
        .map((e) => FormFieldSpec.fromRpc(Map<String, dynamic>.from(e as Map)))
        .toList();
    return FormDoc(
      id: '${form['id']}',
      title: '${form['title'] ?? ''}',
      status: '${form['status'] ?? 'draft'}',
      intro: form['intro'] as String?,
      requireRsvp: form['require_rsvp'] == true,
      afterCheckin: form['after_checkin'] == true,
      canEdit: all['can_edit'] == true,
      fields: fields,
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
}
