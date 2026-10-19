import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/image_compressor.dart';
import '../utils/local_image.dart';
import '../utils/categories.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/formatters.dart';
import '../utils/app_nav.dart';
import '../widgets/form_layout.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';

class CreateListingScreen extends StatefulWidget {
  final Map<String, dynamic>? itemToEdit; 

  const CreateListingScreen({super.key, this.itemToEdit});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  // Looked up on use so the form can be built in widget tests.
  SupabaseClient get _supabase => Supabase.instance.client;
  
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

    // Leaving with unsaved input asks first (router onExit).
    _initialSnapshot = _snapshot();
    FormGuard.register(() => !_isLoading && _snapshot() != _initialSnapshot);
  }

  late final String _initialSnapshot;

  /// Everything the user can change, to tell whether leaving loses input.
  String _snapshot() => [
        _titleController.text,
        _priceController.text,
        _descriptionController.text,
        _category,
        _mediaItems.length,
        _mediaItems.map((m) => m is String ? m : identityHashCode(m)).join(','),
      ].join('|');

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    FormGuard.clear();
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
    // Edit profile is its own page; the form stays underneath with its
    // input, and Publish re-checks the number when they come back.
    context.goEditProfile();
    return false;
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
        // Back to the listing page, which refreshes.
        if (mounted) completeEdit(context, message: s.listingUpdated);
      } else {
        final row = await _supabase.from('listings').insert(data).select().single();
        // The form is replaced by the new listing's page, so back from
        // there returns to where the user started, not to this form.
        if (mounted) {
          completePublish(context, '/item/${row['id']}',
              extra: row, message: s.listingPublished);
        }
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeWriteError(context, e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.itemToEdit != null;
    final s = context.l10n;

    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppCloseButton(),
          title: Text(isEditing ? s.editListing : s.sellItem)),
      body: FormPageBody(
        child: Form(
          key: _formKey,
          // Errors show as soon as a field is touched, not only on submit.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                title: s.sectionPhotos,
                icon: Icons.photo_library_outlined,
                children: [
                  // Shared with the event form
                  MediaPickerGrid(items: _mediaItems, onChanged: () => setState(() {})),
                ],
              ),
              FormSection(
                title: s.sectionDetails,
                icon: Icons.edit_note,
                children: [
                  TextFormField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: s.title, hintText: s.listingTitleHint),
                    validator: (v) => (v == null || v.trim().isEmpty) ? s.required : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: s.description, alignLabelWithHint: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? s.required : null,
                  ),
                ],
              ),
              FormSection(
                title: s.sectionPricing,
                icon: Icons.sell_outlined,
                children: [
                  LayoutBuilder(builder: (context, c) {
                    final price = TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                          labelText: s.priceLabel, prefixText: kCurrencyPrefix, hintText: '12.50'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        return (n == null || n < 0) ? s.priceInvalid : null;
                      },
                    );
                    final category = DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: InputDecoration(labelText: s.category),
                      items: kListingCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    );
                    if (c.maxWidth < 420) {
                      return Column(children: [price, const SizedBox(height: 16), category]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: price),
                        const SizedBox(width: 16),
                        Expanded(child: category),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: PublishBar(
        busy: _isLoading,
        editing: isEditing,
        label: isEditing ? s.saveChanges : s.publish,
        busyLabel: s.saving,
        onPressed: _submit,
      ),
    );
  }
}
