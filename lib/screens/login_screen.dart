import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../widgets/app_logo.dart';
import '../widgets/brand/brand.dart';
import '../widgets/kerawang_motif.dart';
import '../utils/guest_access.dart';
import 'login_cubit.dart'; // This looks in the SAME folder

class LoginScreen extends StatefulWidget {
  /// Path to return to after signing in (`/login?from=…`), e.g. the
  /// shared event a visitor opened before being asked to log in.
  final String? from;

  /// `error_description` an OAuth provider sent back in the URL, e.g.
  /// when the server refused to create a non-student account.
  final String? oauthError;

  const LoginScreen({super.key, this.from, this.oauthError});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    pendingLoginError.addListener(_showPendingError);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final oauthError = widget.oauthError;
      if (oauthError != null && oauthError.isNotEmpty) {
        _showError(oauthError);
      }
      _showPendingError();
    });
  }

  void _showPendingError() {
    final code = pendingLoginError.value;
    if (code == null || !mounted) return;
    pendingLoginError.value = null;
    _showError(code);
  }

  void _showError(String code) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_errorText(context.l10nRead, code),
            style: TextStyle(color: scheme.onError)),
        backgroundColor: scheme.error,
      ),
    );
  }

  @override
  void dispose() {
    pendingLoginError.removeListener(_showPendingError);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final s = context.l10n;

    if (email.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.enterEmailFirst)));
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      messenger.showSnackBar(SnackBar(content: Text(s.resetLinkSent)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  final _formKey = GlobalKey<FormState>();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _submit(BuildContext context, LoginState state) {
    if (state.isLoading) return;
    if (!(_formKey.currentState?.validate() ?? true)) return;
    context.read<LoginCubit>().submit(_emailCtrl.text, _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginCubit(),
      child: Scaffold(
        body: BlocConsumer<LoginCubit, LoginState>(
          // Errors render inline in the form (see _errorBanner); success
          // goes back to where the visitor came from, and the router's
          // redirect takes over from there.
          listenWhen: (prev, next) => next.isSuccess && !prev.isSuccess,
          listener: (context, state) => context.go(safeReturnPath(widget.from) ?? '/home'),
          builder: (context, state) => LayoutBuilder(builder: (context, constraints) {
            final split = constraints.maxWidth >= 900;
            if (split) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(flex: 5, child: _BrandPanel()),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _form(context, state, showLogo: false),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: [
                        _form(context, state, showLogo: true),
                        const SizedBox(height: 32),
                        // First-time visitors: what this is, after the form.
                        const _ValuePoints(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, LoginState state, {required bool showLogo}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final signUp = !state.isLoginMode;

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLogo) ...[
              const _LatticeBand(child: Center(child: AppLogo(size: 88))),
              const SizedBox(height: 16),
            ],
            Text(
              signUp ? s.joinApp : s.welcomeBack,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              signUp ? s.registerToStart : s.loginToContinue,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            if (state.errorMessage != null) ...[
              _errorBanner(context, state.errorMessage!),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _emailCtrl,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: s.email,
                prefixIcon: const Icon(Icons.email_outlined),
                // New accounts need a student address; say so up front.
                helperText: signUp ? s.studentEmailHint : null,
                helperMaxLines: 2,
              ),
              validator: (v) {
                final email = (v ?? '').trim();
                if (email.isEmpty) return s.fillAllFields;
                if (!_emailPattern.hasMatch(email)) return s.emailInvalid;
                if (signUp && !isStudentEmail(email)) return s.studentEmailOnly;
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
              // Enter submits (desktop/web expectation)
              onFieldSubmitted: (_) => _submit(context, state),
              decoration: InputDecoration(
                labelText: s.password,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? s.showPassword : s.hidePassword,
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                final p = v ?? '';
                if (p.isEmpty) return s.fillAllFields;
                if (signUp && p.length < 6) return s.passwordTooShort;
                return null;
              },
            ),

            if (!signUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _sendPasswordReset,
                  child: Text(s.forgotPassword),
                ),
              )
            else
              const SizedBox(height: 16),

            const SizedBox(height: 8),
            // Shape comes from the theme (pill on Kampus Bold, kerawang cut
            // on Istana/Noir) — DESIGN_SPEC §2.
            FilledButton(
              onPressed: state.isLoading ? null : () => _submit(context, state),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: state.isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onPrimary))
                  : Text(signUp ? s.signUp : s.login,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: KerawangDivider(size: 6, color: scheme.outline),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () => context.read<LoginCubit>().signInWithGoogle(from: widget.from),
              icon: const _GoogleMark(),
              label: Text(s.continueWithGoogle),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _formKey.currentState?.reset();
                context.read<LoginCubit>().toggleLoginMode();
              },
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text.rich(
                TextSpan(
                  text: signUp ? s.haveAccountPrefix : s.newUserPrefix,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: signUp ? s.loginLink : s.createAccount,
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (!signUp)
              Text(
                s.studentEmailHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String code) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_errorText(context.l10n, code),
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Left half of the split login: lattice field on the brand colour, the
/// logo, the name and what MYKerawang is for.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      color: scheme.primary,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Lattice field in the on-brand colour (never hardcoded white:
          // Songket Noir's onPrimary is dark).
          KerawangLattice(tileSize: 28, color: scheme.onPrimary, opacity: 0.10),
          Positioned(
            right: 0,
            bottom: 0,
            child: KerawangLattice.corner(
                corner: Alignment.bottomRight, extent: 160, tileSize: 16, color: KTokens.of(context).gold),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 96),
                    const SizedBox(height: 24),
                    Text(AppStrings.appName,
                        style: theme.textTheme.displaySmall?.copyWith(color: scheme.onPrimary)),
                    const SizedBox(height: 8),
                    KerawangDivider(size: 9, color: KTokens.of(context).gold),
                    const SizedBox(height: 24),
                    _ValuePoints(onBrand: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your college, in one place" + three short points.
class _ValuePoints extends StatelessWidget {
  final bool onBrand;
  const _ValuePoints({this.onBrand = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final fg = onBrand ? scheme.onPrimary : scheme.onSurface;
    final accent = onBrand ? scheme.onPrimary : scheme.primary;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: KSpace.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: accent),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge?.copyWith(color: fg))),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.loginValueTitle, style: theme.textTheme.titleLarge?.copyWith(color: fg)),
        point(Icons.event_outlined, s.loginValueEvents),
        point(Icons.storefront_outlined, s.loginValueMarket),
        point(Icons.forum_outlined, s.loginValueCommunity),
      ],
    );
  }
}

/// Lattice panel behind the logo on compact layouts.
class _LatticeBand extends StatelessWidget {
  final Widget child;
  const _LatticeBand({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: KRadius.cut,
              child: const KerawangLattice(tileSize: 22),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Google's four-colour "G", drawn simply so we don't ship the stock
/// Material glyph (which reads as off-brand).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final stroke = size.width * 0.22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final arc = rect.deflate(stroke / 2);

    // Four brand-coloured quadrants of the ring
    paint.color = const Color(0xFF4285F4); // blue
    canvas.drawArc(arc, -0.55, 1.15, false, paint);
    paint.color = const Color(0xFF34A853); // green
    canvas.drawArc(arc, 0.75, 1.4, false, paint);
    paint.color = const Color(0xFFFBBC05); // yellow
    canvas.drawArc(arc, 2.2, 1.35, false, paint);
    paint.color = const Color(0xFFEA4335); // red
    canvas.drawArc(arc, 3.6, 1.6, false, paint);

    // The G's crossbar
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.5, size.height * 0.4, size.width * 0.5,
          size.height * 0.2),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Localizes a [LoginError] code; server messages pass through.
String _errorText(AppStrings s, String error) {
  if (error == LoginError.fillFields) return s.fillAllFields;
  if (error == LoginError.checkEmail) return s.checkEmailConfirm;
  if (error == LoginError.generic) return s.genericAuthError;
  if (error == LoginError.studentEmailOnly) return s.studentEmailOnly;
  // The auth.users trigger rejecting a sign-up surfaces as this.
  if (error.contains('student.uitm.edu.my') ||
      error.toLowerCase().contains('database error saving new user')) {
    return s.studentEmailOnly;
  }
  if (error.startsWith(LoginError.googleFailed)) {
    return s.googleSignInFailed.fill([error.substring(LoginError.googleFailed.length)]);
  }
  return error;
}
