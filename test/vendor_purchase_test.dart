import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:msm_calc/screens/sauda_entry_screen.dart';
import 'package:msm_calc/screens/sauda_report_screen.dart';
import 'package:msm_calc/widgets/vendor_search_autocomplete.dart';
import 'package:msm_calc/widgets/searchable_vendor_modal.dart';
import 'package:msm_calc/providers/inventory_provider.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/models/stock_role.dart';
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

      const double valuation = qty * rate;
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

    test('Case-insensitively deduplicates regions and vendors into uppercase sorted lists', () {
      final rawRegions = ['Nagpur', 'NAGPUR', '  raipur  ', 'Jalna', 'JALNA', ''];
      final Set<String> seenReg = {};
      final List<String> uniqueRegions = [];
      for (final r in rawRegions) {
        final trimmed = r.trim();
        if (trimmed.isNotEmpty && seenReg.add(trimmed.toUpperCase())) {
          uniqueRegions.add(trimmed.toUpperCase());
        }
      }
      uniqueRegions.sort();

      expect(uniqueRegions, ['JALNA', 'NAGPUR', 'RAIPUR']);

      final rawVendors = ['Shruti Steel', 'SHRUTI STEEL', 'shruti steel ', 'Tata Steel'];
      final Set<String> seenVend = {};
      final List<String> uniqueVendors = [];
      for (final v in rawVendors) {
        final trimmed = v.trim();
        if (trimmed.isNotEmpty && seenVend.add(trimmed.toUpperCase())) {
          uniqueVendors.add(trimmed.toUpperCase());
        }
      }
      uniqueVendors.sort();

      expect(uniqueVendors, ['SHRUTI STEEL', 'TATA STEEL']);
    });

    test('Filters purchase records case-insensitively', () {
      final records = [
        {'party': 'SHRUTI STEEL', 'region': 'NAGPUR'},
        {'party': 'Shruti Steel', 'region': 'Nagpur'},
        {'party': 'TATA STEEL', 'region': 'RAIPUR'},
      ];

      const selectedRegion = 'nagpur';
      const selectedVendor = 'shruti steel';

      final filtered = records.where((r) {
        final regMatch = (r['region'] ?? '').trim().toUpperCase() ==
            selectedRegion.trim().toUpperCase();
        final vendMatch = (r['party'] ?? '').trim().toUpperCase() ==
            selectedVendor.trim().toUpperCase();
        return regMatch && vendMatch;
      }).toList();

      expect(filtered.length, 2);
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
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: VendorPurchaseReportScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byTooltip('Back to Dashboard'), findsOneWidget);
      expect(find.text('Total Ordered'), findsOneWidget);
      expect(find.text('Total Received'), findsOneWidget);
      expect(find.text('Pending Balance'), findsOneWidget);
      expect(find.text('Avg Purchase Rate'), findsOneWidget);
      expect(find.text('+ Inward'), findsOneWidget);
    });

    testWidgets('Renders mobile layout with collapsible header, tabs, and actions',
        (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: VendorPurchaseReportScreen(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byTooltip('Back to Dashboard'), findsOneWidget);
      expect(find.text('Vendor Purchases'), findsOneWidget);
      expect(find.byTooltip('Add Supplier'), findsOneWidget);
      expect(find.text('Inward'), findsOneWidget);
      expect(find.text('Purchase'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('RECENT TRANSACTIONS'), findsOneWidget);
      expect(find.text('View All >'), findsOneWidget);
    });
  });

  group('VendorSearchAutocomplete Widget Tests', () {
    testWidgets('Performs case-insensitive substring search and matches vendors',
        (tester) async {
      final controller = TextEditingController();
      final vendors = [
        {'name': 'Tata Steel Ltd'},
        'Jindal Steel & Power',
        {'party_name': 'Sail Bokaro'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VendorSearchAutocomplete(
              controller: controller,
              existingVendors: vendors,
            ),
          ),
        ),
      );

      // Enter lowercase substring "ste"
      await tester.enterText(find.byType(TextFormField), 'ste');
      await tester.pumpAndSettle();

      // Options should show both matching steel vendors
      expect(find.text('TATA STEEL LTD'), findsOneWidget);
      expect(find.text('JINDAL STEEL & POWER'), findsOneWidget);
      expect(find.text('SAIL BOKARO'), findsNothing);

      // Tap on TATA STEEL LTD
      await tester.tap(find.text('TATA STEEL LTD'));
      await tester.pumpAndSettle();

      expect(controller.text, 'TATA STEEL LTD');
    });
  });

  group('SearchableVendorModal Widget Tests', () {
    testWidgets('Sanitizes vendor names, extracts avatar initial, and filters live',
        (tester) async {
      final vendors = [
        "'SAT KEERAT SAGAR'",
        '"TATA STEEL"',
        'JINDAL STEEL',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableVendorModal.show(
                  context,
                  allVendors: vendors,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      // Open bottom sheet modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify sanitized display names without quotes
      expect(find.text('SAT KEERAT SAGAR'), findsOneWidget);
      expect(find.text('TATA STEEL'), findsOneWidget);
      expect(find.text('JINDAL STEEL'), findsOneWidget);

      // Verify avatar initial for SAT KEERAT SAGAR is 'S'
      expect(find.text('S'), findsWidgets);

      // Verify initial registered count
      expect(find.text('3 registered vendors'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'sat');
      await tester.pumpAndSettle();

      // Count subtitle should dynamically update
      expect(find.text('1 registered vendors'), findsOneWidget);
      expect(find.text('SAT KEERAT SAGAR'), findsOneWidget);
      expect(find.text('TATA STEEL'), findsNothing);
      expect(find.text('JINDAL STEEL'), findsNothing);

      // Select vendor
      await tester.tap(find.text('SAT KEERAT SAGAR'));
      await tester.pumpAndSettle();

      // Modal closed
      expect(find.text('Select Vendor'), findsNothing);
    });
  });
}
