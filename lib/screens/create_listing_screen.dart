import 'package:flutter/material.dart';
import '../widgets/brand/brand.dart';
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
import '../utils/form_draft.dart';
import '../widgets/form_layout.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';
import '../l10n/create_strings.dart';
import '../services/club_service.dart';
import '../widgets/post_as_selector.dart';

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
  late TextEditingController _meetupController;
  late TextEditingController _quantityController;
  
  // State
  String _category = 'Books';
  bool _isLoading = false;

  /// Yourself (null) or one of your clubs. Fixed once published.
  PostAsOption? _postAs;
  bool get _asClub => _postAs?.isClub ?? (widget.itemToEdit?['club_id'] != null);
  String? _condition;

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
    _meetupController = TextEditingController(text: item?['meetup'] ?? '');
    _quantityController = TextEditingController(text: item?['quantity']?.toString() ?? '');
    final cond = item?['condition'];
    _condition = CreateStrings.conditions.contains(cond) ? cond as String : null;
    
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
    if (item == null) _restoreDraft();
  }

  /// New listings autosave their text (see FormDraft): a reload while the
  /// camera / photo picker is open doesn't lose it.
  final _draft = FormDraft('create_listing');

  Map<String, dynamic> _draftData() => {
        'title': _titleController.text,
        'price': _priceController.text,
        'description': _descriptionController.text,
        'category': _category,
        'meetup': _meetupController.text,
        'condition': _condition,
      };

  Future<void> _restoreDraft() async {
    final d = await _draft.load();
    // Only into an untouched form.
    if (d == null || !mounted || _snapshot() != _initialSnapshot) return;
    setState(() {
      _titleController.text = d['title'] ?? '';
      _priceController.text = d['price'] ?? '';
      _descriptionController.text = d['description'] ?? '';
      final cat = d['category'];
      if (cat is String && kListingCategories.contains(cat)) _category = cat;
      _meetupController.text = d['meetup'] ?? '';
      final cond = d['condition'];
      if (CreateStrings.conditions.contains(cond)) _condition = cond as String;
    });
    _showDraftRestored();
  }

  void _showDraftRestored() {
    final s = context.l10nRead;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(s.draftRestored),
      action: SnackBarAction(
        label: s.discard,
        onPressed: () {
          if (!mounted) return;
          setState(() {
            _titleController.clear();
            _priceController.clear();
            _descriptionController.clear();
          });
          _draft.clear();
        },
      ),
    ));
  }

  late final String _initialSnapshot;

  /// Everything the user can change, to tell whether leaving loses input.
  String _snapshot() => [
        _titleController.text,
        _priceController.text,
        _descriptionController.text,
        _category,
        _meetupController.text,
        _quantityController.text,
        _condition,
        _postAs?.clubId,
        _mediaItems.length,
        _mediaItems.map((m) => m is String ? m : identityHashCode(m)).join(','),
      ].join('|');

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _meetupController.dispose();
    _quantityController.dispose();
    FormGuard.clear();
    // Leaving on purpose (publish / discard / close) drops the draft; a
    // page reload never gets here, so the draft survives that.
    _draft.clear();
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
        icon: const Icon(AppIcons.phone),
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
      // Club listings use the club's contact (get_listing_contact).
      if (!_asClub && !await _ensurePhone(user.id)) {
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
        'condition': _condition,
        'meetup': _meetupController.text.trim().isEmpty ? null : _meetupController.text.trim(),
        'quantity': _asClub ? int.tryParse(_quantityController.text.trim()) : null,
      };

      if (widget.itemToEdit != null) {
        await _supabase.from('listings').update(data).eq('id', widget.itemToEdit!['id']);
        // Back to the listing page, which refreshes.
        if (mounted) completeEdit(context, message: s.listingUpdated);
      } else {
        final insert = (_postAs ?? const PostAsOption.self('')).applyTo(data, hasAnonymous: false);
        final row = await _supabase.from('listings').insert(insert).select().single();
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
    if (widget.itemToEdit == null) _draft.save(_draftData());
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
                icon: AppIcons.photo,
                children: [
                  // Shared with the event form
                  // The picker returns after an await (camera / file dialog);
                  // the form may be gone by then.
                  MediaPickerGrid(
                      items: _mediaItems,
                      onChanged: () {
                        if (mounted) setState(() {});
                      }),
                ],
              ),
              FormSection(
                title: s.sectionDetails,
                icon: AppIcons.edit,
                children: [
                  if (!isEditing)
                    PostAsSelector(
                      selfLabel: s.create.yourself,
                      label: s.create.sellingAs,
                      value: _postAs,
                      onChanged: (o) => setState(() => _postAs = o),
                    ),
                  if (_asClub) ...[
                    const SizedBox(height: KSpace.s),
                    Text(s.create.clubContactNote,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                  if (!isEditing) const SizedBox(height: KSpace.l),
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
                  const SizedBox(height: 16),
                  Text(s.create.condition, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: KSpace.s),
                  Wrap(
                    spacing: KSpace.s,
                    runSpacing: KSpace.s,
                    children: [
                      for (final c in CreateStrings.conditions)
                        ChoiceChip(
                          label: Text(s.create.conditionLabel(c)),
                          selected: _condition == c,
                          onSelected: (on) => setState(() => _condition = on ? c : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _meetupController,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: s.create.meetup,
                      hintText: s.create.meetupHint,
                      prefixIcon: const Icon(AppIcons.location),
                    ),
                  ),
                ],
              ),
              FormSection(
                title: s.sectionPricing,
                icon: AppIcons.price,
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
                      // Keyed so a restored draft's category shows.
                      key: ValueKey(_category),
                      initialValue: _category,
                      decoration: InputDecoration(labelText: s.category),
                      items: kListingCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    );
                    final quantity = TextFormField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: s.create.quantity, helperText: s.create.quantityHelp, helperMaxLines: 2),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final n = int.tryParse(t);
                        return n == null || n < 1 ? s.create.quantityInvalid : null;
                      },
                    );
                    if (c.maxWidth < 420) {
                      return Column(children: [
                        price,
                        const SizedBox(height: 16),
                        category,
                        if (_asClub) ...[const SizedBox(height: 16), quantity],
                      ]);
                    }
                    if (_asClub) {
                      return Column(children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: price),
                            const SizedBox(width: 16),
                            Expanded(child: category),
                          ],
                        ),
                        const SizedBox(height: 16),
                        quantity,
                      ]);
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
