import 'rule_based_outfit_engine.dart';

class ManualOutfit {
  const ManualOutfit({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    required this.needsCloudSync,
  });

  final String id;
  final String name;
  final List<OutfitItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool needsCloudSync;

  OutfitItem? itemFor(OutfitItemRole role) {
    for (final item in items) {
      if (const RuleBasedOutfitEngine().roleOf(item) == role) return item;
    }
    return null;
  }
}
