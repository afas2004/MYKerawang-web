import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_themes.dart';

// State holds the selected named theme (DESIGN_SPEC.md §2).
// The old seedColor/darkMode model is migrated on first load.
class ThemeState {
  final AppTheme appTheme;
  ThemeState({required this.appTheme});
}

class ThemeCubit extends Cubit<ThemeState> {
  // Default: Kampus Bold
  ThemeCubit() : super(ThemeState(appTheme: AppTheme.kampus)) {
    _loadSettings();
  }

  void changeTheme(AppTheme theme) async {
    emit(ThemeState(appTheme: theme));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appTheme', theme.name);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getString('appTheme');
    if (saved != null) {
      final theme =
          AppTheme.values.where((t) => t.name == saved).firstOrNull;
      if (theme != null) {
        emit(ThemeState(appTheme: theme));
        return;
      }
    }

    // Legacy migration: users who had dark mode on get Noir once,
    // everyone else starts on the Kampus default.
    final legacyDark = prefs.getBool('isDarkMode');
    if (legacyDark == true) {
      emit(ThemeState(appTheme: AppTheme.noir));
      await prefs.setString('appTheme', AppTheme.noir.name);
    }
    await prefs.remove('isDarkMode');
    await prefs.remove('seedColor');
  }
}
