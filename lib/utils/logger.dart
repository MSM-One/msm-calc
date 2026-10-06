// lib/utils/logger.dart
import 'package:flutter/foundation.dart';

class Logger {
  static void d(Object? message) {
    if (kDebugMode) {
      // Using print for simplicity; can swap to package:logger later.
      print(message);
    }
  }
}
