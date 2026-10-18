import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_strings.dart';

class LanguageState {
  final AppLanguage language;
  final AppStrings strings;

  LanguageState(this.language) : strings = AppStrings.of(language);
}

class LanguageCubit extends Cubit<LanguageState> {
  // Default: English
  LanguageCubit() : super(LanguageState(AppLanguage.en)) {
    _load();
  }

  void changeLanguage(AppLanguage lang) async {
    emit(LanguageState(lang));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appLanguage', lang.name);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('appLanguage');
    if (saved != null) {
      final lang = AppLanguage.values
          .where((l) => l.name == saved)
          .firstOrNull;
      if (lang != null) emit(LanguageState(lang));
    }
  }
}

/// Shorthand: `context.l10n.navHome`
/// (rebuilds the widget when the language changes, same as watch)
extension L10nContext on BuildContext {
  AppStrings get l10n => watch<LanguageCubit>().state.strings;
}

/// Non-listening variant for callbacks, validators and code after an
/// `await` — `watch` is only legal during build.
extension L10nReadContext on BuildContext {
  AppStrings get l10nRead => read<LanguageCubit>().state.strings;
  AppLanguage get appLanguage => watch<LanguageCubit>().state.language;
}
