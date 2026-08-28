import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'motion_toast.dart';

// ✅ GLOBAL KEYBOARD & BACK HANDLER
class GlobalViewWrapper extends StatefulWidget {
  final Widget child;
  const GlobalViewWrapper({super.key, required this.child});

  @override
  State<GlobalViewWrapper> createState() => _GlobalViewWrapperState();
}

class _GlobalViewWrapperState extends State<GlobalViewWrapper> {
  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: [GlobalViewWrapper] Building (SIMPLIFIED)');
    return widget.child;
  }
}

// ✅ GLOBAL HELPERS FOR SHARING
Future<void> safeShare(BuildContext context, String text,
    {String? subject}) async {
  try {
    debugPrint(
        "Sharing content: ${text.substring(0, text.length > 50 ? 50 : text.length)}...");
    await Share.share(text, subject: subject);
  } catch (e) {
    debugPrint("Share Error: $e");
    if (context.mounted) {
      MotionToast.show(context, "Error sharing: $e", isError: true);
    }
  }
}

// ✅ HELPER CLASS FOR UI DEBOUNCING
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }
}
