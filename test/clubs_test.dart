import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/admin/club_approvals_tab.dart';
import 'package:mykerawang/screens/clubs/club_directory_screen.dart';
import 'package:mykerawang/screens/clubs/club_manage_screen.dart';
import 'package:mykerawang/screens/clubs/club_page_screen.dart';
import 'package:mykerawang/screens/clubs/club_register_screen.dart';
import 'package:mykerawang/screens/clubs/club_strings.dart';
import 'package:mykerawang/screens/clubs/post_as_selector.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Clubs: pure rules the UI relies on, and every screen at phone (375)
/// and desktop (1280) widths with injected data. Overflow fails a test.
void main() {
  const c = ClubStrings.en;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ------------------------------------------------------------ pure rules
  group('handles', () {
    test('validateHandle mirrors the DB check', () {
      expect(validateHandle(''), HandleIssue.empty);
      expect(validateHandle('ab'), HandleIssue.tooShort);
      expect(validateHandle('a' * 31), HandleIssue.tooLong);
      expect(validateHandle('bad handle'), HandleIssue.badChars);
      expect(validateHandle('kelab-catur'), HandleIssue.badChars);
      expect(validateHandle('Debate_UiTM2'), isNull);
    });

    test('suggestHandle is readable and valid', () {
      expect(suggestHandle('Debate Society UiTM'), 'DebateSocietyUiTM');
      expect(suggestHandle('kelab   catur & dam!'), 'KelabCaturDam');
      expect(validateHandle(suggestHandle('A very long club name that keeps going on')), isNull);
    });

    test('cleanUsername strips @ and spaces', () {
      expect(cleanUsername('  @@aiman '), 'aiman');
    });
  });

  test('sortMembers: president, officers, members, by join date', () {
    final m = sortMembers([
      ClubMember(userId: 'm', role: 'member', joinedAt: DateTime(2024)),
      ClubMember(userId: 'o2', role: 'officer', joinedAt: DateTime(2025)),
      ClubMember(userId: 'p', role: 'president', joinedAt: DateTime(2026)),
      ClubMember(userId: 'o1', role: 'officer', joinedAt: DateTime(2023)),
    ]);
    expect(m.map((x) => x.userId), ['p', 'o1', 'o2', 'm']);
  });

  test('roles', () {
    expect(canManageClub('president'), isTrue);
    expect(canManageClub('officer'), isTrue);
    expect(canManageClub('member'), isFalse);
    expect(canManageClub(null), isFalse);
    expect(isPresident('officer'), isFalse);
  });

  test('clubErrorCode decodes RPC errors', () {
    expect(clubErrorCode(const PostgrestException(message: 'CLUB:handle_taken')), 'handle_taken');
    expect(clubErrorCode(Exception('CLUB:not_president')), 'not_president');
    expect(clubErrorCode(const PostgrestException(message: 'JWT expired')), isNull);
  });

  test('PostAsOption.applyTo sets club_id and never posts a club anonymously', () {
    const self = PostAsOption.self('Me');
    const club = PostAsOption.club(clubId: 'c1', label: 'Debate', handle: 'debate');
    expect(self.applyTo({'title': 'x'})['club_id'], isNull);
    final row = club.applyTo({'title': 'x', 'is_anonymous': true});
    expect(row['club_id'], 'c1');
    expect(row['is_anonymous'], isFalse);
  });

  test('buildSocials drops blanks and @', () {
    expect(buildSocials(instagram: '@debate', tiktok: ' ', website: 'https://x.my'),
        {'instagram': 'debate', 'website': 'https://x.my'});
  });

  test('Club.fromJson', () {
    final club = Club.fromJson({
      'id': '1', 'handle': 'Debate', 'name': 'Debate Society', 'is_verified': true,
      'status': 'active', 'socials': {'instagram': 'debate', 'tiktok': ''},
    });
    expect(club.isActive, isTrue);
    expect(club.socials, {'instagram': 'debate'});
  });

  test('every category has a label in en and ms', () {
    for (final s in [ClubStrings.en, ClubStrings.ms]) {
      for (final k in ClubStrings.categories) {
        expect(s.categoryLabel(k), isNotEmpty);
      }
    }
    expect(ClubStrings.ms.follow, 'Ikuti');
  });

  // ------------------------------------------------------------ screens
  Future<void> pumpAt(WidgetTester tester, double width, Widget child, {bool scaffold = true}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(home: scaffold ? Scaffold(body: child) : child),
    ));
    await tester.pumpAndSettle();
  }

  const club = Club(
    id: 'c1',
    handle: 'DebateUiTM',
    name: 'Debate Society of Universiti Teknologi MARA',
    description: 'We argue about everything, politely. Weekly sessions every Thursday night at the kolej hall.',
    category: 'academic',
    faculty: 'FSKM',
    contactEmail: 'debate@example.com',
    socials: {'instagram': 'debateuitm'},
    isVerified: true,
  );
  final members = [
    ClubMember(userId: 'u1', role: 'president', username: 'aiman', displayName: 'Aiman Hakim'),
    ClubMember(userId: 'u2', role: 'officer', username: 'siti', displayName: 'Siti Nur'),
  ];

  for (final w in [375.0, 1280.0]) {
    testWidgets('club page at ${w.toInt()} px', (tester) async {
      final follows = <bool>[];
      await pumpAt(
        tester,
        w,
        ClubPageView(
          club: club,
          myRole: 'officer',
          followers: 41,
          following: false,
          signedIn: true,
          onSetFollowing: (v) async => follows.add(v),
          onManage: () {},
          loadPosts: () async => [],
          loadEvents: () async => [],
          loadListings: () async => [],
          loadMembers: () async => members,
        ),
        scaffold: false,
      );
      expect(find.textContaining('41 followers'), findsOneWidget);
      expect(find.text(c.manage), findsOneWidget);
      await tester.tap(find.text(c.follow));
      await tester.pumpAndSettle();
      expect(follows, [true]);
      expect(find.textContaining('42 followers'), findsOneWidget);
      expect(find.text(c.following), findsOneWidget);
      // Members tab.
      DefaultTabController.of(tester.element(find.byType(TabBar))).animateTo(3);
      await tester.pumpAndSettle();
      expect(find.text('Aiman Hakim'), findsOneWidget);
      expect(find.text(c.rolePresident), findsOneWidget);
    });

    testWidgets('pending club shows officer banner at ${w.toInt()} px', (tester) async {
      await pumpAt(
        tester,
        w,
        ClubPageView(
          club: const Club(id: 'c2', handle: 'chess', name: 'Chess', status: 'pending'),
          myRole: 'president',
          followers: 0,
          following: false,
          signedIn: true,
          onSetFollowing: (_) async {},
          onManage: () {},
          loadPosts: () async => [],
          loadEvents: () async => [],
          loadListings: () async => [],
          loadMembers: () async => [],
        ),
        scaffold: false,
      );
      expect(find.text(c.pendingBanner), findsOneWidget);
      expect(find.text(c.follow), findsNothing, reason: 'cannot follow a pending club');
      expect(find.text(c.noAnnouncements), findsOneWidget);
    });

    testWidgets('directory at ${w.toInt()} px', (tester) async {
      final opened = <String>[];
      await pumpAt(
        tester,
        w,
        ClubDirectoryView(
          clubs: [club, const Club(id: 'c3', handle: 'robotics', name: 'Robotics', category: 'tech')],
          followerCounts: const {'c1': 41},
          myClubs: const [
            {'id': 'c2', 'handle': 'chess', 'name': 'Chess', 'status': 'pending'},
          ],
          loading: false,
          error: null,
          search: '',
          category: null,
          signedIn: true,
          onSearch: (_) {},
          onCategory: (_) {},
          onRetry: () {},
          onOpen: opened.add,
          onRegister: () {},
        ),
      );
      expect(find.text('Robotics'), findsOneWidget);
      expect(find.textContaining('Chess · ${c.statusPending}'), findsOneWidget);
      await tester.tap(find.text('Robotics'));
      expect(opened, ['robotics']);
    });

    testWidgets('empty directory at ${w.toInt()} px', (tester) async {
      await pumpAt(
        tester,
        w,
        ClubDirectoryView(
          clubs: const [],
          followerCounts: const {},
          myClubs: const [],
          loading: false,
          error: null,
          search: 'zzz',
          category: null,
          signedIn: false,
          onSearch: (_) {},
          onCategory: (_) {},
          onRetry: () {},
          onOpen: (_) {},
          onRegister: () {},
        ),
      );
      expect(find.text(c.noMatch), findsOneWidget);
      expect(find.text(c.registerClub), findsNothing, reason: 'guests cannot register');
    });

    testWidgets('register flow at ${w.toInt()} px', (tester) async {
      Map<String, Object?>? sent;
      var calls = 0;
      await pumpAt(
        tester,
        w,
        ClubRegisterScreen(
          register: ({required name, required handle, description, category, required proofNote}) async {
            calls++;
            if (calls == 1) throw Exception('CLUB:handle_taken');
            sent = {'name': name, 'handle': handle, 'proof': proofNote};
            return 'new-id';
          },
        ),
        scaffold: false,
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Kelab Catur');
      await tester.pump();
      expect(find.text('KelabCatur'), findsOneWidget, reason: 'handle suggested from name');
      final send = find.widgetWithText(FilledButton, c.submitRequest);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(find.text(c.proofTooShort), findsOneWidget);
      await tester.enterText(fields.at(3), 'HEP registration no. 99');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(find.text(c.handleTaken), findsOneWidget);
      await tester.enterText(fields.at(1), 'KelabCatur2');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(sent, {'name': 'Kelab Catur', 'handle': 'KelabCatur2', 'proof': 'HEP registration no. 99'});
      expect(find.text(c.requestSent), findsOneWidget);
    });

    testWidgets('manage page at ${w.toInt()} px', (tester) async {
      ClubEdit? saved;
      final added = <String>[];
      await pumpAt(
        tester,
        w,
        ClubManageView(
          club: club,
          myRole: 'president',
          myUserId: 'u1',
          members: members,
          actions: ClubManageActions(
            save: (e) async => saved = e,
            pickImage: () async => null,
            addOfficer: (u) async => added.add(u),
            removeOfficer: (_) async {},
            transfer: (_) async {},
          ),
        ),
        scaffold: false,
      );
      final save = find.widgetWithText(FilledButton, c.saveChanges);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?.name, club.name);
      expect(saved?.socials, {'instagram': 'debateuitm'});
      final field = find.widgetWithText(TextField, c.addOfficer);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '@farid');
      await tester.tap(find.widgetWithText(FilledButton, c.addOfficer));
      await tester.pumpAndSettle();
      expect(added, ['farid']);
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, c.transfer), findsOneWidget);
    });

    testWidgets('officer (not president) sees Leave, no transfer at ${w.toInt()} px', (tester) async {
      await pumpAt(
        tester,
        w,
        ClubManageView(
          club: club,
          myRole: 'officer',
          myUserId: 'u2',
          members: members,
          actions: ClubManageActions(
            save: (_) async {},
            pickImage: () async => null,
            addOfficer: (_) async {},
            removeOfficer: (_) async {},
            transfer: (_) async {},
          ),
        ),
        scaffold: false,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text(c.leave), findsOneWidget);
      expect(find.text(c.transfer, skipOffstage: false), findsNothing);
      expect(find.text(c.addOfficer, skipOffstage: false), findsNothing);
    });

    testWidgets('admin club request card at ${w.toInt()} px', (tester) async {
      var approved = false;
      await pumpAt(
        tester,
        w,
        SingleChildScrollView(
          child: ClubRequestCard(
            request: {
              'id': 'c9',
              'name': 'Kelab Fotografi Kolej Kerawang',
              'handle': 'Fotografi',
              'category': 'arts',
              'description': 'Photo walks.',
              'proof_note': 'Advisor: Dr. Lim, HEP ref 77',
              'created_at': DateTime(2026, 10, 20).toIso8601String(),
              'president': {'id': 'u5', 'username': 'lim', 'display_name': 'Lim Wei'},
            },
            busy: false,
            onApprove: () => approved = true,
            onReject: () {},
          ),
        ),
      );
      expect(find.text('Advisor: Dr. Lim, HEP ref 77'), findsOneWidget);
      await tester.tap(find.text(c.approve));
      expect(approved, isTrue);
    });

    testWidgets('post-as selector at ${w.toInt()} px', (tester) async {
      PostAsOption? picked;
      await pumpAt(
        tester,
        w,
        PostAsSelector(
          selfLabel: 'Aiman',
          value: null,
          onChanged: (o) => picked = o,
          options: const [
            PostAsOption.self('Aiman'),
            PostAsOption.club(clubId: 'c1', label: 'Debate Society', handle: 'debate', verified: true),
          ],
        ),
      );
      expect(find.text(c.postAs), findsOneWidget);
      await tester.tap(find.text('Debate Society'));
      expect(picked?.clubId, 'c1');
    });
  }

  testWidgets('post-as selector hidden for non-officers', (tester) async {
    await pumpAt(
      tester,
      375,
      PostAsSelector(
        selfLabel: 'Aiman',
        value: null,
        onChanged: (_) {},
        options: const [PostAsOption.self('Aiman')],
      ),
    );
    expect(find.text(c.postAs), findsNothing);
  });

  testWidgets('admin tab lists injected requests', (tester) async {
    await pumpAt(
      tester,
      375,
      ClubApprovalsTab(
        load: () async => [
          {'id': 'c9', 'name': 'Fotografi', 'handle': 'Fotografi', 'proof_note': 'HEP 77'},
        ],
        decide: (_, __, ___) async {},
      ),
    );
    expect(find.text('Fotografi'), findsOneWidget);
  });
}
