import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/image_compressor.dart';
import 'package:mykerawang/utils/local_image.dart';
import 'package:mykerawang/widgets/brand/app_motif.dart';

void main() {
  group('MotifArt.bucket', () {
    test('rounds up to 64 px steps so nearby sizes share a bitmap', () {
      expect(MotifArt.bucket(56, 1), 64);
      expect(MotifArt.bucket(64, 1), 64);
      expect(MotifArt.bucket(65, 1), 128);
      expect(MotifArt.bucket(100, 3), 320);
      expect(MotifArt.bucket(110, 2.75), 320);
    });

    test('never smaller than 64 or bigger than 512', () {
      expect(MotifArt.bucket(1, 1), 64);
      expect(MotifArt.bucket(400, 3), 512);
    });
  });

  group('ImageCompressor.keepSmaller', () {
    final original = Uint8List(1000);
    test('uses the shrunk bytes when they are smaller', () {
      final shrunk = Uint8List(300);
      expect(ImageCompressor.keepSmaller(original, shrunk), same(shrunk));
    });
    test('keeps the original when shrinking failed or grew the file', () {
      expect(ImageCompressor.keepSmaller(original, null), same(original));
      expect(ImageCompressor.keepSmaller(original, Uint8List(0)), same(original));
      expect(ImageCompressor.keepSmaller(original, Uint8List(1200)), same(original));
    });
  });

  test('photo uploads ask browsers to keep them for a year', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);
    final opts = photoUploadOptions(png);
    expect(opts.cacheControl, '31536000');
    expect(opts.contentType, 'image/png');
  });

  testWidgets('MotifArt still paints something before its bitmap is ready', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: MotifArt(AppMotif.sape, size: 80, color: Colors.teal)),
    ));
    expect(find.byType(MotifArt), findsOneWidget);
    final box = tester.getSize(find.byType(MotifArt));
    expect(box, const Size(80, 80));
  });
}
