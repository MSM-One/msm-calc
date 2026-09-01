import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/report_models.dart';
import 'package:msm_calc/utils/item_order_util.dart';
import 'package:msm_calc/widgets/reports/enterprise_stock_movement_table.dart';
import 'package:msm_calc/widgets/reports/reports_sub_tab_bar.dart';
import 'package:msm_calc/widgets/reports/stock_reports_kpi_banner.dart';

void main() {
  group('ItemOrderUtil Canonical Sequence Tests', () {
    test('14 canonical categories are strictly prioritized in order', () {
      expect(ItemOrderUtil.canonicalSequence.length, 14);
      expect(ItemOrderUtil.canonicalSequence[0], 'MS Pipe');
      expect(ItemOrderUtil.canonicalSequence[1], 'MS Angle');
      expect(ItemOrderUtil.canonicalSequence[2], 'MS Channel');
      expect(ItemOrderUtil.canonicalSequence[3], 'Binding Wire');
      expect(ItemOrderUtil.canonicalSequence[4], 'Nails');
      expect(ItemOrderUtil.canonicalSequence[5], 'Sqr Bar');
      expect(ItemOrderUtil.canonicalSequence[6], 'Round Bar');
      expect(ItemOrderUtil.canonicalSequence[7], 'Flats');
      expect(ItemOrderUtil.canonicalSequence[8], 'HR Pipe');
      expect(ItemOrderUtil.canonicalSequence[9], 'MS Structure ISMC');
      expect(ItemOrderUtil.canonicalSequence[10], 'Heavy Structure ISMB');
      expect(ItemOrderUtil.canonicalSequence[11], 'Barbed Wire');
      expect(ItemOrderUtil.canonicalSequence[12], 'GATE Channel');
      expect(ItemOrderUtil.canonicalSequence[13], 'ERW Pipe');

      // Sorting test
      final list = ['Flats', 'MS Pipe', 'Nails', 'MS Angle'];
      list.sort(ItemOrderUtil.compare);
      expect(list, ['MS Pipe', 'MS Angle', 'Nails', 'Flats']);
    });
  });

  group('StockReportsKpiBanner Widget Tests', () {
    testWidgets('renders 4 metric cards with correct data formatting',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StockReportsKpiBanner(
              totalStockMT: 1250.450,
              inwardMT: 120.300,
              outwardMT: 85.200,
              criticalAlertsCount: 3,
              locationLabel: 'All Locations',
              dateRangeLabel: 'Today',
            ),
          ),
        ),
      );

      expect(find.text('Total Yard Stock'), findsOneWidget);
      expect(find.text('1250.450 MT'), findsOneWidget);
      expect(find.text("Today's Inward"), findsOneWidget);
      expect(find.text('+120.300 MT'), findsOneWidget);
      expect(find.text("Today's Outward"), findsOneWidget);
      expect(find.text('-85.200 MT'), findsOneWidget);
      expect(find.text('Critical Alerts'), findsOneWidget);
      expect(find.text('3 Items'), findsOneWidget);
    });
  });

  group('ReportsSubTabBar Widget Tests', () {
    testWidgets('renders all 5 sub-report tabs and handles tab selection',
        (WidgetTester tester) async {
      String selectedTab = 'today';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ReportsSubTabBar(
                  activeTabId: selectedTab,
                  onTabSelected: (id) => setState(() => selectedTab = id),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text("Today's Summary"), findsOneWidget);
      expect(find.text('Stock Movement'), findsOneWidget);
      expect(find.text('Stock Ledger'), findsOneWidget);
      expect(find.text('Low Stock'), findsOneWidget);
      expect(find.text('Non-Moving'), findsOneWidget);

      await tester.tap(find.text('Stock Movement'));
      await tester.pumpAndSettle();
      expect(selectedTab, 'movement');
    });
  });

  group('EnterpriseStockMovementTable Widget Tests', () {
    testWidgets('renders category groups and items in canonical sequence',
        (WidgetTester tester) async {
      final mockData = <String, Map<String, List<StockMovementEntry>>>{
        'Flats': {
          'Flat 25x5': [
            StockMovementEntry(
              category: 'Flats',
              item: 'Flat 25x5',
              sizes: [
                StockSizeMovement(
                  label: '25x5 (1.00kg)',
                  opening: 10.0,
                  inQty: 5.0,
                  outQty: 2.0,
                  closing: 13.0,
                ),
              ],
            ),
          ],
        },
        'MS Pipe': {
          'Pipe 1/2"': [
            StockMovementEntry(
              category: 'MS Pipe',
              item: 'Pipe 1/2"',
              sizes: [
                StockSizeMovement(
                  label: '1/2" (1.20mm)',
                  opening: 5.0,
                  inQty: 2.0,
                  outQty: 8.0,
                  closing: -1.0, // Negative balance test
                ),
              ],
            ),
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnterpriseStockMovementTable(
              groupedReport: mockData,
              isDetailed: true,
              expandedCategories: const {'MS Pipe', 'Flats'},
              onCategoryToggle: (_) {},
            ),
          ),
        ),
      );

      // MS Pipe should come before Flats according to canonical sequence
      expect(find.text('MS PIPE'), findsOneWidget);
      expect(find.text('FLATS'), findsOneWidget);
      expect(find.text('Negative Balance'), findsOneWidget);
      expect(find.text('-1.000 MT'), findsWidgets);
      expect(find.text('13.000 MT'), findsWidgets);
    });
  });
}
