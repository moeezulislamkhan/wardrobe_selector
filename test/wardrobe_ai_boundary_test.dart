import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_recommender_app/features/ai/data/wardrobe_ai_provider.dart';
import 'package:wardrobe_recommender_app/features/outfits/domain/rule_based_outfit_engine.dart';

void main() {
  test('AI is unavailable by default and outfit suggestions stay local', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(wardrobeAiGatewayProvider), isNull);

    final result = const RuleBasedOutfitEngine().generate(const [
      OutfitItem(id: 'shirt', title: 'Blue shirt', category: 'Tops'),
      OutfitItem(id: 'jeans', title: 'Black jeans', category: 'Bottoms'),
      OutfitItem(id: 'shoes', title: 'White sneakers', category: 'Shoes'),
    ]);

    expect(result.suggestions, isNotEmpty);
    expect(
      result.suggestions.single.items.map((item) => item.id),
      containsAll(['shirt', 'jeans', 'shoes']),
    );
  });
}
