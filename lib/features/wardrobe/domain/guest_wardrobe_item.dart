import 'package:flutter/foundation.dart';

@immutable
class GuestWardrobeItem {
  const GuestWardrobeItem({
    required this.localId,
    required this.name,
    required this.category,
    required this.createdAt,
    this.color,
    this.brand,
    this.size,
    this.localImagePath,
    this.imageContentType,
    this.occasions = const [],
    this.seasons = const [],
    this.isFavorite = false,
    this.isArchived = false,
  });

  final String localId;
  final String name;
  final String category;
  final DateTime createdAt;
  final String? color;
  final String? brand;
  final String? size;
  final String? localImagePath;
  final String? imageContentType;
  final List<String> occasions;
  final List<String> seasons;
  final bool isFavorite;
  final bool isArchived;

  GuestWardrobeItem copyWith({bool? isFavorite, bool? isArchived}) {
    return GuestWardrobeItem(
      localId: localId,
      name: name,
      category: category,
      createdAt: createdAt,
      color: color,
      brand: brand,
      size: size,
      localImagePath: localImagePath,
      imageContentType: imageContentType,
      occasions: occasions,
      seasons: seasons,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, Object?> toJson() => {
    'localId': localId,
    'name': name,
    'category': category,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'color': color,
    'brand': brand,
    'size': size,
    'localImagePath': localImagePath,
    'imageContentType': imageContentType,
    'occasions': occasions,
    'seasons': seasons,
    'isFavorite': isFavorite,
    'isArchived': isArchived,
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
      name: _requiredString(json, 'name'),
      category: _requiredString(json, 'category'),
      createdAt: createdAt,
      color: _optionalString(json, 'color'),
      brand: _optionalString(json, 'brand'),
      size: _optionalString(json, 'size'),
      localImagePath: _optionalString(json, 'localImagePath'),
      imageContentType: _optionalString(json, 'imageContentType'),
      occasions: _stringList(json, 'occasions'),
      seasons: _stringList(json, 'seasons'),
      isFavorite: _optionalBool(json, 'isFavorite'),
      isArchived: _optionalBool(json, 'isArchived'),
    );
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
