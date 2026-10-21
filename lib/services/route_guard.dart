import 'package:flutter/material.dart';
import 'access_guard.dart';

/// Enforces navigation-level access control.
///
/// Call [RouteGuard.check] at the top of `initState` in any guarded screen.
/// If the user lacks the required permission, they are redirected to the
/// [AccessRevokedScreen] and cannot access the route through deep links or
/// cached navigation stacks.
///
/// Usage:
/// ```dart
/// @override
/// void initState() {
///   super.initState();
///   RouteGuard.check(context, Permissions.reportsView);
/// }
/// ```
class RouteGuard {
  RouteGuard._();

  /// Checks the [permission] for the current user.
  /// If denied, pops the current route and pushes [AccessRevokedScreen].
  ///
  /// Call this in a `WidgetsBinding.instance.addPostFrameCallback` wrap
  /// if called during `initState` to ensure the context is mounted.
  static void check(BuildContext context, String permission) {
    if (!AccessGuard.canNavigate(permission)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context).pushReplacementNamed('/access-revoked');
      });
    }
  }

  /// Same as [check] but can be called synchronously during `initState`.
  /// Returns `true` if access is granted, `false` if blocked.
  static bool checkSync(String permission) =>
      AccessGuard.canNavigate(permission);
}
