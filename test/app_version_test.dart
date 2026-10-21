import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:msm_calc/constants/app_constants.dart';
import 'package:msm_calc/services/app_version_service.dart';
import 'package:msm_calc/widgets/app_version_badge.dart';
import 'package:msm_calc/widgets/app_drawer.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'MSM Calc',
      packageName: 'com.metaroll.msm_calc',
      version: '1.0.2',
      buildNumber: '3',
      buildSignature: '',
    );
  });

  group('AppVersionService Tests', () {
    test('Initializes and extracts dynamic version from package_info_plus',
        () async {
      await AppVersionService.init();

      expect(AppVersionService.rawVersion, equals('1.0.2'));
      expect(AppVersionService.version, equals('v1.0.2'));
      expect(AppVersionService.buildNumber, equals('3'));
      expect(AppVersionService.fullVersion, equals('v1.0.2 (3)'));
      expect(AppVersionService.currentVersion, equals('v1.0.2+3'));
      expect(AppVersionService.fallbackVersion, equals('v1.0.2'));
      expect(AppVersionService.fallbackBuildNumber, equals('3'));
      expect(AppVersionService.appTitleAndVersion, equals('MSM Calc v1.0.2'));
      expect(AppVersionService.buildEnvironment, isNotEmpty);
    });

    test('Falls back gracefully to AppConstants if not yet initialized', () {
      expect(AppConstants.appVersion, equals('v1.0.2'));
      expect(AppConstants.buildNumber, equals('3'));
      expect(AppConstants.fallbackVersion, equals('v1.0.2'));
      expect(AppConstants.fallbackBuildNumber, equals('3'));
    });
  });

  group('AppVersionBadge Widget Tests', () {
    testWidgets('Renders dynamic version badge with default subtle style',
        (WidgetTester tester) async {
      await AppVersionService.init();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppVersionBadge(),
            ),
          ),
        ),
      );

      expect(find.text('MSM Calc v1.0.2'), findsOneWidget);

      final textWidget = tester.widget<Text>(find.text('MSM Calc v1.0.2'));
      expect(textWidget.style?.fontSize, equals(11));
      expect(textWidget.style?.fontWeight, equals(FontWeight.w500));
      expect(textWidget.style?.color, equals(Colors.grey.shade500));
      expect(textWidget.style?.letterSpacing, equals(0.3));
    });

    testWidgets('Renders dynamic version badge with build number when requested',
        (WidgetTester tester) async {
      await AppVersionService.init();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppVersionBadge(showBuildNumber: true),
            ),
          ),
        ),
      );

      expect(find.text('MSM Calc v1.0.2 (3)'), findsOneWidget);
    });

    testWidgets('Tapping AppVersionBadge opens About dialog',
        (WidgetTester tester) async {
      await AppVersionService.init();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppVersionBadge(),
            ),
          ),
        ),
      );

      await tester.tap(find.text('MSM Calc v1.0.2'));
      await tester.pumpAndSettle();

      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.text('Metaroll Steel Mart'), findsWidgets);
      expect(find.text('Build 3'), findsOneWidget);
    });
  });

  group('AppDrawer Tests', () {
    testWidgets('Renders navigation items and version badge at bottom',
        (WidgetTester tester) async {
      await AppVersionService.init();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: AppDrawer(
              items: [
                AppDrawerItem(
                  title: 'Dashboard',
                  icon: Icons.dashboard,
                  onTap: () {},
                ),
                AppDrawerItem(
                  title: 'Inventory',
                  icon: Icons.inventory_2,
                  onTap: () {},
                ),
              ],
              onLogout: () {},
            ),
            body: const Center(child: Text('Body')),
          ),
        ),
      );

      // Open drawer
      final ScaffoldState state = tester.firstState(find.byType(Scaffold));
      state.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('MSM Calc v1.0.2'), findsOneWidget);
    });
  });
}
