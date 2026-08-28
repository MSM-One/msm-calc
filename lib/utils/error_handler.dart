import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/motion_toast.dart';

class ErrorHandler {
  static void showError(BuildContext context, dynamic error) {
    String message = _parseError(error);

    // Only show if context is still valid
    if (context.mounted) {
      MotionToast.show(context, message, isError: true);
    }
  }

  static String _parseError(dynamic error) {
    if (error is TimeoutException) {
      return "Connection timed out. Please check your internet connection.";
    } else if (error is SocketException) {
      return "No Internet Connection. Please connect to Wi-Fi or Mobile Data.";
    } else if (error is FormatException) {
      return "Data error. The server returned an invalid response.";
    } else if (error is String) {
      return error;
    } else {
      return "An unexpected error occurred: ${error.toString()}";
    }
  }
}
