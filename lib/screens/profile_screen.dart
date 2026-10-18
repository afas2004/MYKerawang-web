import 'package:flutter/material.dart';
import 'package:mykerawang/screens/edit_profile_screen.dart';
import 'package:mykerawang/screens/follow_list_screen.dart';
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
import '../l10n/social_strings.dart';
import '../widgets/post_card.dart';
import '../widgets/saved_items_view.dart';
import '../widgets/status_badge.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../widgets/brand/brand.dart';
import '../widgets/shell_actions.dart';

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
                            padding: const EdgeInsets.all(16),
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
                                  Icon(Icons.videocam_off, color: theme.colorScheme.onSurfaceVariant, size: 40),
                                  const SizedBox(height: 12),
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
        appBar: AppBar(),
        body: _loadError
            ? _ErrorRetry(onRetry: _retry)
            : const _ProfileSkeleton(),
      );
    }
    if (_profile == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(s.userNotFound)));
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = _profile!;

    return Scaffold(
      appBar: AppBar(
        title: Text(p['username'] != null ? "@${p['username']}" : s.profileTitle),
        actions: [
          if (_isMe && widget.userId == null) const ShellSearchButton(),
          IconButton(
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProfileData,
          ),
          IconButton(
            tooltip: s.qrCode,
            icon: const Icon(Icons.qr_code),
            onPressed: _showQRCode,
          ),
          if (_isMe)
            IconButton(
              tooltip: s.settings,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.goSettings(),
            )
          else
            ReportMenuButton(
              targetId: widget.userId!,
              type: 'user',
              label: s.reportUser,
              icon: const Icon(Icons.more_vert),
            ),
        ],
      ),
      body: LinearRefresher(
        onRefresh: _fetchProfileData,
        offset: 0.0,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _identityHeader(context, p)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  tabs: [
                    Tab(text: s.activity),
                    Tab(text: s.navEvents),
                    Tab(text: s.navMarket),
                    if (_isMe) Tab(text: s.social.saved),
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
                  ? _TabEmpty(icon: Icons.event_outlined, text: s.noEventsYet)
                  : _tileGrid(_userEvents, isEvent: true),
              _userListings.isEmpty
                  ? _TabEmpty(icon: Icons.storefront_outlined, text: s.nothingForSale)
                  : _tileGrid(_userListings, isEvent: false),
              if (_isMe) const SavedItemsView(),
            ],
          ),
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _loadError = false;
      _isLoading = true;
    });
    _fetchProfileData();
  }

  /// Cover band with lattice, overlapping avatar, Fraunces name, gold
  /// accent for verified/club accounts, stat chips and the main action.
  Widget _identityHeader(BuildContext context, Map<String, dynamic> p) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final official = p['is_verified'] == true || p['role'] == 'club';
    final avatarUrl = p['avatar_url'] as String?;
    final name = displayNameFor(s, p);
    const coverHeight = 96.0;
    const avatarRadius = 44.0;

    return OfficialFrame(
      enabled: official,
      borderRadius: BorderRadius.zero,
      semanticLabel: roleLabel(s, p['role']),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: coverHeight + avatarRadius,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: avatarRadius,
                child: _CoverBand(
                    color: scheme.primaryContainer,
                    motif: KTokens.of(context).motif),
              ),
              Positioned(
                left: 16,
                bottom: 0,
                child: Semantics(
                  button: avatarUrl != null,
                  label: name,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: avatarUrl == null
                        ? null
                        // Full original image, uncropped (BoxFit.contain)
                        : () => showImagePreview(context, url: avatarUrl),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Gold ring = official (verified or club). Decorative
                        // gold, so the token, not tertiary.
                        color: official
                            ? KTokens.of(context).gold
                            : theme.scaffoldBackgroundColor,
                      ),
                      child: CircleAvatar(
                        radius: avatarRadius,
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
                ),
              ),
              Positioned(
                right: 16,
                bottom: 4,
                child: _primaryAction(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(name, style: theme.textTheme.headlineSmall),
                  if (p['is_verified'] == true)
                    Icon(Icons.verified, color: scheme.tertiary, size: 22),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (p['username'] != null)
                    Text('@${p['username']}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  _RoleChip(label: roleLabel(s, p['role']), official: official),
                ],
              ),
              if ((p['bio'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p['bio'], style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(
                    count: _userPosts.length,
                    label: s.posts,
                    onTap: () => _tabController.animateTo(0),
                  ),
                  _StatChip(
                    count: _followerCount,
                    label: s.followers,
                    onTap: () => _openFollows('followers'),
                  ),
                  _StatChip(
                    count: _followingCount,
                    label: s.following,
                    onTap: () => _openFollows('following'),
                  ),
                ],
              ),
              const SizedBox(height: KSpace.l),
            ],
          ),
        ),
      ],
      ),
    );
  }

  void _openFollows(String type) {
    final uid = widget.userId ?? _supabase.auth.currentUser?.id;
    if (uid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FollowListScreen(userId: uid, type: type)),
    );
  }

  Widget _primaryAction(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    const minSize = Size(112, 44);
    if (_isMe) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: minSize,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
        ).then((value) {
          if (value == true) _fetchProfileData();
        }),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: Text(s.editProfile),
      );
    }
    return FilledButton.icon(
      onPressed: _toggleFollow,
      // Scheme roles so it reads on Songket Noir too
      style: FilledButton.styleFrom(
        minimumSize: minSize,
        shape: const RoundedRectangleBorder(borderRadius: KRadius.cut),
        backgroundColor:
            _isFollowing ? scheme.surfaceContainerHighest : scheme.primary,
        foregroundColor: _isFollowing ? scheme.onSurface : scheme.onPrimary,
      ),
      icon: Icon(_isFollowing ? Icons.check : Icons.person_add_alt, size: 18),
      label: Text(_isFollowing ? s.following : s.follow),
    );
  }

  /// Posts: one column, two side by side when the page is wide.
  Widget _postsTab(BuildContext context) {
    final s = context.l10n;
    if (_userPosts.isEmpty) {
      return _TabEmpty(icon: Icons.forum_outlined, text: s.noPostsYet);
    }
    Widget card(dynamic post) => PostCard(
          post: post,
          showProfileHeader: false,
          onTap: () => context.goPost(post),
        );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _userPosts.length,
          itemBuilder: (_, i) => card(_userPosts[i]),
        );
      }
      final left = [for (var i = 0; i < _userPosts.length; i += 2) _userPosts[i]];
      final right = [for (var i = 1; i < _userPosts.length; i += 2) _userPosts[i]];
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left.map(card).toList())),
            const SizedBox(width: 16),
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
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
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
      borderRadius: KRadius.cut,
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
                    child: Icon(isEvent ? Icons.event : Icons.storefront,
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
                      // Prices are gold; dates stay neutral.
                      color: isEvent ? scheme.onSurfaceVariant : scheme.tertiary,
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

/// Tappable count, e.g. "128 Followers". ≥ 48 px tall.
class _StatChip extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onTap;
  const _StatChip({required this.count, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '$count $label',
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainer,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 6),
                  Text(label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool official;
  const _RoleChip({required this.label, required this.official});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Gold only for official accounts.
    final c = official ? scheme.tertiary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: KRadius.cut,
        border: Border.all(color: c),
      ),
      child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: c)),
    );
  }
}

/// Colour band with a faint lattice — the "carved panel" the profile sits
/// in.
class _CoverBand extends StatelessWidget {
  final Color color;
  final Color motif;
  const _CoverBand({required this.color, required this.motif});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(color: color),
        // No text sits on the band, so the field can be a little stronger
        // than the default background opacity.
        child: KerawangLattice(color: motif, tileSize: 22, opacity: 0.22),
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
      icon: Icons.wifi_off,
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
        KSkeleton(height: 96, borderRadius: BorderRadius.zero),
        Padding(
          padding: EdgeInsets.all(KSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KSkeleton.circle(size: 88),
              SizedBox(height: KSpace.m),
              KSkeleton(width: 180, height: 22),
              SizedBox(height: KSpace.s),
              KSkeleton(width: 120, height: 14),
              SizedBox(height: KSpace.l),
              Row(children: [
                KSkeleton(width: 90, height: 40),
                SizedBox(width: KSpace.s),
                KSkeleton(width: 110, height: 40),
                SizedBox(width: KSpace.s),
                KSkeleton(width: 110, height: 40),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
