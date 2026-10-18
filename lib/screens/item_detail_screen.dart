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
import '../widgets/tap_card.dart';
import 'gallery_view_screen.dart';
import '../utils/responsive.dart';
import '../services/saved_items.dart';
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

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final isOwner = currentUser != null && currentUser.id == _itemData['seller_id'];
    final status = ListingStatus.of(_itemData);
    final isSold = status == ListingStatus.sold;
    final isReserved = status == ListingStatus.reserved;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;

    final List<String> allImages = [
      if (_itemData['image_url'] != null) _itemData['image_url'],
      ...?(_itemData['gallery_urls'] as List?)?.cast<String>(),
    ];

    return Scaffold(
      body: PageBody(child: CustomScrollView(
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
                  // A shared link opens this page cold, with nothing
                  // underneath to pop back to.
                  onPressed: () => popOrHome(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: allImages.length,
                    onPageChanged: (index) => setState(() => _currentImageIndex = index),
                    itemBuilder: (context, index) {
                      return TapCard(
                        borderRadius: BorderRadius.zero,
                        onTap: () {
                          showGallery(context, items: allImages, initialIndex: index);
                        },
                        child: Hero(
                          tag: index == 0 ? _itemData['id'] : "gallery_$index", 
                          child: CachedNetworkImage(
                            imageUrl: allImages[index],
                            fit: BoxFit.cover,
                            // Desaturate sold photos (the colour is only a
                            // saturation=0 mask, not a visible tint)
                            color: isSold ? scheme.outline : null,
                            colorBlendMode: isSold ? BlendMode.saturation : null,
                            placeholder: (_,__) => const Center(child: CircularProgressIndicator()),
                            errorWidget: (_,__,___) => Container(color: scheme.surfaceContainerHighest, child: Icon(Icons.broken_image, color: scheme.onSurfaceVariant)),
                          ),
                        ),
                      );
                    },
                  ),
                  if (status.badge(s) != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: photoScrim(isSold ? 0.4 : 0.25),
                          child: Center(child: StatusBadge.stamp(status.badge(s)!)),
                        ),
                      ),
                    ),
                  if (allImages.length > 1)
                    Positioned(
                      bottom: 16, right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: photoScrim(), borderRadius: BorderRadius.circular(20)),
                        child: Text("${_currentImageIndex + 1} / ${allImages.length}", style: theme.textTheme.labelMedium?.copyWith(color: kOnPhoto, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        label: Text(_itemData['category'] ?? s.categoryGeneral),
                        backgroundColor: scheme.secondaryContainer,
                        labelStyle: TextStyle(color: scheme.onSecondaryContainer),
                        side: BorderSide.none,
                      ),
                      Text(formatPrice(_itemData['price']), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: scheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: Text(_itemData['title'], style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                      SaveButton(type: SavedType.listing, id: _itemData['id'], color: scheme.onSurfaceVariant),
                      IconButton(
                        tooltip: s.share,
                        icon: Icon(Icons.share, color: scheme.onSurfaceVariant),
                        onPressed: () {
                          // Pass cover + gallery so every photo can be shared
                          ShareService.shareContent(
                            context,
                            _itemData['title'],
                            "${s.priceLine.fill([formatPrice(_itemData['price'])])}\n${_itemData['description'] ?? ''}",
                            allImages,
                            // Deep link keeps the description intact — the
                            // Web Share API drops text when files attach.
                            link: '/item/${_itemData['id']}',
                          );
                        },
                      ),
                      if (!isOwner)
                        GuardedReportButton(targetId: _itemData['id'], type: 'listing'),
                    ],
                  ),
                  if (isReserved && !isOwner) ...[
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
                  const SizedBox(height: 20),

                  if (_sellerProfile != null)
                    TapCard(
                      onTap: () => context.goUser(_sellerProfile!['id']),
                      color: scheme.surfaceContainer,
                      border: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(backgroundImage: _sellerProfile!['avatar_url'] != null ? CachedNetworkImageProvider(_sellerProfile!['avatar_url']) : null, child: _sellerProfile!['avatar_url'] == null ? const Icon(Icons.person) : null),
                            const SizedBox(width: 12),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(displayNameFor(s, _sellerProfile), style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(s.viewProfile, style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
                            ]),
                            const Spacer(),
                            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  
                  // --- NEW POST FUNCTION ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.description, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () {
                          if (!requireLogin(context)) return;
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePostScreen(sharedListing: _itemData)));
                        },
                        icon: const Icon(Icons.repeat, size: 16),
                        label: Text(s.repost),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_itemData['description'] ?? s.noDetails),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          )
        ],
      )),
      
      // --- OWNER CONTROLS ---
      bottomSheet: bottomBarConstrained(context, Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))]
        ),
        child: isOwner
            ? Row(
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
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.primary),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_savingStatus)
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                  
                  // 2. EDIT BUTTON
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateListingScreen(itemToEdit: _itemData)));
                        if (result == true) _refreshData(); 
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(s.edit),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. DELETE ICON (Small, beside edit)
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                      tooltip: s.deletePermanently,
                      onPressed: _deleteItem,
                    ),
                  ),
                ],
              )
            // GUEST VIEW
            : !isLoggedIn && !isSold
            ? GuestActionBar(label: s.loginToContact)
            // BUYER VIEW
            : ElevatedButton.icon(
                onPressed: isSold ? null : _showPurchaseDialog, 
                icon: _loadingContact
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                    : const Icon(Icons.chat),
                label: Text(isSold ? s.sold : s.contactOrBuy),
                // Sold = onPressed null, so the theme's disabled colours apply
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
      )),
    );
  }
}