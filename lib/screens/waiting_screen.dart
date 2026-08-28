import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/m_loader.dart';
import '../constants/app_colors.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../models/stock_role.dart';

class WaitingScreen extends StatefulWidget {
  const WaitingScreen({super.key});

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  StreamSubscription? _subscription;
  bool _isNavigating = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    final email = UserSession.userEmail;
    if (email == null || email.isEmpty) {
      setState(() {
        _errorMessage = "No email address found in session.";
      });
      return;
    }

    try {
      _subscription = SupabaseService.client
          .from('users')
          .stream(primaryKey: ['email'])
          .eq('email', email)
          .listen((data) async {
            if (data.isNotEmpty && mounted && !_isNavigating) {
              final userRow = data.first;
              final status = (userRow['status']?.toString() ?? 'PENDING')
                  .toUpperCase()
                  .trim();
              if (status == 'APPROVED') {
                _isNavigating = true;
                try {
                  await AuthService.handlePostLogin(context, email);
                } catch (e) {
                  if (mounted) {
                    setState(() {
                      _isNavigating = false;
                      _errorMessage = "Login synchronization failed: $e";
                    });
                  }
                }
              } else if (status == 'REJECTED') {
                if (mounted) {
                  setState(() {
                    _errorMessage =
                        "Your registration request was rejected by an administrator.";
                  });
                }
              } else if (status == 'HOLD') {
                if (mounted) {
                  setState(() {
                    _errorMessage =
                        "Your account is on hold. Please contact management.";
                  });
                }
              } else {
                // If it went back to PENDING from hold/rejected, clear error
                if (mounted && _errorMessage.isNotEmpty) {
                  setState(() {
                    _errorMessage = "";
                  });
                }
              }
            }
          }, onError: (err) {
            debugPrint("WaitingScreen Supabase stream error: $err");
          });
    } catch (e) {
      debugPrint("WaitingScreen stream setup failed: $e");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    _subscription?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_logged_in');
    await prefs.remove('user_email');
    await prefs.remove('user_display_name');
    await prefs.remove('user_phone_number');
    try {
      await AuthService.googleSignIn.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_empty_rounded,
                  size: 80,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Approval Pending",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Waiting for Admin Approval. Your profile will unlock automatically once approved.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: textGrey,
                  height: 1.5,
                ),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              if (_isNavigating)
                const Column(
                  children: [
                    MLoader(size: 40),
                    SizedBox(height: 12),
                    Text(
                      "Synchronizing profile...",
                      style: TextStyle(fontSize: 12, color: textGrey),
                    ),
                  ],
                )
              else
                const MLoader(size: 60),
              const SizedBox(height: 40),
              TextButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text(
                  "Back to Login",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
