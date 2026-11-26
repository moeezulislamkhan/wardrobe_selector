import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/errors/app_error.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/onboarding/data/onboarding_repository.dart';

void main() {
  Future<SharedPreferences> createPreferences({
    bool onboardingComplete = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': onboardingComplete,
    });
    return SharedPreferences.getInstance();
  }

  testWidgets('guest can navigate between app sections', (tester) async {
    final preferences = await createPreferences(onboardingComplete: true);
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

    expect(find.text('Your wardrobe is empty'), findsOneWidget);
  });

  testWidgets('theme preference is applied and persisted', (tester) async {
    final preferences = await createPreferences(onboardingComplete: true);
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

  testWidgets('first launch explains features and guest continues offline', (
    tester,
  ) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    expect(find.text('Your Digital Wardrobe'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('continue-as-guest')));
    await tester.pumpAndSettle();

    expect(preferences.getBool('onboarding_completed'), isTrue);
    expect(find.text('Guest mode is ready'), findsOneWidget);
  });

  testWidgets('onboarding pages introduce outfit suggestions and planner', (
    tester,
  ) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Outfit Suggestions'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly Planner'), findsOneWidget);
  });

  testWidgets('account actions navigate without blocking guest mode', (
    tester,
  ) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    expect(
      find.textContaining('Account services are not configured yet.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Continue as Guest'));
    await tester.tap(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    expect(find.text('Guest mode is ready'), findsOneWidget);
    expect(preferences.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('sign in destination keeps guest access available', (
    tester,
  ) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(
      find.textContaining('Account services are not configured yet.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Continue as Guest'));
    await tester.tap(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    expect(find.text('Guest mode is ready'), findsOneWidget);
  });

  testWidgets('onboarding save failures can be retried', (tester) async {
    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          onboardingRepositoryProvider.overrideWithValue(
            _FailingOnboardingRepository(preferences),
          ),
        ],
        child: const WardrobeApp(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('continue-as-guest')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('We couldn’t save your choice.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Your Digital Wardrobe'), findsOneWidget);
  });

  testWidgets('onboarding remains usable on a compact screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final preferences = await createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('continue-as-guest')));
    await tester.tap(find.byKey(const ValueKey('continue-as-guest')));
    await tester.pumpAndSettle();

    expect(find.text('Guest mode is ready'), findsOneWidget);
  });
}

class _FailingOnboardingRepository extends OnboardingRepository {
  _FailingOnboardingRepository(super.preferences);

  @override
  Future<void> complete() async {
    throw const AppError('Simulated storage error');
  }
}
