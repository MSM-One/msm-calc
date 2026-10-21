import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../screens/registration_screen.dart';

class AuthenticationGuard extends StatelessWidget {
  final Widget child;
  const AuthenticationGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        debugPrint('DEBUG: [AuthGuard] rebuild — '
            'isInitializing=${userProvider.isInitializing}, '
            'user=${userProvider.user?.email ?? "null"}, '
            'child=$child');

        // ── Phase 1: Auth hydration in progress ──────────────────────────────
        // The session hasn't been determined yet (e.g., splash screen is still
        // doing silent sign-in or awaiting handlePostLogin). Return child
        // (Navigator with splash loader).
        if (userProvider.isInitializing) {
          debugPrint('DEBUG: [AuthGuard] → returning child (initializing)');
          return child;
        }

        final user = userProvider.user;

        // ── Phase 2: Authenticated but not approved ───────────────────────────
        // User is loaded in provider but status is not 'approved'.
        // Overlay RegistrationScreen while keeping child (Navigator) mounted.
        if (user != null && !user.isApproved) {
          debugPrint('DEBUG: [AuthGuard] → showing RegistrationScreen overlay');
          return Stack(
            children: [
              Offstage(offstage: true, child: child),
              const RegistrationScreen(),
            ],
          );
        }

        // ── Phase 3: All clear — let the child through ────────────────────────
        debugPrint('DEBUG: [AuthGuard] → returning child (all clear)');
        return child;
      },
    );
  }
}

