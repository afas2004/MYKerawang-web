import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../widgets/app_logo.dart';
import '../widgets/kerawang_motif.dart';
import '../utils/guest_access.dart';
import 'login_cubit.dart'; // This looks in the SAME folder

class LoginScreen extends StatefulWidget {
  /// Path to return to after signing in (`/login?from=…`), e.g. the
  /// shared event a visitor opened before being asked to log in.
  final String? from;

  const LoginScreen({super.key, this.from});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    // 1. Inject the Cubit
    return BlocProvider(
      create: (context) => LoginCubit(),
      child: Scaffold(
        // 2. Listen to State Changes (Logic)
        body: BlocConsumer<LoginCubit, LoginState>(
          listener: (context, state) {
            // Handle Errors
            if (state.errorMessage != null) {
              final scheme = Theme.of(context).colorScheme;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_errorText(context.l10nRead, state.errorMessage!),
                      style: TextStyle(color: scheme.onError)),
                  backgroundColor: scheme.error,
                ),
              );
            }

            // Handle Navigation on Success — back to where the visitor
            // came from; the router's redirect takes over from there.
            if (state.isSuccess) {
              context.go(safeReturnPath(widget.from) ?? '/home');
            }
          },
          builder: (context, state) {
            final scheme = Theme.of(context).colorScheme;
            final s = context.l10n;
            // 3. Build UI based on State
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- ORIGINAL UI ELEMENTS START ---
                    const AppLogo(size: 104),
                    const SizedBox(height: 16),
                    const KerawangDivider(size: 11),
                    const SizedBox(height: 16),
                    Text(
                      state.isLoginMode ? s.welcomeBack : s.joinApp,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.isLoginMode ? s.loginToContinue : s.registerToStart,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),

                    TextField(
                      controller: _emailCtrl,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: s.email,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      // Enter key submits (desktop/web expectation)
                      onSubmitted: (_) => context
                          .read<LoginCubit>()
                          .submit(_emailCtrl.text, _passCtrl.text),
                      decoration: InputDecoration(
                        labelText: s.password,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? s.showPassword : s.hidePassword,
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),

                    // Forgot password
                    if (state.isLoginMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _sendPasswordReset,
                          child: Text(s.forgotPassword),
                        ),
                      ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        // Call Cubit Function instead of local _submit
                        onPressed: state.isLoading
                            ? null
                            : () {
                                context.read<LoginCubit>().submit(
                                      _emailCtrl.text,
                                      _passCtrl.text,
                                    );
                              },
                        // Shape comes from the theme (pill on Kampus Bold,
                        // kerawang cut on Istana/Noir) — DESIGN_SPEC §2.
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                        ),
                        child: state.isLoading
                            ? CircularProgressIndicator(color: scheme.onPrimary)
                            : Text(
                                state.isLoginMode ? s.login : s.signUp,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // GOOGLE BUTTON
                    OutlinedButton.icon(
                      onPressed: state.isLoading 
                          ? null 
                          : () => context.read<LoginCubit>().signInWithGoogle(from: widget.from),
                      icon: const _GoogleMark(),
                      label: Text(s.continueWithGoogle),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    TextButton(
                      // Call Cubit to toggle mode
                      onPressed: () => context.read<LoginCubit>().toggleLoginMode(),
                      child: RichText(
                        text: TextSpan(
                          text: state.isLoginMode
                              ? s.newUserPrefix
                              : s.haveAccountPrefix,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          children: [
                            TextSpan(
                              text: state.isLoginMode ? s.createAccount : s.loginLink,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          ],
                        ),
                      ),
                    )
                    // --- ORIGINAL UI ELEMENTS END ---
                  ],
                  ),
                ),
              ),
            );
          },
        ),
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
  if (error.startsWith(LoginError.googleFailed)) {
    return s.googleSignInFailed.fill([error.substring(LoginError.googleFailed.length)]);
  }
  return error;
}
