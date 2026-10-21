import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart'; // PointerScrollEvent
import 'package:flutter/material.dart';
// Zoom in/out and chevron-left aren't in AppIcons yet (lib/theme is
// shared); swap to AppIcons once they're added there.
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/local_image.dart';

/// Opens the gallery as an overlay popup rather than a pushed page.
///
/// As a dialog it sits on top of the current screen, so dismissing it
/// (backdrop tap, Esc, Android back, browser back) returns to the page
/// underneath instead of navigating away from it entirely.
Future<void> showGallery(
  BuildContext context, {
  required List<dynamic> items,
  int initialIndex = 0,
}) {
  return showDialog(
    context: context,
    barrierColor: photoScrim(0.92),
    barrierDismissible: true,
    useSafeArea: false,
    builder: (_) => GalleryViewScreen(
      galleryItems: items,
      initialIndex: initialIndex,
      asDialog: true,
    ),
  );
}

/// Full-screen image viewer.
///
/// Desktop web has no swipe gesture and PhotoView swallows drags for
/// panning, so paging needs explicit affordances (UI_UX_AUDIT §13):
/// hover arrows, ← → / Home / End keys, mouse wheel, and Esc / backdrop
/// to close. Zoom: pinch or double-tap on touch, + / − keys, Ctrl+wheel
/// and the zoom buttons on web.
class GalleryViewScreen extends StatefulWidget {
  final List<dynamic> galleryItems; // String (URL) or LocalImage
  final int initialIndex;

  /// When shown via [showGallery] the backdrop is the dialog barrier, so
  /// the viewer itself stays transparent.
  final bool asDialog;

  const GalleryViewScreen({
    super.key,
    required this.galleryItems,
    this.initialIndex = 0,
    this.asDialog = false,
  });

  @override
  State<GalleryViewScreen> createState() => _GalleryViewScreenState();
}

class _GalleryViewScreenState extends State<GalleryViewScreen> {
  late PageController _pageController;
  late int _index;
  final _focusNode = FocusNode();
  bool _hovering = false;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  /// One controller per page, created on demand, so zoom can be driven
  /// by keys/buttons and reset when paging.
  final Map<int, PhotoViewController> _zoom = {};
  PhotoViewController _zoomFor(int i) => _zoom.putIfAbsent(i, PhotoViewController.new);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canPrev => _index > 0;
  bool get _canNext => _index < widget.galleryItems.length - 1;

  void _go(int delta) => _goTo(_index + delta);

  void _goTo(int target) {
    if (target < 0 || target >= widget.galleryItems.length || target == _index) return;
    // Leaving a page resets its zoom.
    _zoom[_index]?.reset();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  static const double _zoomStep = 1.4;

  void _zoomBy(double factor) {
    final c = _zoomFor(_index);
    final current = c.scale ?? 1.0;
    c.scale = (current * factor).clamp(0.2, 8.0);
  }

  void _resetZoom() => _zoom[_index]?.reset();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _go(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _goTo(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _goTo(widget.galleryItems.length - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
      case LogicalKeyboardKey.numpadAdd:
        _zoomBy(_zoomStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _zoomBy(1 / _zoomStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0:
        _resetZoom();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Mouse wheel pages the gallery. Throttled so one flick doesn't skip
  /// several images.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Ctrl + wheel (and trackpad pinch on web) zooms instead of paging.
    if (HardwareKeyboard.instance.isControlPressed) {
      _zoomBy(event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastWheel).inMilliseconds < 220) return;
    _lastWheel = now;
    _go(event.scrollDelta.dy > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.galleryItems.length > 1;
    final s = context.l10n;
    final count = widget.galleryItems.length;

    return Scaffold(
      backgroundColor: widget.asDialog ? Colors.transparent : photoScrim(1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: kOnPhoto),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Semantics(
          liveRegion: true,
          label: s.photoCount.fill([_index + 1, count]),
          child: ExcludeSemantics(
            child: Text(
              "${_index + 1} / $count",
              style: const TextStyle(color: kOnPhoto),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.zoomOut,
            icon: const Icon(LucideIcons.zoomOut, color: kOnPhoto),
            onPressed: () => _zoomBy(1 / _zoomStep),
          ),
          IconButton(
            tooltip: s.zoomIn,
            icon: const Icon(LucideIcons.zoomIn, color: kOnPhoto),
            onPressed: () => _zoomBy(_zoomStep),
          ),
          IconButton(
            tooltip: s.closeGallery,
            icon: const Icon(AppIcons.close, color: kOnPhoto),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Stack(
              children: [
                // Tap the backdrop to close (taps on the image itself are
                // absorbed by PhotoView, so this only fires on empty space).
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
                PhotoViewGallery.builder(
                  scrollPhysics: const BouncingScrollPhysics(),
                  itemCount: widget.galleryItems.length,
                  pageController: _pageController,
                  onPageChanged: (i) {
                    _zoom[_index]?.reset();
                    setState(() => _index = i);
                  },
                  backgroundDecoration:
                      const BoxDecoration(color: Colors.transparent),
                  builder: (context, index) {
                    final item = widget.galleryItems[index];
                    final ImageProvider provider = item is LocalImage
                        ? MemoryImage(item.bytes)
                        : CachedNetworkImageProvider(item as String);

                    return PhotoViewGalleryPageOptions(
                      controller: _zoomFor(index),
                      imageProvider: provider,
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 2.5,
                      heroAttributes: PhotoViewHeroAttributes(tag: index),
                    );
                  },
                  loadingBuilder: (context, event) => const Center(
                    child: CircularProgressIndicator(color: kOnPhoto),
                  ),
                ),

                // Desktop paging arrows
                if (multiple && (kIsWeb || _hovering)) ...[
                  if (_canPrev)
                    _arrow(alignLeft: true),
                  if (_canNext)
                    _arrow(alignLeft: false),
                ],

                // Dot indicator (the counter in the app bar covers big sets)
                if (multiple && count <= 12)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        widget.galleryItems.length,
                        (i) => Container(
                          width: i == _index ? 20 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == _index
                                ? kOnPhoto
                                : kOnPhoto.withValues(alpha: 0.4),
                            borderRadius: KRadius.pill,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrow({required bool alignLeft}) {
    return Positioned(
      left: alignLeft ? 16 : null,
      right: alignLeft ? null : 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: Material(
          color: photoScrim(0.45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _go(alignLeft ? -1 : 1),
            child: Tooltip(
              message: alignLeft ? context.l10n.previousPhoto : context.l10n.nextPhoto,
              child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                alignLeft ? LucideIcons.chevronLeft : AppIcons.chevronRight,
                color: kOnPhoto,
                size: 30,
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
