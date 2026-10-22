import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/announcements/announcements_repository.dart';
import 'package:mykerawang/screens/announcements/announcements_screen.dart';

import 'helpers/pump_app.dart';

final _now = DateTime.utc(2026, 10, 22, 12);

Map<String, dynamic> row({
  String id = 'a1',
  String? category = 'kolej',
  Map<String, dynamic>? club,
  bool pinned = false,
  DateTime? featureUntil,
  String? cover,
  List<Map<String, String>>? links,
  String createdAt = '2026-10-21T08:00:00Z',
}) =>
    {
      'id': id,
      'title': 'Title $id',
      'body': 'Body of $id, long enough to need a preview.',
      'is_announcement': true,
      'announcement_category': category,
      'is_pinned': pinned,
      'created_at': createdAt,
      'user_id': 'u1',
      'profiles': {'id': 'u1', 'display_name': 'Pejabat Kolej', 'is_verified': true},
      'club': club,
      if (featureUntil != null) 'feature_until': featureUntil.toIso8601String(),
      if (cover != null) 'cover_url': cover,
      if (links != null) 'action_links': links,
    };

class _FakeRepo extends AnnouncementsRepository {
  final AnnouncementsData data;
  _FakeRepo(this.data);
  @override
  Future<AnnouncementsData> load() async => data;
}

void main() {
  group('parsing', () {
    test('category, channel, links, featured', () {
      final a = Announcement.fromRow(
        row(
          category: 'club',
          club: {'id': 'c1', 'handle': 'robotics', 'name': 'Robotics Club', 'is_verified': true},
          featureUntil: _now.add(const Duration(days: 1)),
          links: [
            {'label': 'Register', 'url': 'https://forms.gle/x'},
            {'label': 'Bad', 'url': 'javascript:alert(1)'},
            {'label': 'Third', 'url': 'https://a.b'},
          ],
        ),
        now: _now,
      );
      expect(a.category, AnnouncementCategory.club);
      expect(a.channel!.key, 'club:c1');
      expect(a.channel!.name, 'Robotics Club');
      expect(a.channel!.verified, isTrue);
      expect(a.featured, isTrue);
      // javascript: dropped; at most two kept.
      expect(a.links.map((l) => l.label), ['Register', 'Third']);
    });

    test('unknown category → general; author channel without a club', () {
      final a = Announcement.fromRow(row(category: 'weird'), now: _now);
      expect(a.category, AnnouncementCategory.general);
      expect(a.channel!.key, 'user:u1');
      expect(a.featured, isFalse);
    });

    test('cover falls back to the first photo', () {
      expect(Announcement.fromRow(row(cover: 'https://x/c.jpg')).coverUrl,
          'https://x/c.jpg');
      final r = row()..['gallery_urls'] = ['https://x/g.jpg'];
      expect(Announcement.fromRow(r).coverUrl, 'https://x/g.jpg');
      expect(Announcement.fromRow(row()).coverUrl, isNull);
    });

    test('hero: featured, else pinned, else newest three', () {
      List<String> hero(List<Map<String, dynamic>> rows) => AnnouncementsData(
            items: AnnouncementsData.sorted(
                [for (final r in rows) Announcement.fromRow(r, now: _now)]),
            upcomingEvents: const [],
          ).featured.map((a) => a.id).toList();

      expect(
          hero([
            row(id: 'a'),
            row(id: 'b', pinned: true),
            row(id: 'c', featureUntil: _now.add(const Duration(hours: 1))),
          ]),
          ['c']);
      expect(hero([row(id: 'a'), row(id: 'b', pinned: true)]), ['b']);
      expect(
          hero([
            for (var i = 0; i < 5; i++)
              row(id: 'n$i', createdAt: '2026-10-1${i}T00:00:00Z'),
          ]),
          ['n4', 'n3', 'n2']);
    });

    test('channels: clubs first, each once', () {
      final d = AnnouncementsData(items: [
        Announcement.fromRow(row(id: 'x')),
        Announcement.fromRow(row(id: 'y', club: {'id': 'c1', 'name': 'Club'})),
        Announcement.fromRow(row(id: 'z')),
      ], upcomingEvents: const []);
      expect(d.channels.map((c) => c.key), ['club:c1', 'user:u1']);
    });
  });

  group('screen', () {
    final data = AnnouncementsData(
      items: AnnouncementsData.sorted([
        Announcement.fromRow(row(
          id: 'p',
          pinned: true,
          links: [
            {'label': 'Register', 'url': 'https://forms.gle/x'}
          ],
        )),
        Announcement.fromRow(row(
            id: 'c',
            category: 'club',
            club: {'id': 'c1', 'name': 'Robotics Club', 'is_verified': true})),
      ]),
      upcomingEvents: const [],
    );

    Future<void> pump(WidgetTester tester, {bool canPost = false}) async {
      await initTestSupabase(tester);
      await setWidth(tester, 375, height: 1600);
      await pumpScreen(
        tester,
        AnnouncementsScreen(
          repository: _FakeRepo(data),
          canPost: () async => canPost,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('cards, CTA and channel chips', (tester) async {
      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AnnouncementCard), findsNWidgets(2));
      expect(find.text('Register'), findsOneWidget);
      expect(find.text('Robotics Club'), findsWidgets);
      expect(find.byTooltip('New announcement'), findsNothing);
    });

    testWidgets('category tab filters; empty category has its own message',
        (tester) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Clubs'));
      await tester.pump();
      expect(find.byType(AnnouncementCard), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'JPK'));
      await tester.pump();
      expect(find.byType(AnnouncementCard), findsNothing);
      expect(find.text('No JPK announcements yet'), findsOneWidget);
    });

    testWidgets('New announcement shows only when allowed', (tester) async {
      await pump(tester, canPost: true);
      expect(find.byTooltip('New announcement'), findsOneWidget);
    });
  });
}
