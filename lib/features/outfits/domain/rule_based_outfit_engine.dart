class OutfitItem {
  const OutfitItem({
    required this.id,
    required this.title,
    required this.category,
    this.subcategory,
    this.imagePath,
    this.primaryColor,
    this.secondaryColor,
    this.occasions = const [],
    this.seasons = const [],
    this.styleTags = const [],
    this.isFavorite = false,
    this.isArchived = false,
    this.isDeleted = false,
  });

  final String id;
  final String title;
  final String category;
  final String? subcategory;
  final String? imagePath;
  final String? primaryColor;
  final String? secondaryColor;
  final List<String> occasions;
  final List<String> seasons;
  final List<String> styleTags;
  final bool isFavorite;
  final bool isArchived;
  final bool isDeleted;
}

class OutfitPreferences {
  const OutfitPreferences({
    this.preferredColors = const [],
    this.preferredCategories = const [],
    this.styleTags = const [],
  });

  final List<String> preferredColors;
  final List<String> preferredCategories;
  final List<String> styleTags;
}

class OutfitWeather {
  const OutfitWeather({this.season, this.temperatureC, this.rainy = false});

  final String? season;
  final double? temperatureC;
  final bool rainy;
}

class OutfitRequest {
  const OutfitRequest({
    this.occasion,
    this.season,
    this.weather,
    this.preferences = const OutfitPreferences(),
    this.lastWornAt = const {},
    this.excludedCombinationKeys = const {},
    this.now,
  });

  final String? occasion;
  final String? season;
  final OutfitWeather? weather;
  final OutfitPreferences preferences;
  final Map<String, DateTime> lastWornAt;
  final Set<String> excludedCombinationKeys;
  final DateTime? now;
}

class OutfitSuggestion {
  const OutfitSuggestion({
    required this.top,
    required this.bottom,
    required this.shoes,
    required this.reasons,
    required this.score,
    this.layer,
    this.accessory,
  });

  final OutfitItem top;
  final OutfitItem bottom;
  final OutfitItem shoes;
  final OutfitItem? layer;
  final OutfitItem? accessory;
  final List<String> reasons;
  final double score;

  List<OutfitItem> get items {
    final outfitItems = [top, bottom, shoes];
    if (layer != null) outfitItems.add(layer!);
    if (accessory != null) outfitItems.add(accessory!);
    return List.unmodifiable(outfitItems);
  }

  String get combinationKey => '${top.id}|${bottom.id}|${shoes.id}';
}

class OutfitGenerationResult {
  const OutfitGenerationResult({
    required this.suggestions,
    this.fallbackExplanation,
  });

  final List<OutfitSuggestion> suggestions;
  final String? fallbackExplanation;
}

enum OutfitItemRole { top, bottom, shoes, layer, accessory, other }

class RuleBasedOutfitEngine {
  const RuleBasedOutfitEngine();

  OutfitItemRole roleOf(OutfitItem item) {
    final category = _normalize('${item.category} ${item.subcategory ?? ''}');
    if (_containsAny(category, _shoeWords)) return OutfitItemRole.shoes;
    if (_containsAny(category, _accessoryWords)) {
      return OutfitItemRole.accessory;
    }
    if (_containsAny(category, _layerWords)) return OutfitItemRole.layer;
    if (_containsAny(category, _bottomWords)) return OutfitItemRole.bottom;
    if (_containsAny(category, _topWords)) return OutfitItemRole.top;

    final description = _itemText(item);
    if (_containsAny(description, _shoeWords)) return OutfitItemRole.shoes;
    if (_containsAny(description, _accessoryWords)) {
      return OutfitItemRole.accessory;
    }
    if (_containsAny(description, _layerWords)) return OutfitItemRole.layer;
    if (_containsAny(description, _bottomWords)) return OutfitItemRole.bottom;
    if (_containsAny(description, _topWords)) return OutfitItemRole.top;
    return OutfitItemRole.other;
  }

