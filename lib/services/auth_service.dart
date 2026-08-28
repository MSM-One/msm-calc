import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/stock_role.dart';
import '../providers/user_provider.dart';
import '../services/data_repository.dart';
import '../screens/registration_screen.dart';
import '../screens/waiting_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/motion_toast.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class AuthService {
  static final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/spreadsheets'],
    serverClientId: kIsWeb
        ? null
        : "638712845942-kedqro7oijm8fg4df72dkkj7hlc52gf6.apps.googleusercontent.com",
    clientId: kIsWeb
        ? "638712845942-kedqro7oijm8fg4df72dkkj7hlc52gf6.apps.googleusercontent.com"
        : null,
  );

  static Future<void> handlePostLogin(
      BuildContext context, String rawEmail) async {
    final email = rawEmail.toLowerCase().trim();
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // ── Always populate the static email immediately so that any screen
    // navigated to (RegistrationScreen, WaitingScreen, etc.) can display it.
    UserSession.userEmail = email;

    if (email == 'j2833945@gmail.com') {
      final appUser = AppUser.fromRaw({
        'email': email,
        'status': 'approved',
        'role': 'admin',
        'permissions': {},
        'version': 1,
      });
      userProvider.setUser(appUser);
      await DataRepository.syncCurrentUser(email);

      // Auto-populate admin in the database if they don't exist
      try {
        final existingAdmin = await SupabaseService.client
            .from('users')
            .select()
            .eq('email', email)
            .maybeSingle();
        if (existingAdmin == null) {
          await SupabaseService.client.from('users').insert({
            'email': email,
            'user_name': 'Admin',
            'role': 'admin'.toLowerCase().trim(),
            'status': 'APPROVED',
            'permissions': {},
            'version': 1,
          });
        }
      } catch (e) {
        debugPrint("Error auto-inserting admin: $e");
      }

      if (!context.mounted) return;
      _navigateTo(context, const MainScaffold());
      return;
    }

    try {
      // 1. Fetch current authenticated user's own data from backend
      final userData = await SupabaseService.client
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (userData == null) {
        // CASE A (New User): Route directly to RegistrationScreen
        if (!context.mounted) return;
        _navigateTo(context, const RegistrationScreen());
        return;
      }

      final String status =
          (userData['status']?.toString() ?? 'PENDING').toUpperCase().trim();

      if (status == 'PENDING') {
        UserSession.userEmail = email;
        if (!context.mounted) return;
        _navigateTo(context, const WaitingScreen());
        return;
      } else if (status == 'HOLD') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('is_logged_in');
        await prefs.remove('user_email');
        await prefs.remove('user_display_name');
        await prefs.remove('user_phone_number');
        await googleSignIn.signOut();

        if (!context.mounted) return;
        MotionToast.show(
            context, "Access Denied: Account is on Hold. Contact Management.",
            isError: true);
        return;
      } else if (status == 'REJECTED') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('is_logged_in');
        await prefs.remove('user_email');
        await prefs.remove('user_display_name');
        await prefs.remove('user_phone_number');
        await googleSignIn.signOut();

        if (!context.mounted) return;
        MotionToast.show(
            context, "Access Denied: Account registration was rejected.",
            isError: true);
        return;
      } else if (status != 'APPROVED') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('is_logged_in');
        await prefs.remove('user_email');
        await prefs.remove('user_display_name');
        await prefs.remove('user_phone_number');
        await googleSignIn.signOut();

        if (!context.mounted) return;
        MotionToast.show(
            context, "Access Denied: Account status is $status. Contact Admin.",
            isError: true);
        return;
      }

      final appUser = AppUser.fromRaw(userData);
      userProvider.setUser(appUser);

      // Requirement 3: Refetch permissions on login (updates DataRepository and local storage)
      await DataRepository.syncCurrentUser(email);

      if (!context.mounted) return;
      _navigateTo(context, const MainScaffold());
    } catch (e) {
      debugPrint("AuthService Error: $e");
      if (!context.mounted) return;

      String displayMsg = "Authentication Logic Error: $e";
      if (e is String) {
        displayMsg = e;
      } else if (e.toString().contains("Session expired") ||
          e.toString().contains("UNAUTHORIZED")) {
        displayMsg = "Session expired. Please login again.";
      } else if (e.toString().contains("permission") ||
          e.toString().contains("FORBIDDEN")) {
        displayMsg = "You do not have permission to access this screen.";
      } else if (e.toString().contains("SETUP_ERROR")) {
        displayMsg = e.toString().replaceAll("SETUP_ERROR: ", "");
      } else if (e.toString().contains("SocketException") ||
          e.toString().contains("Network Error") ||
          e.toString().contains("Failed to host") ||
          e.toString().contains("ClientException")) {
        displayMsg =
            "Failed to fetch users from server. Please check your internet connection or the server URL.";
      }

      MotionToast.show(context, displayMsg, isError: true);
    }
  }

  static void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => screen),
    );
  }
}
