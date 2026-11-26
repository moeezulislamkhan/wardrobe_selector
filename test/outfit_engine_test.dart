import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_recommender_app/features/outfits/domain/rule_based_outfit_engine.dart';

void main() {
  const engine = RuleBasedOutfitEngine();

  test(
    'generates up to four complete outfits only from active wardrobe items',
    () {
      final wardrobe = [
        _item('top-1', 'Blue shirt', 'Tops', color: 'blue'),
        _item('top-2', 'White tee', 'Tops', color: 'white'),
        _item('bottom-1', 'Black jeans', 'Bottoms', color: 'black'),
        _item('bottom-2', 'Beige trousers', 'Bottoms', color: 'beige'),
        _item('shoe-1', 'Black sneakers', 'Shoes', color: 'black'),
        _item('shoe-2', 'White flats', 'Shoes', color: 'white'),
        _item('layer-1', 'Navy jacket', 'Outerwear', color: 'navy'),
        _item('accessory-1', 'Cream scarf', 'Accessories', color: 'cream'),
        _item('archived-top', 'Archived top', 'Tops', isArchived: true),
        _item('deleted-shoes', 'Deleted shoes', 'Shoes', isDeleted: true),
      ];

      final result = engine.generate(wardrobe);
      final activeIds = wardrobe
          .where((item) => !item.isArchived && !item.isDeleted)
          .map((item) => item.id)
          .toSet();

      expect(result.suggestions, hasLength(4));
      expect(result.fallbackExplanation, isNull);
      for (final suggestion in result.suggestions) {
        expect(suggestion.top.id, startsWith('top-'));
        expect(suggestion.bottom.id, startsWith('bottom-'));
        expect(suggestion.shoes.id, startsWith('shoe-'));
        expect(
          suggestion.items.every((item) => activeIds.contains(item.id)),
          isTrue,
        );
        expect(suggestion.layer?.id, 'layer-1');
        expect(suggestion.accessory?.id, 'accessory-1');
        expect(suggestion.reasons, isNotEmpty);
      }
      expect(
        result.suggestions
            .map(
              (outfit) =>
                  '${outfit.top.id}|${outfit.bottom.id}|${outfit.shoes.id}',
            )
            .toSet(),
        hasLength(4),
      );
    },
  );

  test('explains which required categories are missing', () {
    final result = engine.generate([
      _item('top-1', 'Blue shirt', 'Tops'),
      _item('bottom-1', 'Black jeans', 'Bottoms'),
      _item('archived-shoe', 'Old shoes', 'Shoes', isArchived: true),
    ]);

    expect(result.suggestions, isEmpty);
    expect(result.fallbackExplanation, contains('shoes'));
  });

  test('occasion, season, preferences, and recent wear affect ranking', () {
    final wardrobe = [
      _item(
        'navy-top',
        'Navy shirt',
        'Tops',
        color: 'navy',
        occasions: const ['Work'],
        seasons: const ['Winter'],
      ),
      _item(
        'blue-top',
        'Blue blouse',
        'Tops',
        color: 'blue',
        occasions: const ['Work'],
        seasons: const ['Winter'],
      ),
      _item(
        'black-bottom',
        'Black trousers',
        'Bottoms',
        color: 'black',
        occasions: const ['Work'],
        seasons: const ['Winter'],
      ),
      _item(
        'black-shoes',
        'Black flats',
        'Shoes',
        color: 'black',
        occasions: const ['Work'],
        seasons: const ['Winter'],
      ),
    ];
    final now = DateTime.utc(2026, 11, 26);
    final request = OutfitRequest(
      occasion: 'Work',
      season: 'Winter',
      preferences: const OutfitPreferences(preferredColors: ['blue']),
      now: now,
    );

    final withoutRecentWear = engine.generate(wardrobe, request: request);
    final withRecentWear = engine.generate(
      wardrobe,
      request: OutfitRequest(
        occasion: request.occasion,
        season: request.season,
        preferences: request.preferences,
        lastWornAt: {'blue-top': now.subtract(const Duration(days: 1))},
        now: now,
      ),
    );

    expect(withoutRecentWear.suggestions.first.top.id, 'blue-top');
    expect(withRecentWear.suggestions.first.top.id, 'navy-top');
    expect(
      withRecentWear.suggestions.first.reasons,
      contains('Fits your Work occasion'),
    );
    expect(
      withRecentWear.suggestions.first.reasons,
      contains('Includes Winter-season pieces'),
    );
    expect(
      withRecentWear.suggestions.first.reasons,
      contains('Avoids recently worn pieces'),
    );
  });

  test('cold rainy weather selects useful layers and explains the choice', () {
    final result = engine.generate(
      [
        _item('top-1', 'Cotton tee', 'Tops'),
        _item('bottom-1', 'Jeans', 'Bottoms'),
        _item('shoe-1', 'Sandals', 'Shoes'),
        _item(
          'layer-1',
          'Waterproof rain jacket',
          'Outerwear',
          seasons: const ['Winter'],
        ),
        _item('accessory-1', 'Wool scarf', 'Accessories'),
      ],
      request: const OutfitRequest(
        weather: OutfitWeather(temperatureC: 5, rainy: true),
      ),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.layer?.id, 'layer-1');
    expect(result.suggestions.single.accessory?.id, 'accessory-1');
    expect(
      result.suggestions.single.reasons,
      contains('Adds a layer for cool weather'),
    );
    expect(result.fallbackExplanation, contains('Only 1 complete combination'));
  });
}

OutfitItem _item(
  String id,
  String title,
  String category, {
  String? color,
  List<String> occasions = const [],
  List<String> seasons = const [],
  bool isFavorite = false,
  bool isArchived = false,
  bool isDeleted = false,
}) {
  return OutfitItem(
    id: id,
    title: title,
    category: category,
    primaryColor: color,
    occasions: occasions,
    seasons: seasons,
    isFavorite: isFavorite,
    isArchived: isArchived,
    isDeleted: isDeleted,
  );
}