  List<String> compatibilityHints(Iterable<OutfitItem> selectedItems) {
    final items = <String, OutfitItem>{};
    for (final item in selectedItems) {
      items.putIfAbsent(item.id, () => item);
    }
    if (items.isEmpty) return const ['Select wardrobe items to see hints.'];

    final values = items.values.toList();
    final roles = values.map(roleOf).toSet();
    final hints = <String>[
      if (!roles.contains(OutfitItemRole.top) ||
          !roles.contains(OutfitItemRole.bottom) ||
          !roles.contains(OutfitItemRole.shoes))
        'Choose a top, bottom, and shoes for a complete outfit.',
    ];

    final coloredItems = values
        .where((item) => _itemColors(item).isNotEmpty)
        .toList();
    if (coloredItems.length > 1) {
      final harmony = _colorHarmony(coloredItems);
      if (harmony >= 1) {
        hints.add('Saved color labels coordinate.');
      } else if (harmony < 0) {
        hints.add('Saved colors may clash; consider swapping a piece.');
      } else {
        hints.add('Saved colors have mixed harmony.');
      }
    } else {
      hints.add(
        'Add color details to more items for color compatibility hints.',
      );
    }

    if (_styleCompatibility(values) < 0) {
      hints.add('Some saved style labels may clash; consider another piece.');
    }
    if (hints.length == 1 && roles.length >= 3) {
      hints.add(
        'The selected pieces form a complete outfit from your wardrobe.',
      );
    }
    return List.unmodifiable(hints.take(3));
  }

  OutfitGenerationResult generate(
    Iterable<OutfitItem> wardrobe, {
    OutfitRequest request = const OutfitRequest(),
  }) {
    final uniqueItems = <String, OutfitItem>{};
    for (final item in wardrobe) {
      if (item.id.trim().isEmpty ||
          item.title.trim().isEmpty ||
          item.isArchived ||
          item.isDeleted) {
        continue;
      }
      uniqueItems.putIfAbsent(item.id, () => item);
    }

    final tops = <OutfitItem>[];
    final bottoms = <OutfitItem>[];
    final shoes = <OutfitItem>[];
    final layers = <OutfitItem>[];
    final accessories = <OutfitItem>[];
    for (final item in uniqueItems.values) {
      switch (roleOf(item)) {
        case OutfitItemRole.top:
          tops.add(item);
        case OutfitItemRole.bottom:
          bottoms.add(item);
        case OutfitItemRole.shoes:
          shoes.add(item);
        case OutfitItemRole.layer:
          layers.add(item);
        case OutfitItemRole.accessory:
          accessories.add(item);
        case OutfitItemRole.other:
          break;
      }
    }

    final missing = <String>[
      if (tops.isEmpty) 'a top',
      if (bottoms.isEmpty) 'a bottom',
      if (shoes.isEmpty) 'shoes',
    ];
    if (missing.isNotEmpty) {
      return OutfitGenerationResult(
        suggestions: const [],
        fallbackExplanation:
            'Add ${_joinWithAnd(missing)} to create complete outfits.',
      );
    }

    final now = request.now ?? DateTime.now();
    final candidates = <OutfitSuggestion>[];
    for (final top in tops) {
      for (final bottom in bottoms) {
        for (final shoe in shoes) {
          final baseItems = [top, bottom, shoe];
          final layer = _bestOptionalItem(
            layers,
            baseItems,
            request,
            now,
            omitLayersForHeat: true,
          );
          final accessoryBase = [...baseItems];
          if (layer != null) accessoryBase.add(layer);
          final accessory = _bestOptionalItem(
            accessories,
            accessoryBase,
            request,
            now,
          );
          final completeItems = [...baseItems];
          if (layer != null) completeItems.add(layer);
          if (accessory != null) completeItems.add(accessory);
          final colorHarmony = _colorHarmony(completeItems);
          final score =
              completeItems.fold<double>(
                0,
                (total, item) => total + _itemScore(item, request, now),
              ) +
              colorHarmony * 2.5 +
              _styleCompatibility(baseItems) +
              _weatherScore(shoe, layer, request.weather);
          candidates.add(
            OutfitSuggestion(
              top: top,
              bottom: bottom,
              shoes: shoe,
              layer: layer,
              accessory: accessory,
              reasons: _reasons(
                completeItems,
                colorHarmony,
                request,
                now,
                layer,
              ),
              score: score,
            ),
          );
        }
      }
    }

    final selected = <OutfitSuggestion>[];
    final remaining = candidates
        .where(
          (candidate) => !request.excludedCombinationKeys.contains(
            candidate.combinationKey,
          ),
        )
        .toList();
    while (selected.length < 4 && remaining.isNotEmpty) {
      remaining.sort((first, second) {
        final firstRank = _diversityAdjustedScore(first, selected);
        final secondRank = _diversityAdjustedScore(second, selected);
        final byScore = secondRank.compareTo(firstRank);
        if (byScore != 0) return byScore;
        return _stableKey(first).compareTo(_stableKey(second));
      });
      selected.add(remaining.removeAt(0));
    }

    final fallback = candidates.length < 3
        ? 'Only ${candidates.length} complete '
              '${candidates.length == 1 ? 'combination is' : 'combinations are'} '
              'available. Add more tops, bottoms, or shoes for 3–4 ideas.'
        : null;
    return OutfitGenerationResult(
      suggestions: List.unmodifiable(selected),
      fallbackExplanation: fallback,
    );
  }

