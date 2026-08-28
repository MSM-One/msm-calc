import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_colors.dart';
import '../services/auth_service.dart';
import '../services/data_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleSignIn _googleSignIn = AuthService.googleSignIn;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-cache local assets to prevent frame allocation stalls during route transitions
    precacheImage(const AssetImage('assets/dashboard_logo.png'), context);
  }

  void _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        final token = auth.idToken ?? auth.accessToken;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', account.email);
        await prefs.setString('user_display_name', account.displayName ?? "");
        await prefs.setString('user_phone_number', "");
        await prefs.setBool('is_logged_in', true);
        if (token != null) {
          await prefs.setString('cached_auth_token', token);
        }

        if (mounted) {
          // Fire syncSheetData post-login before navigating to dashboard
          try {
            await DataRepository.syncSheetData(context);
          } catch (e) {
            debugPrint("Post-login data sync error: $e");
          }

          if (mounted) {
            await AuthService.handlePostLogin(context, account.email);
          }
        }
      }
    } on PlatformException catch (e) {
      debugPrint("Google Sign-In Platform Error: ${e.code} - ${e.message}");
      if (mounted) {
        String msg = "Sign-in failed. Please try again.";
        if (e.code == 'popup_closed_by_user') {
          msg = "Sign-in popup was closed before completion.";
        } else if (e.code == 'popup_blocked_by_browser') {
          msg =
              "Sign-in popup was blocked by your browser. Please allow popups for this site.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } catch (error) {
      debugPrint("Google Sign-In Error: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: [Login] build() started');
    final screenSize = MediaQuery.of(context).size;
    final double safeWidth = screenSize.width > 0 ? screenSize.width : 400;
    final double safeHeight = screenSize.height > 0 ? screenSize.height : 800;

    final widgetResult = Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Elegant ambient background mesh
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFCFDFD),
                    Color(0xFFF8FAFC),
                    Color(0xFFF1F5F9),
                  ],
                ),
              ),
            ),
          ),
          // Ambient soft glow top-left
          Positioned(
            top: -safeHeight * 0.2,
            left: -safeWidth * 0.2,
            child: Container(
              width: safeWidth * 0.8,
              height: safeWidth * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    msmRed.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Ambient soft glow bottom-right
          Positioned(
            bottom: -safeHeight * 0.2,
            right: -safeWidth * 0.2,
            child: Container(
              width: safeWidth * 0.8,
              height: safeWidth * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2D3142).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Main layout content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32.0, vertical: 48.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: const Color(0xFFCC2127).withValues(alpha: 0.02),
                          blurRadius: 40,
                          offset: const Offset(0, 12),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white,
                        width: 2.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Premium logo container
                        Container(
                          width: 100,
                          height: 100,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                msmRed,
                                msmRed.withValues(alpha: 0.85),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: msmRed.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              'assets/dashboard_logo.png',
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.business_rounded,
                                  color: msmRed,
                                  size: 44,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // App Title
                        const Text(
                          "Metaroll Steel Mart",
                          style: TextStyle(
                            color: textDark,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        // Subtitle
                        Text(
                          "Enterprise Calculation Portal",
                          style: TextStyle(
                            color: textGrey.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 36),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 36),
                        // Login action text
                        const Text(
                          "Login to Continue",
                          style: TextStyle(
                            color: textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Access your bookings, calculations, and real-time inventory management.",
                          style: TextStyle(
                            color: textGrey.withValues(alpha: 0.75),
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        // Premium Google Sign-In Button
                        _isLoading
                            ? Container(
                                height: 54,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(msmRed),
                                    ),
                                  ),
                                ),
                              )
                            : InkWell(
                                onTap: _handleGoogleSignIn,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  height: 54,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.02),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Fast, offline vector Google Icon (0ms delay, zero network risk)
                                      FaIcon(
                                        FontAwesomeIcons.google,
                                        size: 20,
                                        color: Color(0xFF4285F4),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        "Sign in with Google",
                                        style: TextStyle(
                                          color: textDark,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        const SizedBox(height: 24),
                        // Security Warning / Info Footer
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: textGrey.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Authorized Personnel Only",
                              style: TextStyle(
                                color: textGrey.withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    debugPrint('DEBUG: [Login] build() completed successfully');
    return widgetResult;
  }
}
