import 'dart:typed_data';

/// Off the web there is no browser canvas; the native compressor is used.
Future<Uint8List?> shrinkInBrowser(Uint8List bytes, {required int maxSide, required double quality}) async =>
    null;