  OutfitItem? _bestOptionalItem(
    List<OutfitItem> options,
    List<OutfitItem> baseItems,
    OutfitRequest request,
    DateTime now, {
    bool omitLayersForHeat = false,
  }) {
    if (options.isEmpty ||
        (omitLayersForHeat &&
            request.weather?.temperatureC != null &&
            request.weather!.temperatureC! >= 27)) {
      return null;
    }

    final ranked = [...options]
      ..sort((first, second) {
        final firstScore =
            _itemScore(first, request, now) +
            _colorHarmony([first, ...baseItems]) * 2;
        final secondScore =
            _itemScore(second, request, now) +
            _colorHarmony([second, ...baseItems]) * 2;
        final byScore = secondScore.compareTo(firstScore);
        return byScore == 0 ? first.id.compareTo(second.id) : byScore;
      });
    return ranked.first;
  }

  double _itemScore(OutfitItem item, OutfitRequest request, DateTime now) {
    var score = item.isFavorite ? 1.5 : 0.0;
    final occasion = _normalize(request.occasion);
    if (occasion.isNotEmpty) {
      final itemOccasions = _values(item.occasions);
      if (itemOccasions.contains(occasion)) {
        score += 6;
      } else if (itemOccasions.isNotEmpty) {
        score -= 2;
      }
    }

    final season = _seasonName(request.season ?? request.weather?.season);
    if (season.isNotEmpty) {
      final itemSeasons = _seasonValues(item.seasons);
      if (itemSeasons.contains(season)) {
        score += 5;
      } else if (itemSeasons.isNotEmpty) {
        score -= 3;
      }
    }

    final preferredColors = request.preferences.preferredColors
        .map(_colorName)
        .where((color) => color.isNotEmpty)
        .toSet();
    if (preferredColors.isNotEmpty &&
        _itemColors(item).any((color) => preferredColors.contains(color))) {
      score += 3;
    }
    final preferredCategories = request.preferences.preferredCategories
        .map(_normalize)
        .where((category) => category.isNotEmpty)
        .toSet();
    if (preferredCategories.contains(_normalize(item.category)) ||
        preferredCategories.contains(_roleName(roleOf(item)))) {
      score += 2;
    }
    final preferredTags = request.preferences.styleTags.map(_normalize).toSet();
    if (item.styleTags.any((tag) => preferredTags.contains(_normalize(tag)))) {
      score += 2;
    }

    final lastWornAt = request.lastWornAt[item.id];
    if (lastWornAt != null) {
      final age = now.difference(lastWornAt).inDays;
      if (age <= 1) {
        score -= 6;
      } else if (age <= 3) {
        score -= 4;
      } else if (age <= 7) {
        score -= 2;
      } else if (age <= 14) {
        score -= 1;
      }
    }
    return score;
  }

  double _colorHarmony(List<OutfitItem> items) {
    final colors = items.expand(_itemColors).toList();
    var total = 0.0;
    var pairs = 0;
    for (var first = 0; first < colors.length; first++) {
      for (var second = first + 1; second < colors.length; second++) {
        total += _colorPairScore(colors[first], colors[second]);
        pairs++;
      }
    }
    return pairs == 0 ? 0 : total / pairs;
  }

  double _colorPairScore(String first, String second) {
    if (first == second) return 2;
    if (_neutralColors.contains(first) && _neutralColors.contains(second)) {
      return 1.5;
    }
    if (_neutralColors.contains(first) || _neutralColors.contains(second)) {
      return 1;
    }
    if (_complementaryColors[first] == second ||
        _complementaryColors[second] == first) {
      return 1.5;
    }
    return -0.5;
  }

