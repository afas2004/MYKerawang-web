import 'dart:typed_data';

import '../l10n/app_strings.dart';

/// What a photo upload accepts, checked on the **bytes** before anything is
/// sent.
///
/// Two gates, deliberately:
/// * the picker's `maxWidth`/`maxHeight`/`imageQuality` shrink what the user
///   chose, and
/// * these rules refuse what is not an image at all, what is still too big,
///   and what would expand into a decompression bomb.
///
/// The bucket enforces the same shape server-side
/// (`20261026014100_storage_image_limits.sql`: allowed_mime_types +
/// file_size_limit), so a crafted client cannot store an SVG either. This is
/// the client half — a refusal with a sentence instead of a failed request.

/// 5 MB, matching the bucket's `file_size_limit`. The picker lands around
/// 200–500 KB, so this only catches the unusual path.
const int kMaxUploadBytes = 5 * 1024 * 1024;

/// A 40 MP ceiling (about 7300×5500). A 12000×12000 PNG can be a few hundred
/// KB on disk and 500 MB decoded, which is what kills a browser tab.
const int kMaxUploadPixels = 40 * 1000 * 1000;

enum PhotoProblem { notAnImage, tooLarge, tooManyPixels }

/// Thrown by [PostService.uploadPhotos] when bytes reach it that no picker
/// checked. Callers that already gate at pick time never see it.
class PhotoUploadException implements Exception {
  final PhotoProblem problem;
  const PhotoUploadException(this.problem);

  @override
  String toString() => 'PhotoUploadException($problem)';
}

/// The sentence for [problem], from the app strings.
String photoProblemText(AppStrings s, PhotoProblem problem) => switch (problem) {
      PhotoProblem.notAnImage => s.photoNotImage,
      PhotoProblem.tooLarge => s.photoTooLarge,
      PhotoProblem.tooManyPixels => s.photoTooLarge,
    };

/// The image type of [bytes] from its signature, or null when it is not one of
/// the four formats the app uploads. Never trusts a file name or a MIME type.
String? photoMime(Uint8List b) {
  bool at(int offset, List<int> sig) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
  if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

/// Width and height from the header, when the format lets us read them
/// without decoding. Null means the header is unreadable — [checkPhoto]
/// refuses that rather than let the pixel ceiling be skipped.
(int, int)? photoSize(Uint8List b) {
  int be16(int o) => (b[o] << 8) | b[o + 1];
  int be32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  int le16(int o) => b[o] | (b[o + 1] << 8);
  int le24(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
  int le32(int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  final mime = photoMime(b);
  try {
    if (mime == 'image/png') {
      // signature(8) + length(4) + 'IHDR' + width(4) + height(4)
      if (b.length < 24) return null;
      return (be32(16), be32(20));
    }
    if (mime == 'image/gif') {
      if (b.length < 10) return null;
      return (le16(6), le16(8));
    }
    if (mime == 'image/webp') {
      if (b.length < 30) return null;
      // 'VP8X' extended: 24-bit canvas size, minus one, at 24 and 27.
      if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x58) {
        return (le24(24) + 1, le24(27) + 1);
      }
      // 'VP8 ' lossy: 14-bit dimensions after the 3-byte frame tag.
      if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x20) {
        return (le16(26) & 0x3FFF, le16(28) & 0x3FFF);
      }
      // 'VP8L' lossless: byte 20 is the 0x2F signature, then 4 bytes pack
      // (width - 1) in the low 14 bits and (height - 1) in the next 14.
      if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x4C) {
        if (b.length < 25) return null;
        final bits = le32(21);
        return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
      }
      return null;
    }
    if (mime == 'image/jpeg') {
      // Walk the segments to the SOFn frame header (C0–CF except C4/C8/CC).
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        if (marker == 0xD8 || marker == 0xD9) {
          i += 2;
          continue;
        }
        final length = be16(i + 2);
        if (length < 2) return null;
        final isFrame = marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        if (isFrame) {
          if (i + 9 > b.length) return null;
          return (be16(i + 7), be16(i + 5));
        }
        i += 2 + length;
      }
      return null;
    }
  } catch (_) {
    // A truncated header is not a reason to crash a picker.
    return null;
  }
  return null;
}

/// What is wrong with [bytes], or null when it may be uploaded.
///
/// Order matters: a text file is refused as "not an image" even when it is
/// also huge.
PhotoProblem? checkPhoto(Uint8List bytes) {
  final mime = photoMime(bytes);
  if (mime == null) return PhotoProblem.notAnImage;
  if (bytes.length > kMaxUploadBytes) return PhotoProblem.tooLarge;
  final size = photoSize(bytes);
  if (size == null) {
    // WebP is the one format that could hide its dimensions without the file
    // being broken (VP8L used to return null), so an unreadable WebP is
    // refused outright. For JPEG a missing SOF means a damaged file: the
    // decoder and the bucket's 5 MB cap already cover it, and refusing it
    // here would newly block photos that uploaded fine before this review.
    return mime == 'image/webp' ? PhotoProblem.notAnImage : null;
  }
  if (size.$1 * size.$2 > kMaxUploadPixels) {
    return PhotoProblem.tooManyPixels;
  }
  return null;
}
