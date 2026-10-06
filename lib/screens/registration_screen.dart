import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/stock_role.dart';
import '../widgets/m_loader.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/supabase_service.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  bool _isLoading = false;
  bool _requestSent = false;
  String _errorMessage = "";

  /// Resolves the current user's email from all available sources.
  /// Priority: UserProvider > UserSession static > SharedPreferences cache.
  String? _resolveEmail(UserProvider userProvider) {
    // 1. Provider (set by AuthService.handlePostLogin or SessionGuardService)
    final providerEmail = userProvider.user?.email;
    if (providerEmail != null && providerEmail.isNotEmpty) return providerEmail;

    // 2. Static session (set in handlePostLogin for PENDING path)
    final sessionEmail = UserSession.userEmail;
    if (sessionEmail != null && sessionEmail.isNotEmpty) return sessionEmail;

    return null;
  }

  Future<void> _handleRequestAccess() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final email = _resolveEmail(userProvider);
    if (email == null) {
      setState(
          () => _errorMessage = "No user email found. Please login again.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final checkUser = await SupabaseService.client
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (checkUser == null) {
        final prefs = await SharedPreferences.getInstance();
        final displayName = prefs.getString('user_display_name') ?? "";
        final namePart =
            displayName.isNotEmpty ? displayName : email.split('@').first;
        final formattedName =
            namePart.substring(0, 1).toUpperCase() + namePart.substring(1);

        await SupabaseService.client.from('users').insert({
          'email': email,
          'user_name': formattedName,
          'role': 'staff'.toLowerCase().trim(),
          'status': 'PENDING',
          'permissions': {},
          'version': 1,
        });
      } else {
        final status =
            (checkUser['status']?.toString() ?? 'PENDING').toUpperCase();
        if (status == 'APPROVED') {
          setState(() => _errorMessage =
              "Your account is already approved. Please go back and login.");
          return;
        }
      }

      setState(() => _requestSent = true);
    } catch (e) {
      setState(() => _errorMessage = "Connection error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;
    final isRejected = user?.status.toUpperCase() == 'REJECTED';
    final isPending = !isRejected &&
        (_requestSent || user?.status.toUpperCase() == 'PENDING');

    // Resolve email from all available sources for display
    final displayEmail = _resolveEmail(userProvider) ?? 'Unknown';

    IconData getIcon() {
      if (isRejected) return Icons.error_outline;
      if (isPending) return Icons.check_circle_outline;
      return Icons.person_add_outlined;
    }

    Color getIconColor() {
      if (isRejected) return Colors.red;
      if (isPending) return Colors.green;
      return msmRed;
    }

    String getHeader() {
      if (isRejected) return "Access Denied";
      if (isPending) return "Request Sent";
      return "Access Required";
    }

    String getDescription() {
      if (isRejected) {
        return "Your access request has been rejected by the administrator. Please contact your manager or system administrator for support.";
      }
      if (isPending) {
        return "Your request has been submitted. Please wait for an administrator to approve your account.";
      }
      return "Your email ($displayEmail) is not registered. Please request access to continue.";
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                getIcon(),
                size: 80,
                color: getIconColor(),
              ),
              const SizedBox(height: 24),
              Text(
                getHeader(),
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: textDark),
              ),
              const SizedBox(height: 12),
              Text(
                getDescription(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: textGrey),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 40),
              if (!isPending && !isRejected)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: msmRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _handleRequestAccess,
                    child: _isLoading
                        ? const MLoader(size: 20, color: Colors.white)
                        : const Text("Request Access",
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('is_logged_in');
                  await prefs.remove('user_email');
                  await prefs.remove('user_display_name');
                  await prefs.remove('user_phone_number');
                  await prefs.remove('cached_auth_token');
                  try {
                    await SupabaseService.client.auth.signOut();
                  } catch (e) {
                    debugPrint('Supabase Sign-Out Error: $e');
                  }
                  try {
                    await GoogleSignIn().signOut();
                  } catch (e) {
                    debugPrint('Google Sign-Out Error: $e');
                  }

                  // Clear the provider so AuthenticationGuard releases the lock.
                  if (context.mounted) {
                    Provider.of<UserProvider>(context, listen: false)
                        .clearUser();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );
                  }
                },
                child: Text(
                    (isPending || isRejected) ? "Back to Login" : "Cancel",
                    style: const TextStyle(color: textGrey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
