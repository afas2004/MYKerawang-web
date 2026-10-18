import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mykerawang/services/share_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
 
import 'create_listing_screen.dart';
import 'create_post_screen.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
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

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
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
  }

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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.listingDeleted)));
          popOrHome(context, true);
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
                    icon: const Icon(Icons.chat),
                    label: Text(s.chatOnWhatsApp),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () {
                      final raw = (phone ?? '').toString().trim();
                      if (raw.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.sellerNoPhone)),
                        );
                        return;
                      }
                      ShareService.openWhatsApp(
                        context,
                        raw,
                        s.whatsAppInterest.fill([_itemData['title'], formatPrice(_itemData['price'])]),
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
                        icon: const Icon(Icons.qr_code_2),
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
                          Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
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
                        : Icon(isSaved ? Icons.check_circle : Icons.save_alt, color: isSaved ? scheme.primary : null),
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

  /// Two columns (gallery left, summary card right) from this width.
  static const double _wideFrom = Responsive.desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideFrom;
      return Scaffold(
        appBar: wide
            ? AppBar(
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back),
                  // A shared link opens this page cold, with nothing
                  // underneath to pop back to.
                  onPressed: () => popOrHome(context),
                ),
                actions: [..._actions(context, onPhoto: false), const SizedBox(width: 8)],
              )
            : null,
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
                  aspectRatio: 1,
                  child: ClipRRect(borderRadius: KRadius.cut, child: _gallery(context)),
                ),
                if (_images.length > 1) ...[
                  const SizedBox(height: KSpace.m),
                  _thumbnails(context),
                ],
                const SizedBox(height: KSpace.xxl),
                _descriptionSection(context),
              ],
            ),
          ),
          // ---- right: price, status, seller, Contact ----
          secondary: SingleChildScrollView(
            padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xl),
            child: KCard(
              borderRadius: KRadius.cut,
              padding: const EdgeInsets.all(KSpace.l + KSpace.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _summary(context),
                  const SizedBox(height: KSpace.l + KSpace.xs),
                  _actionBar(context),
                ],
              ),
            ),
          ),
        ),
        // Compact: Contact (or owner controls) pinned to the bottom.
        bottomSheet: wide
            ? null
            : bottomBarConstrained(
                context,
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2)),
                    ],
                  ),
                  child: SafeArea(top: false, child: _actionBar(context)),
                ),
              ),
      );
    });
  }

  // ---------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------

  Widget _compactBody(BuildContext context) {
    return PageBody(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: photoScrim(0.5),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back, color: kOnPhoto),
                  onPressed: () => popOrHome(context),
                ),
              ),
            ),
            actions: _actions(context, onPhoto: true),
            flexibleSpace: FlexibleSpaceBar(
              background: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomLeft: KRadius.cut.bottomLeft,
                  bottomRight: KRadius.cut.bottomRight,
                ),
                child: _gallery(context),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 112),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summary(context),
                  const SizedBox(height: 24),
                  _descriptionSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------

  List<Widget> _actions(BuildContext context, {required bool onPhoto}) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final fg = onPhoto ? kOnPhoto : scheme.onSurfaceVariant;
    Widget wrap(Widget child) => onPhoto
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: CircleAvatar(backgroundColor: photoScrim(0.5), child: child),
          )
        : child;
    return [
      wrap(SaveButton(type: SavedType.listing, id: _itemData['id'], color: fg)),
      wrap(IconButton(tooltip: s.share, icon: Icon(Icons.share, color: fg), onPressed: _share)),
      if (!_isOwner)
        wrap(GuardedReportButton(
          targetId: _itemData['id'],
          type: 'listing',
          icon: Icon(Icons.more_vert, color: fg),
        )),
      if (onPhoto) const SizedBox(width: 6),
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

  /// Photos with the RESERVED / SOLD stamp and a counter.
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
              child: Icon(Icons.storefront_outlined, size: 56, color: scheme.onSurfaceVariant),
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
                    child: Icon(Icons.broken_image, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        // Top scrim so the back / action buttons stay visible.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 100,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [photoScrim(0.45), photoScrim(0)],
                ),
              ),
            ),
          ),
        ),
        if (status.badge(s) != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: photoScrim(isSold ? 0.4 : 0.25),
                child: Center(child: StatusBadge.stamp(status.badge(s)!)),
              ),
            ),
          ),
        if (images.length > 1)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration:
                  BoxDecoration(color: photoScrim(), borderRadius: BorderRadius.circular(20)),
              child: Text("${_currentImageIndex + 1} / ${images.length}",
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: kOnPhoto, fontWeight: FontWeight.bold)),
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
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _currentImageIndex;
          return TapCard(
            semanticLabel: s.photoCount.fill([i + 1, images.length]),
            borderRadius: BorderRadius.circular(8),
            border: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            onTap: () {
              setState(() => _currentImageIndex = i);
              if (_galleryController.hasClients) {
                _galleryController.animateToPage(i,
                    duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
              }
            },
            child: SizedBox(
              width: 72,
              child: CachedNetworkImage(imageUrl: images[i], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  /// Category, price (gold), title, status, reserved note and seller.
  Widget _summary(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ListingStatus.of(_itemData);
    final isSold = status == ListingStatus.sold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(_itemData['category'] ?? s.categoryGeneral),
              backgroundColor: scheme.secondaryContainer,
              labelStyle: TextStyle(color: scheme.onSecondaryContainer),
              side: BorderSide.none,
            ),
            Chip(
              avatar: Icon(
                switch (status) {
                  ListingStatus.available => Icons.check_circle_outline,
                  ListingStatus.reserved => Icons.handshake_outlined,
                  ListingStatus.sold => Icons.block,
                },
                size: 16,
              ),
              label: Text(status.label(s)),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          formatPrice(_itemData['price']),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            // Gold is for prices (design direction).
            color: isSold ? scheme.onSurfaceVariant : scheme.tertiary,
            decoration: isSold ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(_itemData['title'] ?? '',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (status == ListingStatus.reserved && !_isOwner) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.handshake_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.reservedHint,
                      style: TextStyle(color: scheme.onSecondaryContainer)),
                ),
              ],
            ),
          ),
        ],
        if (_sellerProfile != null) ...[
          const SizedBox(height: 16),
          TapCard(
            onTap: () => context.goUser(_sellerProfile!['id']),
            color: scheme.surfaceContainerHigh,
            border: BorderSide(color: scheme.outlineVariant),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage: _sellerProfile!['avatar_url'] != null
                        ? CachedNetworkImageProvider(_sellerProfile!['avatar_url'])
                        : null,
                    child: _sellerProfile!['avatar_url'] == null
                        ? Icon(Icons.person, color: scheme.onPrimaryContainer)
                        : null,
                  ),
                  const SizedBox(width: 12),
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
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(s.viewProfile,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
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
            Expanded(child: Text(s.description, style: theme.textTheme.titleLarge)),
            TextButton.icon(
              onPressed: () {
                if (!requireLogin(context)) return;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CreatePostScreen(sharedListing: _itemData)));
              },
              icon: const Icon(Icons.repeat, size: 16),
              label: Text(s.repost),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          (_itemData['description'] ?? '').toString().trim().isEmpty
              ? s.noDetails
              : _itemData['description'],
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  /// Owner: status, edit, delete. Guest: log in. Buyer: Contact.
  Widget _actionBar(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final status = ListingStatus.of(_itemData);
    final isSold = status == ListingStatus.sold;

    if (_isOwner) {
      return Row(
        children: [
          // 1. STATUS: available / reserved / sold
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_savingStatus)
                      const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.sell_outlined, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(status.label(s),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.arrow_drop_down, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 2. EDIT
          Expanded(
            child: FilledButton(
              onPressed: () async {
                final result = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CreateListingScreen(itemToEdit: _itemData)));
                if (result == true) _refreshData();
              },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(s.edit),
            ),
          ),
          const SizedBox(width: 8),
          // 3. DELETE
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.delete_outline),
            tooltip: s.deletePermanently,
            onPressed: _deleteItem,
          ),
        ],
      );
    }

    if (!isLoggedIn && !isSold) return GuestActionBar(label: s.loginToContact);

    return FilledButton.icon(
      onPressed: isSold ? null : _showPurchaseDialog,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      icon: _loadingContact
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
          : const Icon(Icons.chat),
      // Sold = onPressed null, so the theme's disabled colours apply
      label: Text(isSold ? s.sold : s.contactOrBuy),
    );
  }
}
