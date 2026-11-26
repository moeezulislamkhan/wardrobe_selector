import 'dart:typed_data';

class ClothingImageAnalysis {
  const ClothingImageAnalysis({
    required this.category,
    this.subcategory,
    this.colorLabels = const [],
    this.styleTags = const [],
  });

  final String category;
  final String? subcategory;
  final List<String> colorLabels;
  final List<String> styleTags;
}

class WardrobeAiContextItem {
  const WardrobeAiContextItem({
    required this.id,
    required this.title,
    required this.category,
    this.colors = const [],
    this.styleTags = const [],
  });

  final String id;
  final String title;
  final String category;
  final List<String> colors;
  final List<String> styleTags;
}

enum StylistMessageRole { user, assistant }

class StylistMessage {
  const StylistMessage({required this.role, required this.content});

  final StylistMessageRole role;
  final String content;
}

class StylistReply {
  const StylistReply({
    required this.message,
    this.referencedItemIds = const [],
  });

  final String message;
  final List<String> referencedItemIds;
}

class PersonalizedAdviceRequest {
  const PersonalizedAdviceRequest({
    required this.wardrobe,
    this.preferredColors = const [],
    this.preferredCategories = const [],
    this.styleTags = const [],
    this.occasion,
    this.season,
  });

  final List<WardrobeAiContextItem> wardrobe;
  final List<String> preferredColors;
  final List<String> preferredCategories;
  final List<String> styleTags;
  final String? occasion;
  final String? season;
}

class PersonalizedAdvice {
  const PersonalizedAdvice({
    required this.suggestions,
    this.referencedItemIds = const [],
  });

  final List<String> suggestions;
  final List<String> referencedItemIds;
}

/// Boundary for future AI features; no provider implementation is included.
///
/// Any network implementation must call a trusted backend such as a Supabase
/// Edge Function. Flutter clients must never call an AI provider directly or
/// contain provider API secrets.
abstract interface class WardrobeAiGateway {
  Future<ClothingImageAnalysis> analyzeClothingImage(Uint8List imageBytes);

  Future<StylistReply> replyToStylist({
    required List<StylistMessage> conversation,
    required List<WardrobeAiContextItem> wardrobe,
  });

  Future<PersonalizedAdvice> getPersonalizedAdvice(
    PersonalizedAdviceRequest request,
  );
}
