import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/services/notification_links.dart';
import 'package:mykerawang/services/notification_prefs.dart';
import 'package:mykerawang/services/notification_text.dart';

void main() {
  group('notificationPath opens the exact place', () {
    test('a comment on a post scrolls to that comment', () {
      expect(
          notificationPath({
            'type': 'comment',
            'data': {'post_id': 'p1', 'comment_id': 'c1'}
          }),
          '/post/p1?c=c1');
    });
    test('a comment on an event', () {
      expect(
          notificationPath({
            'type': 'comment',
            'data': {'event_id': 'e1', 'comment_id': 'c1'}
          }),
          '/event/e1?c=c1');
    });
    test('form answers open the answers page', () {
      expect(
          notificationPath({
            'type': 'form_answer',
            'data': {'form_id': 'f1', 'event_id': 'e1'}
          }),
          '/event/e1/form/responses?f=f1');
      expect(
          notificationPath({
            'type': 'form_answer',
            'data': {'form_id': 'f1', 'event_id': null}
          }),
          '/f/f1/responses');
    });
    test('reminders, changes and follows', () {
      expect(notificationPath({'type': 'event_reminder', 'data': {'event_id': 'e1'}}), '/event/e1');
      expect(notificationPath({'type': 'follow', 'actor_id': 'u1', 'data': {}}), '/u/u1');
      expect(notificationPath({'type': 'moderation', 'data': {'route': '/standing'}}), '/standing');
      expect(notificationPath({'type': 'x', 'data': {}}), isNull);
    });
  });

  group('notificationHeadline speaks the reader\'s language', () {
    test('grouped comments in Malay', () {
      final h = notificationHeadline(
          AppStrings.ms,
          {
            'type': 'comment',
            'count': 3,
            'data': {'post_id': 'p', 'snippet': 'Saya ikut!'}
          },
          'Aina');
      expect(h, ('Aina dan 2 lagi mengulas siaran anda', 'Saya ikut!'));
    });
    test('anonymous comment says Someone', () {
      final h = notificationHeadline(AppStrings.en,
          {'type': 'comment', 'data': {'post_id': 'p'}}, null);
      expect(h!.$1, 'Someone commented on your post');
    });
    test('form answers name the latest guest', () {
      final h = notificationHeadline(
          AppStrings.en,
          {
            'type': 'form_answer',
            'count': 5,
            'data': {'form_title': 'Borang', 'who': 'Ali'}
          },
          null);
      expect(h, ('5 new answers to your form', 'Borang · Latest: Ali'));
    });
    test('moderation keeps the stored text', () {
      expect(notificationHeadline(AppStrings.en, {'type': 'moderation', 'data': {}}, null), isNull);
    });
  });

  group('filters', () {
    test('by category, with older rows by type', () {
      expect(notificationFilter({'category': 'form_answers'}), NotifFilter.forms);
      expect(notificationFilter({'category': 'reminders'}), NotifFilter.events);
      expect(notificationFilter({'type': 'mention'}), NotifFilter.social);
      expect(notificationFilter({'type': 'moderation'}), NotifFilter.account);
    });
  });

  group('NotificationPrefs', () {
    test('defaults match the database', () {
      const p = NotificationPrefs();
      expect(p.level('comments'), 'push');
      expect(p.level('event_joins'), 'bell');
      expect(p.level('new_events'), 'off');
      expect(p.quietEnabled, isTrue);
      expect(p.quietStart.hour, 23);
    });
    test('follows never reach the phone', () {
      expect(const NotificationPrefs().withLevel('follows', 'push').level('follows'), 'bell');
    });
  });
}
