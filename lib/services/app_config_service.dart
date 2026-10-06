import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'app_update_service.dart';

/// Dynamic App & Super Admin Configuration Service.
/// Sources Super Admin identity and Restricted Sales Mode dynamically
/// from the Supabase `app_config` table (id = 1).
class AppConfigService {
  static const String _superAdminPrefsKey = 'cached_super_admin_email';
  static const String _salesOnlyModePrefsKey = 'cached_sales_only_mode';

  /// ValueNotifier for the dynamic Super Admin email.
  static final ValueNotifier<String> superAdminEmailNotifier =
      ValueNotifier<String>('');

  /// ValueNotifier for Restricted Sales Mode.
  static final ValueNotifier<bool> salesOnlyModeNotifier =
      ValueNotifier<bool>(false);

  static StreamSubscription<List<Map<String, dynamic>>>? _configStreamSub;
  static bool _isInitialized = false;

  /// Dynamic Super Admin email getter.
  static String get superAdminEmail => superAdminEmailNotifier.value;

  /// Restricted Sales Mode getter.
  static bool get isSalesOnlyMode => salesOnlyModeNotifier.value;

  /// Verifies if a given email is the dynamic Super Admin.
  static bool isSuperAdmin(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final current = email.toLowerCase().trim();
    final target = superAdminEmail.toLowerCase().trim();
    return target.isNotEmpty && current == target;
  }

  /// Initializes configuration from local cache and triggers live Supabase fetch & stream.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedSuper = prefs.getString(_superAdminPrefsKey) ?? '';
      final cachedSalesMode = prefs.getBool(_salesOnlyModePrefsKey) ?? false;

      if (cachedSuper.isNotEmpty) {
        superAdminEmailNotifier.value = cachedSuper;
      }
      salesOnlyModeNotifier.value = cachedSalesMode;

      // Fetch live config from Supabase
      await fetchAppConfig();

      // Listen to realtime updates on app_config
      _setupRealtimeStream();
    } catch (e) {
      debugPrint('[AppConfigService] Init error: $e');
    }
  }

  /// Fetches live configuration from the `app_config` Supabase table (`id = 1`).
  static Future<void> fetchAppConfig() async {
    try {
      final row = await SupabaseService.client
          .from('app_config')
          .select('sales_only_mode, super_admin_email')
          .eq('id', 1)
          .maybeSingle();

      if (row != null) {
        final bool salesMode = row['sales_only_mode'] == true;
        final String superEmail =
            (row['super_admin_email']?.toString() ?? '').trim();

        salesOnlyModeNotifier.value = salesMode;
        if (superEmail.isNotEmpty) {
          superAdminEmailNotifier.value = superEmail;
        }

        final prefs = await SharedPreferences.getInstance();
        if (superEmail.isNotEmpty) {
          await prefs.setString(_superAdminPrefsKey, superEmail);
        }
        await prefs.setBool(_salesOnlyModePrefsKey, salesMode);

        debugPrint(
            '[AppConfigService] Loaded live config: salesOnlyMode=$salesMode, superAdminEmail=$superEmail');
      }
    } catch (e) {
      debugPrint('[AppConfigService] Error fetching app_config: $e');
    }
  }

  static void _setupRealtimeStream() {
    _configStreamSub?.cancel();
    _configStreamSub = SupabaseService.client
        .from('app_config')
        .stream(primaryKey: ['id']).listen((rows) async {
      if (rows.isNotEmpty) {
        final row = rows.first;
        final bool salesMode = row['sales_only_mode'] == true;
        final String superEmail =
            (row['super_admin_email']?.toString() ?? '').trim();

        salesOnlyModeNotifier.value = salesMode;
        if (superEmail.isNotEmpty) {
          superAdminEmailNotifier.value = superEmail;
        }

        final prefs = await SharedPreferences.getInstance();
        if (superEmail.isNotEmpty) {
          await prefs.setString(_superAdminPrefsKey, superEmail);
        }
        await prefs.setBool(_salesOnlyModePrefsKey, salesMode);

        debugPrint(
            '[AppConfigService] Realtime app_config updated: salesOnlyMode=$salesMode, superAdminEmail=$superEmail');
      }
    }, onError: (e) {
      debugPrint('[AppConfigService] Realtime app_config stream error: $e');
    });
  }

  /// Sets Restricted Sales Mode in the `app_config` table.
  static Future<void> setSalesOnlyMode(bool enabled) async {
    await SupabaseService.client
        .from('app_config')
        .update({'sales_only_mode': enabled}).eq('id', 1);
    salesOnlyModeNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_salesOnlyModePrefsKey, enabled);
  }

  /// Transfers the Super Admin role to a new email address.
  static Future<void> transferSuperAdmin(String newSuperAdminEmail) async {
    final normalized = newSuperAdminEmail.toLowerCase().trim();
    if (normalized.isEmpty) throw Exception('Email cannot be empty');

    await SupabaseService.client
        .from('app_config')
        .update({'super_admin_email': normalized}).eq('id', 1);

    superAdminEmailNotifier.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_superAdminPrefsKey, normalized);

    // Promote new super admin to admin role in users table
    await SupabaseService.client
        .from('users')
        .update({'role': 'admin'}).eq('email', normalized);

    debugPrint('[AppConfigService] Super Admin transferred to: $normalized');
  }

  /// Entry point to fetch app configuration and check for updates.
  static Future<void> checkForUpdates(BuildContext context) async {
    await AppUpdateService.checkForUpdates(context);
  }
}
