import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_providers.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/data/onboarding_repository.dart';
import '../features/onboarding/presentation/account_entry_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/reset_password_screen.dart';
import '../features/outfits/presentation/outfits_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/wardrobe/presentation/wardrobe_item_detail_screen.dart';
import '../features/wardrobe/presentation/wardrobe_screen.dart';
import 'shell/navigation_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingRepository = ref.watch(onboardingRepositoryProvider);
  final router = GoRouter(
    initialLocation: onboardingRepository.isCompleted ? '/' : '/onboarding',
    redirect: (context, state) {
      final isOnboarding = state.matchedLocation == '/onboarding';
      if (!onboardingRepository.isCompleted && !isOnboarding) {
        return '/onboarding';
      }
      if (onboardingRepository.isCompleted && isOnboarding) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/account/create',
        name: 'create-account',
        builder: (context, state) =>
            const AccountEntryScreen(createAccount: true),
      ),
      GoRoute(
        path: '/account/sign-in',
        name: 'sign-in',
        builder: (context, state) =>
            const AccountEntryScreen(createAccount: false),
      ),
      GoRoute(
        path: '/account/reset-password',
        name: 'reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            NavigationShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'today',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wardrobe',
                name: 'wardrobe',
                builder: (context, state) => const WardrobeScreen(),
                routes: [
                  GoRoute(
                    path: 'items/:itemId',
                    name: 'wardrobe-item-detail',
                    builder: (context, state) => WardrobeItemDetailScreen(
                      itemId: state.pathParameters['itemId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/outfits',
                name: 'outfits',
                builder: (context, state) => const OutfitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('This page could not be opened: ${state.error}'),
      ),
    ),
  );
  ref.listen(authPasswordRecoveryProvider, (previous, next) {
    if (next.asData?.value == true) {
      router.go('/account/reset-password');
    }
  });
  ref.onDispose(router.dispose);
  return router;
});
