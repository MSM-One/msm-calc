import 'package:flutter/material.dart';
import 'reports_dashboard_screen.dart';

export 'reports_dashboard_screen.dart';

/// Desktop Reports Screen - Alias / Entrypoint for the redesigned Enterprise Stock Reports Dashboard.
class DesktopReportsScreen extends StatelessWidget {
  final String? initialTabId;

  const DesktopReportsScreen({super.key, this.initialTabId});

  @override
  Widget build(BuildContext context) {
    return ReportsDashboardScreen(initialTabId: initialTabId);
  }
}
