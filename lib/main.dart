import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/errors/app_error_reporter.dart';
import 'core/preferences/preferences_provider.dart';
import 'features/auth/data/supabase_auth_gateway.dart';
import 'features/auth/domain/auth_gateway.dart';
import 'features/auth/presentation/auth_providers.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
    AppErrorReporter.install();

    final preferences = await SharedPreferences.getInstance();
    AuthGateway? authGateway;
    String? authConfigurationError;
    try {
      final config = SupabaseConfig.fromEnvironment();
      if (config != null) {
        await Supabase.initialize(
          url: config.url,
          publishableKey: config.publishableKey,
          debug: false,
        );
        authGateway = SupabaseAuthGateway(
          Supabase.instance.client,
          passwordResetRedirect: config.authRedirectUrl,
        );
      }
    } on FormatException catch (error) {
      authConfigurationError = error.message;
    } on Exception catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace);
      authConfigurationError = 'Could not initialize account services. Guest mode is still available.';
    }

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authGatewayProvider.overrideWithValue(authGateway),
          authConfigurationErrorProvider.overrideWithValue(
            authConfigurationError,
          ),
        ],
        child: const WardrobeApp(),
      ),
    );
  }, AppErrorReporter.report);
}
