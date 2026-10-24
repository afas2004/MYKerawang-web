import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One account this device has signed in as.
class KnownAccount {
  final String id;
  final String email;
  final String? name;

  /// 'google' or 'email' (whatever Supabase put in app_metadata).
  final String? provider;

  const KnownAccount({
    required this.id,
    required this.email,
    this.name,
    this.provider,
  });

  /// What the user recognises: their display name, else the address.
  String get label {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        if (name != null) 'name': name,
        if (provider != null) 'provider': provider,
      };

  static KnownAccount fromJson(Map<String, dynamic> json) => KnownAccount(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        name: json['name'] as String?,
        provider: json['provider'] as String?,
      );

  static KnownAccount of(User user) => KnownAccount(
        id: user.id,
        email: user.email ?? '',
        name: _nameOf(user),
        provider: user.appMetadata['provider'] as String?,
      );

  static String? _nameOf(User user) {
    final meta = user.userMetadata;
    if (meta == null) return null;
    for (final key in const ['display_name', 'full_name', 'name']) {
      final v = meta[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

/// The accounts this browser/device has signed in as, newest first.
///
/// Two accounts for one person is the most likely support problem after
/// open registration: a student signs in with their UiTM Google account
/// once, then later with a personal one. Catching it on the device is the
/// cheapest reliable signal — it needs no server change and no permission.
///
/// This only ever *warns*. Nothing is merged or deleted automatically.
/// The list is local, capped, and never leaves the device.
class KnownAccounts {
  static const _key = 'known_accounts_v1';
  static const _max = 5;

  static Future<List<KnownAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) KnownAccount.fromJson(e),
      ].where((a) => a.id.isNotEmpty).toList();
    } catch (_) {
      // A corrupted entry must never block sign-in.
      return const [];
    }
  }

  /// Accounts other than [currentId], newest first.
  static Future<List<KnownAccount>> others(String currentId) async {
    final all = await load();
    return [for (final a in all) if (a.id != currentId) a];
  }

  /// Records [user] as the most recent account on this device.
  static Future<void> remember(User user) async {
    if (user.email == null || user.email!.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final entry = KnownAccount.of(user);
    final all = await load();
    final next = [entry, for (final a in all) if (a.id != entry.id) a];
    if (next.length > _max) next.removeRange(_max, next.length);
    await prefs.setString(_key, jsonEncode([for (final a in next) a.toJson()]));
  }

  /// Forgets one account (used by tests and by "this is not me").
  static Future<void> forget(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [for (final a in await load()) if (a.id != id) a];
    await prefs.setString(_key, jsonEncode([for (final a in next) a.toJson()]));
  }

  static const _askedKey = 'known_accounts_asked_v1';

  /// True once this account has been shown the "another account" notice.
  /// Asking again on every sign-in would train people to dismiss it.
  static Future<bool> hasBeenAsked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_askedKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final list = jsonDecode(raw);
      return list is List && list.contains(id);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markAsked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final asked = <String>{};
    try {
      final raw = prefs.getString(_askedKey);
      final list = raw == null ? null : jsonDecode(raw);
      if (list is List) asked.addAll(list.whereType<String>());
    } catch (_) {
      // Ignore a corrupted list; start a fresh one.
    }
    asked.add(id);
    final trimmed = asked.toList();
    if (trimmed.length > 20) trimmed.removeRange(0, trimmed.length - 20);
    await prefs.setString(_askedKey, jsonEncode(trimmed));
  }
}
