import 'package:flutter/material.dart';
import 'app_update_service.dart';

class AppConfigService {
  /// Entry point to fetch app configuration and check for updates.
  static Future<void> checkForUpdates(BuildContext context) async {
    await AppUpdateService.checkForUpdates(context);
  }
}
