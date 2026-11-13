import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/access_strings.dart';
import '../l10n/form_strings.dart';
import '../l10n/gform_import_strings.dart';
import '../language_cubit.dart';
import '../services/my_forms_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../utils/adaptive.dart';
import 'app_toast.dart';
import 'google_form_import.dart';

/// Lets a composer (post, event, announcement) link one of the user's forms.
/// The result is an ordinary action link — `{label: "Fill in form",
/// url: "/f/:id"}` — so nothing downstream needs to know about forms.
///
/// [openOnly] hides drafts too: for a form people must be able to answer now
/// (the one asked after check-in). It also hides "Import from Google Form",
/// whose result is a draft.
Future<MyForm?> showFormPicker(BuildContext context, {bool openOnly = false}) {
  Widget body(BuildContext ctx) => _FormPickerBody(openOnly: openOnly);
  if (isWide(context)) {
    return showAdaptiveSheet<MyForm>(context: context, builder: body);
  }
  return showModalBottomSheet<MyForm>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: body,
  );
}

/// "Attach a form", for a composer's link section.
class AttachFormButton extends StatelessWidget {
  final void Function(MyForm form) onPicked;
  const AttachFormButton({super.key, required this.onPicked});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        key: const ValueKey('attach-form'),
        onPressed: () async {
          final f = await showFormPicker(context);
          if (f != null) onPicked(f);
        },
        icon: const Icon(AppIcons.list, size: 18),
        label: Text(context.l10n.formAttach),
      );
}

class _FormPickerBody extends StatefulWidget {
  final bool openOnly;
  const _FormPickerBody({this.openOnly = false});

  @override
  State<_FormPickerBody> createState() => _FormPickerBodyState();
}

class _FormPickerBodyState extends State<_FormPickerBody> {
  late final Future<List<MyForm>> _forms = MyFormsService.instance
      .myForms()
      .then((all) => [
            for (final f in all)
              if (widget.openOnly ? f.isOpen : (!f.isHidden && f.status != 'closed')) f
          ]);

  Future<void> _importGoogle() async {
    final form = await importGoogleFormAsStandalone(context);
    if (form == null || !mounted) return;
    showToast(context.l10nRead.gfCreatedDraft);
    Navigator.pop(context, form);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, KSpace.s),
              child: Text(s.formAttachTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: FutureBuilder<List<MyForm>>(
                future: _forms,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(KSpace.l),
                      child: Text(s.somethingWentWrong),
                    );
                  }
                  final forms = snap.data;
                  if (forms == null) {
                    return const Padding(
                      padding: EdgeInsets.all(KSpace.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (forms.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
                      child: Text(s.formAttachEmpty,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in forms)
                        ListTile(
                          key: ValueKey('pick-${f.id}'),
                          leading: const Icon(AppIcons.list),
                          title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            f.isDraft
                                ? s.formAttachDraft
                                : [if (f.clubName != null) f.clubName!, s.formsResponses(f.responses)]
                                    .join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, f),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.s, KSpace.s, KSpace.s, KSpace.s),
              child: Wrap(
                spacing: KSpace.s,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.push('/forms');
                    },
                    icon: const Icon(AppIcons.create, size: 18),
                    label: Text(s.formAttachManage),
                  ),
                  // Makes a draft from a Google Form and attaches it at once.
                  if (!widget.openOnly)
                    TextButton.icon(
                      key: const ValueKey('picker-gform'),
                      onPressed: _importGoogle,
                      icon: const Icon(AppIcons.link, size: 18),
                      label: Text(s.gfImport),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