  double _styleCompatibility(List<OutfitItem> items) {
    final styles = items.map(_styleFamily).toList();
    var score = 0.0;
    for (var first = 0; first < styles.length; first++) {
      for (var second = first + 1; second < styles.length; second++) {
        final pair = {styles[first], styles[second]};
        if (pair.contains('formal') && pair.contains('sport')) {
          score -= 4;
        } else if (pair.contains('formal') && pair.contains('casual')) {
          score -= 2;
        }
      }
    }
    return score;
  }

  double _weatherScore(
    OutfitItem shoes,
    OutfitItem? layer,
    OutfitWeather? weather,
  ) {
    if (weather == null) return 0;
    var score = 0.0;
    final temperature = weather.temperatureC;
    if (temperature != null && temperature <= 12) {
      score += layer == null ? -2 : 4;
      if (_containsAny(_itemText(shoes), const ['sandal', 'open toe'])) {
        score -= 4;
      }
    } else if (temperature != null && temperature >= 27 && layer != null) {
      score -= 2;
    }

    if (weather.rainy) {
      if (_isWeatherproof(shoes)) score += 2;
      if (layer != null && _isWeatherproof(layer)) score += 3;
    }
    return score;
  }

  List<String> _reasons(
    List<OutfitItem> items,
    double colorHarmony,
    OutfitRequest request,
    DateTime now,
    OutfitItem? layer,
  ) {
    final reasons = <String>[];
    final occasion = request.occasion?.trim();
    if (occasion != null &&
        occasion.isNotEmpty &&
        items.any(
          (item) => _values(item.occasions).contains(_normalize(occasion)),
        )) {
      reasons.add('Fits your $occasion occasion');
    }
    if (colorHarmony >= 1) reasons.add('Colors coordinate');

    final season = request.season ?? request.weather?.season;
    if (season != null &&
        season.trim().isNotEmpty &&
        items.any(
          (item) => _seasonValues(item.seasons).contains(_seasonName(season)),
        )) {
      reasons.add('Includes $season-season pieces');
    }
    if (request.weather?.temperatureC case final temperature?
        when temperature <= 12 && layer != null) {
      reasons.add('Adds a layer for cool weather');
    }
    if (items.any((item) => _matchesPreferences(item, request.preferences))) {
      reasons.add('Matches your preferences');
    }
    if (reasons.isEmpty) reasons.add('Complete outfit from your wardrobe');
    if (request.lastWornAt.isNotEmpty &&
        items.every((item) => !_wasWornRecently(item, request, now))) {
      reasons.add('Avoids recently worn pieces');
    }
    return List.unmodifiable(reasons.take(4));
  }

  bool _matchesPreferences(OutfitItem item, OutfitPreferences preferences) {
    final colors = preferences.preferredColors.map(_colorName).toSet();
    final categories = preferences.preferredCategories.map(_normalize).toSet();
    final tags = preferences.styleTags.map(_normalize).toSet();
    return _itemColors(item).any(colors.contains) ||
        categories.contains(_normalize(item.category)) ||
        categories.contains(_roleName(roleOf(item))) ||
        item.styleTags.any((tag) => tags.contains(_normalize(tag)));
  }

  bool _wasWornRecently(OutfitItem item, OutfitRequest request, DateTime now) {
    final wornAt = request.lastWornAt[item.id];
    return wornAt != null && now.difference(wornAt).inDays <= 7;
  }

  double _diversityAdjustedScore(
    OutfitSuggestion suggestion,
    List<OutfitSuggestion> selected,
  ) {
    var score = suggestion.score;
    for (final previous in selected) {
      final previousIds = previous.items.map((item) => item.id).toSet();
      score -=
          suggestion.items
              .where((item) => previousIds.contains(item.id))
              .length *
          1.5;
    }
    return score;
  }

  String _styleFamily(OutfitItem item) {
    final text = _itemText(item);
    if (_containsAny(text, const ['formal', 'dressy', 'business', 'evening'])) {
      return 'formal';
    }
    if (_containsAny(text, const ['sport', 'athletic', 'gym', 'running'])) {
      return 'sport';
    }
    if (_containsAny(text, const ['casual', 'relaxed', 'everyday'])) {
      return 'casual';
    }
    return 'unknown';
  }

