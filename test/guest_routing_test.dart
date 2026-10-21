import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/router.dart';
import 'package:mykerawang/screens/announcements/announcements_repository.dart';

void main() {
  String? guest(String loc) => authRedirect(Uri.parse(loc), loggedIn: false);

  test('guests can open the browse tabs and public pages', () {
    for (final p in [
      '/home', '/announcements', '/market', '/events', '/search',
      '/post/1', '/event/2', '/item/3', '/u/4', '/tag/jpk', '/settings/privacy',
    ]) {
      expect(guest(p), isNull, reason: p);
    }
  });

  test('member-only pages send guests to login with from', () {
    expect(guest('/create/post'), '/login?from=%2Fcreate%2Fpost');
    for (final p in ['/notifications', '/settings', '/profile', '/admin', '/post/1/edit']) {
      expect(guest(p), startsWith('/login'), reason: p);
    }
  });

  test('signed-in users leave login for from', () {
    expect(authRedirect(Uri.parse('/login?from=/market'), loggedIn: true), '/market');
    expect(authRedirect(Uri.parse('/profile'), loggedIn: true), isNull);
  });

  test('announcement categories', () {
    AnnouncementCategory c(Map<String, dynamic> p, String role) =>
        AnnouncementsRepository.categorize(p, {'role': role});
    expect(c({'tags': ['JPK']}, 'admin'), AnnouncementCategory.jpk);
    expect(c({'events': {'id': 'e'}}, 'club'), AnnouncementCategory.events);
    expect(c({}, 'club'), AnnouncementCategory.clubs);
    expect(c({}, 'admin'), AnnouncementCategory.kolej);
  });
}
