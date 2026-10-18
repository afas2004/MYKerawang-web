import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/image_compressor.dart';
import '../utils/local_image.dart';
import '../utils/categories.dart';
import '../l10n/app_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';
import 'edit_profile_screen.dart';

class CreateListingScreen extends StatefulWidget {
  final Map<String, dynamic>? itemToEdit; 

  const CreateListingScreen({super.key, this.itemToEdit});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  
  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;
  
  // State
  String _category = 'Books';
  bool _isLoading = false;

  // UNIFIED MEDIA LIST (Stores both Strings/URLs and LocalImages)
  // Index 0 is ALWAYS the Cover Photo.
  final List<dynamic> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    final item = widget.itemToEdit;
    
    _titleController = TextEditingController(text: item?['title'] ?? '');
    _priceController = TextEditingController(text: item?['price']?.toString() ?? '');
    _descriptionController = TextEditingController(text: item?['description'] ?? '');
    
    if (item != null) {
      // Older/seeded listings may carry a category no longer offered
      final cat = item['category'];
      _category = kListingCategories.contains(cat) ? cat : 'Others';
      
      // LOAD EXISTING MEDIA
      // 1. Cover
      if (item['image_url'] != null) {
        _mediaItems.add(item['image_url']);
      }
      // 2. Gallery
      if (item['gallery_urls'] != null) {
        final extras = List<String>.from(item['gallery_urls']);
        // Avoid duplicates if cover is also in gallery list
        for (var url in extras) {
          if (!_mediaItems.contains(url)) _mediaItems.add(url);
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<bool> _hasPhone(String userId) async {
    final row = await _supabase
        .from('profile_contacts')
        .select('phone_number')
        .eq('user_id', userId)
        .maybeSingle();
    final phone = row?['phone_number'];
    return phone is String && phone.trim().isNotEmpty;
  }

  /// Buyers reach sellers on WhatsApp, and onboarding no longer asks for
  /// the number — so selling is where it becomes required. Offers Edit
  /// profile and re-checks when they come back.
  Future<bool> _ensurePhone(String userId) async {
    if (await _hasPhone(userId)) return true;
    if (!mounted) return false;
    final s = context.l10nRead;
    final goEdit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.phone),
        title: Text(s.social.whatsappNeededTitle),
        content: Text(s.social.whatsappNeededBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.editProfile)),
        ],
      ),
    );
    if (goEdit != true || !mounted) return false;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
    return _hasPhone(userId);
  }

  // --- 2. UPLOAD LOGIC ---
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final s = context.l10nRead;

    if (_mediaItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.addPhotoRequired)));
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;
    if (!await ensureCanWrite(context, ModScope.market) || !mounted) return;

    setState(() => _isLoading = true);
    try {
      if (!await _ensurePhone(user.id)) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]))));
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      String? finalCoverUrl;
      List<String> finalGalleryUrls = [];

      // Loop and Process
      for (int i = 0; i < _mediaItems.length; i++) {
        final item = _mediaItems[i];
        String url;

        if (item is LocalImage) {
          // Compress & Upload (bytes — works on web and mobile)
          final compressed = await ImageCompressor.compressBytes(item.bytes);
          final path = 'listings/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await _supabase.storage.from('images').uploadBinary(
                path,
                compressed,
                fileOptions: FileOptions(contentType: imageContentType(compressed)),
              );
          url = _supabase.storage.from('images').getPublicUrl(path);
        } else {
          // Already a URL
          url = item as String;
        }

        if (i == 0) {
          finalCoverUrl = url;
        } else {
          finalGalleryUrls.add(url);
        }
      }
      
      final data = {
        'seller_id': user.id,
        'title': _titleController.text.trim(),
        'price': double.parse(_priceController.text),
        'category': _category,
        'description': _descriptionController.text.trim(),
        'image_url': finalCoverUrl,      // Index 0
        'gallery_urls': finalGalleryUrls, // Index 1+
        'fulfillment_type': 'Pickup',
      };

      if (widget.itemToEdit != null) {
        await _supabase.from('listings').update(data).eq('id', widget.itemToEdit!['id']);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.listingUpdated)));
      } else {
        await _supabase.from('listings').insert(data);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.listingPublished)));
      }

      if (mounted) Navigator.pop(context, true); 

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeWriteError(context, e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.itemToEdit != null;
    final theme = Theme.of(context);
    final s = context.l10n;

    return Scaffold(
      appBar: appBarConstrained(context,
          title: Text(isEditing ? s.editListing : s.sellItem)),
      body: PageBody(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- MEDIA (shared with the event form) ---
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(s.photos, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              MediaPickerGrid(items: _mediaItems, onChanged: () => setState(() {})),
              const SizedBox(height: 24),

              // --- FORM FIELDS ---
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: s.title, hintText: s.listingTitleHint),
                validator: (v) => v!.isEmpty ? s.required : null,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(labelText: s.priceLabel, prefixText: kCurrencyPrefix),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v == null || double.tryParse(v) == null) ? s.invalid : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: InputDecoration(labelText: s.category),
                      items: kListingCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: InputDecoration(labelText: s.description, alignLabelWithHint: true),
                validator: (v) => v!.isEmpty ? s.required : null,
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      )),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor, 
          border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)))
        ),
        // Same submit bar as the event form
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary))
              : Icon(isEditing ? Icons.check : Icons.publish),
          label: Text(_isLoading ? s.saving : (isEditing ? s.saveChanges : s.publish)),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }
}