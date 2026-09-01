import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/stock_role.dart';
import 'package:msm_calc/models/user_session_notifier.dart';
import 'package:msm_calc/widgets/dashboard/executive_telemetry_header.dart';
import 'package:msm_calc/widgets/dashboard/compact_kpi_ribbon.dart';
import 'package:msm_calc/widgets/dashboard/unified_stock_distribution_card.dart';
import 'package:msm_calc/widgets/dashboard/enterprise_quick_actions_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
    });

    UserSessionNotifier.instance.value = const PermissionSnapshot(
      allowedAccess: 'ALL',
      canStockIn: true,
      canStockOut: true,
      canStockTransfer: true,
      canCheckRates: true,
      canViewReports: true,
      canVendorPurchase: true,
      canViewStockMovement: true,
      canViewNonMoving: true,
      canViewTodaySummary: true,
      canViewStockLedger: true,
      canViewLowStock: true,
      canViewStockOverview: true,
      role: StockRole.ADMIN,
      canViewInventoryQuantity: true,
      canViewInventoryMetrics: true,
      canViewTxnQuantity: true,
      canAccessDashboard: true,
      canAccessUsers: true,
      canAccessQuotation: true,
      canAccessCalculator: true,
      canAccessSaudaBooking: true,
      canAccessVendorPurchaseScreen: true,
      canAccessStockInventory: true,
      canAccessReports: true,
      canAccessInventoryDash: true,
      canAccessCurrentStock: true,
      canAccessTransactions: true,
      canAccessStockDetail: true,
      canAccessItemDetail: true,
      canAccessTxnDetail: true,
      canAccessSampleRate: true,
      canAccessSalesDocCenter: true,
      canAccessMasterSize: true,
      canAccessStockSheet: true,
      canDelete: true,
    );
  });

  group('ExecutiveTelemetryHeader Widget Tests', () {
    testWidgets('renders compact greeting, telemetry pills and actions',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool refreshClicked = false;
      bool profileClicked = false;
      bool alertsClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExecutiveTelemetryHeader(
              userName: 'Vivek Salve',
              subtitle: 'MSM Yard Inventory & Operations',
              isSupabaseLive: true,
              isSyncing: false,
              locationLabel: 'Yard: All',
              attentionCount: 56,
              onRefresh: () => refreshClicked = true,
              onProfileTap: () => profileClicked = true,
              onAttentionTap: () => alertsClicked = true,
            ),
          ),
        ),
      );

      expect(find.text('Welcome back, Vivek Salve'), findsOneWidget);
      expect(find.text('MSM Yard Inventory & Operations'), findsOneWidget);
      expect(find.text('Supabase Live'), findsOneWidget);
      expect(find.text('Yard: All'), findsOneWidget);
      expect(find.text('56 Items Attention'), findsOneWidget);

      await tester.tap(find.text('56 Items Attention'));
      expect(alertsClicked, isTrue);

      await tester.tap(find.byTooltip('Sync Data with Cloud ERP'));
      expect(refreshClicked, isTrue);

      await tester.tap(find.byTooltip('Profile & Settings'));
      expect(profileClicked, isTrue);
    });
  });

  group('CompactKpiRibbon Widget Tests', () {
    testWidgets('renders all 4 metric cards with right formatting and indicators',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactKpiRibbon(
              totalStockMT: 558.900,
              todayInwardMT: 45.250,
              todayOutwardMT: 30.120,
              attentionDeficitCount: 56,
            ),
          ),
        ),
      );

      expect(find.text('Total Stock'), findsOneWidget);
      expect(find.text('558.900 MT'), findsOneWidget);

      expect(find.text('Inward Today'), findsOneWidget);
      expect(find.text('+45.250 MT'), findsOneWidget);

      expect(find.text('Outward Today'), findsOneWidget);
      expect(find.text('-30.120 MT'), findsOneWidget);

      expect(find.text('Attention / Deficits'), findsOneWidget);
      expect(find.text('56 Items'), findsOneWidget);
    });
  });

  group('UnifiedStockDistributionCard Widget Tests', () {
    testWidgets('renders dual location progress comparison and metrics',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UnifiedStockDistributionCard(
              yardStockMT: 558.900,
              factoryStockMT: 0.0,
              totalStockMT: 558.900,
            ),
          ),
        ),
      );

      expect(find.text('Stock Distribution'), findsOneWidget);
      expect(find.text('• Location Allocation Ratio'), findsOneWidget);
      expect(find.text('Total: 558.900 MT'), findsOneWidget);
      expect(find.text('Yard Stock'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('• 558.900 MT'), findsOneWidget);
      expect(find.text('Factory Stock'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('• 0.000 MT'), findsOneWidget);
    });
  });

  group('EnterpriseQuickActionsGrid Widget Tests', () {
    testWidgets('renders high density quick actions tiles',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EnterpriseQuickActionsGrid(),
            ),
          ),
        ),
      );

      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Direct Module Launch'), findsOneWidget);
      expect(find.text('CORE OPERATIONS'), findsOneWidget);
      expect(find.text('MANAGEMENT & UTILITIES'), findsOneWidget);

      expect(find.text('Inventory In & Out'), findsOneWidget);
      expect(find.text('Sauda Booking'), findsOneWidget);
      expect(find.text('Reports Dashboard'), findsOneWidget);
      expect(find.text('Netrate Calc'), findsOneWidget);
    });
  });
}