  bool _isWeatherproof(OutfitItem item) => _containsAny(_itemText(item), const [
    'waterproof',
    'water resistant',
    'rain',
    'weatherproof',
  ]);

  Iterable<String> _itemColors(OutfitItem item) => [
    if (item.primaryColor != null) _colorName(item.primaryColor!),
    if (item.secondaryColor != null) _colorName(item.secondaryColor!),
  ].where((color) => color.isNotEmpty);

  String _itemText(OutfitItem item) => _normalize(
    '${item.title} ${item.category} ${item.subcategory ?? ''} '
    '${item.styleTags.join(' ')}',
  );

  List<String> _values(Iterable<String> values) => values
      .expand((value) => value.split(','))
      .map(_normalize)
      .where((value) => value.isNotEmpty)
      .toList();

  List<String> _seasonValues(Iterable<String> values) => values
      .expand((value) => value.split(','))
      .map(_seasonName)
      .where((value) => value.isNotEmpty)
      .toList();

  String _seasonName(String? value) {
    final normalized = _normalize(value);
    return normalized == 'fall' ? 'autumn' : normalized;
  }

  String _normalize(String? value) =>
      (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String _colorName(String value) {
    final normalized = _normalize(value);
    for (final color in _knownColors) {
      if (normalized.split(' ').contains(color)) return color;
    }
    return '';
  }

  bool _containsAny(String text, List<String> words) {
    final normalized = _normalize(text);
    return words.any((word) {
      final normalizedWord = _normalize(word);
      return normalized.split(' ').contains(normalizedWord) ||
          normalized.contains(normalizedWord);
    });
  }

  String _roleName(OutfitItemRole role) => switch (role) {
    OutfitItemRole.top => 'top',
    OutfitItemRole.bottom => 'bottom',
    OutfitItemRole.shoes => 'shoes',
    OutfitItemRole.layer => 'layer',
    OutfitItemRole.accessory => 'accessory',
    OutfitItemRole.other => 'other',
  };

  String _stableKey(OutfitSuggestion suggestion) =>
      '${suggestion.top.id}|${suggestion.bottom.id}|${suggestion.shoes.id}';

  String _joinWithAnd(List<String> values) {
    if (values.length == 1) return values.single;
    if (values.length == 2) return '${values.first} and ${values.last}';
    return '${values.take(values.length - 1).join(', ')}, and ${values.last}';
  }
}

const _shoeWords = [
  'shoe',
  'shoes',
  'footwear',
  'sneaker',
  'sneakers',
  'boot',
  'boots',
  'sandal',
  'sandals',
  'heels',
  'flats',
];

const _accessoryWords = [
  'accessory',
  'accessories',
  'bag',
  'scarf',
  'hat',
  'belt',
  'jewelry',
  'jewellery',
  'tie',
  'watch',
  'glasses',
  'sunglasses',
];

const _layerWords = [
  'layer',
  'layers',
  'outerwear',
  'jacket',
  'coat',
  'blazer',
  'cardigan',
  'parka',
  'raincoat',
];

const _bottomWords = [
  'bottom',
  'bottoms',
  'pants',
  'trousers',
  'jeans',
  'shorts',
  'skirt',
  'skirts',
  'leggings',
  'joggers',
];

const _topWords = [
  'top',
  'tops',
  'shirt',
  'shirts',
  'blouse',
  'blouses',
  'tee',
  't shirt',
  'tshirt',
  'tank',
  'camisole',
  'sweater',
  'knitwear',
  'hoodie',
  'sweatshirt',
];

const _knownColors = [
  'black',
  'white',
  'gray',
  'grey',
  'charcoal',
  'beige',
  'cream',
  'ivory',
  'tan',
  'camel',
  'brown',
  'navy',
  'blue',
  'teal',
  'green',
  'olive',
  'red',
  'burgundy',
  'pink',
  'purple',
  'lavender',
  'yellow',
  'gold',
  'orange',
  'rust',
];

const _neutralColors = {
  'black',
  'white',
  'gray',
  'grey',
  'charcoal',
  'beige',
  'cream',
  'ivory',
  'tan',
  'camel',
  'brown',
  'navy',
};

const _complementaryColors = {
  'red': 'green',
  'blue': 'orange',
  'yellow': 'purple',
  'pink': 'olive',
  'teal': 'rust',
};
