import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/form_strings.dart';
import '../../language_cubit.dart';
import '../../services/my_forms_service.dart';
import '../../services/share_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../utils/adaptive.dart';
import '../../utils/app_nav.dart';
import '../../utils/feedback.dart';
import '../../utils/form_rules.dart';
import '../../utils/responsive.dart';

/// "My forms" (`/forms`): every standalone form the user made, and those of
/// the clubs they are an officer of. New forms start here; each row opens the
/// editor and carries the link to paste or attach elsewhere.
class MyFormsScreen extends StatefulWidget {
  const MyFormsScreen({super.key});

  @override
  State<MyFormsScreen> createState() => _MyFormsScreenState();
}

class _MyFormsScreenState extends State<MyFormsScreen> {
  List<MyForm>? _forms;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final forms = await MyFormsService.instance.myForms();
      if (mounted) setState(() => _forms = forms);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _fail(Object e, VoidCallback retry) => showErrorWithRetry(context, e,
      onRetry: retry, message: context.l10nRead.formServerError(formErrorCode(e)));

  /// New forms start in the template gallery, which opens the editor in its
  /// place; coming back here reloads the list.
  Future<void> _create() async {
    await context.push('/forms/new');
    if (mounted) _load();
  }

  Future<void> _copyLink(MyForm f) async {
    await Clipboard.setData(ClipboardData(text: '$kAppBaseUrl${f.path}'));
    if (mounted) _toast(context.l10nRead.formsLinkCopied);
  }

  Future<void> _close(MyForm f) async {
    final s = context.l10nRead;
    final ok = await _confirm(s.formsCloseTitle, s.formsCloseBody, s.formsClose);
    if (!ok) return;
    try {
      await MyFormsService.instance.close(f.id);
      _load();
    } catch (e) {
      if (mounted) _fail(e, () => _close(f));
    }
  }

  Future<void> _delete(MyForm f) async {
    final s = context.l10nRead;
    final ok = await _confirm(s.formsDeleteTitle, s.formsDeleteBody(f.responses), s.formsDelete,
        destructive: true);
    if (!ok) return;
    try {
      await MyFormsService.instance.delete(f.id);
      if (!mounted) return;
      _toast(s.formsDeleted);
      _load();
    } catch (e) {
      if (mounted) _fail(e, () => _delete(f));
    }
  }

  Future<bool> _confirm(String title, String body, String action, {bool destructive = false}) async {
    final s = context.l10nRead;
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error, foregroundColor: scheme.onError)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final forms = _forms;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: Responsive.detailMaxWidth,
        leading: const AppBackButton(),
        title: Text(s.formsMine),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: KSpace.s),
            child: TextButton.icon(
              onPressed: _create,
              icon: const Icon(AppIcons.create, size: 18),
              label: Text(s.formsNew),
            ),
          ),
        ],
      ),
      body: _error != null
          ? _Message(
              icon: AppIcons.error,
              title: s.somethingWentWrong,
              action: TextButton(onPressed: _load, child: Text(s.retry)),
            )
          : forms == null
              ? const Center(child: CircularProgressIndicator())
              : forms.isEmpty
                  ? _Message(
                      icon: AppIcons.list,
                      title: s.formsEmpty,
                      body: s.formsEmptySub,
                      action: FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(AppIcons.create, size: 18),
                        label: Text(s.formsNew),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: Responsive.detailMaxWidth),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(KSpace.l),
                            itemCount: forms.length,
                            separatorBuilder: (_, __) => const SizedBox(height: KSpace.s),
                            itemBuilder: (context, i) => _FormTile(
                              form: forms[i],
                              onOpen: () async {
                                await context.push('/f/${forms[i].id}/edit');
                                if (mounted) _load();
                              },
                              onAction: (a) => switch (a) {
                                _Action.answer => context.push(forms[i].path),
                                _Action.responses => context.push('${forms[i].path}/responses'),
                                _Action.copy => _copyLink(forms[i]),
                                _Action.close => _close(forms[i]),
                                _Action.delete => _delete(forms[i]),
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
    );
  }
}

enum _Action { answer, responses, copy, close, delete }

class _FormTile extends StatelessWidget {
  final MyForm form;
  final VoidCallback onOpen;
  final void Function(_Action) onAction;

  const _FormTile({required this.form, required this.onOpen, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (status, color) = form.isHidden
        ? (s.formsRemoved, scheme.error)
        : switch (form.status) {
            'open' => (s.formOpen, scheme.primary),
            'closed' => (s.formClosed, scheme.onSurfaceVariant),
            _ => (s.formDraft, scheme.tertiary),
          };
    final meta = [
      if (form.clubName != null) form.clubName!,
      s.formsResponses(form.responses),
    ].join(' · ');

    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.card,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('form-${form.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.xs, KSpace.m),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: KSpace.xs),
                    Wrap(
                      spacing: KSpace.s,
                      runSpacing: KSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: KRadius.pill,
                            border: Border.all(color: color),
                          ),
                          child: Text(status,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                        ),
                        Text(meta,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                tooltip: s.more,
                icon: Icon(AppIcons.more, color: scheme.onSurfaceVariant),
                onSelected: onAction,
                itemBuilder: (_) => [
                  if (!form.isHidden)
                    PopupMenuItem(value: _Action.answer, child: Text(s.formAnswerTitle)),
                  if (!form.isHidden)
                    PopupMenuItem(value: _Action.responses, child: Text(s.formOpenAnswers)),
                  if (!form.isHidden)
                    PopupMenuItem(value: _Action.copy, child: Text(s.formsCopyLink)),
                  if (form.isOpen)
                    PopupMenuItem(value: _Action.close, child: Text(s.formsClose)),
                  PopupMenuItem(
                    value: _Action.delete,
                    child: Text(s.formsDelete, style: TextStyle(color: scheme.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  const _Message({required this.icon, required this.title, this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: scheme.onSurfaceVariant),
              const SizedBox(height: KSpace.m),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              if (body != null) ...[
                const SizedBox(height: KSpace.xs),
                Text(body!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
              if (action != null) ...[
                const SizedBox(height: KSpace.l),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
