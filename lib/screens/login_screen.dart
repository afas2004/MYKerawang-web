import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../main.dart'; // This goes up one level to find main.dart
import '../widgets/kerawang_motif.dart';
import 'login_cubit.dart'; // This looks in the SAME folder

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: Colors.red,
                ),
              );
            }

            // Handle Navigation on Success
            if (state.isSuccess) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()), // <--- Point to AuthGate
                (route) => false,
              );
            }
          },
          builder: (context, state) {
            final scheme = Theme.of(context).colorScheme;
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
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.school, size: 60, color: scheme.primary),
                    ),
                    const SizedBox(height: 16),
                    const KerawangDivider(),
                    const SizedBox(height: 16),
                    Text(
                      state.isLoginMode ? "Selamat kembali" : "Jom sertai MYKerawang",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.isLoginMode
                          ? "Log masuk untuk teruskan"
                          : "Daftar akaun untuk mula",
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 40),

                    TextField(
                      controller: _emailCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      // Enter key submits (desktop/web expectation)
                      onSubmitted: (_) => context
                          .read<LoginCubit>()
                          .submit(_emailCtrl.text, _passCtrl.text),
                      decoration: InputDecoration(
                        labelText: "Kata laluan",
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? "Tunjuk" : "Sembunyi",
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: state.isLoading
                            ? CircularProgressIndicator(color: scheme.onPrimary)
                            : Text(
                                state.isLoginMode ? "Log masuk" : "Daftar",
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
                          : () => context.read<LoginCubit>().signInWithGoogle(),
                      icon: const Icon(Icons.g_mobiledata, size: 28), // Or use a Google Logo asset
                      label: const Text("Teruskan dengan Google"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    TextButton(
                      // Call Cubit to toggle mode
                      onPressed: () => context.read<LoginCubit>().toggleLoginMode(),
                      child: RichText(
                        text: TextSpan(
                          text: state.isLoginMode
                              ? "Pengguna baru? "
                              : "Dah ada akaun? ",
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          children: [
                            TextSpan(
                              text: state.isLoginMode ? "Daftar sini" : "Log masuk",
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