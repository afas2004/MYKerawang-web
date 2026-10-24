import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/student_verification.dart';
import '../../theme/app_icons.dart';
import '../../utils/formatters.dart';
import '../../utils/moderation_logic.dart';
import '../login_cubit.dart';

/// "Verify your student status" — one sheet, four states: no record,
/// waiting, verified, or refused. Submitting asks an admin to check the
/// UiTM address by hand (there is no code-by-email yet).
///
/// Returns true when the account's state changed, so the caller can
/// refresh whatever it was showing.
Future<bool?> showVerifySheet(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const VerifySheet(),
    );

class VerifySheet extends StatefulWidget {
  const VerifySheet({super.key});

  @override
  State<VerifySheet> createState() => _VerifySheetState();
}

class _VerifySheetState extends State<VerifySheet> {
  final _email = TextEditingController();
  StudentVerification? _current;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final v = await StudentVerificationService.mine();
    if (!mounted) return;
    final login = Supabase.instance.client.auth.currentUser?.email ?? '';
    setState(() {
      _current = v;
      _loading = false;
      if (_email.text.isEmpty) {
        _email.text = v?.email.isNotEmpty == true
            ? v!.email
            : (isStudentEmail(login) ? login : '');
      }
    });
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await StudentVerificationService.request(email);
      final v = await StudentVerificationService.mine();
      if (!mounted) return;
      setState(() {
        _current = v;
        _sending = false;
        _changed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _errorText(e);
      });
    }
  }

  /// Refusals from request_student_verification, in plain words.
  String _errorText(Object e) {
    final s = context.l10n;
    return switch (parseModError(e)?.code) {
      'verify_closed' => s.verifyClosed,
      'verify_domain' => s.verifyDomainError,
      'verify_email_taken' => s.verifyTakenError,
      'verify_wait' => s.verifyWaitError,
      'verify_already_verified' => s.verifyAlreadyError,
      'verify_email_invalid' => s.emailInvalid,
      _ => s.somethingWentWrong,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(s.verifySheetTitle, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (_current?.isVerified == true)
                        _verified(s, theme, scheme)
                      else if (_current?.isPending == true)
                        _pending(s, theme, scheme)
                      else
                        _form(s, theme, scheme),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _verified(AppStrings s, ThemeData theme, ColorScheme scheme) {
    final at = _current?.verifiedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(AppIcons.verified, color: scheme.primary),
            const SizedBox(width: 8),
            Text(s.verifyStatusVerified,
                style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          at == null ? _current?.email ?? '' : s.verifyVerifiedBody.fill([formatDate(at)]),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: Text(s.closeGallery),
        ),
      ],
    );
  }

  Widget _pending(AppStrings s, ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(AppIcons.verified, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(s.verifyStatusPending, style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 10),
        Text(_current?.email ?? '', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Text(s.verifyPendingBody,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: Text(s.closeGallery),
        ),
      ],
    );
  }

  Widget _form(AppStrings s, ThemeData theme, ColorScheme scheme) {
    final refused = _current == null
        ? null
        : _current!.status == 'rejected'
            ? s.verifyRejectedBody
            : _current!.status == 'revoked'
                ? s.verifyRevokedBody
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.verifySheetIntro, style: theme.textTheme.bodyMedium),
        if (refused != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(refused,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onErrorContainer)),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: s.verifyEmailLabel,
            hintText: s.verifyEmailHint,
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _sending ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _sending
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(s.verifySubmit),
        ),
      ],
    );
  }
}
