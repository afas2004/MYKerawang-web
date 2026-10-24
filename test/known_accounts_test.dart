import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/known_accounts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('label prefers the name, falls back to the email', () {
    const noName = KnownAccount(id: '1', email: 'a@x.my');
    expect(noName.label, 'a@x.my');

    const named = KnownAccount(id: '2', email: 'b@x.my', name: '  Ali  ');
    expect(named.label, 'Ali');

    const blank = KnownAccount(id: '3', email: 'c@x.my', name: '   ');
    expect(blank.label, 'c@x.my');
  });

  test('round trips through JSON, omitting empty fields', () {
    const account = KnownAccount(
        id: '1', email: 'e@x.my', name: 'N', provider: 'google');
    final back = KnownAccount.fromJson(account.toJson());
    expect(back.id, '1');
    expect(back.email, 'e@x.my');
    expect(back.name, 'N');
    expect(back.provider, 'google');

    final bare = KnownAccount(id: '2', email: 'z@x.my').toJson();
    expect(bare.containsKey('name'), isFalse);
    expect(bare.containsKey('provider'), isFalse);
  });

  test('others excludes the current account and keeps newest first', () async {
    SharedPreferences.setMockInitialValues({
      'known_accounts_v1': jsonEncode([
        {'id': 'a', 'email': 'a@x.my'},
        {'id': 'b', 'email': 'b@x.my'},
      ]),
    });

    final others = await KnownAccounts.others('a');
    expect([for (final o in others) o.id], ['b']);
  });

  test('a corrupted store never blocks sign-in', () async {
    SharedPreferences.setMockInitialValues({'known_accounts_v1': 'not json'});
    expect(await KnownAccounts.load(), isEmpty);
    expect(await KnownAccounts.others('a'), isEmpty);
  });

  test('entries without an id are ignored', () async {
    SharedPreferences.setMockInitialValues({
      'known_accounts_v1': jsonEncode([
        {'email': 'stale@x.my'},
        {'id': 'b', 'email': 'b@x.my'},
      ]),
    });
    expect([for (final a in await KnownAccounts.load()) a.id], ['b']);
  });

  test('the notice is shown once per account', () async {
    expect(await KnownAccounts.hasBeenAsked('x'), isFalse);
    await KnownAccounts.markAsked('x');
    expect(await KnownAccounts.hasBeenAsked('x'), isTrue);
    expect(await KnownAccounts.hasBeenAsked('y'), isFalse);
  });

  test('forget removes one account', () async {
    SharedPreferences.setMockInitialValues({
      'known_accounts_v1': jsonEncode([
        {'id': 'a', 'email': 'a@x.my'},
        {'id': 'b', 'email': 'b@x.my'},
      ]),
    });
    await KnownAccounts.forget('a');
    expect([for (final o in await KnownAccounts.load()) o.id], ['b']);
  });
}
