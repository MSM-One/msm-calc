import 'package:flutter/material.dart';
import '../services/access_guard.dart';

/// A reusable gating widget that conditionally shows or hides its [child]
/// based on whether the current user has the given [permission].
///
/// Usage:
/// ```dart
/// FeatureGate(
///   permission: Permissions.stockIn,
///   child: StockInButton(),
/// )
/// ```
///
/// Set [disableInstead] to `true` to render the child in a dimmed,
/// non-interactive state instead of hiding it entirely.
class FeatureGate extends StatelessWidget {
  const FeatureGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.disableInstead = false,
    this.location,
  });

  final String permission;
  final Widget child;

  /// Widget shown when access is denied. Defaults to [SizedBox.shrink].
  final Widget? fallback;

  /// If `true`, shows the child but dims and blocks interaction.
  final bool disableInstead;

  /// Optional location string for scope-based permission validation.
  final String? location;

  @override
  Widget build(BuildContext context) {
    final allowed = AccessGuard.can(permission, location: location);

    if (allowed) return child;

    if (disableInstead) {
      return IgnorePointer(
        child: Opacity(opacity: 0.35, child: child),
      );
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Wraps a [ListTile] or similar widget and disables it if the user
/// does not have the given permission. Shows a lock icon as a trailing hint.
class GatedListTile extends StatelessWidget {
  const GatedListTile({
    super.key,
    required this.permission,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
  });

  final String permission;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final allowed = AccessGuard.can(permission);
    return ListTile(
      leading: leading,
      title: allowed ? title : Opacity(opacity: 0.45, child: title),
      subtitle: subtitle,
      enabled: allowed,
      onTap: allowed ? onTap : null,
      trailing: allowed
          ? null
          : Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
    );
  }
}
