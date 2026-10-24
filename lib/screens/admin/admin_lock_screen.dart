import 'package:flutter/material.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';

/// PIN gate shown inside the admin route before the console opens.
class AdminLockScreen extends StatefulWidget {
  final Future<bool> Function(String pin) unlock;
  final VoidCallback onUnlocked;

  const AdminLockScreen({super.key, required this.unlock, required this.onUnlocked});

  @override
  State<AdminLockScreen> createState() => _AdminLockScreenState();
}

class _AdminLockScreenState extends State<AdminLockScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    if (pin.isEmpty || _busy) return;
    final m = context.l10nRead.mod;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.unlock(pin);
      if (!mounted) return;
      if (ok) {
        _pin.clear();
        widget.onUnlocked();
      } else {
        setState(() => _error = m.wrongPin);
      }
    } catch (e) {
      if (mounted) setState(() => _error = modErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KSpace.l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(ModIcons.lock, size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: KSpace.m),
                Text(m.adminLocked,
                    textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                const SizedBox(height: KSpace.xs),
                Text(m.adminLockedBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: KSpace.l),
                TextField(
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: m.adminPin,
                    prefixIcon: const Icon(AppIcons.lock),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: KSpace.m),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(m.unlock),
                ),
                const SizedBox(height: KSpace.s),
                Text(m.idleLockNote,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
