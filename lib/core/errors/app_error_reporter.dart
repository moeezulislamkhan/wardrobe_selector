import 'package:flutter/foundation.dart';

class AppErrorReporter {
  AppErrorReporter._();

  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return false;
    };
  }

  static void report(Object error, StackTrace? stackTrace) {
    debugPrint('Unhandled application error: $error');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
