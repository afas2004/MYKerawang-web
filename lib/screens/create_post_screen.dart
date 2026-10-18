import 'package:flutter/material.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';

class CreatePostScreen extends StatefulWidget {
  final Map<String, dynamic>? sharedEvent;
  final Map<String, dynamic>? sharedListing;

  const CreatePostScreen({super.key, this.sharedEvent, this.sharedListing});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _bodyCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  bool _isAnon = false;
  bool _isLoading = false;

  /// Suggested shortcuts — users can also type anything they like.
  final List<String> _tags = ['Question', 'Confession', 'Lost&Found', 'Rant', 'Academic'];

  /// Tags currently in the field, normalised to lowercase without '#'.
  List<String> get _currentTags => RegExp(r'#?([\w&-]+)')
      .allMatches(_tagsCtrl.text)
      .map((m) => m.group(1)!.toLowerCase())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _appendTag(String tag) {
    if (_currentTags.contains(tag.toLowerCase())) return;
    final text = _tagsCtrl.text.trimRight();
    _tagsCtrl.text = text.isEmpty ? "#$tag " : "$text #$tag ";
    _tagsCtrl.selection =
        TextSelection.collapsed(offset: _tagsCtrl.text.length);
    setState(() {});
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a title")));
      return;
    }
    
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;

    try {
      // --- CHANGED SECTION START ---
      // We change .insert() to .select().single() so we get the new Post ID back
      final newPost = await Supabase.instance.client.from('posts').insert({
        'user_id': user!.id,
        'title': _titleCtrl.text,
        'body': _bodyCtrl.text, // Make sure this uses your controller name
        'is_anonymous': _isAnon,
        'shared_event_id': widget.sharedEvent?['id'],
        'shared_listing_id': widget.sharedListing?['id'],
        'tags': _currentTags,
      }).select().single(); // <--- CRITICAL CHANGE

      // Trigger the notifications using the new ID
      await _processMentions(_bodyCtrl.text, newPost['id']);
      // --- CHANGED SECTION END ---

      if (mounted) {
        Navigator.pop(context, true); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Posted successfully!")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processMentions(String text, String postId, {String? commentId}) async {
    // 1. Extract all unique @usernames using Regex
    final regex = RegExp(r"\@(\w+)");
    final matches = regex.allMatches(text);
    final usernames = matches.map((m) => m.group(1)).toSet().toList();

    if (usernames.isEmpty) return;

    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser!.id;

    // 2. Find User IDs for these usernames
    final users = await supabase
        .from('profiles')
        .select('id, username')
        .inFilter('username', usernames);

    // 3. Send Notifications
    for (var user in users) {
      if (user['id'] == myId) continue; // Don't notify yourself

      await supabase.from('notifications').insert({
        'user_id': user['id'],
        'actor_id': myId,
        'type': 'mention',
        'title': 'You were mentioned',
        'body': 'mentioned you in a post',
        'data': {'post_id': postId, 'comment_id': commentId},
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEvent = widget.sharedEvent != null;
    final bool isListing = widget.sharedListing != null;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        // In a dialog on desktop a ✕ reads better than a back arrow (H4/2.1)
        leading: IconButton(
          tooltip: "Close",
          icon: Icon(isWide(context) ? Icons.close : Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(context.l10n.createPostTitle),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: Text(context.l10n.post,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: PageBody(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isEvent || isListing)
          Container(
            // Optional: Add a little border/color to make it pop (like in the event screen)
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // DYNAMIC ICON: Calendar for Event, Shopping Bag for Item
                Icon(
                  isEvent ? Icons.event : Icons.shopping_bag, 
                  size: 20,
                  color: isEvent ? Theme.of(context).primaryColor : Colors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // DYNAMIC LABEL
                      Text(
                        isEvent ? "Referencing Event:" : "Referencing Item:", 
                        style: const TextStyle(fontSize: 10, color: Colors.grey)
                      ),
                      // DYNAMIC TITLE
                      Text(
                        isEvent ? widget.sharedEvent!['title'] : widget.sharedListing!['title'], 
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              hintText: "Title (e.g. Lost Wallet)",
              border: InputBorder.none,
              hintStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          MentionInput(
            controller: _bodyCtrl,
            hintText: context.l10n.whatsOnYourMind,
            isMultiLine: true,
          ),
          const SizedBox(height: 20),
          
          // Options
          SwitchListTile(
            title: const Text("Post Anonymously"),
            subtitle: const Text("Hide your name from everyone"),
            value: _isAnon,
            onChanged: (val) => setState(() => _isAnon = val),
          ),
          
          const SizedBox(height: 10),
          Text(context.l10n.addTags,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Free-text hashtags. Chips are shortcuts that append into the
          // field; they can't be added twice.
          TextField(
            controller: _tagsCtrl,
            decoration: InputDecoration(
              hintText: context.l10n.tagsHint,
              prefixIcon: const Icon(Icons.tag),
            ),
            onChanged: (_) => setState(() {}), // refresh chip states
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _tags.map((tag) {
              final already = _currentTags.contains(tag.toLowerCase());
              return ActionChip(
                avatar: Icon(already ? Icons.check : Icons.add, size: 16),
                label: Text(tag),
                onPressed: already ? null : () => _appendTag(tag),
              );
            }).toList(),
          )
        ],
      )),
    );
  }
}