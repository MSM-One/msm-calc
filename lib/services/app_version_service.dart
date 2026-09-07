import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/app_constants.dart';
import '../constants/app_colors.dart';
import 'app_update_service.dart';

class AppVersionService {
  static const String fallbackVersion = AppConstants.fallbackVersion;
  static const String fallbackBuildNumber = AppConstants.fallbackBuildNumber;
  static String currentVersion = '$fallbackVersion+$fallbackBuildNumber';

  static String _version = fallbackVersion;
  static String _buildNumber = fallbackBuildNumber;
  static PackageInfo? _packageInfo;
  static bool _isInitialized = false;

  /// Initializes package info asynchronously during app startup with fail-safe fallback.
  static Future<void> init() async {
    if (_isInitialized) return;
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(milliseconds: 1500),
      );
      _packageInfo = info;
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (v.isNotEmpty) {
        _version = v.startsWith('v') ? v : 'v$v';
      }
      if (b.isNotEmpty) {
        _buildNumber = b;
      }
      currentVersion = '$_version+$_buildNumber';
      _isInitialized = true;
      debugPrint(
          'DEBUG: [AppVersionService] Initialized version: $version ($buildNumber)');
    } catch (e) {
      // Fallback cleanly on Web without crashing startup
      _version = fallbackVersion;
      _buildNumber = fallbackBuildNumber;
      currentVersion = '$_version+$_buildNumber';
      debugPrint('AppVersionService init fallback: $e');
    }
  }

  /// Optional direct access to resolved package info
  static PackageInfo? get packageInfo => _packageInfo;

  /// Raw version string e.g. "1.0.2"
  static String get rawVersion => _version.replaceAll('v', '');

  /// Semantic version with 'v' prefix e.g. "v1.0.2"
  static String get version =>
      _version.startsWith('v') ? _version : 'v$_version';

  /// Build number e.g. "3"
  static String get buildNumber => _buildNumber;

  /// Full version with build number e.g. "v1.0.2 (3)"
  static String get fullVersion => '$version ($buildNumber)';

  /// App display label e.g. "MSM Calc v1.0.2"
  static String get appTitleAndVersion => '${AppConstants.appName} $version';

  /// Environment description
  static String get buildEnvironment {
    if (kReleaseMode) return 'Production';
    if (kProfileMode) return 'Profile';
    return 'Development';
  }

  /// Target Platform String
  static String get platformName {
    if (kIsWeb) return 'Web Application';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isWindows) return 'Windows Desktop';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Universal Client';
  }

  /// Displays the About MSM Calc modal
  static void showAboutAppDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _MsmAboutDialog(),
    );
  }
}

class _MsmAboutDialog extends StatelessWidget {
  const _MsmAboutDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const isProd = kReleaseMode;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App Icon Header
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: msmRed.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200, width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/msm_app_icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.calculate_rounded,
                      size: 40,
                      color: msmRed,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // App Name
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppConstants.appFullName,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // Version & Environment Pills
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: msmRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: msmRed.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Text(
                      AppVersionService.version,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: msmRed,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    child: Text(
                      'Build ${AppVersionService.buildNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isProd
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isProd
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFFDE68A),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: isProd
                                ? Color(0xFF10B981)
                                : Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          AppVersionService.buildEnvironment,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isProd
                                ? Color(0xFF065F46)
                                : Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Platform detail card
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildInfoRow('Platform', AppVersionService.platformName),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildInfoRow('Status', 'Active & Synchronized'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Check for updates button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: msmRed,
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    backgroundColor: const Color(0xFFFEF2F2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    AppUpdateService.checkForUpdates(context);
                  },
                  icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                  label: const Text(
                    'Check for Updates',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Close button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Copyright
              Text(
                AppConstants.copyright,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade400,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
