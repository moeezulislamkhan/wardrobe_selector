import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/preferences/preferences_provider.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(sharedPreferencesProvider));
});

class OnboardingRepository {
  OnboardingRepository(this._preferences);

  static const _completionKey = 'onboarding_completed';

  final SharedPreferences _preferences;

  bool get isCompleted => _preferences.getBool(_completionKey) ?? false;

  Future<void> complete() async {
    late final bool saved;
    try {
      saved = await _preferences.setBool(_completionKey, true);
    } on Exception catch (error) {
      throw AppError(
        'The onboarding choice could not be saved.',
        cause: error,
      );
    }
    if (!saved) {
      throw const AppError('The onboarding choice could not be saved.');
    }
  }
}
