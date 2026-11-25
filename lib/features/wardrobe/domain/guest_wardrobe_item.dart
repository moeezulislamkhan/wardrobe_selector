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
}
