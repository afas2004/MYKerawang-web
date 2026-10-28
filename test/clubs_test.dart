import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/admin/club_approvals_tab.dart';
import 'package:mykerawang/screens/admin/club_registry_screen.dart';
import 'package:mykerawang/screens/admin/join_requests_tab.dart';
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

    test('registryHandlePreview matches what register_club will actually assign', () {
      // strip punctuation, keep case
      expect(registryHandlePreview('HEP/2024/042', 'Debate Society'), 'HEP2024042');
      // a short code gets the "club" prefix, exactly like `v_base := 'club' || v_base`
      expect(registryHandlePreview('A/B', 'Debate Society'), 'clubAB');
      // cut to 24 before the prefix check
      expect(registryHandlePreview('HEP/2024/${'9' * 30}', 'X'), 'HEP2024${'9' * 17}');
      // an empty code falls back to the name, as the database's coalesce does
      expect(registryHandlePreview('', 'Debate Society'), 'DebateSociety');
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

  test('parseCouncil reads "Name - Position" lines', () {
    expect(parseCouncil('Aiman - Secretary\n\nSiti | Treasurer\nAli'), [
      {'name': 'Aiman', 'position': 'Secretary'},
      {'name': 'Siti', 'position': 'Treasurer'},
      {'name': 'Ali', 'position': ''},
    ]);
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

    testWidgets('club page join request at ${w.toInt()} px', (tester) async {
      var joined = 0;
      await pumpAt(
        tester,
        w,
        ClubPageView(
          club: club,
          myRole: null,
          followers: 0,
          following: false,
          signedIn: true,
          onJoin: () async => joined++,
          onSetFollowing: (_) async {},
          onManage: () {},
          loadPosts: () async => [],
          loadEvents: () async => [],
          loadListings: () async => [],
          loadMembers: () async => [],
        ),
        scaffold: false,
      );
      // The request entry point is a footer on the Members tab now, not a
      // header button. Scroll the tab strip first: on a 375 px screen the
      // Members tab sits off the right edge.
      await tester.ensureVisible(find.text(c.tabMembers));
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.tabMembers));
      await tester.pumpAndSettle();
      expect(find.text(c.joinClub), findsOneWidget);
      await tester.tap(find.text(c.joinClub));
      await tester.pumpAndSettle();
      expect(joined, 1);
      expect(find.text(c.joinPending), findsOneWidget);
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
      await pumpAt(
        tester,
        w,
        ClubRegisterScreen(
          loadRegistry: () async => const [
            ClubRegistryEntry(
              id: 'r1',
              code: 'HEP/2024/012',
              name: 'Kelab Catur',
              faculty: 'FSKM',
              category: 'academic',
            ),
          ],
          register: ({required registryId, required officialEmail, required position, council = const [], note}) async {
            sent = {
              'registry': registryId,
              'email': officialEmail,
              'position': position,
              'council': council,
            };
            return {'id': 'new-id', 'handle': 'HEP2024012'};
          },
        ),
        scaffold: false,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kelab Catur · HEP/2024/012').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, c.officialEmail), 'kelabcatur@gmail.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, c.council), 'Aiman - Secretary\nSiti - Treasurer');
      final send = find.widgetWithText(FilledButton, c.submitRequest);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(sent, {
        'registry': 'r1',
        'email': 'kelabcatur@gmail.com',
        'position': 'president',
        'council': [
          {'name': 'Aiman', 'position': 'Secretary'},
          {'name': 'Siti', 'position': 'Treasurer'},
        ],
      });
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
            addMember: (u) async => added.add(u),
            removeMember: (_) async {},
            setPosition: (_, __) async {},
            setRole: (_, __) async {},
            decideJoin: (_, __) async {},
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
      final field = find.widgetWithText(TextField, c.addMember);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '@farid');
      await tester.tap(find.widgetWithText(FilledButton, c.addMember));
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
            addMember: (_) async {},
            removeMember: (_) async {},
            setPosition: (_, __) async {},
            setRole: (_, __) async {},
            decideJoin: (_, __) async {},
            transfer: (_) async {},
          ),
        ),
        scaffold: false,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text(c.leave), findsOneWidget);
      expect(find.text(c.transfer, skipOffstage: false), findsNothing);
      expect(find.text(c.addMember, skipOffstage: false), findsNothing);
    });

    testWidgets('manage approves a join request at ${w.toInt()} px', (tester) async {
      String? decided;
      bool? approved;
      await pumpAt(
        tester,
        w,
        ClubManageView(
          club: club,
          myRole: 'president',
          myUserId: 'u1',
          members: members,
          joinRequests: [
            {
              'id': 'j1',
              'message': 'Can I join?',
              'user': {'id': 'u9', 'username': 'farid', 'display_name': 'Farid'},
            },
          ],
          actions: ClubManageActions(
            save: (_) async {},
            pickImage: () async => null,
            addMember: (_) async {},
            removeMember: (_) async {},
            setPosition: (_, __) async {},
            setRole: (_, __) async {},
            decideJoin: (id, ok) async {
              decided = id;
              approved = ok;
            },
            transfer: (_) async {},
          ),
        ),
        scaffold: false,
      );
      await tester.dragUntilVisible(
        find.text(c.joinRequests),
        find.byType(ListView).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.approveJoin).first);
      await tester.pumpAndSettle();
      expect(find.text(c.approveJoinTitle.replaceAll('{0}', 'Farid')), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(c.approveJoin),
      ));
      await tester.pumpAndSettle();
      expect(decided, 'j1');
      expect(approved, isTrue);
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

  testWidgets('admin join requests tab approves', (tester) async {
    bool? approved;
    await pumpAt(
      tester,
      375,
      JoinRequestsTab(
        load: () async => [
          {
            'id': 'j1',
            'club_name': 'Debate Society',
            'club_handle': 'debate',
            'message': 'Can I join?',
            'user': {'id': 'u9', 'username': 'farid', 'display_name': 'Farid'},
          },
        ],
        decide: (_, ok) async => approved = ok,
      ),
    );
    expect(find.text('Farid'), findsOneWidget);
    await tester.tap(find.text(c.approveJoin));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(c.approveJoin),
    ));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
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

  test('clubSearchRow maps a club for the search section', () {
    const club = Club(
      id: 'c1',
      handle: 'DebateUiTM',
      name: 'Debate Society',
      logoUrl: 'https://cdn/logo.png',
    );
    final row = clubSearchRow(club);
    expect(row['title'], 'Debate Society');
    expect(row['subtitle'], '@DebateUiTM');
    expect(row['avatar_url'], 'https://cdn/logo.png');
    expect(row['route'], '/c/DebateUiTM');
  });

  testWidgets('manage contact section saves the phone for listings', (tester) async {
    String? savedPhone;
    String? savedQr;
    var qrPicks = 0;
    await pumpAt(
      tester,
      375,
      ClubManageView(
        club: club,
        myRole: 'president',
        myUserId: 'u1',
        members: members,
        contact: const ClubContact(phone: '011-111 2222'),
        actions: ClubManageActions(
          save: (_) async {},
          pickImage: () async => null,
          addMember: (_) async {},
          removeMember: (_) async {},
          setPosition: (_, __) async {},
          setRole: (_, __) async {},
          decideJoin: (_, __) async {},
          transfer: (_) async {},
          saveContact: (p, q) async {
            savedPhone = p;
            savedQr = q;
          },
          pickQr: () async {
            qrPicks++;
            return null;
          },
        ),
      ),
      scaffold: false,
    );

    await tester.dragUntilVisible(
      find.text(c.contactForListings),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final phoneField = find.widgetWithText(TextField, c.phone);
    expect(tester.widget<TextField>(phoneField).controller?.text, '011-111 2222');

    await tester.tap(find.widgetWithText(OutlinedButton, c.uploadQr));
    await tester.pumpAndSettle();
    expect(qrPicks, 1);

    await tester.enterText(phoneField, '019-888 7777');
    final save = find.widgetWithText(FilledButton, c.saveContact);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(savedPhone, '019-888 7777');
    expect(savedQr, isNull);
    expect(find.text(c.contactSaved), findsOneWidget);
  });

  testWidgets('admin registry lists entries and adds one', (tester) async {
    final saved = <Map<String, Object?>>[];
    await pumpAt(
      tester,
      375,
      ClubRegistryScreen(
        checkAdmin: () async => true,
        load: () async => const [
          ClubRegistryEntry(id: 'r1', code: 'HEP/2024/042', name: 'Debate Society', faculty: 'FSKM'),
        ],
        save: ({id, required code, required name, faculty, category, active = true}) async {
          saved.add({'id': id, 'code': code, 'name': name, 'active': active});
        },
      ),
      scaffold: false,
    );
    expect(find.text('Debate Society'), findsOneWidget);
    await tester.tap(find.text(c.addRegistryClub));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'HEP/2024/055');
    await tester.enterText(fields.at(1), 'Robotics');
    await tester.tap(find.text(c.saveRegistry));
    await tester.pumpAndSettle();
    expect(saved.single['code'], 'HEP/2024/055');
    expect(saved.single['name'], 'Robotics');
    expect(find.text(c.registrySaved), findsOneWidget);
  });

  testWidgets('admin clubs tab filters and suspends with a reason', (tester) async {
    final calls = <(String, String, String)>[];
    Map<String, dynamic> row(String status) => {
          'id': 'c1',
          'handle': 'debate',
          'name': 'Debate Society',
          'status': status,
          'is_verified': true,
        };
    await pumpAt(
      tester,
      375,
      ClubApprovalsTab(
        load: () async => [],
        decide: (_, __, ___) async {},
        loadClubs: (status) async => [row(status)],
        setStatus: (id, status, reason) async => calls.add((id, status, reason)),
      ),
    );
    expect(find.text(c.noClubRequests), findsOneWidget);

    await tester.tap(find.text(c.statusActive));
    await tester.pumpAndSettle();
    expect(find.text('Debate Society'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, c.suspend));
    await tester.pumpAndSettle();
    expect(find.text(c.suspendTitle.replaceAll('{0}', 'Debate Society')), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'spam listings');
    await tester.tap(find.widgetWithText(FilledButton, c.suspend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, [('c1', 'suspended', 'spam listings')]);
    expect(find.text(c.suspendedDone), findsOneWidget);

    final suspendedChip = find.text(c.statusSuspended);
    await tester.ensureVisible(suspendedChip);
    await tester.tap(suspendedChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text(c.reactivate));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'appeal accepted');
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(c.reactivate),
    ));
    await tester.pumpAndSettle();
    expect(calls.last, ('c1', 'active', 'appeal accepted'));
  });
}
