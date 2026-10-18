import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';

class ShareService {
  
  // 1. THE WHATSAPP FIX
  static Future<void> openWhatsApp(BuildContext context, String rawPhone, String message) async {
    // 1. THE CLEANER: Remove everything that is NOT a number
    // "012-345 (Main)" -> "012345"
    // "http://scam.com" -> "" (Empty string)
    final s = context.l10nRead;
    String phone = rawPhone.replaceAll(RegExp(r'\D'), '');

    // International prefixes: "+60..." and "0060..." both reduce to "60..."
    if (phone.startsWith('00')) phone = phone.substring(2);

    // 2. Safety Check: If they typed nonsense/links, 'phone' is now empty.
    if (phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.invalidPhone.fill([rawPhone]))),
      );
      return;
    }

    // 3. Malaysia format. Order matters: check the 60 country code first,
    //    otherwise "60123..." would be mistaken for a local "0..." number.
    if (phone.startsWith('60')) {
      // already international
    } else if (phone.startsWith('0')) {
      phone = '60${phone.substring(1)}'; // 012xxxx -> 6012xxxx
    } else {
      phone = '60$phone'; // bare 12xxxxxx
    }

    final url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");

    try {
      // externalApplication is right on Android 11+, but on web it can be
      // rejected outright — there the platform default opens a new tab.
      final mode =
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
      if (!await launchUrl(url, mode: mode, webOnlyWindowName: '_blank')) {
        throw 'Could not launch';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.whatsAppFailed)),
        );
      }
    }
  }

  /// Share sheet that carries **all** images plus the description, and
  /// lets the user edit the message and deselect images first.
  ///
  /// [imageUrls] may hold the cover plus gallery images; every selected
  /// one is attached, not just the first.
  static Future<void> shareContent(
    BuildContext context,
    String title,
    String body,
    dynamic images, // String? cover, or List<String> of urls
  ) async {
    final urls = <String>[
      if (images is String && images.isNotEmpty) images,
      if (images is List) ...images.whereType<String>().where((u) => u.isNotEmpty),
    ];

    final defaultText =
        "$title\n\n$body\n\n${context.l10nRead.shareFooter}";

    final result = await showDialog<_ShareChoice>(
      context: context,
      builder: (_) => _ShareSheet(initialText: defaultText, imageUrls: urls),
    );
    if (result == null || !context.mounted) return;

    await _performShare(context, result.text, result.selectedUrls);
  }

  static Future<void> _performShare(
      BuildContext context, String text, List<String> urls) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;

    // share_plus 13 API: the old static Share.share()/shareXFiles() were
    // removed in favour of SharePlus.instance.share(ShareParams(...)).
    try {
      final files = <XFile>[];
      for (var i = 0; i < urls.length; i++) {
        final response = await http.get(Uri.parse(urls[i]));
        if (response.statusCode == 200) {
          files.add(XFile.fromData(
            response.bodyBytes,
            name: 'mykerawang_$i.jpg',
            mimeType: 'image/jpeg',
          ));
        }
      }

      await SharePlus.instance.share(ShareParams(
        text: text,
        // `subject` survives in some targets (email, a few chat apps) even
        // when they drop the body for multi-file shares.
        subject: text.split('\n').first,
        files: files.isEmpty ? null : files,
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      debugPrint("Share error: $e");
      // Fall back to text-only if the images couldn't be fetched
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
    }
  }
}

class _ShareChoice {
  final String text;
  final List<String> selectedUrls;
  _ShareChoice(this.text, this.selectedUrls);
}

/// Lets the user tweak the message and pick which photos go along.
class _ShareSheet extends StatefulWidget {
  final String initialText;
  final List<String> imageUrls;

  const _ShareSheet({required this.initialText, required this.imageUrls});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late TextEditingController _ctrl;
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _selected = {for (var i = 0; i < widget.imageUrls.length; i++) i};
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;

    return AlertDialog(
      title: Text(s.share),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ctrl,
                maxLines: 6,
                minLines: 3,
                decoration: InputDecoration(
                  labelText: s.message,
                  alignLabelWithHint: true,
                ),
              ),
              if (widget.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(s.photosCount.fill([_selected.length, widget.imageUrls.length]),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
                if (_selected.length > 1)
                  Text(
                    s.captionDropWarning,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.imageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final on = _selected.contains(i);
                      return InkWell(
                        onTap: () => setState(() {
                          on ? _selected.remove(i) : _selected.add(i);
                        }),
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Opacity(
                                opacity: on ? 1 : 0.35,
                                child: Image.network(widget.imageUrls[i],
                                    width: 84, height: 84, fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                on
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: on ? scheme.primary : kOnPhoto,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        // Several apps (WhatsApp especially) silently drop the caption when
        // more than one image is attached — this guarantees the text is
        // always obtainable.
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _ctrl.text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.textCopied)),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 16),
          label: Text(s.copyText),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel)),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _ShareChoice(
              _ctrl.text,
              [for (final i in _selected) widget.imageUrls[i]],
            ),
          ),
          icon: const Icon(Icons.share, size: 18),
          label: Text(s.share),
        ),
      ],
    );
  }
}