import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../providers/user_provider.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    // Safety net: if initialization takes too long, force navigate to Login
    Future.delayed(const Duration(seconds: 10), () {
      if (!_navigated) {
        _navigateToLogin(reason: 'safety timeout');
      }
    });
  }

  /// Safely navigate to LoginScreen inside post-frame callback
  void _navigateToLogin({String reason = ''}) {
    if (_navigated) return;
    _navigated = true;
    debugPrint('DEBUG: [Splash] _navigateToLogin called ($reason)');

    if (mounted) {
      Provider.of<UserProvider>(context, listen: false).markInitialized();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (appNavigatorKey.currentState != null) {
        debugPrint('DEBUG: [Splash] PostFrameCallback — pushing LoginScreen');
        appNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  /// Safely navigate to authenticated dashboard inside post-frame callback
  void _navigateToDashboard(String email) {
    if (_navigated) return;
    _navigated = true;
    debugPrint('DEBUG: [Splash] _navigateToDashboard called for $email');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = appNavigatorKey.currentContext ?? context;
      if (ctx.mounted) {
        try {
          await AuthService.handlePostLogin(ctx, email);
        } catch (e) {
          debugPrint('DEBUG: [Splash] PostLogin error ($e) — falling back to Login');
          _navigated = false;
          _navigateToLogin(reason: 'post-login failed');
        }
      }
    });
  }

  Future<void> _initializeApp() async {
    debugPrint('DEBUG: [Splash] _initializeApp started');

    // Kick off network sync in background without blocking
    unawaited(DataRepository.syncSheetData(null).catchError((e) {
      debugPrint('DEBUG: [Splash] Background sync error: $e');
    }));

    // Splash display timer
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // 1. Check silent sign-in via Google
    GoogleSignInAccount? account = AuthService.googleSignIn.currentUser;
    if (account == null) {
      try {
        account = await AuthService.googleSignIn
            .signInSilently()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        debugPrint(
            'DEBUG: [Splash] Silent sign-in result: account=${account?.email}');
      } catch (e) {
        debugPrint('DEBUG: [Splash] Silent sign-in error: $e');
      }
    }

    // 2. Read local session preferences
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final storedEmail = prefs.getString('user_email') ?? "";
    final hasCachedToken =
        kIsWeb && (prefs.getString('cached_auth_token')?.isNotEmpty ?? false);

    // Determine target authenticated email
    final String activeEmail = account?.email ?? (isLoggedIn ? storedEmail : "");

    // 3. Routing decision: if active session exists, route to Dashboard
    if (activeEmail.isNotEmpty && (account != null || isLoggedIn || hasCachedToken)) {
      debugPrint(
          '[Splash] Authenticated session restored -> Navigating to Dashboard ($activeEmail)');
      _navigateToDashboard(activeEmail);
      return;
    }

    // 4. No active session -> route to LoginScreen
    debugPrint('[Splash] No active session -> Navigating to LoginScreen');
    if (!mounted) return;
    _navigateToLogin(reason: 'no active session');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: [Splash] build() called');
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFD32F2F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Centered Brand Hero Component ──
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Circular Logo Card
                Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Image.asset(
                    'assets/dashboard_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.precision_manufacturing_rounded,
                      size: 60,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 2. Primary Title
                const Text(
                  'MSM CALC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),

                // 3. Subtitle
                Text(
                  'MSM ONE PORTAL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.5,
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom Progress Bar & Security Footer ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: Colors.amberAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AUTHORIZED PERSONNEL ONLY',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
