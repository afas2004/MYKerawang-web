import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart'; // PointerScrollEvent
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    barrierColor: Colors.black.withValues(alpha: 0.92),
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
/// hover arrows, ← → keys, mouse wheel, and Esc / backdrop to close.
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
    super.dispose();
  }

  bool get _canPrev => _index > 0;
  bool get _canNext => _index < widget.galleryItems.length - 1;

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.galleryItems.length) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _go(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
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
    final now = DateTime.now();
    if (now.difference(_lastWheel).inMilliseconds < 220) return;
    _lastWheel = now;
    _go(event.scrollDelta.dy > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.galleryItems.length > 1;

    return Scaffold(
      backgroundColor: widget.asDialog ? Colors.transparent : Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          "${_index + 1} / ${widget.galleryItems.length}",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: "Close",
            icon: const Icon(Icons.close, color: Colors.white),
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
                  onPageChanged: (i) => setState(() => _index = i),
                  backgroundDecoration:
                      const BoxDecoration(color: Colors.transparent),
                  builder: (context, index) {
                    final item = widget.galleryItems[index];
                    final ImageProvider provider = item is LocalImage
                        ? MemoryImage(item.bytes)
                        : CachedNetworkImageProvider(item as String);

                    return PhotoViewGalleryPageOptions(
                      imageProvider: provider,
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 2.5,
                      heroAttributes: PhotoViewHeroAttributes(tag: index),
                    );
                  },
                  loadingBuilder: (context, event) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),

                // Desktop paging arrows
                if (multiple && (kIsWeb || _hovering)) ...[
                  if (_canPrev)
                    _arrow(alignLeft: true),
                  if (_canNext)
                    _arrow(alignLeft: false),
                ],

                // Dot indicator
                if (multiple)
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
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(99),
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
          color: Colors.black.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _go(alignLeft ? -1 : 1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                alignLeft ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
