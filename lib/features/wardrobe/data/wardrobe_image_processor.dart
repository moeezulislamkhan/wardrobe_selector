import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../core/errors/app_error.dart';

final wardrobeImageProcessorProvider = Provider<WardrobeImageProcessor>(
  (ref) => const WardrobeImageProcessor(),
);

class WardrobeImageProcessor {
  const WardrobeImageProcessor();

  static const maxInputBytes = 30 * 1024 * 1024;
  static const maxOutputBytes = 3 * 1024 * 1024;
  static const maxDimension = 1800;

  Future<Uint8List> compress(Uint8List input) async {
    if (input.isEmpty) {
      throw const AppError('The selected photo is empty.');
    }
    if (input.length > maxInputBytes) {
      throw const AppError('Choose a photo smaller than 30 MB.');
    }

    late final Uint8List output;
    try {
      output = await compute<Uint8List, Uint8List>(_compressImage, input);
    } on Exception catch (error) {
      throw AppError(
        'The selected photo could not be decoded. Choose a JPEG or PNG image.',
        cause: error,
      );
    }
    if (output.isEmpty || output.length > maxOutputBytes) {
      throw const AppError(
        'The photo could not be compressed to 3 MB or less.',
      );
    }
    return output;
  }
}

Uint8List _compressImage(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('Unsupported image data.');

  final oriented = img.bakeOrientation(decoded);
  final longestSide = math.max(oriented.width, oriented.height);
  final resized = longestSide <= WardrobeImageProcessor.maxDimension
      ? oriented
      : img.copyResize(
          oriented,
          width: (oriented.width *
                  WardrobeImageProcessor.maxDimension /
                  longestSide)
              .round(),
          height: (oriented.height *
                  WardrobeImageProcessor.maxDimension /
                  longestSide)
              .round(),
          interpolation: img.Interpolation.average,
        );

  for (final quality in [82, 68, 54]) {
    final compressed = Uint8List.fromList(
      img.encodeJpg(resized, quality: quality),
    );
    if (compressed.length <= WardrobeImageProcessor.maxOutputBytes) {
      return compressed;
    }
  }
  throw const FormatException('Compressed image exceeded the size limit.');
}
