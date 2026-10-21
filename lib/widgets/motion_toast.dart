import 'dart:async';
import 'package:flutter/material.dart';

class MotionToast {
  static void show(BuildContext context, String message,
      {bool isError = false}) {
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50.0, // Slides down elegantly from the top header tracking area
        left: 20.0,
        right: 20.0,
        child: Material(
          color: Colors.transparent,
          child: MotionMessageWidget(
            message: message,
            isError: isError,
            onDismiss: () {
              overlayEntry.remove();
            },
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlayEntry);
  }
}

class MotionMessageWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const MotionMessageWidget({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<MotionMessageWidget> createState() => _MotionMessageWidgetState();
}

class _MotionMessageWidgetState extends State<MotionMessageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
      reverseCurve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    ));

    _controller.forward();

    // Auto dismiss after 3 seconds
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indicatorColor =
        widget.isError ? Colors.redAccent : const Color(0xFF10B981);

    return GestureDetector(
      onTap: _dismiss,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // Premium dark grey
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Left indicator accent bar
                Container(
                  width: 4.0,
                  height: 24.0,
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
                const SizedBox(width: 12.0),
                // Status icon
                Icon(
                  widget.isError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: indicatorColor,
                  size: 20.0,
                ),
                const SizedBox(width: 12.0),
                // Text Message
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
