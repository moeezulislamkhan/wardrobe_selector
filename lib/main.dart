import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/errors/app_error_reporter.dart';
import 'core/preferences/preferences_provider.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppErrorReporter.install();

    final preferences = await SharedPreferences.getInstance();
    runApp(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );
  }, AppErrorReporter.report);
}
