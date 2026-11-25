import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferences_provider.dart';

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _preferenceKey = 'theme_mode';

  @override
  ThemeMode build() {
    final savedMode = ref
        .read(sharedPreferencesProvider)
        .getString(_preferenceKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == savedMode,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_preferenceKey, mode.name);
    state = mode;
  }
}
