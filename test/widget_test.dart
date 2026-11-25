import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SharedPreferences> createPreferences() {
    return SharedPreferences.getInstance();
  }

  testWidgets('guest can navigate between app sections', (tester) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    expect(find.text('Guest mode is ready'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Wardrobe'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your wardrobe starts here'), findsOneWidget);
  });

  testWidgets('theme preference is applied and persisted', (tester) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(preferences.getString('theme_mode'), 'dark');
  });
}
