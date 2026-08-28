import 'package:flutter/material.dart';
import '../models/user_session_notifier.dart';
import '../screens/permission_denied_screen.dart';

/// A reactive wrapper that enforces screen-level access control.
///
/// It listens to the [UserSessionNotifier] and automatically replaces the [child]
/// with a [PermissionDeniedScreen] if the current user loses access at runtime.
class ScreenGate extends StatelessWidget {
  /// A function that returns true if the user has access to this screen.
  /// Example: `(s) => s.canAccessReports`
  final bool Function(PermissionSnapshot) canAccess;

  /// The human-readable name of the screen for the denial message.
  final String screenName;

  /// The protected screen content.
  final Widget child;

  const ScreenGate({
    super.key,
    required this.canAccess,
    required this.screenName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, snapshot, _) {
        if (!canAccess(snapshot)) {
          return PermissionDeniedScreen(screenName: screenName);
        }
        return child;
      },
    );
  }
}
