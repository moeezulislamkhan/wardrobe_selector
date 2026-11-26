import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../wardrobe/data/local_wardrobe_repository.dart';
import '../../wardrobe/domain/guest_wardrobe_item.dart';
import '../../../core/preferences/preferences_provider.dart';
import '../domain/rule_based_outfit_engine.dart';

const _wearHistoryKey = 'outfit_last_worn_at_v1';
const _seasons = ['Any season', 'Spring', 'Summer', 'Autumn', 'Winter'];
const _occasions = [
  'Any occasion',
  'Work',
  'Casual',
  'Formal',
  'Date night',
  'Travel',
  'Workout',
];

class OutfitsScreen extends ConsumerStatefulWidget {
  const OutfitsScreen({super.key});

  @override
  ConsumerState<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends ConsumerState<OutfitsScreen> {
  final _preferredColorsController = TextEditingController();
  final _preferredCategoriesController = TextEditingController();
  final _preferredStylesController = TextEditingController();
  String _occasion = _occasions.first;
  String _season = _seasons.first;
  bool _rainy = false;
  bool _isLoadingWearHistory = true;
  String? _wearHistoryError;
  Map<String, DateTime> _lastWornAt = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadWearHistory());
  }

  @override
  void dispose() {
    _preferredColorsController.dispose();
    _preferredCategoriesController.dispose();
    _preferredStylesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wardrobe = ref.watch(wardrobeItemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Outfit ideas')),
      body: wardrobe.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading your wardrobe',
          ),
        ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Your wardrobe could not be loaded.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(wardrobeItemsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (items) => _buildSuggestions(context, items),
      ),
    );
  }

  Widget _buildSuggestions(
    BuildContext context,
    List<GuestWardrobeItem> wardrobe,
  ) {
    final activeItems = wardrobe
        .where((item) => !item.isArchived && !item.isDeleted)
        .toList();
    final request = OutfitRequest(
      occasion: _occasion == _occasions.first ? null : _occasion,
      season: _season == _seasons.first ? null : _season,
      weather: _rainy
          ? const OutfitWeather(rainy: true)
          : null,
      preferences: OutfitPreferences(
        preferredColors: _splitValues(_preferredColorsController.text),
        preferredCategories: _splitValues(
          _preferredCategoriesController.text,
        ),
        styleTags: _splitValues(_preferredStylesController.text),
      ),
      lastWornAt: _lastWornAt,
    );
    final result = const RuleBasedOutfitEngine().generate(
      activeItems.map(_toOutfitItem),
      request: request,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Outfit ideas from your own wardrobe',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Suggestions use local styling rules only. No items are invented or '
          'sent to an AI service.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _DropdownFilter(
          label: 'Occasion',
          value: _occasion,
          options: _occasions,
          onChanged: (value) => setState(() => _occasion = value),
        ),
        const SizedBox(height: 12),
        _DropdownFilter(
          label: 'Season',
          value: _season,
          options: _seasons,
          onChanged: (value) => setState(() => _season = value),
        ),
        const SizedBox(height: 8),
        FilterChip(
          label: const Text('Rainy weather'),
          avatar: const Icon(Icons.umbrella_outlined, size: 18),
          selected: _rainy,
          onSelected: (value) => setState(() => _rainy = value),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _preferredColorsController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Preferred colors',
            hintText: 'e.g. navy, cream',
            helperText: 'Optional; separate values with commas.',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _preferredCategoriesController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Preferred categories',
            hintText: 'e.g. tops, shoes',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _preferredStylesController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Preferred style tags',
            hintText: 'e.g. minimal, classic',
          ),
        ),
        if (_isLoadingWearHistory) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          const Text('Loading recent-wear history…'),
        ],
        if (_wearHistoryError case final error?) ...[
          const SizedBox(height: 12),
          _InfoMessage(message: error, isError: true),
        ],
        const SizedBox(height: 20),
        if (activeItems.isEmpty)
          _NoWardrobeItems(
            onAddItem: () => context.pushNamed('wardrobe-item-add'),
          )
        else if (result.suggestions.isEmpty)
          _InfoMessage(
            message:
                result.fallbackExplanation ??
                'Add more wardrobe items to create a complete outfit.',
          )
        else ...[
          Text(
            'Suggested combinations',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < result.suggestions.length; index++)
            _SuggestionCard(
              number: index + 1,
              suggestion: result.suggestions[index],
              onMarkWorn: () => _markWorn(result.suggestions[index]),
            ),
          if (result.fallbackExplanation case final explanation?) ...[
            const SizedBox(height: 8),
            _InfoMessage(message: explanation),
          ],
        ],
      ],
    );
  }

  Future<void> _loadWearHistory() async {
    try {
      final encoded = ref
          .read(sharedPreferencesProvider)
          .getString(_wearHistoryKey);
      if (encoded == null) {
        if (mounted) setState(() => _isLoadingWearHistory = false);
        return;
      }

      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('Recent-wear history must be a map.');
      }
      final lastWornAt = <String, DateTime>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Recent-wear history has invalid data.');
        }
        final date = DateTime.tryParse(entry.value as String);
        if (date == null) {
          throw const FormatException('Recent-wear history has an invalid date.');
        }
        lastWornAt[entry.key as String] = date;
      }
      if (mounted) {
        setState(() {
          _lastWornAt = Map.unmodifiable(lastWornAt);
          _isLoadingWearHistory = false;
        });
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _isLoadingWearHistory = false;
        _wearHistoryError =
            'Recent-wear history could not be read. Suggestions will not '
            'include the wear penalty until it is available again.';
      });
    }
  }

  Future<void> _markWorn(OutfitSuggestion suggestion) async {
    final now = DateTime.now();
    final updated = Map<String, DateTime>.of(_lastWornAt);
    for (final item in suggestion.items) {
      updated[item.id] = now;
    }

    try {
      final persisted = await ref
          .read(sharedPreferencesProvider)
          .setString(
            _wearHistoryKey,
            jsonEncode(
              updated.map(
                (id, date) => MapEntry(id, date.toUtc().toIso8601String()),
              ),
            ),
          );
      if (!persisted) {
        throw StateError('Recent-wear history could not be saved.');
      }
      if (!mounted) return;
      setState(() {
        _lastWornAt = Map.unmodifiable(updated);
        _wearHistoryError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outfit marked as recently worn.')),
      );
    } on Exception {
      if (!mounted) return;
      setState(() {
        _wearHistoryError =
            'Could not save recent-wear history. The wear penalty was not '
            'updated.';
      });
    }
  }
}

