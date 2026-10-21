import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/m_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import 'login_screen.dart';
import 'main_inventory_shell.dart';
import '../services/data_repository.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AccessRestrictedScreen extends StatefulWidget {
  const AccessRestrictedScreen({super.key});

  @override
  State<AccessRestrictedScreen> createState() => _AccessRestrictedScreenState();
}

class _AccessRestrictedScreenState extends State<AccessRestrictedScreen> {
  Timer? _syncTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Start periodic sync every 20 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      _checkStatus();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final user = DataRepository.currentUserNotifier.value;
    if (user != null && user.email.isNotEmpty) {
      await DataRepository.syncCurrentUser(user.email);
      final updatedUser = DataRepository.currentUserNotifier.value;
      if (updatedUser != null && updatedUser.isApproved) {
        _navigateToDashboard();
      }
    }
  }

  Future<void> _manualRefresh() async {
    setState(() => _isRefreshing = true);
    await _checkStatus();
    if (mounted) setState(() => _isRefreshing = false);
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainInventoryShell()),
      (route) => false,
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear 'is_logged_in' and other flags

    // Clear Hive cache
    try {
      await Hive.box('msm_cache_box').clear();
    } catch (_) {}

    // Clear memory notifier
    DataRepository.currentUserNotifier.value = null;

    // Google Sign Out
    final googleSignIn = AuthService.googleSignIn;
    try {
      await googleSignIn.signOut();
      await googleSignIn.disconnect();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _contactAdmin() async {
    final user = DataRepository.currentUserNotifier.value;
    final email = user?.email ?? "Unknown";
    const String supportNumber = "7391000346"; // From Main App constants

    final message =
        "Hi, I have registered on the Metaroll Steel Mart app with my email $email. Please approve my account for access.";
    final uri = Uri.parse(
        "https://wa.me/91$supportNumber?text=${Uri.encodeComponent(message)}");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch WhatsApp")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: DataRepository.currentUserNotifier,
      builder: (context, user, _) {
        final status = user?.status ?? 'Pending';

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text("Access Restricted",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: msmRed,
            elevation: 0,
            automaticallyImplyLeading: false,
            actions: [
              if (_isRefreshing)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: MLoader(size: 20, color: Colors.white),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _manualRefresh,
                )
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: msmRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status == 'Blocked' ? Icons.block : Icons.hourglass_empty,
                      size: 80,
                      color: msmRed,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    status == 'Blocked' ? "Access Revoked" : "Approval Pending",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    status == 'Blocked'
                        ? "Your account has been blocked by an Administrator. Please contact support for more details."
                        : "Your account is waiting for approval by an Administrator. You will be able to access the application once approved.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: textGrey),
                  ),
                  const SizedBox(height: 48),

                  // Primary Action: Contact Admin
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF25D366), // WhatsApp Green
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _contactAdmin,
                      icon: const Icon(Icons.chat),
                      label: const Text("Contact Administrator",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Secondary Action: Logout/Switch
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        foregroundColor: textDark,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text("Switch User or Logout",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
