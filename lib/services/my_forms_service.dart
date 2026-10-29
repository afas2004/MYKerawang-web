import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of "My forms": a standalone form the caller owns, or one of a club
/// they are an officer of.
class MyForm {
  final String id;
  final String title;
  final String status;
  final String? clubId;
  final String? clubName;
  final String? clubHandle;
  final int responses;
  final bool isHidden;
  final DateTime? updatedAt;

  const MyForm({
    required this.id,
    required this.title,
    required this.status,
    this.clubId,
    this.clubName,
    this.clubHandle,
    this.responses = 0,
    this.isHidden = false,
    this.updatedAt,
  });

  bool get isOpen => status == 'open' && !isHidden;
  bool get isDraft => status == 'draft';

  /// The in-app link a post, event or announcement carries.
  String get path => '/f/$id';
}

/// One question of a gallery template, as the card and the preview show it.
class TemplateQuestion {
  final String kind;
  final String label;
  final String? labelMs;
  final bool required;
  final List<String> choices;
  final List<String> choicesMs;

  const TemplateQuestion({
    required this.kind,
    required this.label,
    this.labelMs,
    this.required = false,
    this.choices = const [],
    this.choicesMs = const [],
  });

  String labelIn(bool malay) => (malay ? labelMs : null) ?? label;
  List<String> choicesIn(bool malay) => malay && choicesMs.isNotEmpty ? choicesMs : choices;
}

/// A starting point in the template gallery (`form_template_gallery()`).
class GalleryTemplate {
  final String slug;
  final String name;
  final String? nameMs;
  final String? description;
  final String? descriptionMs;

  /// events · signups · feedback · orders · campus · academic.
  final String category;
  final List<TemplateQuestion> questions;

  const GalleryTemplate({
    required this.slug,
    required this.name,
    this.nameMs,
    this.description,
    this.descriptionMs,
    this.category = 'events',
    this.questions = const [],
  });

  String nameIn(bool malay) => (malay ? nameMs : null) ?? name;
  String descriptionIn(bool malay) => ((malay ? descriptionMs : null) ?? description) ?? '';

  /// Questions that are answered (headings are layout).
  int get questionCount => questions.where((q) => q.kind != 'heading').length;

  /// Search across both languages, so "baju" finds the merch order in English.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      name, nameMs, description, descriptionMs,
      for (final x in questions) ...[x.label, x.labelMs],
    ].whereType<String>().join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  static GalleryTemplate fromJson(Map<String, dynamic> j) {
    List<String> list(Object? v) => [for (final e in (v as List?) ?? const []) '$e'];
    return GalleryTemplate(
      slug: '${j['slug']}',
      name: '${j['name'] ?? ''}',
      nameMs: j['name_ms'] as String?,
      description: j['description'] as String?,
      descriptionMs: j['description_ms'] as String?,
      category: '${j['category'] ?? 'events'}',
      questions: [
        for (final f in (j['fields'] as List?) ?? const [])
          if (f is Map)
            TemplateQuestion(
              kind: '${f['kind']}',
              label: '${f['label'] ?? ''}',
              labelMs: f['label_ms'] as String?,
              required: f['required'] == true,
              choices: list(f['choices']),
              choicesMs: list(f['choices_ms']),
            ),
      ],
    );
  }
}

/// Standalone forms: creating, listing, closing and deleting them, and taking
/// back an answer. The editor and the answer page keep using [FormService],
/// which already works by form id.
///
/// Swappable for widget tests: `MyFormsService.instance = Fake…()`.
abstract class MyFormsService {
  Future<List<MyForm>> myForms();

  /// The template gallery, every template with its questions.
  Future<List<GalleryTemplate>> gallery();

  /// A new draft; [clubId] makes it the club's. [templateSlug] copies a
  /// gallery template's questions, in [lang] (`en` or `ms`).
  Future<String> create({String? title, String? clubId, String? templateSlug, String lang = 'en'});

  Future<void> close(String formId);

  /// Deletes the form and every answer to it.
  Future<void> delete(String formId);

  /// Removes the caller's own answer.
  Future<void> withdraw(String formId);

  static MyFormsService instance = const SupabaseMyFormsService();

  @visibleForTesting
  static void debugReset() => instance = const SupabaseMyFormsService();
}

class SupabaseMyFormsService implements MyFormsService {
  const SupabaseMyFormsService();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<MyForm>> myForms() async {
    final rows = await _db.rpc('my_forms') as List;
    return [
      for (final e in rows)
        if (e is Map)
          MyForm(
            id: '${e['id']}',
            title: '${e['title'] ?? ''}',
            status: '${e['status'] ?? 'draft'}',
            clubId: e['club_id'] as String?,
            clubName: e['club_name'] as String?,
            clubHandle: e['club_handle'] as String?,
            responses: (e['responses'] as num?)?.toInt() ?? 0,
            isHidden: e['is_hidden'] == true,
            updatedAt: DateTime.tryParse('${e['updated_at'] ?? ''}'),
          ),
    ];
  }

  @override
  Future<List<GalleryTemplate>> gallery() async {
    final raw = await _db.rpc('form_template_gallery');
    return [
      for (final e in (raw as List?) ?? const [])
        if (e is Map) GalleryTemplate.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  @override
  Future<String> create({
    String? title,
    String? clubId,
    String? templateSlug,
    String lang = 'en',
  }) async =>
      '${await _db.rpc('create_standalone_form', params: {
            'p_title': title,
            'p_club_id': clubId,
            'p_template_slug': templateSlug,
            'p_lang': lang,
          })}';

  @override
  Future<void> close(String formId) => _db.rpc('close_form', params: {'p_form_id': formId});

  @override
  Future<void> delete(String formId) => _db.rpc('delete_form', params: {'p_form_id': formId});

  @override
  Future<void> withdraw(String formId) =>
      _db.rpc('withdraw_form_response', params: {'p_form_id': formId});
}
