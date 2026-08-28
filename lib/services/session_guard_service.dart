import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/stock_role.dart';
import '../services/data_repository.dart';
import '../services/supabase_service.dart';
import '../main.dart' show LoginScreen;
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../models/app_user.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionGuardService
//
// Attaches a Supabase real-time stream on the `users` table filtered to the
// currently-logged-in email.  The moment the row is deleted OR the `status`
// column is changed to anything other than APPROVED, this service:
//   1. Cancels the stream subscription.
//   2. Clears all local session data (SharedPreferences + Google Sign-In).
//   3. Navigates the app to the login screen via the global navigator key.
//
// Usage:
//   Call [SessionGuardService.attach(navigatorKey)] once inside
//   _MainScaffoldState.initState() and [SessionGuardService.detach()] inside
//   dispose().
// ─────────────────────────────────────────────────────────────────────────────
class SessionGuardService {
  SessionGuardService._();

  static StreamSubscription<List<Map<String, dynamic>>>? _sub;
  static bool _isHandlingEviction = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Starts listening.  Safe to call multiple times — re-attaches cleanly.
  static void attach(GlobalKey<NavigatorState> navigatorKey) {
    final email = UserSession.userEmail;
    if (email == null || email.isEmpty) {
      debugPrint('[SessionGuard] No email in session — guard not attached.');
      return;
    }

    // Super-admin account is never evicted by the DB stream.
    if (email == 'j2833945@gmail.com') {
      debugPrint('[SessionGuard] Super-admin bypass — guard not attached.');
      return;
    }

    // Cancel any existing subscription before opening a new one.
    _sub?.cancel();
    _isHandlingEviction = false;

    debugPrint('[SessionGuard] Attaching real-time guard for $email');

    _sub = SupabaseService.client
        .from('users')
        .stream(primaryKey: ['email'])
        .eq('email', email)
        .listen(
          (rows) => _onData(rows, navigatorKey),
          onError: (Object err) {
            // Network blip — log but do NOT evict.  We prefer false-negatives
            // over false-positives (accidentally logging out a valid user).
            debugPrint('[SessionGuard] Stream error (non-fatal): $err');
          },
        );
  }

  /// Cancels the stream subscription.  Call from dispose().
  static void detach() {
    _sub?.cancel();
    _sub = null;
    _isHandlingEviction = false;
    debugPrint('[SessionGuard] Detached.');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  static void _onData(
    List<Map<String, dynamic>> rows,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    if (_isHandlingEviction) return;

    // Deleted row scenario — user was removed from the `users` table entirely.
    if (rows.isEmpty) {
      debugPrint('[SessionGuard] ❌ User row deleted — forcing logout.');
      _evict(
        navigatorKey,
        reason: 'Your account was removed by an administrator.',
      );
      return;
    }

    final row = rows.first;
    final status =
        (row['status']?.toString() ?? 'PENDING').toUpperCase().trim();

    final context = navigatorKey.currentContext;
    if (context != null) {
      try {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        if (userProvider.user != null) {
          final updatedUser = AppUser(
            email: userProvider.user!.email,
            status: status.toLowerCase(),
            role: row['role']?.toString() ?? userProvider.user!.role,
            allowedActions: userProvider.user!.allowedActions,
          );
          userProvider.setUser(updatedUser);
        }
      } catch (e) {
        debugPrint('[SessionGuard] UserProvider update error: $e');
      }
    }

    if (status != 'APPROVED') {
      debugPrint(
          '[SessionGuard] ❌ Status changed to "$status" — forcing logout.');
      final message = switch (status) {
        'PENDING' => 'Your account is pending administrator approval.',
        'REJECTED' => 'Your account access was rejected by an administrator.',
        'HOLD' => 'Your account has been placed on hold. Contact management.',
        _ => 'Your account status changed to "$status". Contact admin.',
      };
      _evict(navigatorKey, reason: message);
    }
    // else: status == APPROVED — session is healthy, nothing to do.
  }

  static void _evict(
    GlobalKey<NavigatorState> navigatorKey, {
    required String reason,
  }) async {
    if (_isHandlingEviction) return;
    _isHandlingEviction = true;

    final context = navigatorKey.currentContext;

    // 1. Cancel stream immediately to prevent duplicate firings.
    await _sub?.cancel();
    _sub = null;

    // 2. Clear all local session data.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_logged_in');
      await prefs.remove('user_email');
      await prefs.remove('user_display_name');
      await prefs.remove('user_phone_number');
      await prefs.remove('currentUser');
      await prefs.remove('cached_auth_token');
    } catch (e) {
      debugPrint('[SessionGuard] Prefs clear error: $e');
    }

    // 3. Clear in-memory user state.
    try {
      DataRepository.currentUserNotifier.value = null;
      UserSession.userEmail = null;
      UserSession.currentRole = StockRole.VIEWER;
      UserSession.roleId = 'staff';
      UserSession.customPermissions = {};

      if (context != null && context.mounted) {
        Provider.of<UserProvider>(context, listen: false).clearUser();
      }
    } catch (e) {
      debugPrint('[SessionGuard] UserSession clear error: $e');
    }

    // 4. Sign out of Google.
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('[SessionGuard] Google sign-out error (non-fatal): $e');
    }

    // 5. Navigate to login — remove ALL routes.
    if (context == null || !navigatorKey.currentState!.mounted) {
      debugPrint(
          '[SessionGuard] Navigator context unavailable — cannot redirect.');
      _isHandlingEviction = false;
      return;
    }

    navigatorKey.currentState!.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const _LoginScreenProxy()),
      (route) => false,
    );

    // 6. After navigation, show a toast-like dialog explaining why.
    //    We do this post-frame to ensure the new route has settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newContext = navigatorKey.currentContext;
      if (newContext == null) return;
      _showEvictionDialog(newContext, reason);
      _isHandlingEviction = false;
    });
  }

  static void _showEvictionDialog(BuildContext context, String reason) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFFEE2E2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.security_rounded,
            color: Color(0xFFDC2626),
            size: 32,
          ),
        ),
        title: const Text(
          'Session Terminated',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          reason,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            height: 1.5,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFED1C24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text(
              'OK',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thin proxy so we can reference LoginScreen without coupling imports further.
// ---------------------------------------------------------------------------
class _LoginScreenProxy extends StatelessWidget {
  const _LoginScreenProxy();

  @override
  Widget build(BuildContext context) => const LoginScreen();
}
