import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/theme/app_themes.dart';
import 'package:mykerawang/widgets/image_crop_dialog.dart';
import 'package:mykerawang/utils/app_links.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/roles.dart';
import '../l10n/access_strings.dart';
import '../l10n/account_strings.dart';
import '../l10n/feed_strings.dart';
import '../l10n/social_strings.dart';
import '../widgets/post_card.dart';
import '../widgets/saved_items_view.dart';
import '../widgets/status_badge.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../widgets/admin_icon_button.dart';
import '../widgets/brand/brand.dart';
import '../widgets/shell_actions.dart';
import 'login_cubit.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; 

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController; // Controls the 3 tabs
  
  bool _isLoading = true;
  bool _loadError = false;
  bool _isMe = false;
  bool _isFollowing = false;

  /// Own profile only: signed in with a student address and no backup —
  /// the account dies with the mailbox. Dismissable for this visit.
  bool _backupNeeded = false;
  bool _backupBannerHidden = false;
  int _followerCount = 0;   // <--- Add this
  int _followingCount = 0;
  
  Map<String, dynamic>? _profile;
  List<dynamic> _userPosts = [];
  List<dynamic> _userEvents = [];
  List<dynamic> _userListings = []; // <--- NEW: Store Listings
  
  @override
  void initState() {
    super.initState();
    // Own profile gets a fourth, private "Saved" tab.
    final currentUid = _supabase.auth.currentUser?.id;
    _isMe = currentUid != null && (widget.userId ?? currentUid) == currentUid;
    _tabController = TabController(length: _isMe ? 4 : 3, vsync: this);
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    final currentUid = _supabase.auth.currentUser?.id;
    final targetUid = widget.userId ?? currentUid;

    if (targetUid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _isMe = (currentUid == targetUid);

    try {
      // 1. Fetch Profile
      final profileData = await _supabase
          .from('profiles')
          // Explicit: never pull private columns for someone else's page.
          .select('id, username, display_name, full_name, avatar_url, bio, is_verified, role')
          .eq('id', targetUid)
          .single();
      
      // 2. Fetch Content (Posts, Events, AND Listings)
      // posts_public nulls user_id on anonymous rows, so anonymous posts no
      // longer appear on anyone's profile — including the author's own.
      // That's deliberate: a profile page is public, so listing them here
      // would deanonymise them.
      final posts = await _supabase.from('posts_public').select('*').eq('user_id', targetUid).order('created_at', ascending: false);
      final events = await _supabase.from('events').select().eq('organizer_id', targetUid).order('start_datetime', ascending: false);
      
      // <--- NEW: Fetch Listings
      final listings = await _supabase.from('listings').select().eq('seller_id', targetUid).order('created_at', ascending: false);

      // 3. Check Follow Status
      if (!_isMe && currentUid != null) {
        final followCheck = await _supabase.from('followers')
            .select()
            .eq('follower_id', currentUid)
            .eq('following_id', targetUid)
            .maybeSingle();
        _isFollowing = followCheck != null;
      }

      // 1. Count how many people follow THIS user
      final followers = await _supabase
          .from('followers')
          .count(CountOption.exact)
          .eq('following_id', targetUid);

      // 2. Count how many people THIS user follows
      final following = await _supabase
          .from('followers')
          .count(CountOption.exact)
          .eq('follower_id', targetUid);

      if (mounted) {
        setState(() {
          _profile = profileData;
          _userPosts = posts.map((p) => {...p, 'type': 'post'}).toList();
          _userEvents = events.map((e) => {...e, 'type': 'event'}).toList();
          _userListings = listings.map((l) => {...l, 'type': 'listing'}).toList(); // <--- NEW
          _isLoading = false;
          _followerCount = followers;
          _followingCount = following;
        });
      }

      // Only the owner can read this row; a failure just hides the banner.
      if (_isMe && isStudentEmail(_supabase.auth.currentUser?.email)) {
        var needs = true;
        try {
          final c = await _supabase
              .from('profile_contacts')
              .select('backup_email')
              .eq('user_id', targetUid)
              .maybeSingle();
          final backup = (c?['backup_email'] as String?)?.trim();
          needs = backup == null || backup.isEmpty;
        } catch (_) {
          needs = false;
        }
        if (mounted && needs != _backupNeeded) {
          setState(() => _backupNeeded = needs);
        }
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
      if (!mounted) return;
      if (_profile == null) {
        setState(() => _loadError = true);
      } else {
        // Keep what's on screen; just say the refresh failed.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10nRead.connectionError),
          action: SnackBarAction(
              label: context.l10nRead.tryAgain, onPressed: _fetchProfileData),
        ));
      }
    }
  }

  Future<void> _toggleFollow() async {
    final currentUid = _supabase.auth.currentUser?.id;
    final targetUid = widget.userId;
    if (targetUid == null) return;
    if (currentUid == null) {
      requireLogin(context);
      return;
    }

    // Optimistic UI Update
    setState(() {
      _isFollowing = !_isFollowing;
      _followerCount += _isFollowing ? 1 : -1;
    });

    try {
      if (_isFollowing) {
        // 1. Insert Follow Record
        await _supabase.from('followers').insert({'follower_id': currentUid, 'following_id': targetUid});
        
        // 2. SEND NOTIFICATION (New!)
        // Fetch my name first so the notification looks nice ("Fahmi followed you")
        final myProfile = await _supabase.from('profiles').select('display_name').eq('id', currentUid).single();

        // Read by the recipient, so written in the canonical language.
        const n = AppStrings.en;
        await _supabase.from('notifications').insert({
          'user_id': targetUid,      // Send TO target
          'actor_id': currentUid,    // From ME
          'type': 'follow',
          'title': n.notifFollowTitle,
          'body': n.notifFollowBody.fill([myProfile['display_name']]),
          'data': {}, // No extra data needed for follow
        });

      } else {
        // Unfollow
        await _supabase.from('followers').delete().match({'follower_id': currentUid, 'following_id': targetUid});
      }
    } catch (e) {
      // Revert if error, and say so
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
          _followerCount += _isFollowing ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.l10nRead.errorWithDetail.fill([e]))));
      }
    }
  }

  void _showQRCode() {
    final theme = Theme.of(context);
    final qrColor = theme.colorScheme.onSurface;
    final s = context.l10nRead;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: theme.scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: DefaultTabController(
          length: 2,
          child: SizedBox(
            height: 450,
            child: Column(
              children: [
                TabBar(
                  tabs: [Tab(text: s.myCode), Tab(text: s.scan)],
                ),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // TAB 1: MY CODE
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(KSpace.l),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: QrImageView(
                              // https so a phone camera can open it too
                              data: profileUrl(_profile!['id']),
                              version: QrVersions.auto,
                              size: 200.0,
                              eyeStyle: QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: qrColor,
                              ),
                              dataModuleStyle: QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: qrColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "@${_profile?['username'] ?? ''}",
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),

                      // TAB 2: SCANNER (FIXED)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                        child: MobileScanner(
                          // FIX 1: Only 2 arguments (context, error)
                          errorBuilder: (context, error) { 
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(AppIcons.camera, color: theme.colorScheme.onSurfaceVariant, size: 40),
                                  const SizedBox(height: KSpace.m),
                                  Text(
                                    s.cameraError.fill([error.errorCode.name]),
                                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            );
                          },
                          // FIX 2: Only 1 argument (context)
                          placeholderBuilder: (context) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                          onDetect: (capture) {
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              if (barcode.rawValue != null) {
                                final userId = userIdFromProfileCode(barcode.rawValue!);
                                if (userId != null) {
                                  Navigator.pop(ctx);
                                  context.goUser(userId);
                                  break;
                                }
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    if (_isLoading && _profile == null) {
      return Scaffold(
        appBar: AppBar(leading: _inShell(context) ? null : const AppBackButton()),
        body: _loadError
            ? _ErrorRetry(onRetry: _retry)
            : const _ProfileSkeleton(),
      );
    }
    if (_profile == null && !isLoggedIn && widget.userId == null) {
      // "My profile" while signed out: offer login instead of "not found".
      return Scaffold(
        appBar: AppBar(leading: _inShell(context) ? null : const AppBackButton()),
        body: BrandEmptyState(
          icon: AppIcons.profile,
          title: s.guestPromptTitle,
          message: s.guestPromptBody,
          actionLabel: s.loginOrSignUp,
          onAction: () => goToLogin(context),
        ),
      );
    }
    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(leading: _inShell(context) ? null : const AppBackButton()),
        body: BrandEmptyState(icon: AppIcons.person, title: s.userNotFound),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = _profile!;

    return Scaffold(
      appBar: AppBar(
        // A pushed page (own or someone else's, also opened cold) gets a
        // back button; only the legacy shell tab goes without.
        leading: _inShell(context) ? null : const AppBackButton(),
        title: Text(p['username'] != null ? "@${p['username']}" : s.profileTitle),
        actions: [
          if (_isMe && _inShell(context)) const ShellSearchButton(),
          // Own profile is reached from an avatar now, so Settings is a
          // visible action rather than buried in the menu.
          if (_isMe) ...[
            const AdminIconButton(),
            IconButton(
              tooltip: s.settings,
              icon: const Icon(AppIcons.settings),
              onPressed: () => context.goSettings(),
            ),
          ],
          _overflowMenu(context),
        ],
      ),
      body: LinearRefresher(
        onRefresh: _fetchProfileData,
        offset: 0.0,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _header(context, p)),
            if (_isMe && _backupNeeded && !_backupBannerHidden)
              SliverToBoxAdapter(child: _backupBanner(context)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: theme.textTheme.labelLarge,
                  tabs: [
                    Tab(icon: const Icon(AppIcons.list, size: 20), text: s.activity, height: 60),
                    Tab(icon: const Icon(AppIcons.events, size: 20), text: s.navEvents, height: 60),
                    Tab(icon: const Icon(AppIcons.market, size: 20), text: s.navMarket, height: 60),
                    if (_isMe)
                      Tab(icon: const Icon(AppIcons.save, size: 20), text: s.social.saved, height: 60),
                  ],
                ),
                background: theme.scaffoldBackgroundColor,
                divider: scheme.outlineVariant,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _postsTab(context),
              _userEvents.isEmpty
                  ? _TabEmpty(icon: AppIcons.events, text: s.noEventsYet)
                  : _tileGrid(_userEvents, isEvent: true),
              _userListings.isEmpty
                  ? _TabEmpty(icon: AppIcons.market, text: s.nothingForSale)
                  : _tileGrid(_userListings, isEvent: false),
              if (_isMe) const SavedItemsView(),
            ],
          ),
        ),
      ),
    );
  }

  /// Own profile: no backup email means the account dies with the
  /// student mailbox. One line of warning, dismissable for this visit.
  Widget _backupBanner(BuildContext context) {
    final a = context.l10n.account;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onTint = scheme.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, 0),
      child: Container(
        padding: const EdgeInsets.all(KSpace.m),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: KRadius.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.warning, size: 20, color: onTint),
            const SizedBox(width: KSpace.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.backupNudgeTitle,
                      style: theme.textTheme.titleSmall?.copyWith(color: onTint)),
                  const SizedBox(height: 2),
                  Text(
                    a.backupNudgeBody
                        .fill([_supabase.auth.currentUser?.email ?? '']),
                    style: theme.textTheme.bodySmall?.copyWith(color: onTint),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    TextButton(
                      onPressed: () => context.push('/profile/edit'),
                      child: Text(a.backupNudgeAdd),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _backupBannerHidden = true),
                      child: Text(a.backupNudgeLater),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// QR, refresh and settings (own) / report (others) in one menu.
  Widget _overflowMenu(BuildContext context) {    final s = context.l10n;
    return PopupMenuButton<String>(
      icon: const Icon(AppIcons.more),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      onSelected: (v) {
        switch (v) {
          case 'qr':
            _showQRCode();
          case 'refresh':
            _fetchProfileData();
          case 'report':
            if (requireLogin(context)) {
              showReportDialog(context, widget.userId!, 'user');
            }
        }
      },
      itemBuilder: (_) => [
        _menuItem('qr', AppIcons.qrCode, s.qrCode),
        _menuItem('refresh', AppIcons.refresh, s.refresh),
        if (!_isMe) _menuItem('report', AppIcons.report, s.reportUser),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: KSpace.m),
            Text(label),
          ],
        ),
      );

  /// True only when rendered as a tab inside the shell's branch navigator.
  /// Profile is normally a pushed page (from the avatar action or /u/:id).
  bool _inShell(BuildContext context) =>
      StatefulNavigationShell.maybeOf(context) != null;

  void _retry() {
    setState(() {
      _loadError = false;
      _isLoading = true;
    });
    _fetchProfileData();
  }

  /// Avatar left, name/handle/role beside it, then bio, a one-line stats
  /// row and the full-width primary action.
  Widget _header(BuildContext context, Map<String, dynamic> p) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarUrl = p['avatar_url'] as String?;
    final name = displayNameFor(s, p);

    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, KSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: avatarUrl != null,
                label: name,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: avatarUrl == null
                      ? null
                      // Full original image, uncropped (BoxFit.contain)
                      : () => showImagePreview(context, url: avatarUrl),
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(name.characters.first.toUpperCase(),
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: scheme.onPrimaryContainer))
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: KSpace.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 22, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (p['is_verified'] == true) ...[
                          const SizedBox(width: KSpace.xs),
                          Icon(AppIcons.verified,
                              color: scheme.primary,
                              size: 20,
                              semanticLabel: context.feedL10n.verified),
                        ],
                      ],
                    ),
                    const SizedBox(height: KSpace.xs),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: KSpace.s,
                      runSpacing: KSpace.xs,
                      children: [
                        if (p['username'] != null)
                          Text('@${p['username']}',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        _RoleChip(
                          label: roleLabel(s, p['role']),
                          official: p['role'] == 'club' || p['is_verified'] == true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((p['bio'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: KSpace.m),
            Text(p['bio'], style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: KSpace.s),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatLink(
                count: _userPosts.length,
                label: s.posts,
                onTap: () => _tabController.animateTo(0),
              ),
              const _Dot(),
              _StatLink(
                count: _followerCount,
                label: s.followers,
                onTap: () => _openFollows('followers'),
              ),
              const _Dot(),
              _StatLink(
                count: _followingCount,
                label: s.following,
                onTap: () => _openFollows('following'),
              ),
            ],
          ),
          const SizedBox(height: KSpace.s),
          SizedBox(width: double.infinity, child: _primaryAction(context)),
        ],
      ),
    );
  }

  void _openFollows(String type) {
    final uid = widget.userId ?? _supabase.auth.currentUser?.id;
    if (uid == null) return;
    context.goFollowList(uid, type);
  }

  Widget _primaryAction(BuildContext context) {
    final s = context.l10n;
    const minSize = Size.fromHeight(48);
    if (_isMe) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: minSize),
        // Its own route; leaving it refreshes this page (contentChanges).
        onPressed: () => context.goEditProfile(),
        icon: const Icon(AppIcons.edit, size: 18),
        label: Text(s.editProfile),
      );
    }
    if (_isFollowing) {
      return FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: minSize),
        onPressed: _toggleFollow,
        icon: const Icon(AppIcons.following, size: 18),
        label: Text(s.following),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: minSize),
      onPressed: _toggleFollow,
      icon: const Icon(AppIcons.follow, size: 18),
      label: Text(s.follow),
    );
  }

  /// Posts: one column, two side by side when the page is wide.
  Widget _postsTab(BuildContext context) {
    final s = context.l10n;
    if (_userPosts.isEmpty) {
      return _TabEmpty(icon: AppIcons.comment, text: s.noPostsYet);
    }
    Widget card(dynamic post) => PostCard(
          post: post,
          showProfileHeader: false,
          onTap: () => context.goPost(post),
        );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: KSpace.s),
          itemCount: _userPosts.length,
          itemBuilder: (_, i) => card(_userPosts[i]),
        );
      }
      final left = [for (var i = 0; i < _userPosts.length; i += 2) _userPosts[i]];
      final right = [for (var i = 1; i < _userPosts.length; i += 2) _userPosts[i]];
      return SingleChildScrollView(
        padding: const EdgeInsets.all(KSpace.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left.map(card).toList())),
            const SizedBox(width: KSpace.l),
            Expanded(child: Column(children: right.map(card).toList())),
          ],
        ),
      );
    });
  }

  /// Events / Market as captioned tiles; 2 columns on phones, more as the
  /// page widens.
  Widget _tileGrid(List<dynamic> items, {required bool isEvent}) {
    return LayoutBuilder(builder: (context, c) {
      final cols = Responsive.gridColumnsFor(c.maxWidth - 2 * KSpace.l);
      return GridView.builder(
        padding: const EdgeInsets.all(KSpace.l),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: KSpace.m,
          mainAxisSpacing: KSpace.m,
          childAspectRatio: 0.78,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _ProfileTile(item: items[i], isEvent: isEvent),
      );
    });
  }
}

