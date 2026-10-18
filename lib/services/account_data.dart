import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/file_saver_stub.dart'
    if (dart.library.js_interop) '../utils/file_saver_web.dart' as download;

/// PDPA self-service: export and delete the signed-in user's data.
class AccountData {
  AccountData._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Everything the app stores about the current user, as one JSON
  /// document. Each section is fetched independently; a section that
  /// can't be read is recorded under `_errors` instead of failing the
  /// whole export.
  static Future<Map<String, dynamic>> collect() async {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('not signed in');
    final uid = user.id;

    final out = <String, dynamic>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'account': {
        'id': uid,
        'email': user.email,
        'created_at': user.createdAt,
      },
    };
    final errors = <String, String>{};

    Future<void> section(String name, Future<Object?> Function() load) async {
      try {
        out[name] = await load();
      } catch (e) {
        errors[name] = '$e';
      }
    }

    await Future.wait([
      section('profile',
          () => _db.from('profiles').select().eq('id', uid).maybeSingle()),
      section(
          'contact_details',
          () => _db
              .from('profile_contacts')
              .select('phone_number, payment_qr_url, updated_at')
              .eq('user_id', uid)
              .maybeSingle()),
      // Base tables: RLS lets the author read their own anonymous rows.
      section('posts',
          () => _db.from('posts').select().eq('user_id', uid).order('created_at')),
      section('comments',
          () => _db.from('comments').select().eq('user_id', uid).order('created_at')),
      section('listings',
          () => _db.from('listings').select().eq('seller_id', uid).order('created_at')),
      section('events_organised',
          () => _db.from('events').select().eq('organizer_id', uid)),
      section('events_joined',
          () => _db.from('event_participants').select().eq('user_id', uid)),
      section('following',
          () => _db.from('followers').select('following_id').eq('follower_id', uid)),
      section('followers',
          () => _db.from('followers').select('follower_id').eq('following_id', uid)),
      section('saved_items',
          () => _db.from('saved_items').select().eq('user_id', uid)),
      section('notifications',
          () => _db.from('notifications').select().eq('user_id', uid).order('created_at')),
      section('reports_filed',
          () => _db.from('reports').select().eq('reporter_id', uid)),
    ]);

    if (errors.isNotEmpty) out['_errors'] = errors;
    return out;
  }

  /// Builds the export and hands it to the user: a browser download on
  /// web, the share sheet elsewhere.
  static Future<void> exportToFile() async {
    final data = await collect();
    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final name = 'mykerawang-data-$date.json';

    if (kIsWeb) {
      download.downloadBytes(bytes, name);
      return;
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/json', name: name)],
      fileNameOverrides: [name],
    ));
  }

  /// Deletes the account server-side (see migration
  /// 20261019003200_delete_my_account.sql), then signs out locally.
  static Future<void> deleteAccount(String confirmUsername) async {
    await _db.rpc('delete_my_account',
        params: {'p_confirm_username': confirmUsername});
    // The auth user is gone; local sign-out just clears the session.
    try {
      await _db.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  /// True when [typed] confirms [username] (case-insensitive, optional @).
  static bool confirms(String typed, String? username) {
    if (username == null || username.isEmpty) return false;
    final t = typed.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    return t == username.toLowerCase();
  }
}
