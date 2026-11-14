import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/form_strings.dart';
import '../language_cubit.dart';
import '../services/share_service.dart';
import '../utils/file_saver.dart';
import 'brand/brand.dart';
import 'app_toast.dart';

/// A form's own QR code: print it on a poster or show it on a screen, and
/// anyone who scans it lands on the form. [path] is the guest-safe `/f/…`
/// link (an event form's `/event/:id/form` page needs sign-in).
///
///   showFormQr(context, title: doc.title, path: '/f/${doc.slug ?? doc.id}')
Future<void> showFormQr(
  BuildContext context, {
  required String title,
  required String path,
  bool draft = false,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => FormQrDialog(title: title, path: path, draft: draft),
    );

class FormQrDialog extends StatelessWidget {
  final String title;
  final String path;

  /// A draft takes no answers yet: say so under the code.
  final bool draft;

  const FormQrDialog({super.key, required this.title, required this.path, this.draft = false});

  String get url => ShareService.absoluteUrl(path);

  /// The code as a PNG, black on white with a quiet margin, big enough to
  /// print on an A4 poster.
  static Future<Uint8List?> pngBytes(String data, {double size = 1024}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
    final margin = size * 0.08;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, size + margin * 2, size + margin * 2),
        Paint()..color = Colors.white);
    canvas.translate(margin, margin);
    painter.paint(canvas, Size(size, size));
    final px = (size + margin * 2).round();
    final image = await rec.endRecording().toImage(px, px);
    final data2 = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data2?.buffer.asUint8List();
  }

  /// A file name from the title: letters, digits and dashes only.
  static String fileName(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final short = slug.length > 40 ? slug.substring(0, 40) : slug;
    return 'qr-${short.isEmpty ? 'form' : short}.png';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text(s.formQrTitle),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(KSpace.m),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: KRadius.card,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: QrImageView(
                key: const ValueKey('form-qr'),
                data: url,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
            const SizedBox(height: KSpace.m),
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: KSpace.xs),
            SelectableText(url,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: KSpace.s),
            Text(draft ? s.panelShareDraft : s.formQrHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: draft ? scheme.error : scheme.onSurfaceVariant)),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton.icon(
          key: const ValueKey('form-qr-copy'),
          onPressed: () async {
            final copied = context.l10nRead.formsLinkCopied;
            await Clipboard.setData(ClipboardData(text: url));
            showToast(copied);
          },
          icon: const Icon(AppIcons.copy, size: 16),
          label: Text(s.formsCopyLink),
        ),
        FilledButton.icon(
          key: const ValueKey('form-qr-save'),
          onPressed: () async {
            final strings = context.l10nRead;
            final bytes = await pngBytes(url);
            final ok = bytes != null && await saveImageBytes(bytes, filename: fileName(title));
            showToast(ok ? strings.formQrSaved : strings.formQrSaveFailed);
          },
          icon: const Icon(AppIcons.download, size: 16),
          label: Text(s.formQrSave),
        ),
      ],
    );
  }
}
