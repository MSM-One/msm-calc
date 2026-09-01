import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:msm_calc/screens/sauda_entry_screen.dart';
import 'package:msm_calc/screens/sauda_report_screen.dart';
import 'package:msm_calc/providers/inventory_provider.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:msm_calc/core/app_permissions.dart';

void main() {
  setUp(() {
    DataRepository.currentUserNotifier.value = UserModel(
      email: 'admin@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {
        AppPermissions.screensVendorPurchase: true,
        AppPermissions.vendorPurchase: true,
        AppPermissions.usersDelete: true,
      },
    );
  });

  group('Vendor Purchase Calculations & Math Unit Tests', () {
    test('Calculates purchase valuation accurately from Qty and Basic Rate', () {
      const double qty = 25.500; // 25.5 MT
      const double rate = 48500.0; // ₹48,500 / MT

      final double valuation = qty * rate;
      expect(valuation, 1236750.0);
    });

    test('Calculates weighted average rate across multiple purchase entries', () {
      const entries = [
        {'ord': 10.0, 'rate': 50000.0}, // 500,000
        {'ord': 20.0, 'rate': 47000.0}, // 940,000
        {'ord': 10.0, 'rate': 49000.0}, // 490,000
      ];

      double sumQty = 0;
      double totalValue = 0;
      for (var r in entries) {
        double q = r['ord']!;
        double rt = r['rate']!;
        sumQty += q;
        totalValue += (q * rt);
      }

      final double weightedAvgRate = sumQty > 0 ? totalValue / sumQty : 0.0;
      // totalValue = 1,930,000 / 40 MT = 48,250
      expect(sumQty, 40.0);
      expect(weightedAvgRate, 48250.0);
    });
  });

  group('SaudaEntryScreen Widget Tests', () {
    testWidgets('Renders all form sections, fields, valuation banner and action buttons',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => InventoryProvider()),
          ],
          child: const MaterialApp(
            home: SaudaEntryScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Header verification
      expect(find.text('Vendor Purchase Inward'), findsOneWidget);
      expect(find.text('Vendor & Procurement Details'), findsOneWidget);
      expect(find.text('Material & Size Specifications'), findsOneWidget);
      expect(find.text('Purchase Valuation & Numbers'), findsOneWidget);
      expect(find.text('TOTAL ORDER WEIGHT'), findsOneWidget);
      expect(find.text('NET PURCHASE VALUATION'), findsOneWidget);
      expect(find.text('SAVE INWARD ENTRY'), findsOneWidget);
      expect(find.text('Clear Form'), findsOneWidget);
      expect(find.text('Recent Purchase Ledger'), findsOneWidget);
    });

    testWidgets('Renders mobile layout on narrow screens without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(380, 800));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => InventoryProvider()),
          ],
          child: const MaterialApp(
            home: SaudaEntryScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Vendor Purchase Inward'), findsOneWidget);
      expect(find.text('SAVE INWARD ENTRY'), findsOneWidget);
    });
  });

  group('VendorPurchaseReportScreen Widget Tests', () {
    testWidgets('Renders 4-card KPI strip and filter toolbar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: VendorPurchaseReportScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Vendor Purchase Ledger'), findsOneWidget);
      expect(find.text('Total Ordered'), findsOneWidget);
      expect(find.text('Total Received'), findsOneWidget);
      expect(find.text('Pending Balance'), findsOneWidget);
      expect(find.text('Avg Purchase Rate'), findsOneWidget);
      expect(find.text('Filter Records'), findsOneWidget);
      expect(find.text('Show Hidden'), findsOneWidget);
    });
  });
}
