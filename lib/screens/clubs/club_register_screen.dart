import 'package:flutter/material.dart';
import '../../utils/app_nav.dart';

import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../widgets/brand/brand.dart';
import 'club_strings.dart';
import 'club_widgets.dart';

typedef RegisterClub = Future<String> Function({
  required String name,
  required String handle,
  String? description,
  String? category,
  required String proofNote,
});

/// /clubs/register — request a club page. The caller becomes president
/// of a PENDING club; an admin approves it. Replaces the old onboarding
/// toggle that stored proof in the bio.
class ClubRegisterScreen extends StatefulWidget {
  final RegisterClub register;
  const ClubRegisterScreen({super.key, this.register = ClubService.register});

  @override
  State<ClubRegisterScreen> createState() => _ClubRegisterScreenState();
}

class _ClubRegisterScreenState extends State<ClubRegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _description = TextEditingController();
  final _proof = TextEditingController();
  String? _category;
  bool _handleEdited = false;
  bool _sending = false;
  String? _serverHandleError;
  String? _done; // handle once sent

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _description.dispose();
    _proof.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverHandleError = null);
    if (!_form.currentState!.validate()) return;
    final c = context.l10nRead.club;
    setState(() => _sending = true);
    try {
      await widget.register(
        name: _name.text.trim(),
        handle: _handle.text.trim(),
        description: _description.text.trim(),
        category: _category,
        proofNote: _proof.text.trim(),
      );
      if (mounted) setState(() => _done = _handle.text.trim());
    } catch (e) {
      if (!mounted) return;
      if (clubErrorCode(e) == 'handle_taken') {
        setState(() => _serverHandleError = c.handleTaken);
        _form.currentState!.validate();
      } else {
        showClubSnack(context, clubErrorText(c, e), error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return Scaffold(
      appBar: AppBar(title: Text(c.registerClub)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: AnimatedSwitcher(
            duration: KMotion.of(context).medium,
            child: _done != null ? _sent(context, _done!) : _formView(context),
          ),
        ),
      ),
    );
  }

  Widget _sent(BuildContext context, String handle) {
    final c = context.l10n.club;
    return BrandEmptyState(
      key: const ValueKey('sent'),
      illo: AppIllo.welcome,
      title: c.requestSent,
      message: c.requestSentBody.fill([_name.text.trim()]),
      actionLabel: c.viewPage,
      // The finished form is replaced by the club page, so back doesn't
      // return to it.
      onAction: () => completePublish(context, '/c/$handle'),
    );
  }

  Widget _formView(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final handle = _handle.text.trim();
    return Form(
      key: _form,
      child: ListView(
        key: const ValueKey('form'),
        padding: const EdgeInsets.all(KSpace.l),
        children: [
          Text(c.registerIntro,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: KSpace.xl),
          TextFormField(
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(labelText: c.clubName),
            onChanged: (v) {
              if (!_handleEdited) setState(() => _handle.text = suggestHandle(v));
            },
            validator: (v) => (v ?? '').trim().length < 2 ? c.nameInvalid : null,
          ),
          const SizedBox(height: KSpace.m),
          TextFormField(
            controller: _handle,
            maxLength: 30,
            decoration: InputDecoration(
              labelText: c.handle,
              prefixText: '@',
              helperText: c.handleHelp.fill([handle.isEmpty ? '…' : handle]),
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {
              _handleEdited = true;
              _serverHandleError = null;
            }),
            validator: (v) => _serverHandleError ?? handleIssueText(c, validateHandle(v ?? '')),
          ),
          const SizedBox(height: KSpace.m),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: InputDecoration(labelText: c.category),
            items: [
              for (final k in ClubStrings.categories)
                DropdownMenuItem(value: k, child: Text(c.categoryLabel(k))),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: KSpace.m),
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: InputDecoration(labelText: c.description),
          ),
          const SizedBox(height: KSpace.m),
          TextFormField(
            controller: _proof,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: c.proof,
              helperText: c.proofHelp,
              helperMaxLines: 3,
              prefixIcon: const Icon(AppIcons.lock),
            ),
            validator: (v) => (v ?? '').trim().length < 10 ? c.proofTooShort : null,
          ),
          const SizedBox(height: KSpace.xl),
          FilledButton(
            onPressed: _sending ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(c.submitRequest),
          ),
        ],
      ),
    );
  }
}
