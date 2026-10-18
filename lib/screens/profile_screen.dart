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
import '../widgets/post_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/tap_card.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
    _tabController = TabController(length: 3, vsync: this); // <--- CHANGED: 2 -> 3
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    final currentUid = _supabase.auth.currentUser?.id;
    final targetUid = widget.userId ?? currentUid;

    if (targetUid == null) return; 

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
    }
  }

  Future<void> _toggleFollow() async {
    final currentUid = _supabase.auth.currentUser?.id;
    final targetUid = widget.userId;
    if (currentUid == null || targetUid == null) return;

    // Optimistic UI Update
    setState(() => _isFollowing = !_isFollowing); 

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
      // Revert if error
      if (mounted) setState(() => _isFollowing = !_isFollowing);
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

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null) return Scaffold(body: Center(child: Text(s.userNotFound)));

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_profile!['username'] != null ? "@${_profile!['username']}" : s.profileTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.refresh,
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
              tooltip: context.l10n.settings,
              icon: const Icon(Icons.settings),
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
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Avatar
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      final url = _profile!['avatar_url'];
                      if (url == null) return;
                      // Full original image, uncropped (BoxFit.contain)
                      showImagePreview(context, url: url);
                    },
                    child: CircleAvatar(
                        radius: 40,
                        backgroundImage: _profile!['avatar_url'] != null 
                            ? NetworkImage(_profile!['avatar_url']) 
                            : null,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: _profile!['avatar_url'] == null 
                            ? Text(_profile!['display_name']?[0] ?? "U", style: const TextStyle(fontSize: 30)) 
                            : null,
                      ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Name & Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        displayNameFor(s, _profile),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      // Gold marks officialness (DESIGN_SPEC §2)
                      if (_profile!['is_verified'] == true) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, color: scheme.tertiary, size: 20),
                      ]
                    ],
                  ),
                  
                  if (_profile!['bio'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Text(_profile!['bio'], textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ),


                  // Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem(s.posts, "${_userPosts.length}"), // No tap for posts
                      
                      // Followers Tap
                      _statItem(
                        s.followers, 
                        "$_followerCount", 
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(userId: widget.userId ?? _supabase.auth.currentUser!.id, type: 'followers')))
                      ),
                      
                      // Following Tap
                      _statItem(
                        s.following, 
                        "$_followingCount",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(userId: widget.userId ?? _supabase.auth.currentUser!.id, type: 'following')))
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Follow / Edit Button
                  if (!_isMe)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _toggleFollow,
                        // Scheme roles so it reads on Songket Noir too
                        style: FilledButton.styleFrom(
                          backgroundColor: _isFollowing ? scheme.surfaceContainerHighest : scheme.primary,
                          foregroundColor: _isFollowing ? scheme.onSurface : scheme.onPrimary,
                        ),
                        child: Text(_isFollowing ? s.following : s.follow),
                      ),
                    ),
                  if (_isMe)
                    OutlinedButton(
                      onPressed: () {
                         Navigator.push(
                          context, 
                          MaterialPageRoute(builder: (_) => const EditProfileScreen())
                        ).then((value) {
                          if (value == true) _fetchProfileData(); // Refresh profile when back
                        });
                      },
                      child: Text(s.editProfile),
                    ),
                ],
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              indicatorColor: scheme.primary,
              tabs: [
                Tab(text: s.activity),
                Tab(text: s.navEvents),
                Tab(text: s.navMarket),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Posts
                  _userPosts.isEmpty
                    ? Center(child: Text(s.noPostsYet))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _userPosts.length,
                        itemBuilder: (context, index) {
                          return PostCard(
                            post: _userPosts[index],
                            showProfileHeader: false, // remove profile header in post card
                            onTap: () { 
                              context.goPost(_userPosts[index]);
                            },
                          );
                        },
                      ),
                  
                  // Tab 2: Events - SWITCH TO GRID
                  _userEvents.isEmpty 
                    ? Center(child: Text(s.noEventsYet))
                    : _buildPhotoGrid(_userEvents, true), // <--- USE YOUR FUNCTION HERE
                    
                  // Tab 3: Shop - SWITCH TO GRID
                  _userListings.isEmpty
                    ? Center(child: Text(s.nothingForSale))
                    : _buildPhotoGrid(_userListings, false), // <--- AND HERE
                ],
              ),
            ),
          ],
        ),
      ),
      )
    );
  }

  Widget _statItem(String label, String count, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return TapCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            Text(count, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // Helper Widget for Insta-Grid
  Widget _buildPhotoGrid(List<dynamic> items, bool isEvent) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // 3 across like Instagram
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final s = context.l10n;
        return TapCard(
          borderRadius: BorderRadius.zero,
          onTap: () {
            // Navigate to details
            if (isEvent) {
              context.goEvent(item);
            } else {
              // Check type (Listing vs Post) if mixed, otherwise assume Listing
              context.goItem(item);
            }
          },
          onLongPress: () {
            // Point 5: "Pop up details" - Simple implementation is a SnackBar or Dialog
            showDialog(
              context: context,
              builder: (_) => Dialog(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(item['image_url'], height: 200, fit: BoxFit.cover),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(item['title'] ?? s.untitled, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Stack(
          fit: StackFit.expand,
            children: [
              // 1. The Image (Keep existing)
              Image.network(
                item['image_url'] ?? '',
                cacheWidth: 400, // grid tile
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.image_not_supported, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),

              // Same SOLD badge as the market grid
              if (item['is_sold'] == true)
                Container(
                  color: photoScrim(0.35),
                  alignment: Alignment.center,
                  child: StatusBadge(s.sold),
                ),
            ],
          )
        );
      },
    );
  }
}