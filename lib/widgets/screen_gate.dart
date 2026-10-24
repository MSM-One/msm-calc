import 'package:flutter/material.dart';
import '../models/user_session_notifier.dart';
import '../models/stock_role.dart';
import '../services/data_repository.dart';

/// A reactive wrapper that enforces screen-level access control.
///
/// It listens to [UserSessionNotifier] and [DataRepository.salesOnlyModeNotifier],
/// automatically **silently popping back** if the current user loses permission
/// at runtime or if global Restricted Sales Mode is active.
///
/// Zero-Knowledge Stealth Mode: restricted users never see "Access Denied"
/// screens — they are silently redirected back, as if the route never existed.
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
            // ── Stealth Mode: silently redirect forbidden routes ──────────
            bool denied = false;

            // If global Restricted Sales Mode is ON, lock all non-Super-Admin
            // users out of everything except the allowed sales modules.
            if (isSalesOnly && !UserSession.isSuperAdmin) {
              final normalizedName = screenName.toLowerCase().trim();
              final isAllowed =
                  _salesOnlyAllowedScreens.contains(normalizedName);
              if (!isAllowed) {
                denied = true;
              }
            }

            // Standard permission check
            if (!denied && !canAccess(snapshot)) {
              denied = true;
            }

            if (denied) {
              // Stealth pop: schedule a silent pop-back after this frame.
              // Renders an empty scaffold momentarily to avoid visual flash.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  Navigator.of(context).maybePop();
                }
              });
              return const Scaffold(body: SizedBox.shrink());
            }

            return child;
          },
        );
      },
    );
  }
}
