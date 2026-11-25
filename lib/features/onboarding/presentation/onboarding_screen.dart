import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../data/onboarding_repository.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _features = [
    _OnboardingFeature(
      icon: Icons.checkroom_rounded,
      eyebrow: 'EVERY PIECE, IN ONE PLACE',
      title: 'Your Digital Wardrobe',
      description:
          'Keep the clothes you own organised in one personal wardrobe, '
          'right on your device.',
      accent: Color(0xFF8A6854),
    ),
    _OnboardingFeature(
      icon: Icons.auto_awesome_rounded,
      eyebrow: 'GET DRESSED WITH EASE',
      title: 'Outfit Suggestions',
      description:
          'Find thoughtful outfit combinations from pieces already in your '
          'wardrobe, with no guesswork.',
      accent: Color(0xFF687B68),
    ),
    _OnboardingFeature(
      icon: Icons.calendar_month_rounded,
      eyebrow: 'A LITTLE PLAN GOES A LONG WAY',
      title: 'Weekly Planner',
      description:
          'Plan what to wear for the week ahead and make busy mornings feel '
          'a little simpler.',
      accent: Color(0xFF6D718F),
    ),
  ];

  final _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;
  String? _saveError;
  String? _pendingLocation;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _continueTo(String location) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _saveError = null;
      _pendingLocation = location;
    });

    try {
      await ref.read(onboardingRepositoryProvider).complete();
      if (mounted) context.go(location);
    } on AppError {
      if (mounted) {
        setState(() {
          _saveError = 'We couldn’t save your choice. Check your device storage and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _movePage(int offset) {
    final nextPage = (_currentPage + offset).clamp(0, _features.length - 1);
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastPage = _currentPage == _features.length - 1;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final illustrationHeight = math
                .min(math.max(constraints.maxHeight * 0.48, 280), 390)
                .toDouble();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.style_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'WARDROBE',
                              style: theme.textTheme.labelLarge?.copyWith(
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_currentPage + 1} of ${_features.length}',
                              style: theme.textTheme.labelLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          label:
                              'Onboarding page ${_currentPage + 1} of ${_features.length}',
                          child: LinearProgressIndicator(
                            value: (_currentPage + 1) / _features.length,
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: illustrationHeight,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _features.length,
                            onPageChanged: (page) {
                              setState(() {
                                _currentPage = page;
                                _saveError = null;
                              });
                            },
                            itemBuilder: (context, index) =>
                                SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: illustrationHeight,
                                    ),
                                    child: _FeaturePage(
                                      feature: _features[index],
                                    ),
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_features.length, (index) {
                            final selected = index == _currentPage;
                            return Semantics(
                              label: 'Page ${index + 1}',
                              selected: selected,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: selected ? 24 : 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: _currentPage == 0 || _isSaving
                                  ? null
                                  : () => _movePage(-1),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Back'),
                            ),
                            TextButton.icon(
                              onPressed: isLastPage || _isSaving
                                  ? null
                                  : () => _movePage(1),
                              icon: const Icon(Icons.arrow_forward),
                              iconAlignment: IconAlignment.end,
                              label: const Text('Next'),
                            ),
                          ],
                        ),
                        if (_saveError != null) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _saveError!,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () => _continueTo(
                                            _pendingLocation ?? '/',
                                          ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            key: const ValueKey('continue-as-guest'),
                            onPressed: _isSaving
                                ? null
                                : () => _continueTo('/'),
                            icon: _isSaving && _pendingLocation == '/'
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_outline),
                            label: Text(
                              _isSaving && _pendingLocation == '/'
                                  ? 'Saving…'
                                  : 'Continue as Guest',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => _continueTo('/account/create'),
                                child: const Text('Create Account'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => _continueTo('/account/sign-in'),
                                child: const Text('Sign In'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No account needed to get started.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OnboardingFeature {
  const _OnboardingFeature({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
}

class _FeaturePage extends StatelessWidget {
  const _FeaturePage({required this.feature});

  final _OnboardingFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: feature.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: feature.accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(feature.icon, size: 48, color: feature.accent),
                Positioned(
                  top: 16,
                  right: 12,
                  child: Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: colorScheme.tertiary,
                  ),
                ),
                Positioned(
                  bottom: 18,
                  left: 12,
                  child: Icon(
                    Icons.circle,
                    size: 10,
                    color: colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            feature.eyebrow,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: feature.accent,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            feature.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              feature.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
