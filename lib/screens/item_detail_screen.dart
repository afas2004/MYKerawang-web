import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mykerawang/services/share_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
 
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../services/category_service.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/file_saver.dart';
import '../utils/formatters.dart';
import '../utils/feedback.dart';
import '../utils/guest_access.dart';
import '../utils/listing_status.dart';
import '../utils/roles.dart';
import '../widgets/status_badge.dart';
import '../widgets/brand/brand.dart';
import '../widgets/tap_card.dart';
import 'gallery_view_screen.dart';
import '../widgets/save_button.dart';
import '../widgets/app_toast.dart';

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen>
    with RefreshOnContentChange {
  late Map<String, dynamic> _itemData;
  Map<String, dynamic>? _sellerProfile;
  bool _loadingContact = false;
  bool _savingStatus = false;
int _currentImageIndex = 0;
  final _galleryController = PageController();

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _itemData = widget.item;
    _refreshData();
    // Labels resolve from the cache (or the bundled seeds); repaint once
    // the live names arrive, for a category added since the seeds.
    CategoryService.forKind('listing').then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void onContentChanged() => _refreshData();

  Future<void> _refreshData() async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Fetch fresh item details
      final freshItem = await supabase
          .from('listings')
          .select()
          .eq('id', _itemData['id'])
          .single();

      // 2. Seller profile — public fields only. Phone and payment QR are
      // fetched on demand by _showPurchaseDialog (get_listing_contact).
      final seller = await supabase
          .from(isLoggedIn ? 'profiles' : 'profiles_public')
          .select('id, username, display_name, avatar_url')
          .eq('id', freshItem['seller_id'])
          .maybeSingle();

      if (mounted) {
        setState(() {
          _itemData = freshItem;
          _sellerProfile = seller;
        });
      }
    } catch (e) {
      debugPrint("Error refreshing item: $e");
    }
  }

  // --- LISTING STATUS (available / reserved / sold) ---
  Future<void> _setStatus(ListingStatus next) async {
    final previous = ListingStatus.of(_itemData);
    if (next == previous || _savingStatus) return;
    final s = context.l10nRead;

    // Optimistic; reverted on failure.
    setState(() {
      _savingStatus = true;
      _itemData = {..._itemData, 'status': next.dbValue, 'is_sold': next == ListingStatus.sold};
    });

    try {
      // Both columns are written; the database trigger keeps them in
      // sync either way (20261019002500_listing_status.sql).
      await Supabase.instance.client
          .from('listings')
          .update({'status': next.dbValue, 'is_sold': next == ListingStatus.sold})
          .eq('id', _itemData['id']);
      if (!mounted) return;
      showSuccess(context, switch (next) {
        ListingStatus.sold => s.markedSold,
        ListingStatus.available => s.markedAvailable,
        ListingStatus.reserved => s.statusUpdated,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _itemData = {
            ..._itemData,
            'status': previous.dbValue,
            'is_sold': previous == ListingStatus.sold,
          });
      showErrorWithRetry(context, e, onRetry: () => _setStatus(next));
    } finally {
      if (mounted) setState(() => _savingStatus = false);
    }
  }

  Future<void> _deleteItem() async {
    final s = context.l10nRead;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteListing),
        content: Text(s.deleteListingConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.delete, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('listings').delete().eq('id', _itemData['id']);
        if (mounted) {
          showToast(s.listingDeleted);
          notifyContentChanged(); // lists drop the deleted listing
          popOrHome(context);
        }
      } catch (e) {
        if (mounted) showErrorWithRetry(context, e, onRetry: _deleteItem);
      }
    }
  }

  /// Contact sheet.Talking comes first: WhatsApp is the primary action,
  /// and the seller's payment QR stays behind an explicit step with a
  /// reminder to pay only once the deal is agreed.
  Future<void> _showPurchaseDialog() async {
    if (!requireLogin(context)) return;
    if (_loadingContact) return;

    // Contact details are private (profile_contacts) and only revealed —
    // and logged — when a buyer asks for them here.
    final Map<String, dynamic> contact;
    setState(() => _loadingContact = true);
    try {
      final rows = await Supabase.instance.client
          .rpc('get_listing_contact', params: {'p_listing_id': _itemData['id']});
      final list = rows is List ? rows : const [];
      contact = list.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(list.first);
    } catch (e) {
      if (!mounted) return;
      // get_listing_contact's limits (20261019002600): no Retry, since
      // retrying straight away can't succeed.
      final text = e.toString();
      if (text.contains('rate_limited')) {
        showErrorWithRetry(context, e, message: context.l10nRead.tooManyContactRequests);
      } else if (text.contains('listing_sold')) {
        setState(() => _itemData = {..._itemData, 'status': 'sold', 'is_sold': true});
        showErrorWithRetry(context, e, message: context.l10nRead.listingNowSold);
      } else {
        showErrorWithRetry(context, e, onRetry: _showPurchaseDialog);
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingContact = false);
    }
    if (!mounted) return;

    final qrUrl = contact['payment_qr_url'] as String?;
    final phone = contact['phone_number'];
    final sellerName = contact['username'] ??
        _sellerProfile?['username'] ??
        context.l10nRead.seller;

    // Track state LOCALLY inside this function logic
    bool showQr = false;
    bool isSaving = false;
    bool isSaved = false;

    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        // 'setModalState' allows us to rebuild ONLY this bottom sheet
        builder: (BuildContext context, StateSetter setModalState) {
          final s = context.l10n;
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.contactSeller, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(s.buyingFrom.fill([sellerName]), style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(s.chatFirstHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),

                // 1. WHATSAPP — talk first
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(AppIcons.comment),
                    label: Text(s.chatOnWhatsApp),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () {
                      final raw = (phone ?? '').toString().trim();
                      if (raw.isEmpty) {
                        showToast(s.sellerNoPhone);
                        return;
                      }
                      ShareService.openWhatsApp(
                        context,
                        raw,
                        // The seller gets a link to the exact listing.
                        ShareService.withPageLink(
                          s.whatsAppInterest.fill([_itemData['title'], formatPrice(_itemData['price'])]),
                          '/item/${_itemData['id']}',
                        ),
                      );
                    },
                  ),
                ),

                // 2. PAYMENT QR — only on request
                if (qrUrl != null) ...[
                  const SizedBox(height: 12),
                  if (!showQr)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(AppIcons.qrCode),
                        label: Text(s.showPaymentQr),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: () => setModalState(() => showQr = true),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(AppIcons.info, size: 18, color: scheme.onTertiaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.paymentCaution,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Brand name of the payment scheme — not translated
                    const Text("DuitNow QR", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      height: 200, width: 200,
                      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant)),
                      child: CachedNetworkImage(
                        imageUrl: qrUrl,
                        fit: BoxFit.contain,
                        placeholder: (_,__) => const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: (isSaving || isSaved)
                        ? null // Disable if busy or done
                        : () async {
                            setModalState(() => isSaving = true);
                            try {
                              // One button, right behaviour per platform:
                              // browser download on web, gallery on mobile.
                              final response = await http.get(Uri.parse(qrUrl));
                              final ok = await saveImageBytes(
                                response.bodyBytes,
                                filename:
                                    'duitnow-${contact['username'] ?? 'qr'}.jpg',
                              );
                              setModalState(() {
                                isSaving = false;
                                isSaved = ok;
                              });
                            } catch (e) {
                              debugPrint("Save error: $e");
                              setModalState(() => isSaving = false);
                            }
                          },
                      icon: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(isSaved ? AppIcons.success : AppIcons.download, color: isSaved ? scheme.primary : null),
                      label: Text(
                        isSaving
                            ? s.saving
                            : (isSaved
                                ? s.saved
                                : (kIsWeb ? s.downloadQr : s.saveToGallery)),
                        style: TextStyle(
                          color: isSaved ? scheme.primary : null,
                          fontWeight: isSaved ? FontWeight.bold : null
                        ),
                      ),
                    ),
                    Text(s.scanToPay, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],

                const SizedBox(height: 12),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.close)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------

  bool get _isOwner {
    final me = Supabase.instance.client.auth.currentUser;
    return me != null && me.id == _itemData['seller_id'];
  }

  List<String> get _images => [
        if (_itemData['image_url'] != null) _itemData['image_url'],
        ...?(_itemData['gallery_urls'] as List?)?.whereType<String>(),
      ];

  /// Two columns (gallery left, details right) from this width.
  static const double _wideFrom = Responsive.desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideFrom;
      return Scaffold(
        // A plain app bar on every size: back, save, share, more — no
        // dark circles floating on the photo.
        appBar: AppBar(
          leading: const AppBackButton(),
          actions: [..._actions(context), const SizedBox(width: KSpace.xs)],
        ),
        body: AdaptiveScaffoldBody(
          primaryFlex: 3,
          secondaryFlex: 2,
          compact: _compactBody(context),
          // ---- left: gallery + thumbnails, description ----
          primary: SelectionArea(
            child: ListView(
              padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xxl),
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(borderRadius: KRadius.card, child: _gallery(context)),
                ),
                if (_images.length > 1) ...[
                  const SizedBox(height: KSpace.m),
                  _thumbnails(context),
                ],
                const SizedBox(height: KSpace.xl),
                _descriptionSection(context),
              ],
            ),
          ),
          // ---- right: price, details, seller, primary action ----
          secondary: SingleChildScrollView(
            padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary(context),
                const SizedBox(height: KSpace.l),
                _actionBar(context),
              ],
            ),
          ),
        ),
        // Compact: the primary action is pinned to the bottom.
        bottomNavigationBar: wide ? null : _bottomBar(context),
      );
    });
  }

  // ---------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------

  Widget _compactBody(BuildContext context) {
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.only(bottom: KSpace.xl),
        children: [
          AspectRatio(aspectRatio: 16 / 10, child: _gallery(context)),
          if (_images.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, 0),
              child: _thumbnails(context),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary(context),
                const SizedBox(height: KSpace.xl),
                _descriptionSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.m),
      child: SafeArea(top: false, child: _actionBar(context)),
    );
  }

  // ---------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------

  /// Save, share, and a "more" menu: Report for visitors; Edit and Delete
  /// for the seller (Delete lives here, not as a big red button).
  List<Widget> _actions(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return [
      SaveButton(type: SavedType.listing, id: _itemData['id'], color: scheme.onSurfaceVariant),
      IconButton(tooltip: s.share, icon: const Icon(AppIcons.share), onPressed: _share),
      if (_isOwner)
        PopupMenuButton<String>(
          tooltip: s.more,
          icon: const Icon(AppIcons.more),
          onSelected: (v) {
            if (v == 'edit') context.goEditListing(_itemData);
            if (v == 'delete') _deleteItem();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.edit),
                title: Text(s.edit),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(AppIcons.delete, color: scheme.error),
                title: Text(s.deletePermanently, style: TextStyle(color: scheme.error)),
              ),
            ),
          ],
        )
      else
        GuardedReportButton(
          targetId: _itemData['id'],
          type: 'listing',
          icon: const Icon(AppIcons.more),
        ),
    ];
  }

  void _share() {
    final s = context.l10nRead;
    // Pass cover + gallery so every photo can be shared
    ShareService.shareContent(
      context,
      _itemData['title'],
      "${s.priceLine.fill([formatPrice(_itemData['price'])])}\n${_itemData['description'] ?? ''}",
      _images,
      // Deep link keeps the description intact — the Web Share API drops
      // text when files attach.
      link: '/item/${_itemData['id']}',
    );
  }

  /// Photos with the Reserved / Sold badge and a counter.
  Widget _gallery(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ListingStatus.of(_itemData);
    final isSold = status == ListingStatus.sold;
    final images = _images;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (images.isEmpty)
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: Icon(AppIcons.photo, size: 48, color: scheme.onSurfaceVariant),
            ),
          )
        else
          PageView.builder(
            controller: _galleryController,
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) => TapCard(
              borderRadius: BorderRadius.zero,
              semanticLabel: s.photoCount.fill([index + 1, images.length]),
              onTap: () => showGallery(context, items: images, initialIndex: index),
              child: Hero(
                tag: index == 0 ? _itemData['id'] : "gallery_$index",
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  fit: BoxFit.cover,
                  // Desaturate sold photos (the colour is only a
                  // saturation=0 mask, not a visible tint)
                  color: isSold ? scheme.outline : null,
                  colorBlendMode: isSold ? BlendMode.saturation : null,
                  placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(AppIcons.photo, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        if (status.badge(s) != null)
          Positioned(
            top: KSpace.m,
            left: KSpace.m,
            child: IgnorePointer(child: StatusBadge.stamp(status.badge(s)!)),
          ),
        if (images.length > 1)
          Positioned(
            bottom: KSpace.m,
            right: KSpace.m,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: KSpace.s + 2, vertical: KSpace.xs),
                decoration: BoxDecoration(color: photoScrim(0.6), borderRadius: KRadius.pill),
                child: Text("${_currentImageIndex + 1} / ${images.length}",
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: kOnPhoto, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _thumbnails(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final images = _images;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: KSpace.s),
        itemBuilder: (context, i) {
          final selected = i == _currentImageIndex;
          return TapCard(
            semanticLabel: s.photoCount.fill([i + 1, images.length]),
            borderRadius: KRadius.small,
            border: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            onTap: () {
              setState(() => _currentImageIndex = i);
              if (_galleryController.hasClients) {
                _galleryController.animateToPage(i,
                    duration: KMotion.of(context).medium, curve: KMotion.curve);
              }
            },
            child: SizedBox(
              width: 64,
              child: CachedNetworkImage(imageUrl: images[i], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  /// Price and title, then the details card, the reserved note and the
  /// seller card.
  Widget _summary(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ListingStatus.of(_itemData);
    final isSold = status == ListingStatus.sold;
    final posted = parseLocal(_itemData['created_at']);

    Widget infoRow(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: KSpace.s),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formatPrice(_itemData['price']),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: isSold ? scheme.onSurfaceVariant : scheme.tertiary,
            decoration: isSold ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: KSpace.xs),
        Text(_itemData['title'] ?? '', style: theme.textTheme.titleLarge),
        const SizedBox(height: KSpace.l),

        // ---- details ----
        KCard(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.l, vertical: KSpace.xs),
          child: Column(
            children: [
              infoRow(AppIcons.price, s.category,
                  CategoryService.labelsFor('listing', _itemData, s) ?? s.categoryGeneral),
              const Divider(height: 1),
              infoRow(
                switch (status) {
                  ListingStatus.available => AppIcons.success,
                  ListingStatus.reserved => AppIcons.clock,
                  ListingStatus.sold => AppIcons.sold,
                },
                s.listingStatus,
                status.label(s),
              ),
              if (posted != null) ...[
                const Divider(height: 1),
                infoRow(AppIcons.calendar, s.postedOn, formatDate(posted)),
              ],
            ],
          ),
        ),

        if (status == ListingStatus.reserved && !_isOwner) ...[
          const SizedBox(height: KSpace.m),
          Container(
            padding: const EdgeInsets.all(KSpace.m),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: KRadius.input,
            ),
            child: Row(
              children: [
                Icon(AppIcons.info, size: 18, color: scheme.onSecondaryContainer),
                const SizedBox(width: KSpace.m),
                Expanded(
                  child: Text(s.reservedHint,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSecondaryContainer)),
                ),
              ],
            ),
          ),
        ],

        // ---- seller ----
        if (_sellerProfile != null) ...[
          const SizedBox(height: KSpace.m),
          KCard(
            onTap: () => context.goUser(_sellerProfile!['id']),
            padding: const EdgeInsets.all(KSpace.m),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: _sellerProfile!['avatar_url'] != null
                      ? CachedNetworkImageProvider(_sellerProfile!['avatar_url'])
                      : null,
                  child: _sellerProfile!['avatar_url'] == null
                      ? Icon(AppIcons.person, color: scheme.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(width: KSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.seller,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      Text(displayNameFor(s, _sellerProfile),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
                Text(s.viewProfile,
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                Icon(AppIcons.chevronRight, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _descriptionSection(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(s.description, style: theme.textTheme.titleMedium)),
            TextButton.icon(
              onPressed: () {
                if (!requireLogin(context)) return;
                context.goCreatePost(sharedListing: _itemData);
              },
              icon: const Icon(AppIcons.repost, size: 16),
              label: Text(s.repost),
            ),
          ],
        ),
        const SizedBox(height: KSpace.s),
        Text(
          (_itemData['description'] ?? '').toString().trim().isEmpty
              ? s.noDetails
              : _itemData['description'],
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  /// Seller: status dropdown + Edit (Delete is in the ⋮ menu). Guest: log
  /// in. Buyer: Contact.
  Widget _actionBar(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final status = ListingStatus.of(_itemData);
    final isSold = status == ListingStatus.sold;

    if (_isOwner) {
      return Row(
        children: [
          Expanded(
            child: PopupMenuButton<ListingStatus>(
              tooltip: s.listingStatus,
              enabled: !_savingStatus,
              initialValue: status,
              onSelected: _setStatus,
              itemBuilder: (_) => [
                for (final st in ListingStatus.values)
                  CheckedPopupMenuItem(
                    value: st,
                    checked: st == status,
                    child: Text(st.label(s)),
                  ),
              ],
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: KSpace.m),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outline),
                  borderRadius: KRadius.pill,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_savingStatus)
                      const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(AppIcons.price, size: 18, color: scheme.onSurface),
                    const SizedBox(width: KSpace.s),
                    Flexible(
                      child: Text(status.label(s),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                    const SizedBox(width: KSpace.xs),
                    Icon(AppIcons.chevronRight, size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: KSpace.s),
          Expanded(
            child: FilledButton.icon(
              // Edit is its own route; saving brings us back here and
              // refreshes through contentChanges.
              onPressed: () => context.goEditListing(_itemData),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(AppIcons.edit, size: 18),
              label: Text(s.edit),
            ),
          ),
        ],
      );
    }

    if (!isLoggedIn && !isSold) return GuestActionBar(label: s.loginToContact);

    return FilledButton.icon(
      onPressed: isSold ? null : _showPurchaseDialog,
      // The page's one accent action.
      style: accentButtonStyle(context, minimumSize: const Size.fromHeight(52)),
      icon: _loadingContact
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: KTokens.of(context).onAccent))
          : const Icon(AppIcons.comment),
      // Sold = onPressed null, so the theme's disabled colours apply
      label: Text(isSold ? s.sold : s.contactOrBuy),
    );
  }
}
