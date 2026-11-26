import 'rule_based_outfit_engine.dart';

enum OutfitPlanSyncState { pending, syncing, synced, failed }

enum OutfitPlanStatus { planned, worn, skipped, modified }

class OutfitPlan {
  const OutfitPlan({
    required this.id,
    required this.plannedFor,
    required this.occasion,
    required this.outfitName,
    required this.items,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.syncState,
    this.syncError,
  });

  final String id;
  final DateTime plannedFor;
  final String occasion;
  final String outfitName;
  final List<OutfitItem> items;
  final OutfitPlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final OutfitPlanSyncState syncState;
  final String? syncError;

  OutfitPlan copyWith({
    String? occasion,
    String? outfitName,
    List<OutfitItem>? items,
    OutfitPlanStatus? status,
    DateTime? updatedAt,
    OutfitPlanSyncState? syncState,
    String? syncError,
  }) => OutfitPlan(
    id: id,
    plannedFor: plannedFor,
    occasion: occasion ?? this.occasion,
    outfitName: outfitName ?? this.outfitName,
    items: items ?? this.items,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncState: syncState ?? this.syncState,
    syncError: syncError,
  );

  factory OutfitPlan.fromJson(Map<String, Object?> json) => OutfitPlan(
    id: _stringValue(json, 'id'),
    plannedFor: DateTime.parse(_stringValue(json, 'plannedFor')),
    occasion: _stringValue(json, 'occasion'),
    outfitName: _stringValue(json, 'outfitName'),
    items: List.unmodifiable(
      (_listValue(json, 'items')).map(
        (value) => _outfitItemFromJson(Map<String, Object?>.from(value as Map)),
      ),
    ),
    status: json['status'] is String
        ? OutfitPlanStatus.values.byName(json['status']! as String)
        : OutfitPlanStatus.planned,
    createdAt: DateTime.parse(_stringValue(json, 'createdAt')),
    updatedAt: DateTime.parse(_stringValue(json, 'updatedAt')),
    syncState: OutfitPlanSyncState.values.byName(
      _stringValue(json, 'syncState'),
    ),
    syncError: _optionalStringValue(json, 'syncError'),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'plannedFor': planDateKey(plannedFor),
    'occasion': occasion,
    'outfitName': outfitName,
    'items': items.map(_outfitItemToJson).toList(),
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'syncState': syncState.name,
    'syncError': syncError,
  };
}

class OutfitPlanHistoryEntry {
  const OutfitPlanHistoryEntry({
    required this.id,
    required this.planId,
    required this.plannedFor,
    required this.status,
    required this.occasion,
    required this.outfitName,
    required this.items,
    required this.recordedAt,
  });

  final String id;
  final String planId;
  final DateTime plannedFor;
  final OutfitPlanStatus status;
  final String occasion;
  final String outfitName;
  final List<OutfitItem> items;
  final DateTime recordedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'planId': planId,
    'plannedFor': planDateKey(plannedFor),
    'status': status.name,
    'occasion': occasion,
    'outfitName': outfitName,
    'items': items.map(_outfitItemToJson).toList(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> toCloudRow(String userId) => {
    'id': id,
    'plan_id': planId,
    'user_id': userId,
    'planned_for': DateTime.utc(
      plannedFor.year,
      plannedFor.month,
      plannedFor.day,
    ).toIso8601String(),
    'status': status.name,
    'occasion': occasion,
    'outfit_name': outfitName,
    'item_snapshot': items.map(_outfitItemToJson).toList(),
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };

  factory OutfitPlanHistoryEntry.fromJson(Map<String, Object?> json) =>
      OutfitPlanHistoryEntry(
        id: _stringValue(json, 'id'),
        planId: _stringValue(json, 'planId'),
        plannedFor: DateTime.parse(_stringValue(json, 'plannedFor')),
        status: OutfitPlanStatus.values.byName(_stringValue(json, 'status')),
        occasion: _stringValue(json, 'occasion'),
        outfitName: _stringValue(json, 'outfitName'),
        items: List.unmodifiable(
          _listValue(json, 'items').map(
            (value) => _outfitItemFromJson(
              Map<String, Object?>.from(value as Map),
            ),
          ),
        ),
        recordedAt: DateTime.parse(_stringValue(json, 'recordedAt')),
      );
}

String planDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime nextWeekMonday(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final daysUntilMonday = (DateTime.monday - today.weekday + 7) % 7;
  return today.add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
}

Map<String, Object?> _outfitItemToJson(OutfitItem item) => {
  'id': item.id,
  'title': item.title,
  'category': item.category,
  'subcategory': item.subcategory,
  'imagePath': item.imagePath,
  'primaryColor': item.primaryColor,
  'secondaryColor': item.secondaryColor,
  'occasions': item.occasions,
  'seasons': item.seasons,
  'styleTags': item.styleTags,
};

OutfitItem _outfitItemFromJson(Map<String, Object?> json) => OutfitItem(
  id: _stringValue(json, 'id'),
  title: _stringValue(json, 'title'),
  category: _stringValue(json, 'category'),
  subcategory: _optionalStringValue(json, 'subcategory'),
  imagePath: _optionalStringValue(json, 'imagePath'),
  primaryColor: _optionalStringValue(json, 'primaryColor'),
  secondaryColor: _optionalStringValue(json, 'secondaryColor'),
  occasions: _stringListValue(json, 'occasions'),
  seasons: _stringListValue(json, 'seasons'),
  styleTags: _stringListValue(json, 'styleTags'),
);

String _stringValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Outfit plan has an invalid $key.');
  }
  return value;
}

String? _optionalStringValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Outfit plan has an invalid $key.');
  }
  return value;
}

List<Object?> _listValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((element) => element is! Map)) {
    throw FormatException('Outfit plan has invalid $key data.');
  }
  return value.cast<Object?>();
}

List<String> _stringListValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((element) => element is! String)) {
    throw FormatException('Outfit plan has invalid $key data.');
  }
  return List.unmodifiable(value.cast<String>());
}
