import 'package:flutter/material.dart';

/// Lightweight, high-performance sparkline chart for Enterprise KPI cards.
/// Renders a smooth cubic bezier trend line with an optional subtle gradient fill.
class MiniSparklineChart extends StatelessWidget {
  final List<double> data;
  final Color lineColor;
  final Color? fillColor;
  final double strokeWidth;
  final bool showDot;
  final double height;
  final double width;

  const MiniSparklineChart({
    super.key,
    required this.data,
    required this.lineColor,
    this.fillColor,
    this.strokeWidth = 2.0,
    this.showDot = true,
    this.height = 36,
    this.width = 80,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height, width: width);

    return SizedBox(
      height: height,
      width: width,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          lineColor: lineColor,
          fillColor: fillColor ?? lineColor.withValues(alpha: 0.12),
          strokeWidth: strokeWidth,
          showDot: showDot,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color fillColor;
  final double strokeWidth;
  final bool showDot;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.fillColor,
    required this.strokeWidth,
    required this.showDot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final double minVal = data.reduce((a, b) => a < b ? a : b);
    final double maxVal = data.reduce((a, b) => a > b ? a : b);
    final double range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;

    final double stepX = size.width / (data.length - 1);
    final double paddingY = strokeWidth * 1.5;
    final double usableHeight = size.height - (paddingY * 2);

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final double x = i * stepX;
      final double normalized = (data[i] - minVal) / range;
      // Invert Y because canvas Y=0 is at top
      final double y = size.height - paddingY - (normalized * usableHeight);
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p1.dx,
        p1.dy,
      );
    }

    // Gradient fill under curve
    final fillPath = Path.from(path);
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.lineTo(points.first.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fillColor,
          fillColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Latest data point indicator dot
    if (showDot) {
      final lastPoint = points.last;
      // Outer glow
      final glowPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(lastPoint, strokeWidth * 2.2, glowPaint);

      // Core solid dot
      final dotPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(lastPoint, strokeWidth * 1.3, dotPaint);

      // Inner white center
      final centerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(lastPoint, strokeWidth * 0.6, centerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