class _ProfileTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isEvent;
  const _ProfileTile({required this.item, required this.isEvent});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = parseLocal(item['start_datetime']);
    final end = parseLocal(item['end_datetime']) ?? start;
    final ended = isEvent && end != null && end.isBefore(DateTime.now());
    final subtitle = isEvent
        ? (start != null ? formatEventDate(start) : s.dateTba)
        : formatPrice(item['price']);
    final badge = isEvent
        ? (ended ? s.ended : null)
        : (item['is_sold'] == true ? s.sold : null);

    return KCard(
      padding: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      semanticLabel: '${item['title'] ?? s.untitled}, $subtitle',
      onTap: () => isEvent ? context.goEvent(item) : context.goItem(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  item['image_url'] ?? '',
                  cacheWidth: 400,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(isEvent ? AppIcons.events : AppIcons.market,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
                if (badge != null)
                  Container(
                    color: photoScrim(0.35),
                    alignment: Alignment.center,
                    child: StatusBadge(badge),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title'] ?? s.untitled,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isEvent ? scheme.onSurfaceVariant : scheme.primary,
                      fontWeight: isEvent ? null : FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "128 Followers" as plain tappable text, padded to a 48 px target.
class _StatLink extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onTap;
  const _StatLink({required this.count, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '$count $label',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: KRadius.small,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: KSpace.xs),
                Text(label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.xs),
          child: Text('·',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool official;
  const _RoleChip({required this.label, required this.official});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = official ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = official ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: KRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (official) ...[
            Icon(AppIcons.official, size: 14, color: fg),
            const SizedBox(width: KSpace.xs),
          ],
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;
  final Color divider;
  _TabBarDelegate(this.tabBar, {required this.background, required this.divider});

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.tabBar != tabBar || old.background != background;
}

class _TabEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TabEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) =>
      BrandEmptyState(icon: icon, title: text, compact: true);
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return BrandEmptyState(
      icon: AppIcons.error,
      illo: AppIllo.offline,
      title: s.connectionError,
      actionLabel: s.tryAgain,
      onAction: onRetry,
    );
  }
}

/// Loading placeholder shaped like the header.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Padding(
          padding: EdgeInsets.all(KSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                KSkeleton.circle(size: 88),
                SizedBox(width: KSpace.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KSkeleton(width: 180, height: 22),
                      SizedBox(height: KSpace.s),
                      KSkeleton(width: 120, height: 14),
                    ],
                  ),
                ),
              ]),
              SizedBox(height: KSpace.l),
              KSkeleton(width: 260, height: 14),
              SizedBox(height: KSpace.l),
              KSkeleton(height: 48, borderRadius: KRadius.pill),
            ],
          ),
        ),
      ],
    );
  }
}
