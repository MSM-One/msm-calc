import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import '../widgets/update_dialog.dart';

class AppUpdateService {
  /// Checks Supabase 'app_versions' (or 'app_config') table for latest version info.
  /// If a newer version is available, presents an update dialog to the user.
  static Future<void> checkForUpdates(BuildContext context) async {
    debugPrint('DEBUG UPDATE CHECK: Starting update check...');

    try {
      Map<String, dynamic>? response;

      // 1. Try querying 'app_versions' table first
      try {
        response = await SupabaseService.client
            .from('app_versions')
            .select('*')
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (e) {
        debugPrint('DEBUG UPDATE CHECK: app_versions query fallback: $e');
      }

      // 2. Fallback to 'app_config' table if app_versions didn't return data
      if (response == null) {
        try {
          response = await SupabaseService.client
              .from('app_config')
              .select('*')
              .order('id', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (e) {
          debugPrint('DEBUG UPDATE CHECK: app_config query fallback: $e');
        }
      }

      debugPrint('DEBUG UPDATE CHECK: Supabase response = $response');
      if (response == null) {
        debugPrint('DEBUG UPDATE CHECK: No app_versions or app_config row found in Supabase!');
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final String currentSemver = packageInfo.version.trim();
      final String currentFullVersion = '${packageInfo.version.trim()}+${packageInfo.buildNumber.trim()}';
      final String latestVersion =
          (response['latest_version']?.toString() ?? '1.0.0').trim();
      final String minSupportedVersion =
          (response['min_supported_version']?.toString() ?? '1.0.0').trim();
      final String apkUrl = response['apk_url']?.toString() ?? '';
      final String releaseNotes = response['release_notes']?.toString() ??
          'Bug fixes and performance improvements.';
      final bool isForceUpdateConfig = response['is_force_update'] == true;

      debugPrint(
          'DEBUG UPDATE CHECK: Installed Version = "$currentFullVersion" (SemVer: "$currentSemver"), Remote Latest = "$latestVersion", Min Supported = "$minSupportedVersion"');

      final bool isOutdated = _isVersionLower(currentFullVersion, latestVersion) ||
          _isVersionLower(currentSemver, latestVersion);
      final bool shouldTriggerUpdate = isOutdated;

      final bool isForceUpdate = isForceUpdateConfig ||
          _isVersionLower(currentFullVersion, minSupportedVersion) ||
          _isVersionLower(currentSemver, minSupportedVersion);

      // Skip showing update if it's optional and user previously dismissed this version
      if (shouldTriggerUpdate && !isForceUpdate) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final String? dismissedVersion = prefs.getString('dismissed_update_version');
          if (dismissedVersion == latestVersion) {
            debugPrint(
                'DEBUG UPDATE CHECK: Version $latestVersion was previously dismissed by user. Skipping dialog.');
            return;
          }
        } catch (e) {
          debugPrint('DEBUG UPDATE CHECK: SharedPreferences error: $e');
        }
      }

      debugPrint(
          'DEBUG UPDATE CHECK: isOutdated=$isOutdated, shouldTriggerUpdate=$shouldTriggerUpdate, isForceUpdate=$isForceUpdate, context.mounted=${context.mounted}');

      if (shouldTriggerUpdate && context.mounted) {
        debugPrint('DEBUG UPDATE CHECK: Displaying update dialog now!');
        _showUpdateDialog(
          context: context,
          currentVersion: currentSemver,
          latestVersion: latestVersion,
          apkUrl: apkUrl,
          releaseNotes: releaseNotes,
          isForceUpdate: isForceUpdate,
        );
      } else {
        debugPrint(
            'DEBUG UPDATE CHECK: Update dialog NOT displayed. (shouldTriggerUpdate=$shouldTriggerUpdate, context.mounted=${context.mounted})');
      }
    } catch (e) {
      debugPrint('DEBUG UPDATE CHECK ERROR: $e');
    }
  }

  /// Compares semantic version strings (e.g., '1.0.0' vs '1.0.2').
  /// Returns true if [installed] version is strictly lower than [remote] version.
  static bool _isVersionLower(String installed, String remote) {
    try {
      final installedClean = installed.trim();
      final remoteClean = remote.trim();

      final installedSplit = installedClean.split('+');
      final remoteSplit = remoteClean.split('+');

      final installedParts = installedSplit[0]
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final remoteParts = remoteSplit[0]
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      final maxLength = remoteParts.length > installedParts.length
          ? remoteParts.length
          : installedParts.length;

      for (int i = 0; i < maxLength; i++) {
        final inst = i < installedParts.length ? installedParts[i] : 0;
        final rem = i < remoteParts.length ? remoteParts[i] : 0;
        if (rem > inst) return true;
        if (rem < inst) return false;
      }

      // If semver parts match, check build number
      if (installedSplit.length > 1 && remoteSplit.length > 1) {
        final instBuild = int.tryParse(installedSplit[1]) ?? 0;
        final remBuild = int.tryParse(remoteSplit[1]) ?? 0;
        if (remBuild > instBuild) return true;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error comparing version strings: $e');
    }
    return false;
  }

  /// Displays the update dialog. If [isForceUpdate] is true, the dialog is non-dismissible.
  static void _showUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required String latestVersion,
    required String apkUrl,
    required String releaseNotes,
    required bool isForceUpdate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (dialogContext) {
        return UpdateDialog(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          apkUrl: apkUrl,
          releaseNotes: releaseNotes,
          isForceUpdate: isForceUpdate,
        );
      },
    );
  }
}
