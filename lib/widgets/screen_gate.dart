import 'package:flutter/material.dart';
import '../models/user_session_notifier.dart';
import '../models/stock_role.dart';
import '../services/data_repository.dart';
import '../screens/permission_denied_screen.dart';

/// A reactive wrapper that enforces screen-level access control.
///
/// It listens to [UserSessionNotifier] and [DataRepository.salesOnlyModeNotifier],
/// automatically replacing [child] with [PermissionDeniedScreen] if the current user
/// loses permission at runtime or if global Restricted Sales Mode is active.
class ScreenGate extends StatelessWidget {
  /// A function that returns true if the user has access to this screen.
  /// Example: `(s) => s.canAccessReports`
  final bool Function(PermissionSnapshot) canAccess;

  /// The human-readable name of the screen for the denial message.
  final String screenName;

  /// The protected screen content.
  final Widget child;

  /// Allowed screen identifiers when Restricted Sales Mode is ON.
  static const Set<String> _salesOnlyAllowedScreens = {
    'quotation',
    'netrate calc',
    'calculator',
    'sample rate',
    'sales document center',
    'sales docs',
  };

  const ScreenGate({
    super.key,
    required this.canAccess,
    required this.screenName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DataRepository.salesOnlyModeNotifier,
      builder: (context, isSalesOnly, _) {
        return ValueListenableBuilder<PermissionSnapshot>(
          valueListenable: UserSessionNotifier.instance,
          builder: (context, snapshot, _) {
            // If global Restricted Sales Mode is ON, lock all non-Super-Admin users
            // out of everything except the 4 allowed sales modules.
            if (isSalesOnly && !UserSession.isSuperAdmin) {
              final normalizedName = screenName.toLowerCase().trim();
              final isAllowed = _salesOnlyAllowedScreens.contains(normalizedName);
              if (!isAllowed) {
                return PermissionDeniedScreen(screenName: screenName);
              }
            }

            if (!canAccess(snapshot)) {
              return PermissionDeniedScreen(screenName: screenName);
            }
            return child;
          },
        );
      },
    );
  }
}
