import 'package:flutter/material.dart';

import 'app_error.dart';

extension ErrorSnackbar on BuildContext {
  void showAppError(Object error) {
    final message = error is AppError
        ? error.message
        : 'Something went wrong. Please try again.';
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
