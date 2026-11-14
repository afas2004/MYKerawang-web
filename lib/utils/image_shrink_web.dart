import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Shrinks a photo with the browser's own decoder and canvas: scale so the
/// longest side is at most [maxSide], then re-encode as JPEG at [quality]
/// (0–1). The browser applies the photo's EXIF rotation while decoding, so
/// sideways phone shots come out upright. Transparent areas become white.
///
/// Returns null when the browser can't do it (the caller then uploads the
/// original bytes).
Future<Uint8List?> shrinkInBrowser(Uint8List bytes, {required int maxSide, required double quality}) async {
  web.ImageBitmap? bitmap;
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    bitmap = await web.window.createImageBitmap(blob).toDart;
    final w = bitmap.width, h = bitmap.height;
    if (w == 0 || h == 0) return null;
    final scale = (w > h ? w : h) > maxSide ? maxSide / (w > h ? w : h) : 1.0;
    final tw = (w * scale).round(), th = (h * scale).round();

    final canvas = web.HTMLCanvasElement()
      ..width = tw
      ..height = th;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.fillStyle = 'white'.toJS;
    ctx.fillRect(0, 0, tw, th);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, tw, th);

    final done = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/jpeg', quality.toJS);
    final out = await done.future.timeout(const Duration(seconds: 20));
    if (out == null) return null;
    final buffer = await out.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  } finally {
    bitmap?.close();
  }
}
