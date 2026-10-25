import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/guest_access.dart';
import '../services/registration_policy.dart';
import '../utils/browser_history_stub.dart'
    if (dart.library.js_interop) '../utils/browser_history_web.dart';

/// Error codes put in [LoginState.errorMessage]. The cubit has no
/// BuildContext, so the screen turns these into localized text
/// (see `login_screen.dart`). Anything else is a server message shown as-is.
abstract final class LoginError {
  static const fillFields = 'login.fill_fields';
  static const checkEmail = 'login.check_email';
  static const generic = 'login.generic';
  static const studentEmailOnly = 'login.student_email_only';

  /// Prefix; the underlying error follows it.
  static const googleFailed = 'login.google:';
}

/// New accounts must use a UiTM student address. Existing accounts with
/// other addresses (e.g. the owner's) keep working — only sign-ups are
/// checked, here and by the auth.users trigger in
/// 20261019002400_student_email_signup.sql.
const kStudentEmailDomain = '@student.uitm.edu.my';

bool isStudentEmail(String? email) =>
    (email ?? '').trim().toLowerCase().endsWith(kStudentEmailDomain);

/// A [LoginError] code raised outside the login screen (after an OAuth
/// redirect); the login screen shows it and clears it.
final ValueNotifier<String?> pendingLoginError = ValueNotifier(null);

/// Address to pre-fill on the login screen, set when the app sends someone
/// here on purpose (e.g. "use the account this device already knows").
/// The login screen consumes and clears it.
final ValueNotifier<String?> pendingLoginEmail = ValueNotifier(null);

/// Google sign-in can create an account without the student check the
/// email form does. Call on every signedIn event: an account created by
/// this sign-in whose address isn't a student one is signed out again.
/// The server trigger normally rejects it first; this covers projects
/// where that migration isn't applied yet.
Future<void> enforceStudentEmailForNewAccount(User user) async {
  if (isStudentEmail(user.email)) return;
  final created = DateTime.tryParse(user.createdAt);
  final lastSignIn = DateTime.tryParse(user.lastSignInAt ?? '');
  // Brand-new account: first sign-in happens at creation time.
  final isNew = created != null &&
      (lastSignIn == null || lastSignIn.difference(created).inSeconds.abs() < 60);
  if (!isNew) return; // grandfathered
  // The owner may have opened signup to any address.
  if (await RegistrationPolicy.ensureLoaded()) return;
  debugPrint('Non-student sign-up rejected: ${user.email}');
  pendingLoginError.value = LoginError.studentEmailOnly;
  await Supabase.instance.client.auth.signOut();
}

// 1. Define the detailed States for your screen
class LoginState {
  final bool isLoginMode;      // Replaces _isLogin
  final bool isLoading;        // Replaces _isLoading
  final String? errorMessage;  // For Snackbars
  final bool isSuccess;        // To trigger Navigation

  LoginState({
    this.isLoginMode = true,
    this.isLoading = false,
    this.errorMessage,
    this.isSuccess = false,
  });

  // Helper to create a new state based on the old one
  LoginState copyWith({
    bool? isLoginMode,
    bool? isLoading,
    String? errorMessage,
    bool? isSuccess,
  }) {
    return LoginState(
      isLoginMode: isLoginMode ?? this.isLoginMode,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage, // If passed as null, it clears the error
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

// 2. The Logic Controller (Cubit)
class LoginCubit extends Cubit<LoginState> {
  LoginCubit() : super(LoginState());

  // Looked up on use, not at construction, so the screen can be built
  // in widget tests without a Supabase client.
  SupabaseClient get supabase => Supabase.instance.client;

  // Replaces: setState(() => _isLogin = !_isLogin)
  void toggleLoginMode() {
    emit(state.copyWith(isLoginMode: !state.isLoginMode));
  }

  // Replaces: Future<void> _submit() async
  Future<void> submit(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      emit(state.copyWith(errorMessage: LoginError.fillFields));
      return;
    }

    // Only new accounts are restricted; logging in stays open so
    // existing non-student accounts keep working. The owner can open
    // signup to any address (access_settings.registration_mode), and the
    // auth.users trigger enforces the same rule server-side.
    if (!state.isLoginMode &&
        !RegistrationPolicy.isOpen &&
        !isStudentEmail(email)) {
      emit(state.copyWith(errorMessage: LoginError.studentEmailOnly));
      return;
    }

    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      if (state.isLoginMode) {
        // Log In Logic
        await supabase.auth.signInWithPassword(
          email: email.trim(),
          password: password.trim(),
        );
      } else {
        // Sign Up Logic
        await supabase.auth.signUp(
          email: email.trim(),
          password: password.trim(),
        );
        // Optional: emit a specific message for signup success if needed
      }

      // Check if session exists (Login Successful)
      if (supabase.auth.currentSession != null) {
        emit(state.copyWith(isLoading: false, isSuccess: true));
      } else {
        // Sometimes signup requires email confirmation, so session might be null
        emit(state.copyWith(isLoading: false, errorMessage: LoginError.checkEmail));
      }

    } on AuthException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.message));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: LoginError.generic));
    }
  }

  /// [from] is the page to return to; on web it rides along in the
  /// redirect URL (`/login?from=…`), and the router forwards there once
  /// the restored session arrives.
  Future<void> signInWithGoogle({String? from}) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      // WEB: come back to this same page after Google login.
      // MOBILE: deep link back into the app (must match Supabase URL settings
      // and the AndroidManifest intent filter).
      // The full URL must be allowed in Supabase Auth → URL
      // Configuration (e.g. https://mykerawang-app.web.app/**).
      final redirectTo = kIsWeb
          ? '${Uri.base.origin}${loginPathFor(from)}'
          : 'mykerawang://login-callback';

      // On the web the redirect is launched here rather than by
      // signInWithOAuth, so it can *replace* this page's history entry
      // instead of adding one. A pushed entry left the browser's Back
      // pointing at Google's account chooser after signing in. Same URL,
      // same PKCE verifier — only the history mode differs.
      if (kIsWeb) {
        final oauth = await supabase.auth.getOAuthSignInUrl(
          provider: OAuthProvider.google,
          redirectTo: redirectTo,
        );
        if (replaceLocationForOAuth(oauth.url)) return;
      }

      // 1. Trigger Supabase OAuth
      // NOTE: Ensure you have "Google" enabled in Supabase Auth Providers
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        // iOS WebKit blocks the storage access a popup needs to finish the
        // credential exchange (ITP), so the popup silently dies after account
        // selection. A same-tab, full-page redirect avoids popups entirely.
        authScreenLaunchMode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );

      // The flow leaves the page here. On return, SessionWatcher + the
      // router's auth redirect pick up the restored session — that's this
      // app's equivalent of Firebase's getRedirectResult().
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: '${LoginError.googleFailed}$e'));
    }
  }
}