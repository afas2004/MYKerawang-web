import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/photo_rules.dart';

/// The upload gate: what the bytes say, not what the file is called.
Uint8List png(int w, int h) {
  final b = BytesBuilder();
  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.add([0, 0, 0, 13]); // IHDR length
  b.add('IHDR'.codeUnits);
  b.add([(w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF]);
  b.add([(h >> 24) & 0xFF, (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF]);
  b.add(List.filled(16, 0)); // bit depth, colour type, CRC tail
  return b.toBytes();
}

Uint8List gif(int w, int h) => Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
      w & 0xFF, (w >> 8) & 0xFF,
      h & 0xFF, (h >> 8) & 0xFF,
      ...List.filled(8, 0),
    ]);

/// A JPEG with one APP0 segment and then a baseline SOF0.
Uint8List jpeg(int w, int h) => Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE0, 0x00, 0x10, ...List.filled(14, 0), // APP0, length 16
      0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, length 17, precision 8
      (h >> 8) & 0xFF, h & 0xFF, // height
      (w >> 8) & 0xFF, w & 0xFF, // width
      ...List.filled(8, 0),
    ]);

Uint8List webpX(int w, int h) => Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
      0x57, 0x45, 0x42, 0x50, // WEBP
      0x56, 0x50, 0x38, 0x58, 0x0A, 0, 0, 0, // 'VP8X' + chunk size
      0x00, 0, 0, 0, // flags + 3 reserved bytes
      (w - 1) & 0xFF, ((w - 1) >> 8) & 0xFF, ((w - 1) >> 16) & 0xFF,
      (h - 1) & 0xFF, ((h - 1) >> 8) & 0xFF, ((h - 1) >> 16) & 0xFF,
      ...List.filled(8, 0),
    ]);

/// A lossless WebP ('VP8L'): the size is bit-packed, 14 bits each, minus one.
Uint8List webpL(int w, int h) {
  final bits = ((w - 1) & 0x3FFF) | (((h - 1) & 0x3FFF) << 14);
  return Uint8List.fromList([
    0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
    0x57, 0x45, 0x42, 0x50, // WEBP
    0x56, 0x50, 0x38, 0x4C, 0x2F, 0, 0, 0, // 'VP8L' + chunk size
    0x2F, // signature byte
    bits & 0xFF, (bits >> 8) & 0xFF, (bits >> 16) & 0xFF, (bits >> 24) & 0xFF,
    ...List.filled(8, 0),
  ]);
}

/// A WebP whose chunk we do not understand, so the size cannot be read.
Uint8List webpUnknown() => Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
      0x57, 0x45, 0x42, 0x50, // WEBP
      0x56, 0x50, 0x38, 0x5A, 0x0A, 0, 0, 0, // 'VP8Z'
      ...List.filled(12, 0),
    ]);

void main() {
  group('photoMime', () {
    test('reads the signature, not the extension', () {
      expect(photoMime(png(10, 10)), 'image/png');
      expect(photoMime(jpeg(10, 10)), 'image/jpeg');
      expect(photoMime(gif(10, 10)), 'image/gif');
      expect(photoMime(webpX(10, 10)), 'image/webp');
    });

    test('refuses anything else — including things a picker may hand back', () {
      expect(photoMime(Uint8List.fromList('<?xml version="1.0"?><svg/>'.codeUnits)), isNull);
      expect(photoMime(Uint8List.fromList('<html><script>alert(1)</script>'.codeUnits)), isNull);
      expect(photoMime(Uint8List.fromList('%PDF-1.7'.codeUnits)), isNull);
      expect(photoMime(Uint8List(0)), isNull);
      expect(photoMime(Uint8List.fromList([0xFF, 0xD8])), isNull); // truncated JPEG
    });
  });

  group('photoSize', () {
    test('reads dimensions from each header', () {
      expect(photoSize(png(1920, 1080)), (1920, 1080));
      expect(photoSize(gif(320, 240)), (320, 240));
      expect(photoSize(jpeg(800, 600)), (800, 600));
      expect(photoSize(webpX(1000, 750)), (1000, 750));
      expect(photoSize(webpL(640, 480)), (640, 480));
    });

    test('null for a format it cannot read, and for rubbish', () {
      expect(photoSize(Uint8List.fromList('%PDF'.codeUnits)), isNull);
      expect(photoSize(Uint8List(3)), isNull);
      expect(photoSize(webpUnknown()), isNull);
    });
  });

  group('checkPhoto', () {
    test('a normal photo passes', () {
      expect(checkPhoto(png(1920, 1080)), isNull);
      expect(checkPhoto(jpeg(4000, 3000)), isNull); // 12 MP, fine
    });

    test('a renamed non-image is refused before it is uploaded', () {
      expect(checkPhoto(Uint8List.fromList('not a photo'.codeUnits)),
          PhotoProblem.notAnImage);
      expect(checkPhoto(Uint8List.fromList('<svg onload=alert(1)>'.codeUnits)),
          PhotoProblem.notAnImage);
    });

    test('too many bytes is refused', () {
      final big = Uint8List(kMaxUploadBytes + 1);
      big.setAll(0, png(100, 100)); // valid header, oversize payload
      expect(checkPhoto(big), PhotoProblem.tooLarge);
    });

    test('a decompression bomb is refused even when the file is small', () {
      final bomb = png(12000, 12000); // 144 MP, a few hundred bytes here
      expect(bomb.length, lessThan(kMaxUploadBytes));
      expect(checkPhoto(bomb), PhotoProblem.tooManyPixels);
    });

    test('a lossless-WebP bomb is caught, not let through as unknown', () {
      // VP8L used to return null from photoSize, and checkPhoto allowed an
      // unknown size — so this 144 MP file passed every gate.
      final bomb = webpL(12000, 12000);
      expect(bomb.length, lessThan(kMaxUploadBytes));
      expect(photoSize(bomb), (12000, 12000));
      expect(checkPhoto(bomb), PhotoProblem.tooManyPixels);
      expect(checkPhoto(webpL(800, 600)), isNull);
    });

    test('a WebP whose size cannot be read is refused', () {
      expect(checkPhoto(webpUnknown()), PhotoProblem.notAnImage);
    });

    test('the pixel ceiling is where we think it is', () {
      expect(checkPhoto(png(8000, 4999)), isNull); // 40.0 MP, just under
      expect(checkPhoto(png(8000, 5001)), PhotoProblem.tooManyPixels);
    });
  });
}
