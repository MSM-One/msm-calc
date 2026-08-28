import 'package:flutter/material.dart';
import '../models/user_session_notifier.dart';
import '../models/permission_model.dart';
import '../services/access_guard.dart';

/// A reactive widget that shows a numeric/MT value only when the current
/// user has the required permission. Otherwise shows a masked placeholder.
///
/// It automatically rebuilds whenever [UserSessionNotifier] changes,
/// so a permission reset is instantly reflected without hot-restart.
///
/// ### Usage
/// ```dart
/// GuardedMetric(
///   permission: Permissions.inventoryMetricsView,
///   value: '106.918 MT',
/// )
/// ```
class GuardedMetric extends StatelessWidget {
  /// The permission slug to check (use [Permissions] constants).
  final String permission;

  /// The formatted value to display when allowed (e.g. '72.700 MT').
  final String value;

  /// Text style applied to [value] when visible.
  final TextStyle? style;

  /// Text alignment.
  final TextAlign textAlign;

  /// Widget to show instead when access is denied.
  /// Defaults to a lock badge showing '— MT'.
  final Widget? placeholder;

  const GuardedMetric({
    super.key,
    required this.permission,
    required this.value,
    this.style,
    this.textAlign = TextAlign.start,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder ensures rebuild on every permission change.
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, _, __) {
        final allowed = AccessGuard.can(permission);
        if (allowed) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: textAlign == TextAlign.center
                ? Alignment.center
                : (textAlign == TextAlign.end
                    ? Alignment.centerRight
                    : Alignment.centerLeft),
            child: Text(value, style: style, textAlign: textAlign),
          );
        }
        return placeholder ?? _DefaultMask(style: style);
      },
    );
  }
}

/// The default masked placeholder shown when a metric is hidden.
/// Renders a subtle lock + dashed placeholder to indicate restricted data.
class _DefaultMask extends StatelessWidget {
  final TextStyle? style;
  const _DefaultMask({this.style});

  @override
  Widget build(BuildContext context) {
    final fs = style?.fontSize ?? 14.0;
    final color = (style?.color ?? Colors.black).withValues(alpha: 0.25);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded, size: fs * 0.75, color: color),
        const SizedBox(width: 3),
        Text(
          '••••',
          style: (style ?? const TextStyle()).copyWith(
            color: color,
            fontSize: fs,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

/// Convenience wrapper for inline quantity text that should be masked.
/// Wraps [GuardedMetric] with a pre-set text style from the caller.
class GuardedMT extends StatelessWidget {
  final String permission;
  final double mtValue;
  final int decimalPlaces;
  final TextStyle? style;
  final TextAlign textAlign;
  final String unit;

  const GuardedMT({
    super.key,
    required this.permission,
    required this.mtValue,
    this.decimalPlaces = 3,
    this.style,
    this.textAlign = TextAlign.start,
    this.unit = ' MT',
  });

  @override
  Widget build(BuildContext context) {
    final formatted = '${mtValue.toStringAsFixed(decimalPlaces)}$unit';
    return GuardedMetric(
      permission: permission,
      value: formatted,
      style: style,
      textAlign: textAlign,
    );
  }
}
