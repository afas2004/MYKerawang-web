import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';

/// Square crop popup: pan/zoom the image inside a fixed viewport, then
/// capture exactly what's framed. Pure Flutter (RepaintBoundary → toImage),
/// so it works identically on web/wasm and mobile with no extra plugin.
class ImageCropDialog extends StatefulWidget {
  final Uint8List bytes;
  final bool circle;

  const ImageCropDialog({super.key, required this.bytes, this.circle = true});

  /// Returns the cropped PNG bytes, or null if cancelled.
  static Future<Uint8List?> show(BuildContext context, Uint8List bytes,
          {bool circle = true}) =>
      showDialog<Uint8List>(
        context: context,
        builder: (_) => ImageCropDialog(bytes: bytes, circle: circle),
      );

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final _boundaryKey = GlobalKey();
  final _controller = TransformationController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // 3x for a crisp result on high-DPI screens
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.pop(context, data?.buffer.asUint8List());
    } catch (e) {
      debugPrint("Crop failed: $e");
      if (mounted) Navigator.pop(context, widget.bytes); // fall back to original
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    const size = 280.0;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: kerawangCut),
      title: Text(s.changePhoto),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.circle ? size : 12),
            child: RepaintBoundary(
              key: _boundaryKey,
              child: SizedBox(
                width: size,
                height: size,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 0.5,
                  maxScale: 5,
                  clipBehavior: Clip.hardEdge,
                  child: Image.memory(widget.bytes, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(s.cropHint,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(s.save),
        ),
      ],
    );
  }
}

/// Full-size image preview — shows the whole picture (contain, not cropped).
Future<void> showImagePreview(BuildContext context,
    {String? url, Uint8List? bytes}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.pop(ctx),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: InteractiveViewer(
          maxScale: 4,
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.contain)
              : Image.network(url!, fit: BoxFit.contain),
        ),
      ),
    ),
  );
}
