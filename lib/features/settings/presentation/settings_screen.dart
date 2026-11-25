import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_snackbar.dart';
import '../../../core/preferences/theme_mode_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Choose how Wardrobe looks on this device.'),
          const SizedBox(height: 16),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.settings_suggest_outlined),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) async {
              try {
                await ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(selection.single);
              } catch (error) {
                if (context.mounted) {
                  context.showAppError(error);
                }
              }
            },
          ),
          const SizedBox(height: 32),
          Text('Account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('Using guest mode'),
            subtitle: Text(
              'Your local wardrobe works without signing in. '
              'Cloud sync can be connected later.',
            ),
          ),
        ],
      ),
    );
  }
}
