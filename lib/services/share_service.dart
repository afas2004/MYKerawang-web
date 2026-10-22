import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';

/// Where deep links point when we're not running on the web.
const String kAppBaseUrl = 'https://mykerawang-app.web.app';

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

  /// Absolute URL for a route such as `/item/<id>`.
  ///
  /// On web `Uri.base` is the page currently open, so a share from
  /// localhost produces a localhost link and a share from production
  /// produces a production one. Native has no meaningful `Uri.base`, so it
  /// falls back to the deployed host.
  static String absoluteUrl(String path) {
    final origin = kIsWeb ? Uri.base.origin : kAppBaseUrl;
    return '$origin$path';
  }

  /// [text] followed by the page's absolute URL on its own line, so the
  /// person receiving a chat message can open the exact listing / event.
  static String withPageLink(String text, String path) =>
      '$text\n${absoluteUrl(path)}';

  /// Share sheet.
  ///
  /// [link] is a route such as `/item/<id>`. When present, the default on
  /// web is to share **text + link**: the Web Share API drops the caption
  /// whenever files are attached — the message is handed over correctly and
  /// then discarded by the receiving app. A link keeps the description and
  /// still gets the recipient to every photo, at full resolution.
  ///
  /// [images] may be a single cover URL or a list. Attaching them is still
  /// offered, but on web it becomes an explicit choice with a warning.
  static Future<void> shareContent(
    BuildContext context,
    String title,
    String body,
    dynamic images, { // String? cover, or List<String> of urls
    String? link,
  }) async {
    final urls = <String>[
      if (images is String && images.isNotEmpty) images,
      if (images is List) ...images.whereType<String>().where((u) => u.isNotEmpty),
    ];

    final url = link == null ? null : absoluteUrl(link);

    final defaultText =
        "$title\n\n$body\n\n${context.l10nRead.shareFooter}";

    final result = await showDialog<_ShareChoice>(
      context: context,
      builder: (_) => _ShareSheet(
        initialText: defaultText,
        imageUrls: urls,
        link: url,
      ),
    );
    if (result == null || !context.mounted) return;

    await _performShare(context, result.text, result.selectedUrls, result.link);
  }

  static Future<void> _performShare(BuildContext context, String text,
      List<String> urls, String? link) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;

    // The link rides inside `text` rather than in a separate uri member:
    // every share target linkifies a bare URL, whereas a distinct member is
    // one more thing an implementation is free to ignore.
    final message = link == null ? text : '$text\n\n$link';

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
        text: message,
        // `subject` survives in some targets (email, a few chat apps) even
        // when they drop the body for multi-file shares.
        subject: message.split('\n').first,
        files: files.isEmpty ? null : files,
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      debugPrint("Share error: $e");
      // Fall back to text-only if the images couldn't be fetched
      await SharePlus.instance.share(
        ShareParams(text: message, sharePositionOrigin: origin),
      );
    }
  }
}

class _ShareChoice {
  final String text;
  final List<String> selectedUrls;
  final String? link;
  _ShareChoice(this.text, this.selectedUrls, this.link);
}

/// Lets the user tweak the message, and choose between sending a link
/// (which keeps the message) or the photos themselves (which often doesn't).
class _ShareSheet extends StatefulWidget {
  final String initialText;
  final List<String> imageUrls;
  final String? link;

  const _ShareSheet({
    required this.initialText,
    required this.imageUrls,
    this.link,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late TextEditingController _ctrl;
  late Set<int> _selected;

  /// Attaching photos costs the caption on web. Where a link is available,
  /// default to that instead; otherwise photos are all we have.
  late bool _attachPhotos;

  bool get _hasLink => widget.link != null;
  bool get _hasPhotos => widget.imageUrls.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _selected = {for (var i = 0; i < widget.imageUrls.length; i++) i};
    _attachPhotos = _hasPhotos && !(kIsWeb && _hasLink);
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
              // ---- the link that will be appended ----
              if (_hasLink) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.link!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      IconButton(
                        tooltip: s.copyLink,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy, size: 15),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: widget.link!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.linkCopied)),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],

              // ---- photos: opt-in when a link exists, because of the cost ----
              if (_hasPhotos) ...[
                const SizedBox(height: 8),
                if (_hasLink)
                  CheckboxListTile(
                    value: _attachPhotos,
                    onChanged: (v) => setState(() => _attachPhotos = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(
                      s.attachPhotosInstead,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    subtitle: Text(
                      kIsWeb
                          ? s.attachPhotosWebWarning
                          : s.attachPhotosNativeWarning,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  )
                else ...[
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
                ],

                if (_attachPhotos) ...[
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
            ],
          ),
        ),
      ),
      actions: [
        // Guarantees the text is always obtainable, whatever the target
        // decides to keep.
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(
              text: widget.link == null
                  ? _ctrl.text
                  : '${_ctrl.text}\n\n${widget.link}',
            ));
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
              _attachPhotos
                  ? [for (final i in _selected) widget.imageUrls[i]]
                  : const [],
              widget.link,
            ),
          ),
          icon: const Icon(Icons.share, size: 18),
          label: Text(s.share),
        ),
      ],
    );
  }
}