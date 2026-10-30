import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/roles.dart';
import '../utils/app_nav.dart';
import '../widgets/brand/brand.dart';

class FollowListScreen extends StatefulWidget {
  final String userId;
  final String type; // 'followers' or 'following'

  const FollowListScreen({super.key, required this.userId, required this.type});

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    try {
      dynamic response;
      
      // The Logic:
      // If 'followers': We want the profiles of people who follow userId.
      // If 'following': We want the profiles of people userId follows.

      if (widget.type == 'followers') {
        // Get rows where 'following_id' is target. Expand 'follower_id' profile.
        response = await _supabase
            .from('followers')
            // Name the columns. `profiles!follower_id(*)` returned every column
            // granted to a signed-in user (full_name, device_id, ban_reason,
            // last_active_at…) for every follower, while the tile only draws a
            // name, a handle and an avatar.
            .select('profiles!follower_id(id, username, display_name, avatar_url)')
            .eq('following_id', widget.userId);
      } else {
        // Get rows where 'follower_id' is target. Expand 'following_id' profile.
        response = await _supabase
            .from('followers')
            .select('profiles!following_id(id, username, display_name, avatar_url)')
            .eq('follower_id', widget.userId);
      }

      if (mounted) {
        setState(() {
          // Clean up the data structure (unwrap the nested profile)
          _users = List<Map<String, dynamic>>.from(
            response.map((row) => row['profiles'])
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching follow list: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        leading: const AppBackButton(),
        title: Text(widget.type == 'followers' ? s.followers : s.following),
      ),
      body: PageBody(child: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _users.isEmpty
          ? Center(child: Text(s.listEmpty))
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['avatar_url'] != null 
                        ? NetworkImage(user['avatar_url']) 
                        : null,
                    child: user['avatar_url'] == null 
                        ? const Icon(AppIcons.person) 
                        : null,
                  ),
                  title: Text(displayNameFor(s, user)),
                  subtitle: Text("@${user['username'] ?? ''}"),
                  onTap: () => context.goUser(user['id']),
                );
              },
            )),
    );
  }
}