OutfitItem _toOutfitItem(GuestWardrobeItem item) => OutfitItem(
  id: item.localId,
  title: item.title,
  category: item.category,
  subcategory: item.subcategory,
  primaryColor: item.primaryColor,
  secondaryColor: item.secondaryColor,
  occasions: item.occasionValues,
  seasons: item.seasonValues,
  styleTags: item.styleTags,
  isFavorite: item.isFavorite,
  isArchived: item.isArchived,
  isDeleted: item.isDeleted,
);

List<String> _splitValues(String value) => List.unmodifiable(
  value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet(),
);

class _DropdownFilter extends StatelessWidget {
  const _DropdownFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.number,
    required this.suggestion,
    required this.onMarkWorn,
  });

  final int number;
  final OutfitSuggestion suggestion;
  final VoidCallback onMarkWorn;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outfit $number', style: textTheme.titleMedium),
            const SizedBox(height: 10),
            _OutfitPiece(label: 'Top', item: suggestion.top),
            _OutfitPiece(label: 'Bottom', item: suggestion.bottom),
            _OutfitPiece(label: 'Shoes', item: suggestion.shoes),
            if (suggestion.layer case final layer?)
              _OutfitPiece(label: 'Layer', item: layer),
            if (suggestion.accessory case final accessory?)
              _OutfitPiece(label: 'Accessory', item: accessory),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final reason in suggestion.reasons)
                  Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(reason),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onMarkWorn,
                icon: const Icon(Icons.checkroom_outlined),
                label: const Text('Mark as worn'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitPiece extends StatelessWidget {
  const _OutfitPiece({required this.label, required this.item});

  final String label;
  final OutfitItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(item.title)),
          if (item.primaryColor case final color?)
            Text(
              color,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _NoWardrobeItems extends StatelessWidget {
  const _NoWardrobeItems({required this.onAddItem});

  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.checkroom_outlined, size: 44),
        const SizedBox(height: 12),
        Text(
          'Add your own wardrobe items',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Outfit ideas are made only from items you save. There is no sample '
          'or invented inventory.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAddItem,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add a wardrobe item'),
        ),
      ],
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError ? colors.onErrorContainer : colors.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
