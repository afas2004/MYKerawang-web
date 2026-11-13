import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/attendance_form_strings.dart';
import '../../l10n/form_strings.dart';
import '../../language_cubit.dart';
import '../../services/checkin_form_service.dart';
import '../../services/form_service.dart';
import '../../services/student_verification.dart';
import '../../theme/app_icons.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/brand/brand.dart';

/// In-app check-in: live camera only, so a screenshot from the gallery
/// cannot be scanned. The QR is a URL, so the token is its `t` parameter.
class CheckinScanScreen extends StatefulWidget {
  final String eventId;
  final String title;

  const CheckinScanScreen(
      {super.key, required this.eventId, required this.title});

  @override
  State<CheckinScanScreen> createState() => _CheckinScanScreenState();
}

class _CheckinScanScreenState extends State<CheckinScanScreen> {
  bool _busy = false;

  static String? _tokenOf(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri != null && uri.queryParameters['t'] != null) {
      return uri.queryParameters['t'];
    }
    return v;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    final token = _tokenOf(raw);
    if (token == null) return;

    _busy = true;
    final s = context.l10nRead;
    try {
      final res = await Supabase.instance.client
          .rpc('checkin_with_token', params: {'p_token': token});
      if (!mounted) return;
      await _showResult(res == 'already' ? s.evAlreadyIn : s.evCheckedIn, true);
    } catch (e) {
      if (!mounted) return;
      await _showResult(_errorText(e), false);
    } finally {
      _busy = false;
    }
  }

  String _errorText(Object e) {
    final s = context.l10n;
    return switch (parseModError(e)?.code) {
      'checkin_expired' => s.evCheckinExpired,
      'checkin_invalid' => s.evCheckinInvalid,
      'checkin_verify' => s.evCheckinVerify,
      'checkin_login_required' => s.guestPromptTitle,
      _ => s.somethingWentWrong,
    };
  }

  Future<void> _showResult(String text, bool ok) async {
    final s = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(ok ? AppIcons.success : AppIcons.warning,
            color: ok ? Theme.of(ctx).colorScheme.primary : null),
        title: Text(ok ? s.evCheckedIn : s.evCheckIn),
        content: Text(text),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.close),
          ),
        ],
      ),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(s.evCheckIn)),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(KSpace.l),
                child: Text('${s.cameraError.fill([error.errorCode.name])}',
                    textAlign: TextAlign.center),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(KSpace.l),
              child: Text(
                s.evScanHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The phone-camera fallback: the QR opens this page. It redeems the token
/// and shows the outcome.
class CheckinPage extends StatefulWidget {
  final String eventId;
  final String? token;

  const CheckinPage({super.key, required this.eventId, this.token});

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  bool _loading = true;
  String? _message;
  bool _ok = false;

  /// The form the organiser asked for after check-in, if any.
  FormDoc? _form;

  @override
  void initState() {
    super.initState();
    _redeem();
  }

  /// When the organiser chose a form for this check-in, this is the moment it
  /// is offered — once, on the success screen, not as another button on the
  /// page.
  Future<void> _loadFormOffer() async {
    final form = await loadCheckinOffer(widget.eventId);
    if (mounted && form != null) setState(() => _form = form);
  }

  Future<void> _redeem() async {
    final s = context.l10nRead;
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _message = s.evCheckinInvalid;
      });
      return;
    }
    try {
      final res = await Supabase.instance.client
          .rpc('checkin_with_token', params: {'p_token': token});
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = res == 'already' ? s.evAlreadyIn : s.evCheckedIn;
        _loading = false;
      });
      await _loadFormOffer();
    } catch (e) {
      if (!mounted) return;
      final code = parseModError(e)?.code;
      setState(() {
        _loading = false;
        _message = switch (code) {
          'checkin_expired' => s.evCheckinExpired,
          'checkin_invalid' => s.evCheckinInvalid,
          'checkin_verify' => s.evCheckinVerify,
          'checkin_login_required' => s.guestPromptTitle,
          _ => s.somethingWentWrong,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.evCheckIn)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(KSpace.l),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_ok ? AppIcons.success : AppIcons.warning,
                        size: 56,
                        color: _ok ? theme.colorScheme.primary : null),
                    const SizedBox(height: KSpace.m),
                    Text(_message ?? '',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: KSpace.l),
                    if (_form != null) ...[
                      CheckinFormOffer(form: _form!),
                      const SizedBox(height: KSpace.s),
                      TextButton(
                        onPressed: () => context.go('/event/${widget.eventId}'),
                        child: Text(s.viewEvent),
                      ),
                    ] else
                      FilledButton(
                        onPressed: () => context.go('/event/${widget.eventId}'),
                        child: Text(s.viewEvent),
                      ),
                    if (!_ok) ...[
                      const SizedBox(height: KSpace.s),
                      TextButton(
                        onPressed: () async {
                          await StudentVerificationService.isEnabled();
                          if (mounted) _redeem();
                        },
                        child: Text(s.tryAgain),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// The form to offer someone who just checked in to [eventId], or null.
///
/// Asks `event_checkin_form` (any form the organiser picked). Without that
/// migration, falls back to the old rule: the event's own open form, when its
/// after-check-in flag is on. Never throws: the check-in already stands.
Future<FormDoc?> loadCheckinOffer(String eventId) async {
  try {
    String? id;
    var fromChoice = true;
    try {
      id = await CheckinFormService.instance.offered(eventId);
    } on CheckinFormUnsupported {
      fromChoice = false;
      id = await FormService.instance.openFormId(eventId);
    }
    if (id == null) return null;
    final view = await FormService.instance.load(id);
    if (!fromChoice && !view.doc.afterCheckin) return null;
    if (!view.canAnswer || view.answered) return null;
    return view.doc;
  } catch (e) {
    // No forms migration, or a network hiccup: the check-in still stands.
    debugPrint('No check-in form offer: $e');
    return null;
  }
}

/// "Answer the form" on the success screen, linking to [form]'s own answer
/// page (`/f/:id` for a standalone form, the event's form page otherwise).
class CheckinFormOffer extends StatelessWidget {
  final FormDoc form;
  const CheckinFormOffer({super.key, required this.form});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (form.title.trim().isNotEmpty) ...[
          Text(
            form.title,
            key: const ValueKey('offer-title'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: KSpace.s),
        ],
        FilledButton.icon(
          key: const ValueKey('offer-answer'),
          onPressed: () => context.go(form.answerPath),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(AppIcons.list, size: 18),
          label: Text(form.isKi ? s.formAnswerKiNow : s.afAnswerNow),
        ),
      ],
    );
  }
}
