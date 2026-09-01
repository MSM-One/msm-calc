import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/services/whatsapp_share_service.dart';
import 'package:msm_calc/widgets/dealer_share/dealer_share_toolbar.dart';
import 'package:msm_calc/widgets/dealer_share/category_stock_accordion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
    });
  });

  group('WhatsappShareService Unit Tests', () {
    final mockStock = <String, List<Map<String, dynamic>>>{
      'MS Angle': [
        {
          'category_name': 'MS Angle',
          'size_label': '50x50x6',
          'unit_weight_kg': 27.0,
          'size_difference': 500.0,
          'current_stock_mt': 15.250,
        },
      ],
      'MS Pipe': [
        {
          'category_name': 'MS Pipe',
          'size_label': '70x35',
          'unit_weight_kg': 22.0,
          'size_difference': 0.0,
          'current_stock_mt': 25.500,
        },
        {
          'category_name': 'MS Pipe',
          'size_label': '50x50',
          'unit_weight_kg': 18.0,
          'size_difference': -300.0,
          'current_stock_mt': -0.320, // Deficit item
        },
      ],
    };

    test('generates full WhatsApp broadcast in canonical sequence with deficit alert', () {
      final broadcast = WhatsappShareService.formatFullStockBroadcast(
        location: 'YARD',
        groupedStock: mockStock,
      );

      expect(broadcast, contains('METAROLL / MSM ONE'));
      expect(broadcast, contains('AVAILABLE DEALER STOCK SHEET'));
      expect(broadcast, contains('*Location:* YARD'));

      // MS Pipe (Index 0) MUST appear before MS Angle (Index 1) in text
      final pipeIndex = broadcast.indexOf('MS PIPE');
      final angleIndex = broadcast.indexOf('MS ANGLE');
      expect(pipeIndex, isNonNegative);
      expect(angleIndex, isNonNegative);
      expect(pipeIndex, lessThan(angleIndex));

      // Check deficit formatting
      expect(broadcast, contains('⚠️ *-0.320 MT* (Deficit)'));

      // Check grand total
      expect(broadcast, contains('TOTAL AVAILABLE STOCK:* 40.430 MT'));
    });

    test('generates single category WhatsApp broadcast', () {
      final text = WhatsappShareService.formatCategoryBroadcast(
        category: 'MS Pipe',
        rows: mockStock['MS Pipe']!,
        location: 'YARD',
      );

      expect(text, contains('MS PIPE'));
      expect(text, contains('25.180 MT'));
      expect(text, contains('70x35'));
      expect(text, contains('⚠️ *-0.320 MT*'));
    });
  });

  group('DealerShareToolbar Widget Tests', () {
    testWidgets('renders location selector, search field, select all pill and action buttons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String selectedLocation = 'YARD';
      bool selectAllClicked = false;
      bool whatsAppClicked = false;
      bool pdfClicked = false;
      bool shareClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DealerShareToolbar(
              activeLocation: selectedLocation,
              onLocationChanged: (loc) => selectedLocation = loc,
              searchController: TextEditingController(),
              searchQuery: '',
              onSearchChanged: (_) {},
              onClearSearch: () {},
              selectedCount: 20,
              totalCount: 25,
              totalSelectedStockMT: 150.500,
              onToggleSelectAll: () => selectAllClicked = true,
              onCopyWhatsApp: () => whatsAppClicked = true,
              onExportPdf: () => pdfClicked = true,
              onShare: () => shareClicked = true,
            ),
          ),
        ),
      );

      expect(find.text('Yard Stock'), findsOneWidget);
      expect(find.text('Factory Stock'), findsOneWidget);
      expect(find.text('Copy for WhatsApp'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('20 / 25'), findsOneWidget);

      await tester.tap(find.text('Copy for WhatsApp'));
      expect(whatsAppClicked, isTrue);

      await tester.tap(find.text('Export PDF'));
      expect(pdfClicked, isTrue);

      await tester.tap(find.text('Share'));
      expect(shareClicked, isTrue);

      await tester.tap(find.text('Select All'));
      expect(selectAllClicked, isTrue);
    });
  });

  group('CategoryStockAccordion Widget Tests', () {
    testWidgets('renders category header, deficit badge, and multi-column items',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool categoryWhatsAppClicked = false;
      final items = [
        {
          'category_name': 'MS Pipe',
          'size_label': '70x35',
          'unit_weight_kg': 22.0,
          'size_difference': 500.0,
          'current_stock_mt': 12.500,
        },
        {
          'category_name': 'MS Pipe',
          'size_label': '50x50',
          'unit_weight_kg': 18.0,
          'size_difference': 0.0,
          'current_stock_mt': -0.320,
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CategoryStockAccordion(
                categoryName: 'MS Pipe',
                items: items,
                isExpanded: true,
                onToggleExpand: () {},
                categorySelectionState: true,
                onToggleCategorySelection: (_) {},
                isItemSelected: (_) => true,
                onToggleItemSelection: (_, __) {},
                onCopyCategoryWhatsApp: () => categoryWhatsAppClicked = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('MS Pipe'), findsOneWidget);
      expect(find.text('12.180 MT'), findsNWidgets(2)); // Header + Subtotal footer
      expect(find.text('SIZE & SECTION'), findsOneWidget);
      expect(find.text('12.500 MT'), findsOneWidget);
      expect(find.text('-0.320 MT'), findsOneWidget); // Raw deficit displayed
      expect(find.text('Subtotal (MS Pipe)'), findsOneWidget);

      await tester.tap(find.text('WhatsApp'));
      expect(categoryWhatsAppClicked, isTrue);
    });
  });
}
