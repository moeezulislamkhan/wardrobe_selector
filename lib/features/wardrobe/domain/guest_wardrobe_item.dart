import 'package:flutter/foundation.dart';

@immutable
class GuestWardrobeItem {
  const GuestWardrobeItem({
    required this.localId,
    String? title,
    String? name,
    required this.category,
    required this.createdAt,
    this.subcategory,
    String? primaryColor,
    String? color,
    this.secondaryColor,
    this.brand,
    this.size,
    this.notes,
    this.localImagePath,
    this.imageContentType,
    this.occasion,
    this.occasions = const [],
    this.season,
    this.seasons = const [],
    this.styleTags = const [],
    this.isFavorite = false,
    this.isArchived = false,
    this.needsCloudSync = false,
    this.cloudSyncError,
  }) : title = title ?? name ?? '',
       primaryColor = primaryColor ?? color;

  final String localId;
  final String title;
  String get name => title;
  final String category;
  final String? subcategory;
  final DateTime createdAt;
  final String? primaryColor;
  String? get color => primaryColor;
  final String? secondaryColor;
  final String? brand;
  final String? size;
  final String? notes;
  final String? localImagePath;
  final String? imageContentType;
  final String? occasion;
  final List<String> occasions;
  final String? season;
  final List<String> seasons;
  final List<String> styleTags;
  final bool isFavorite;
  final bool isArchived;
  final bool needsCloudSync;
  final String? cloudSyncError;

  List<String> get occasionValues => _valuesFor(occasion, occasions);
  List<String> get seasonValues => _valuesFor(season, seasons);

  GuestWardrobeItem copyWith({
    String? localImagePath,
    String? imageContentType,
    bool? isFavorite,
    bool? isArchived,
    bool? needsCloudSync,
    String? cloudSyncError,
    bool clearCloudSyncError = false,
  }) {
    return GuestWardrobeItem(
      localId: localId,
      title: title,
      category: category,
      subcategory: subcategory,
      createdAt: createdAt,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      brand: brand,
      size: size,
      notes: notes,
      localImagePath: localImagePath ?? this.localImagePath,
      imageContentType: imageContentType ?? this.imageContentType,
      occasion: occasion,
      occasions: occasions,
      season: season,
      seasons: seasons,
      styleTags: styleTags,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      needsCloudSync: needsCloudSync ?? this.needsCloudSync,
      cloudSyncError: clearCloudSyncError
          ? null
          : cloudSyncError ?? this.cloudSyncError,
    );
  }

  Map<String, Object?> toJson() => {
    'localId': localId,
    'title': title,
    'name': title,
    'category': category,
    'subcategory': subcategory,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'primaryColor': primaryColor,
    'color': primaryColor,
    'secondaryColor': secondaryColor,
    'brand': brand,
    'size': size,
    'notes': notes,
    'localImagePath': localImagePath,
    'imageContentType': imageContentType,
    'occasion': occasion,
    'occasions': occasions,
    'season': season,
    'seasons': seasons,
    'styleTags': styleTags,
    'isFavorite': isFavorite,
    'isArchived': isArchived,
    'needsCloudSync': needsCloudSync,
    'cloudSyncError': cloudSyncError,
  };

  factory GuestWardrobeItem.fromJson(Map<String, Object?> json) {
    final createdAtValue = json['createdAt'];
    final createdAt = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)
        : null;
    if (createdAt == null) {
      throw const FormatException('Wardrobe item has an invalid createdAt.');
    }

    return GuestWardrobeItem(
      localId: _requiredString(json, 'localId'),
      title: json['title'] is String
          ? _requiredString(json, 'title')
          : _requiredString(json, 'name'),
      category: _requiredString(json, 'category'),
      subcategory: _optionalString(json, 'subcategory'),
      createdAt: createdAt,
      primaryColor:
          _optionalString(json, 'primaryColor') ?? _optionalString(json, 'color'),
      secondaryColor: _optionalString(json, 'secondaryColor'),
      brand: _optionalString(json, 'brand'),
      size: _optionalString(json, 'size'),
      notes: _optionalString(json, 'notes'),
      localImagePath: _optionalString(json, 'localImagePath'),
      imageContentType: _optionalString(json, 'imageContentType'),
      occasion: _optionalString(json, 'occasion'),
      occasions: _stringList(json, 'occasions'),
      season: _optionalString(json, 'season'),
      seasons: _stringList(json, 'seasons'),
      styleTags: _stringList(json, 'styleTags'),
      isFavorite: _optionalBool(json, 'isFavorite'),
      isArchived: _optionalBool(json, 'isArchived'),
      needsCloudSync: _optionalBool(json, 'needsCloudSync'),
      cloudSyncError: _optionalString(json, 'cloudSyncError'),
    );
  }

  static List<String> _valuesFor(String? primary, List<String> legacyValues) {
    final values = <String>{};
    if (primary != null && primary.trim().isNotEmpty) values.add(primary);
    values.addAll(legacyValues.where((value) => value.trim().isNotEmpty));
    return List<String>.unmodifiable(values);
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Wardrobe item has an invalid $key.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Wardrobe item has an invalid $key.');
    }
    return value;
  }

  static List<String> _stringList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List || value.any((element) => element is! String)) {
      throw FormatException('Wardrobe item has an invalid $key.');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  static bool _optionalBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return false;
    if (value is! bool) {
      throw FormatException('Wardrobe item has an invalid $key.');
    }
    return value;
  }
}
