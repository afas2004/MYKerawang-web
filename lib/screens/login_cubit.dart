import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/guest_access.dart';

/// Error codes put in [LoginState.errorMessage]. The cubit has no
/// BuildContext, so the screen turns these into localized text
/// (see `login_screen.dart`). Anything else is a server message shown as-is.
abstract final class LoginError {
  static const fillFields = 'login.fill_fields';
  static const checkEmail = 'login.check_email';
  static const generic = 'login.generic';

  /// Prefix; the underlying error follows it.
  static const googleFailed = 'login.google:';
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

  final supabase = Supabase.instance.client;

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
      // 1. Trigger Supabase OAuth
      // NOTE: Ensure you have "Google" enabled in Supabase Auth Providers
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // WEB: come back to this same page after Google login.
        // MOBILE: deep link back into the app (must match Supabase URL settings
        // and the AndroidManifest intent filter).
        // The full URL must be allowed in Supabase Auth → URL
        // Configuration (e.g. https://mykerawang-app.web.app/**).
        redirectTo: kIsWeb
            ? '${Uri.base.origin}${loginPathFor(from)}'
            : 'mykerawang://login-callback',
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