import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class MLoader extends StatefulWidget {
  final double size;
  final Color? color;
  const MLoader({super.key, this.size = 60, this.color});

  static BuildContext? _loadingContext;

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _loadingContext = ctx;
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const MLoader(size: 50),
          ),
        );
      },
    );
  }

  static void hide() {
    if (_loadingContext != null) {
      Navigator.of(_loadingContext!).pop();
      _loadingContext = null;
    }
  }

  @override
  State<MLoader> createState() => _MLoaderState();
}

class _MLoaderState extends State<MLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _MPainter(
              progress: _controller.value,
              color: widget.color ?? msmRed,
            ),
          ),
        );
      },
    );
  }
}

class _MPainter extends CustomPainter {
  final double progress;
  final Color color;

  _MPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    // Starting point (Bottom Left)
    path.moveTo(size.width * 0.1, size.height * 0.9);
    // Left vertical line
    path.lineTo(size.width * 0.1, size.height * 0.1);
    // Middle "V" part
    path.lineTo(size.width * 0.5, size.height * 0.6);
    path.lineTo(size.width * 0.9, size.height * 0.1);
    // Right vertical line
    path.lineTo(size.width * 0.9, size.height * 0.9);

    // Animate the path drawing
    PathMetrics pathMetrics = path.computeMetrics();
    for (PathMetric pathMetric in pathMetrics) {
      Path extractPath =
          pathMetric.extractPath(0.0, pathMetric.length * progress);
      canvas.drawPath(extractPath, paint);

      // Add a subtle glowing head point
      if (progress > 0 && progress < 1.0) {
        final tangent =
            pathMetric.getTangentForOffset(pathMetric.length * progress);
        if (tangent != null) {
          final pos = tangent.position;
          canvas.drawCircle(
              pos, paint.strokeWidth * 0.6, paint..style = PaintingStyle.fill);
          paint.style =
              PaintingStyle.stroke; // Reset for next iteration or frame
        }
      }
    }

    // Second pass for a subtle pulse/shadow effect
    if (progress > 0.8) {
      final opacity = (progress - 0.8) * 5; // Fade in at the end
      final pulsePaint = Paint()
        ..color = color.withValues(
            alpha: 0.2 * (1.0 - opacity >= 0 ? 1.0 - opacity : 0))
        ..strokeWidth = paint.strokeWidth * 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(_MPainter oldDelegate) => oldDelegate.progress != progress;
}
