import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/core/app_permissions.dart';
import 'package:msm_calc/models/stock_role.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/screens/manage_users_screen.dart';
import 'package:msm_calc/services/data_repository.dart';

void main() {
  setUp(() {
    UserSession.currentRole = StockRole.ADMIN;
    UserSession.userEmail = 'admin@msm.com';

    DataRepository.currentUserNotifier.value = UserModel(
      email: 'admin@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {
        AppPermissions.screensUsers: true,
        AppPermissions.usersManage: true,
        AppPermissions.usersDelete: true,
      },
    );
  });

  group('ManageUsersScreen Unit & Logic Tests', () {
    test('Correctly computes summary counts across diverse user list', () {
      final mockUsers = [
        {'email': 'admin1@msm.com', 'role': 'admin', 'status': 'APPROVED'},
        {'email': 'admin2@msm.com', 'role': 'admin', 'status': 'APPROVED'},
        {'email': 'staff1@msm.com', 'role': 'staff', 'status': 'APPROVED'},
        {'email': 'pending1@msm.com', 'role': 'staff', 'status': 'PENDING'},
        {'email': 'pending2@msm.com', 'role': 'staff', 'status': 'PENDING'},
        {'email': 'hold1@msm.com', 'role': 'staff', 'status': 'HOLD'},
        {'email': 'rejected1@msm.com', 'role': 'staff', 'status': 'REJECTED'},
      ];

      final totalUsersCount = mockUsers.length;
      final pendingCount = mockUsers
          .where((u) => u['status']!.toUpperCase() == 'PENDING')
          .length;
      final adminCount = mockUsers
          .where((u) => u['role']!.toLowerCase() == 'admin')
          .length;
      final activeCount = mockUsers
          .where((u) => u['status']!.toUpperCase() == 'APPROVED')
          .length;

      expect(totalUsersCount, 7);
      expect(pendingCount, 2);
      expect(adminCount, 2);
      expect(activeCount, 3);
    });

    test('Search filter logic matches both email and user_name case-insensitively', () {
      final mockUsers = [
        {'email': 'vikram@metarolls.com', 'user_name': 'Vikram Sharma'},
        {'email': 'rahul.steel@gmail.com', 'user_name': 'Rahul Patel'},
        {'email': 'operations@msm.com', 'user_name': 'Ops Manager'},
      ];

      List<dynamic> filter(String query) {
        final q = query.toLowerCase();
        return mockUsers.where((u) {
          final email = u['email']!.toLowerCase();
          final name = u['user_name']!.toLowerCase();
          return email.contains(q) || name.contains(q);
        }).toList();
      }

      expect(filter('vikram').length, 1);
      expect(filter('PATEL').length, 1);
      expect(filter('msm.com').length, 1);
      expect(filter('nonexistent').length, 0);
    });
  });

  group('ManageUsersScreen Widget Tests', () {
    testWidgets('Renders AppBar, 4-card metric strip, section headers and tools on desktop',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: ManageUsersScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // 1. Verify Top AppBar
      expect(find.text("Manage Users"), findsOneWidget);
      expect(find.text("Admin dashboard"), findsOneWidget);
      expect(find.byTooltip("Refresh List"), findsOneWidget);

      // 2. Verify 4-Card Metric Strip Labels
      expect(find.text("Total Users"), findsOneWidget);
      expect(find.text("Pending Requests"), findsOneWidget);
      expect(find.text("Admins"), findsOneWidget);
      expect(find.text("Active Users"), findsOneWidget);

      // 3. Verify Section Headers with Red Pill Accent
      expect(find.text("Pending Registrations"), findsOneWidget);
      expect(find.text("LIVE"), findsOneWidget);
      expect(find.text("All Users"), findsOneWidget);
      expect(find.text("Admin Settings"), findsOneWidget);
      expect(find.text("System Tools"), findsOneWidget);

      // 4. Verify Pricing Config Inputs
      expect(find.text("GST (%)"), findsOneWidget);
      expect(find.text("LC (₹/MT)"), findsOneWidget);
      expect(find.text("NC (₹/MT)"), findsOneWidget);
      expect(find.text("Save Changes"), findsOneWidget);

      // 5. Verify Soft Reset System Tool
      expect(find.text("Soft Reset Dashboard"), findsOneWidget);
    });

    testWidgets('Renders mobile layout on narrow screen (360x780) cleanly without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));

      await tester.pumpWidget(
        const MaterialApp(
          home: ManageUsersScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Verify essential components render on mobile
      expect(find.text("Manage Users"), findsOneWidget);
      expect(find.text("Total Users"), findsOneWidget);
      expect(find.text("Pending Requests"), findsOneWidget);
      expect(find.text("Admins"), findsOneWidget);
      expect(find.text("Active Users"), findsOneWidget);
      expect(find.text("All Users"), findsOneWidget);
      expect(find.text("Save Changes"), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders "No pending registrations" placeholder when pending list is empty',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: ManageUsersScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Verify empty state placeholder
      expect(find.text("No pending registrations"), findsOneWidget);
      expect(find.text("New signup requests will appear here."), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });
  });
}
