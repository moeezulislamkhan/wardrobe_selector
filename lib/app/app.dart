import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/preferences/theme_mode_provider.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class WardrobeApp extends ConsumerWidget {
  const WardrobeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Wardrobe',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
