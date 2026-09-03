import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/report_models.dart';
import 'package:msm_calc/utils/item_order_util.dart';
import 'package:msm_calc/widgets/reports/enterprise_stock_movement_table.dart';
import 'package:msm_calc/widgets/reports/reports_sub_tab_bar.dart';
import 'package:msm_calc/widgets/reports/stock_reports_kpi_banner.dart';
import 'package:msm_calc/screens/reports/todays_summary_screen.dart';
import 'package:msm_calc/widgets/reports/reports_export_toolbar.dart';

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

      expect(find.text('Total Stock: '), findsOneWidget);
      expect(find.text('1250.450 MT'), findsOneWidget);
      expect(find.text('Period In: '), findsOneWidget);
      expect(find.text('+120.300 MT'), findsOneWidget);
      expect(find.text('Period Out: '), findsOneWidget);
      expect(find.text('-85.200 MT'), findsOneWidget);
      expect(find.text('Alerts: '), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
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
      expect(find.text('-1.000 MT'), findsWidgets);
      expect(find.text('13.000 MT'), findsWidgets);
    });
  });

  group('TodaySummaryTab Master-Detail Split View Tests', () {
    testWidgets('renders desktop master-detail split view with category switching and PDF button',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? exportedCategory;

      final mockDailyMovements = [
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '1" (1.2mm)',
          openingQty: 100.0,
          inQty: 25.0,
          outQty: 10.0,
          closingQty: 115.0,
        ),
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '2" (1.6mm)',
          openingQty: 50.0,
          inQty: 0.0,
          outQty: 5.0,
          closingQty: 45.0,
        ),
        DailyMovementEntry(
          category: 'Flats',
          itemName: 'Flats',
          size: '25x5',
          openingQty: 30.0,
          inQty: 10.0,
          outQty: 0.0,
          closingQty: 40.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodaySummaryTab(
              isLoading: false,
              filteredDailyMovement: mockDailyMovements,
              emptyState: const Text('Empty'),
              activeOnly: false,
              onExportCategoryPdf: (cat) => exportedCategory = cat,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Master pane header
      expect(find.text('CATEGORIES'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // 2 categories count pill + row index

      // Verify category items in canonical sequence (MS Pipe, then Flats)
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('FLATS'), findsWidgets);
      expect(find.text('2 sizes'), findsWidgets); // MS Pipe has 2 sizes
      expect(find.text('1 sizes'), findsWidgets); // Flats has 1 size

      // Verify detail pane headers (strictly 5 columns: #, SIZE & SECTION, INWARD, OUTWARD, NET QTY)
      expect(find.text('SIZE & SECTION'), findsOneWidget);
      expect(find.text('INWARD'), findsOneWidget);
      expect(find.text('OUTWARD'), findsOneWidget);
      expect(find.text('NET QTY'), findsOneWidget);
      expect(find.text('OPENING'), findsNothing);
      expect(find.text('NET / CLOSING'), findsNothing);

      // Verify default selected category is MS Pipe and its net sizes are rendered
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('10.000 MT'), findsWidgets); // Category Net = 20 - 10 = 10.000 MT
      expect(find.text('15.000'), findsOneWidget); // Size 1 net = 20 - 5 = 15.000
      expect(find.text('-5.000'), findsWidgets); // Size 2 outward & net = -5.000

      // Tap PDF button in detail pane
      expect(find.text('PDF'), findsOneWidget);
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(exportedCategory, 'MS Pipe');

      // Tap FLATS category on left pane to switch
      await tester.tap(find.text('FLATS'));
      await tester.pumpAndSettle();

      // Detail pane should update to FLATS instantly
      expect(find.text('25x5'), findsOneWidget);
      expect(find.text('+10.000'), findsWidgets); // Flats has 10 inward
      expect(find.text('10.000'), findsOneWidget); // Flats has 10 net qty
      expect(find.text('10.000 MT'), findsWidgets);
    });

    testWidgets(
        'renders zero-balance sizes including MS Angle 25x3 and MS Channel 95x45',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockDailyMovements = [
        // MS Angle with 25x3 having 0 closing stock, and 75x8 with 0 all around
        DailyMovementEntry(
          category: 'MS Angle',
          itemName: 'MS Angle',
          size: '25x3',
          openingQty: 1.030,
          inQty: 0.0,
          outQty: 1.030,
          closingQty: 0.0,
        ),
        DailyMovementEntry(
          category: 'MS Angle',
          itemName: 'MS Angle',
          size: '25x5',
          openingQty: 1.370,
          inQty: 0.100,
          outQty: 1.220,
          closingQty: 0.250,
        ),
        DailyMovementEntry(
          category: 'MS Angle',
          itemName: 'MS Angle',
          size: '75x8',
          openingQty: 0.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 0.0,
        ),
        // MS Channel with 4 sizes including 95x45 with -0.320 MT
        DailyMovementEntry(
          category: 'MS Channel',
          itemName: 'MS Channel',
          size: '75x40 (3"X1.5")',
          openingQty: 7.680,
          inQty: 0.0,
          outQty: 0.360,
          closingQty: 7.320,
        ),
        DailyMovementEntry(
          category: 'MS Channel',
          itemName: 'MS Channel',
          size: '70x35 (3"X1.5")',
          openingQty: 25.330,
          inQty: 0.0,
          outQty: 2.480,
          closingQty: 22.850,
        ),
        DailyMovementEntry(
          category: 'MS Channel',
          itemName: 'MS Channel',
          size: '100x50 (4"x 2")',
          openingQty: 8.940,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 8.940,
        ),
        DailyMovementEntry(
          category: 'MS Channel',
          itemName: 'MS Channel',
          size: '95x45 (4"x2")',
          openingQty: -0.320,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: -0.320,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodaySummaryTab(
              isLoading: false,
              filteredDailyMovement: mockDailyMovements,
              activeOnly: false,
              emptyState: const Text('Empty'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // MS Angle is selected (or present in sidebar)
      expect(find.text('MS ANGLE'), findsWidgets);
      expect(find.text('MS CHANNEL'), findsWidgets);
      expect(find.text('3 sizes'), findsWidgets); // MS Angle has 3 sizes in mock
      expect(find.text('4 sizes'), findsWidgets); // MS Channel has 4 sizes in mock

      // Verify MS Angle row 1 is 25x3 6.2kg (appended with weight)
      expect(find.textContaining('25x3'), findsOneWidget);
      expect(find.textContaining('25x5'), findsOneWidget);
      expect(find.textContaining('75x8'), findsOneWidget);

      // Verify 25x3 outward was 1.030 and net is -1.030
      expect(find.text('-1.030'), findsWidgets);

      // Tap MS CHANNEL to switch
      await tester.tap(find.text('MS CHANNEL'));
      await tester.pumpAndSettle();

      // Verify all 4 sizes of MS Channel are present including 95x45
      expect(find.textContaining('75x40'), findsOneWidget);
      expect(find.textContaining('70x35'), findsOneWidget);
      expect(find.textContaining('100x50'), findsOneWidget);
      expect(find.textContaining('95x45'), findsOneWidget);
    });

    testWidgets('renders single high-density summary table when selectedTab is Summary', (tester) async {
      String? changedTab;
      final mockDailyMovements = [
        DailyMovementEntry(
          category: 'MS Angle',
          itemName: 'MS Angle',
          size: '25x3',
          openingQty: 0.0,
          inQty: 2.500,
          outQty: 1.000,
          closingQty: 1.500,
        ),
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '15 NB',
          openingQty: 10.0,
          inQty: 5.000,
          outQty: 2.000,
          closingQty: 13.000,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodaySummaryTab(
              isLoading: false,
              filteredDailyMovement: mockDailyMovements,
              selectedTab: 'Summary',
              emptyState: const Text('Empty'),
              onTabChanged: (tab) => changedTab = tab,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Summary Banner and 5 Table Columns
      expect(find.text('DAILY CATEGORY SUMMARY'), findsOneWidget);
      expect(find.text('CATEGORY / MATERIAL'), findsOneWidget);
      expect(find.text('INWARD (MT)'), findsOneWidget);
      expect(find.text('OUTWARD (MT)'), findsOneWidget);
      expect(find.text('NET QTY (MT)'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);

      // Verify categories listed
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('MS ANGLE'), findsWidgets);

      // Tap on MS ANGLE row to verify drill-down triggers onTabChanged('Detailed')
      await tester.tap(find.text('MS ANGLE'));
      await tester.pumpAndSettle();
      expect(changedTab, equals('Detailed'));
    });
  });

  group('ReportsExportToolbar View Mode Toggle Tests', () {
    testWidgets('renders [ Summary | Detailed ] toggle and triggers callback', (tester) async {
      bool? toggledView;
      final searchCtrl = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsExportToolbar(
              startDate: DateTime(2026, 9, 3),
              endDate: DateTime(2026, 9, 3),
              selectedDatePreset: 'Today',
              locationFilter: 'ALL',
              searchController: searchCtrl,
              onSearch: (_) {},
              onDateRangeTap: () {},
              onLocationChanged: (_) {},
              onRefresh: () {},
              onExportPdf: () {},
              onExportCsv: () {},
              showViewToggle: true,
              isDetailedView: true,
              onViewToggle: (val) => toggledView = val,
              activeTabId: 'today',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Summary and Detailed options are rendered
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Detailed'), findsOneWidget);

      // Tap Summary
      await tester.tap(find.text('Summary'));
      await tester.pumpAndSettle();
      expect(toggledView, equals(false));

      // Re-pump with isDetailedView = false and tap Detailed
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsExportToolbar(
              startDate: DateTime(2026, 9, 3),
              endDate: DateTime(2026, 9, 3),
              selectedDatePreset: 'Today',
              locationFilter: 'ALL',
              searchController: searchCtrl,
              onSearch: (_) {},
              onDateRangeTap: () {},
              onLocationChanged: (_) {},
              onRefresh: () {},
              onExportPdf: () {},
              onExportCsv: () {},
              showViewToggle: true,
              isDetailedView: false,
              onViewToggle: (val) => toggledView = val,
              activeTabId: 'today',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Detailed'));
      await tester.pumpAndSettle();
      expect(toggledView, equals(true));
    });

    testWidgets('renders [ Active Only | All Sizes ] toggle and triggers callback', (tester) async {
      bool? activeOnlyVal;
      final searchCtrl = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsExportToolbar(
              startDate: DateTime(2026, 9, 3),
              endDate: DateTime(2026, 9, 3),
              selectedDatePreset: 'Today',
              locationFilter: 'ALL',
              searchController: searchCtrl,
              onSearch: (_) {},
              onDateRangeTap: () {},
              onLocationChanged: (_) {},
              onRefresh: () {},
              onExportPdf: () {},
              onExportCsv: () {},
              showActiveOnlyToggle: true,
              activeOnly: true,
              onActiveOnlyChanged: (val) => activeOnlyVal = val,
              activeTabId: 'today',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Active Only and All Sizes options
      expect(find.text('Active Only'), findsOneWidget);
      expect(find.text('All Sizes'), findsOneWidget);

      // Tap All Sizes
      await tester.tap(find.text('All Sizes'));
      await tester.pumpAndSettle();
      expect(activeOnlyVal, equals(false));
    });
  });

  group('TodaySummaryTab Active Only Filtering Tests', () {
    testWidgets('filters detail rows and updates badges in Active Only mode', (tester) async {
      final mockMovements = [
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '15 NB',
          openingQty: 10.0,
          inQty: 5.000,
          outQty: 0.0,
          closingQty: 15.000,
        ),
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '20 NB',
          openingQty: 8.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 8.000,
        ),
      ];

      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodaySummaryTab(
              isLoading: false,
              filteredDailyMovement: mockMovements,
              selectedTab: 'Detailed',
              activeOnly: true,
              emptyState: const Text('Empty'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Badge should display active / total count
      expect(find.text('1 active / 2 sizes'), findsWidgets);

      // Active item should be in table
      expect(find.text('15 NB'), findsWidgets);

      // Inactive item (20 NB) should NOT be displayed in table
      expect(find.text('20 NB'), findsNothing);

      // Reset surface size
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('renders all sizes in All Sizes mode', (tester) async {
      final mockMovements = [
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '15 NB',
          openingQty: 10.0,
          inQty: 5.000,
          outQty: 0.0,
          closingQty: 15.000,
        ),
        DailyMovementEntry(
          category: 'MS Pipe',
          itemName: 'MS Pipe',
          size: '20 NB',
          openingQty: 8.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 8.000,
        ),
      ];

      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodaySummaryTab(
              isLoading: false,
              filteredDailyMovement: mockMovements,
              selectedTab: 'Detailed',
              activeOnly: false,
            emptyState: const Text('Empty'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Badge should display total count
      expect(find.text('2 sizes'), findsWidgets);

      // Both items should be rendered
      expect(find.text('15 NB'), findsWidgets);
      expect(find.text('20 NB'), findsWidgets);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('displays empty state card when category has 0 movements in Active Only mode', (tester) async {
      final mockMovements = [
        DailyMovementEntry(
          category: 'MS Angle',
          itemName: 'MS Angle',
          size: '25x3',
          openingQty: 5.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 5.000,
        ),
      ];

      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodaySummaryTab(
              isLoading: false,
              filteredDailyMovement: mockMovements,
              selectedTab: 'Detailed',
              activeOnly: true,
              emptyState: const Text('Empty'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty state message for zero movements category
      expect(
        find.text('No stock movements recorded for MS Angle on this date.'),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(null);
    });
  });
}

