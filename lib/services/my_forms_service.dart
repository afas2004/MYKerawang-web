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

/// Standalone forms: creating, listing, closing and deleting them, and taking
/// back an answer. The editor and the answer page keep using [FormService],
/// which already works by form id.
///
/// Swappable for widget tests: `MyFormsService.instance = Fake…()`.
abstract class MyFormsService {
  Future<List<MyForm>> myForms();

  /// A new draft; [clubId] makes it the club's. [templateSlug] copies a
  /// shipped template's questions (the KI survey).
  Future<String> create({String? title, String? clubId, String? templateSlug});

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
  Future<String> create({String? title, String? clubId, String? templateSlug}) async =>
      '${await _db.rpc('create_standalone_form', params: {
            'p_title': title,
            'p_club_id': clubId,
            'p_template_slug': templateSlug,
          })}';

  @override
  Future<void> close(String formId) => _db.rpc('close_form', params: {'p_form_id': formId});

  @override
  Future<void> delete(String formId) => _db.rpc('delete_form', params: {'p_form_id': formId});

  @override
  Future<void> withdraw(String formId) =>
      _db.rpc('withdraw_form_response', params: {'p_form_id': formId});
}
