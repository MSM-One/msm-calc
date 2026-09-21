import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:msm_calc/core/app_permissions.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/providers/inventory_provider.dart';
import 'package:msm_calc/screens/quick_rate_calculator_screen.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:msm_calc/services/sample_rate_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
    });

    DataRepository.currentUserNotifier.value = UserModel(
      email: 'test@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {
        AppPermissions.screensSampleRate: true,
      },
    );
  });

  group('Sample Rate Formula Calculations', () {
    test('calculates net rate with Base, SD, Loading Charge, NC Discount, and GST', () {
      const double basic = 50000.0;
      const double sd = 500.0;
      const double loading = 255.0;
      const double ncDiscount = 3000.0;
      const double gstRate = 0.18;

      // Effective Base = 50000 + 500 + 255 = 50755
      // Final with 18% GST = 50755 * 1.18 = 59890.9 -> 59891
      double effectiveBase = basic + sd + loading;
      double finalRate = effectiveBase * (1.0 + gstRate);
      expect(finalRate.round(), equals(59891));

      // With NC discount: (50755 - 3000) * 1.18 = 47755 * 1.18 = 56350.9 -> 56351
      double effectiveBaseNc = effectiveBase - ncDiscount;
      double finalRateNc = effectiveBaseNc * (1.0 + gstRate);
      expect(finalRateNc.round(), equals(56351));

      // With GST OFF: 47755
      expect(effectiveBaseNc.round(), equals(47755));
    });
  });

  group('Sample Rate Isolated Benchmark Scope & Dynamic Matching', () {
    test('InventoryProvider loads 6 core categories with updated benchmark sizes and dynamic matching', () async {
      final invProvider = InventoryProvider();

      // Mock catalog data in DataRepository sheetDataNotifier & itemSizesNotifier
      DataRepository.sheetDataNotifier.value = {
        'items': [
          {
            'name': 'MS PIPE',
            'sizes': [
              {
                'size_label': '0.75" 19x19 (1.6)', // Varied spacing
                'size_difference': 6500, // Dynamic SD from catalog
                'unit_weight_kg': 5.0,
              },
              {
                'size_label': '1" 25X25(1.6)', // Uppercase X, no space
                'size_difference': 4500,
                'unit_weight_kg': 7.0,
              },
            ],
          },
          {
            'name': 'MS ANGLE',
            'sizes': [
              {
                'label': '25x3',
                'diffRate': 3000,
                'std_weight': 6.2,
              },
              {
                'label': '65x5',
                'diffRate': 0,
                'std_weight': 30.0,
              },
            ],
          },
          {
            'name': 'BINDING WIRE', // Excluded category
            'sizes': [
              {'label': '20G', 'sd': 0, 'weight': 25.0},
            ],
          },
        ],
        'meta': {
          'loading_charge': 255,
          'gst_rate': 0.18,
        },
      };

      await invProvider.fetchSampleRateData(force: true);

      final categories = invProvider.sampleRateCategories;

      // Restrict strictly to the 6 core structural categories
      expect(categories.keys, equals([
        'MS Pipe',
        'MS Angle',
        'MS Channel',
        'Sqr Bar',
        'Round Bar',
        'Flats',
      ]));

      // 1. MS PIPE: 18 Benchmark sizes
      expect(categories['MS Pipe']!.length, equals(18));
      final pipe1 = categories['MS Pipe']!.first;
      expect(pipe1.label, equals('0.75" 19x19(1.6)'));
      expect(pipe1.sd, equals(6500)); // Matched dynamic SD
      expect(pipe1.weight, equals(5.0)); // Matched dynamic weight

      final pipe2 = categories['MS Pipe']![1];
      expect(pipe2.label, equals('1" 25x25(1.6)'));
      expect(pipe2.sd, equals(4500));
      expect(pipe2.weight, equals(7.0));

      // 2. MS ANGLE: 8 Benchmark sizes
      expect(categories['MS Angle']!.length, equals(8));
      expect(categories['MS Angle']!.map((s) => s.label).toList(), equals([
        '25x3',
        '25x5',
        '32x3',
        '35x5',
        '40x4',
        '40x5',
        '50x5',
        '65x5',
      ]));

      // 3. MS CHANNEL: 3 Benchmark sizes
      expect(categories['MS Channel']!.length, equals(3));
      expect(categories['MS Channel']!.map((s) => s.label).toList(), equals([
        '70x35 (3"X1.5")',
        '75x40 (3"X1.5")',
        '100x50 (4"x 2")',
      ]));

      // 4. SQR BAR: 2 Benchmark sizes
      expect(categories['Sqr Bar']!.length, equals(2));
      expect(categories['Sqr Bar']!.map((s) => s.label).toList(), equals(['8MM', '10MM']));

      // 5. ROUND BAR: 3 Benchmark sizes
      expect(categories['Round Bar']!.length, equals(3));
      expect(categories['Round Bar']!.map((s) => s.label).toList(), equals(['10MM', '12MM', '16MM']));

      // 6. FLATS: 4 Benchmark sizes
      expect(categories['Flats']!.length, equals(4));
      expect(categories['Flats']!.map((s) => s.label).toList(), equals([
        'F 25x3',
        'F 40x3',
        'F 40x5',
        'F 50x5',
      ]));
    });
  });

  group('SampleRateCalcScreen Widget Tests', () {
    testWidgets('renders desktop layout with 6 core categories only and hides excluded categories',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('0.75" 19x19(1.6)', 6500, 5.0),
          SampleRateSize('1" 25x25(1.6)', 4500, 7.0),
          SampleRateSize('1.25" 32x32(1.6)', 4000, 9.0),
          SampleRateSize('1.5" 38x38(2.0)', 3500, 13.0),
          SampleRateSize('2" 50x50(1.6)', 3500, 15.0),
          SampleRateSize('2" 50x50(2.0)', 3500, 18.0),
          SampleRateSize('2.5" 60x60(2.0)', 4000, 22.0),
          SampleRateSize('3" 72x72(2.0)', 4500, 27.0),
          SampleRateSize('1.5"x 0.75" 40x20 (1.6)', 5000, 9.0),
          SampleRateSize('2"x1" 50x25 (2.0)', 3500, 13.0),
          SampleRateSize('3"x1" 75x25 (2.0)', 4500, 17.0),
          SampleRateSize('3"x1.5" 80x40 (2.0)', 4000, 22.0),
          SampleRateSize('4"x2" 96x48 (2.0)', 4500, 27.0),
          SampleRateSize('0.75" 25OD (1.6)', 6500, 5.0),
          SampleRateSize('1" 33.4OD (1.6)', 4500, 7.0),
          SampleRateSize('1.25" 41OD (1.6)', 4500, 9.0),
          SampleRateSize('1.5" 48.3OD (2.0)', 3500, 13.0),
          SampleRateSize('2" 60.3OD (1.6)', 3500, 14.0),
        ],
        'MS Angle': [
          SampleRateSize('25x3', 3000, 6.2),
          SampleRateSize('25x5', 3000, 10.0),
          SampleRateSize('32x3', 2500, 8.5),
          SampleRateSize('35x5', 2000, 14.5),
          SampleRateSize('40x4', 1500, 14.5),
          SampleRateSize('40x5', 1000, 18.0),
          SampleRateSize('50x5', 0, 21.5),
          SampleRateSize('65x5', 0, 30.0),
        ],
        'MS Channel': [
          SampleRateSize('70x35 (3"X1.5")', 2500, 22.0),
          SampleRateSize('75x40 (3"X1.5")', 1500, 36.0),
          SampleRateSize('100x50 (4"x 2")', 0, 56.0),
        ],
        'Sqr Bar': [
          SampleRateSize('8MM', 2000, 0.0),
          SampleRateSize('10MM', 1500, 0.0),
        ],
        'Round Bar': [
          SampleRateSize('10MM', 1500, 0.0),
          SampleRateSize('12MM', 0, 0.0),
          SampleRateSize('16MM', 0, 0.0),
        ],
        'Flats': [
          SampleRateSize('F 25x3', 2500, 0.0),
          SampleRateSize('F 40x3', 2000, 0.0),
          SampleRateSize('F 40x5', 1000, 0.0),
          SampleRateSize('F 50x5', 0, 0.0),
        ],
        'BINDING WIRE': [
          SampleRateSize('20G', 0, 25.0),
        ],
        'NAILS': [
          SampleRateSize('2"', 0, 50.0),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify Screen Header
      expect(find.text('Sample Rate Calc'), findsOneWidget);

      // Verify Single Share Icon in AppBar
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);

      // Verify NO Floating Action Button
      expect(find.byType(FloatingActionButton), findsNothing);

      // Verify Left Sidebar Form
      expect(find.text('Pipe Basic'), findsOneWidget);
      expect(find.text('Angle Basic'), findsOneWidget);
      expect(find.text('Channel Basic'), findsOneWidget);
      expect(find.text('SQR Bar Basic'), findsOneWidget);
      expect(find.text('Round/Flats Basic'), findsOneWidget);
      expect(find.text('Apply Pipe Rate to All'), findsOneWidget);

      // Verify Surcharges & Formula Toggles
      expect(find.text('GST (18%)'), findsWidgets);
      expect(find.text('NC Discount'), findsWidgets);

      // Verify Core Category Tabs are shown
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('MS ANGLE'), findsWidgets);
      expect(find.text('MS CHANNEL'), findsWidgets);
      expect(find.text('SQR BAR'), findsWidgets);
      expect(find.text('ROUND BAR'), findsWidgets);
      expect(find.text('FLATS'), findsWidgets);

      // Verify Excluded Category Tabs are HIDDEN
      expect(find.text('BINDING WIRE'), findsNothing);
      expect(find.text('NAILS'), findsNothing);

      // Verify Pricing Table Headers
      expect(find.text('SIZE DIMENSION'), findsOneWidget);
      expect(find.text('SD VALUE'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);

      // Verify MS Pipe displays 18 sizes and count pill
      expect(find.text('18 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsOneWidget);
      expect(find.text('2" 60.3OD (1.6) 14kg'), findsOneWidget);

      // Enter Pipe Basic rate and verify dynamic calculation
      final pipeInput = find.widgetWithText(TextField, '');
      await tester.enterText(pipeInput.first, '50000');
      await tester.pump();

      // Net rate should now be displayed
      expect(find.textContaining('66,971'), findsWidgets);

      // Switch to MS Angle
      await tester.tap(find.text('MS ANGLE').first);
      await tester.pump();
      expect(find.text('8 sizes'), findsOneWidget);
      expect(find.text('25x3 6.2kg'), findsOneWidget);
      expect(find.text('65x5 30kg'), findsOneWidget);

      // Switch to MS Channel
      await tester.tap(find.text('MS CHANNEL').first);
      await tester.pump();
      expect(find.text('3 sizes'), findsOneWidget);
      expect(find.text('70x35 (3"X1.5") 22kg'), findsOneWidget);
      expect(find.text('100x50 (4"x 2") 56kg'), findsOneWidget);

      // Switch to Sqr Bar
      await tester.tap(find.text('SQR BAR').first);
      await tester.pump();
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('8MM'), findsOneWidget);
      expect(find.text('10MM'), findsOneWidget);

      // Switch to Round Bar
      await tester.tap(find.text('ROUND BAR').first);
      await tester.pump();
      expect(find.text('3 sizes'), findsOneWidget);
      expect(find.text('10MM'), findsOneWidget);
      expect(find.text('12MM'), findsOneWidget);
      expect(find.text('16MM'), findsOneWidget);

      // Switch to Flats
      await tester.tap(find.text('FLATS').first);
      await tester.pump();
      expect(find.text('4 sizes'), findsOneWidget);
      expect(find.text('F 25x3'), findsOneWidget);
      expect(find.text('F 50x5'), findsOneWidget);
    });

    testWidgets('renders mobile layout on narrow viewport with single share button in AppBar and no FAB',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('0.75" 19x19(1.6)', 6500, 5.0),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sample Rate Calc'), findsOneWidget);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Preview & Share Rates'), findsNothing);
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('SIZE DIMENSION'), findsOneWidget);
      expect(find.text('SD VALUE'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);
    });

    testWidgets('supports dynamic + Add Size modal, - Remove removal mode, and Reset Defaults',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Provide master database catalog in DataRepository.itemSizesNotifier
      DataRepository.itemSizesNotifier.value = [
        {
          'material_name': 'MS Pipe',
          'size_label': '0.75" 19x19(1.6)',
          'unit_weight_kg': 5.0,
          'size_difference': 6500,
        },
        {
          'material_name': 'MS Pipe',
          'size_label': '1" 25x25(1.6)',
          'unit_weight_kg': 7.0,
          'size_difference': 4500,
        },
        {
          'material_name': 'MS Pipe',
          'size_label': '2" 50x50(2.5)',
          'unit_weight_kg': 23.0,
          'size_difference': 3500,
        },
      ];

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('0.75" 19x19(1.6)', 6500, 5.0),
          SampleRateSize('1" 25x25(1.6)', 4500, 7.0),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Initial state: 2 sizes in MS Pipe (which is modified from the default 18 benchmarks)
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsOneWidget);
      expect(find.text('1" 25x25(1.6) 7kg'), findsOneWidget);
      expect(find.text('2" 50x50(2.5) 23kg'), findsNothing);

      // Verify Header Action Buttons
      expect(find.text('+ New Item'), findsOneWidget);
      expect(find.text('+ Add Size'), findsOneWidget);
      expect(find.text('- Remove'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);

      // ── TEST 1: TAP "+ Add Size" AND SELECT NEW MASTER SIZE ──
      await tester.tap(find.text('+ Add Size').first);
      await tester.pumpAndSettle();

      // Modal should be visible
      expect(find.text('Add Size: MS Pipe'), findsOneWidget);
      expect(find.text('3 master sizes cataloged'), findsOneWidget);

      // Existing sizes should show "Added"
      expect(find.text('Added'), findsNWidgets(2));

      // Extra size "2\" 50x50(2.5) (23 kg)" should be available to add
      expect(find.text('2" 50x50(2.5) (23 kg)'), findsOneWidget);
      expect(find.text('SD: +₹3500'), findsOneWidget);

      // Tap on "Add" button for the new size
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Size count should now increment to 3 sizes
      expect(find.text('3 sizes'), findsOneWidget);
      expect(find.text('2" 50x50(2.5) 23kg'), findsOneWidget);
      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('+₹3500'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);

      // Verify SharedPreferences has saved the 3 sizes
      final prefs = await SharedPreferences.getInstance();
      final savedMsPipe = prefs.getStringList('sample_rate_active_sizes_ms_pipe');
      expect(savedMsPipe, isNotNull);
      expect(savedMsPipe!.length, equals(3));
      expect(savedMsPipe.any((s) => s.contains('50x50(2.5)')), isTrue);

      // ── TEST 2: TAP "- Remove" TOGGLE TO ENTER REMOVAL MODE ──
      await tester.tap(find.text('- Remove'));
      await tester.pump();

      // Button changes to "Done"
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('ACTION'), findsOneWidget);

      // Column 3 displays red "Remove" buttons
      expect(find.text('Remove'), findsNWidgets(3));

      // Remove the first benchmark item ('0.75" 19x19(1.6) 5kg')
      await tester.tap(find.text('Remove').first);
      await tester.pump();

      // Count should now be 2 sizes
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsNothing);

      // Verify SharedPreferences was updated
      final updatedMsPipe = prefs.getStringList('sample_rate_active_sizes_ms_pipe');
      expect(updatedMsPipe!.length, equals(2));
      expect(updatedMsPipe.any((s) => s.contains('19x19(1.6)')), isFalse);

      // Tap "Done" to exit removal mode
      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(find.text('- Remove'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);

      // ── TEST 3: TAP "Reset" TO RESTORE INITIAL WHITELIST ──
      await tester.tap(find.text('Reset'));
      await tester.pump();

      // SharedPreferences key should be cleared
      expect(prefs.getStringList('sample_rate_active_sizes_ms_pipe'), isNull);

      // Should reset back to canonical 18 benchmark sizes
      expect(find.text('18 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsOneWidget);
      expect(find.text('1" 25x25(1.6) 7kg'), findsOneWidget);
      expect(find.text('2" 50x50(2.5) 23kg'), findsNothing);
      expect(find.text('Reset'), findsNothing);
    });

    test('SharedPreferences persistence survives simulated page refresh', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Simulate saving 2 customized sizes in SharedPreferences
      await SampleRateService.saveActiveSizes('MS Pipe', [
        SampleRateSize('1" 25x25(1.6)', 4500, 7.0),
        SampleRateSize('2" 50x50(2.0)', 3500, 18.0),
        SampleRateSize('Custom Size 100x100', 5000, 25.0, isCustom: true),
      ]);

      // Verify key format
      expect(prefs.containsKey('sample_rate_active_sizes_ms_pipe'), isTrue);

      // Re-fetch categories as would happen on page reload
      final categories = await SampleRateService.fetchSampleRateCategories(force: true);
      final msPipes = categories['MS Pipe']!;

      expect(msPipes.length, equals(3));
      expect(msPipes[0].label, equals('1" 25x25(1.6)'));
      expect(msPipes[1].label, equals('2" 50x50(2.0)'));
      expect(msPipes[2].label, equals('Custom Size 100x100'));
      expect(msPipes[2].isCustom, isTrue);

      // Clear / Reset
      await SampleRateService.clearActiveSizes('MS Pipe');
      expect(prefs.containsKey('sample_rate_active_sizes_ms_pipe'), isFalse);

      // Re-fetch returns baseline 18 sizes
      final resetCategories = await SampleRateService.fetchSampleRateCategories(force: true);
      expect(resetCategories['MS Pipe']!.length, equals(18));
    });

    testWidgets('mobile layout contains ExpansionTile for basic rates and horizontal scrolling categories',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('0.75" 19x19(1.6)', 6500, 5.0),
          SampleRateSize('1" 25x25(1.6)', 4500, 7.0),
        ],
        'MS Angle': [
          SampleRateSize('25x3', 3000, 6.2),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify collapsible card with subtitle
      expect(find.text('Rate Settings & Inputs'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.textContaining('Active Base:'), findsOneWidget);
      expect(find.textContaining('GST: 18%'), findsOneWidget);

      // Verify compact header row on mobile (<600px renders touch-friendly IconButtons)
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('+ Set Base'), findsOneWidget);
      expect(find.byTooltip('New Item / Category'), findsOneWidget);
      expect(find.byTooltip('Add Size'), findsOneWidget);
      expect(find.byTooltip('Remove Mode'), findsOneWidget);

      // Verify table column headers
      expect(find.text('SIZE DIMENSION'), findsOneWidget);
      expect(find.text('SD VALUE'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);
    });
  });

  group('All 18 MS Pipe Benchmark Specifications & Item Sizes Verification', () {
    test('contains exact verified weights and SD values for all 18 MS Pipe benchmarks', () {
      final specs = SampleRateService.benchmarkSpecifications['MS Pipe']!;
      expect(specs.length, equals(18));

      final expectedBenchmarks = [
        {'id': 2, 'label': '0.75" 19x19(1.6)', 'weight': 5.0, 'sd': 6500},
        {'id': 5, 'label': '1" 25x25(1.6)', 'weight': 7.0, 'sd': 4500},
        {'id': 9, 'label': '1.25" 32x32(1.6)', 'weight': 9.0, 'sd': 4000},
        {'id': 15, 'label': '1.5" 38x38(2.0)', 'weight': 13.0, 'sd': 3500},
        {'id': 20, 'label': '2" 50x50(1.6)', 'weight': 15.0, 'sd': 3500},
        {'id': 21, 'label': '2" 50x50(2.0)', 'weight': 18.0, 'sd': 3500},
        {'id': 25, 'label': '2.5" 60x60(2.0)', 'weight': 22.0, 'sd': 4000},
        {'id': 28, 'label': '3" 72x72(2.0)', 'weight': 27.0, 'sd': 4500},
        {'id': 32, 'label': '1.5"x 0.75" 40x20 (1.6)', 'weight': 9.0, 'sd': 5000},
        {'id': 37, 'label': '2"x1" 50x25 (2.0)', 'weight': 13.0, 'sd': 3500},
        {'id': 48, 'label': '3"x1" 75x25 (2.0)', 'weight': 17.0, 'sd': 4500},
        {'id': 52, 'label': '3"x1.5" 80x40 (2.0)', 'weight': 22.0, 'sd': 4000},
        {'id': 56, 'label': '4"x2" 96x48 (2.0)', 'weight': 27.0, 'sd': 4500},
        {'id': 60, 'label': '0.75" 25OD (1.6)', 'weight': 5.0, 'sd': 6500},
        {'id': 63, 'label': '1" 33.4OD (1.6)', 'weight': 7.0, 'sd': 4500},
        {'id': 67, 'label': '1.25" 41OD (1.6)', 'weight': 9.0, 'sd': 4500},
        {'id': 73, 'label': '1.5" 48.3OD (2.0)', 'weight': 13.0, 'sd': 3500},
        {'id': 77, 'label': '2" 60.3OD (1.6)', 'weight': 14.0, 'sd': 3500},
      ];

      for (int i = 0; i < 18; i++) {
        final spec = specs[i];
        final expected = expectedBenchmarks[i];
        expect(spec.id, equals(expected['id']), reason: "ID mismatch at index $i");
        expect(spec.label, equals(expected['label']), reason: "Label mismatch at index $i");
        expect(spec.defaultWeight, equals(expected['weight']), reason: "Weight mismatch at index $i for ${spec.label}");
        expect(spec.defaultSd, equals(expected['sd']), reason: "SD mismatch at index $i for ${spec.label}");
      }
    });

    test('dynamically matches item_sizes records with 100% precision and ignores mismatched gauge items', () async {
      // Mock item_sizes containing both 1.2 and 1.6 items
      DataRepository.itemSizesNotifier.value = [
        {
          'id': 1,
          'material_id': 1,
          'size_label': '0.75" 19x19(1.2)',
          'unit_weight_kg': 4.0,
          'size_difference': 7500,
        },
        {
          'id': 2,
          'material_id': 1,
          'size_label': '0.75" 19x19(1.6)',
          'unit_weight_kg': 5.0,
          'size_difference': 6500,
        },
        {
          'id': 4,
          'material_id': 1,
          'size_label': '1" 25x25(1.2)',
          'unit_weight_kg': 6.0,
          'size_difference': 5500,
        },
        {
          'id': 5,
          'material_id': 1,
          'size_label': '1" 25x25(1.6)',
          'unit_weight_kg': 7.0,
          'size_difference': 4500,
        },
      ];

      final categories = await SampleRateService.fetchSampleRateCategories(force: true);
      final msPipes = categories['MS Pipe']!;

      final pipe19x19 = msPipes.firstWhere((s) => s.label == '0.75" 19x19(1.6)');
      expect(pipe19x19.weight, equals(5.0)); // Must be 5.0kg, NOT 4.0kg
      expect(pipe19x19.sd, equals(6500)); // Must be +6500, NOT +7500

      final pipe25x25 = msPipes.firstWhere((s) => s.label == '1" 25x25(1.6)');
      expect(pipe25x25.weight, equals(7.0)); // Must be 7.0kg, NOT 6.0kg
      expect(pipe25x25.sd, equals(4500)); // Must be +4500, NOT +5500
    });
  });

  group('Add Item & Size Workflow & Persistence', () {
    test('InventoryProvider.addNewItemSize adds size to active category and persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryProvider();
      await inv.fetchSampleRateData(force: true);

      // Add custom size to Flats
      final addedSize = await inv.addNewItemSize(
        category: 'Flats',
        sizeLabel: 'F 65x6',
        weight: 18.5,
        sd: 0.0,
      );

      expect(addedSize.label, equals('F 65x6'));
      expect(addedSize.weight, equals(18.5));
      expect(addedSize.sd, equals(0.0));
      expect(addedSize.isCustom, isTrue);

      final flatsList = inv.sampleRateCategories['Flats']!;
      expect(flatsList.any((s) => s.label == 'F 65x6'), isTrue);

      // Verify persisted in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final storedKey = SampleRateService.getStorageKey('Flats');
      final stored = prefs.getStringList(storedKey);
      expect(stored, isNotNull);
      expect(stored!.any((s) => s.contains('F 65x6')), isTrue);
    });

    test('InventoryProvider.addNewItemSize creates new category and persists across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryProvider();
      await inv.fetchSampleRateData(force: true);

      // Create new category BEAMS
      await inv.addNewItemSize(
        category: 'BEAMS',
        sizeLabel: '100x50 56kg',
        weight: 56.0,
        sd: 0.0,
        isNewCategory: true,
      );

      expect(inv.sampleRateCategories.containsKey('BEAMS'), isTrue);
      expect(inv.sampleRateCategories['BEAMS']!.length, equals(1));
      expect(inv.sampleRateCategories['BEAMS']!.first.label, equals('100x50 56kg'));

      // Verify custom categories list saved in SharedPreferences
      final customCats = await SampleRateService.loadCustomCategories();
      expect(customCats, contains('BEAMS'));

      // Simulate app restart / reload
      final reloadedCategories = await SampleRateService.fetchSampleRateCategories(force: true);
      expect(reloadedCategories.containsKey('BEAMS'), isTrue);
      expect(reloadedCategories['BEAMS']!.any((s) => s.label == '100x50 56kg'), isTrue);
    });

    testWidgets('Header row contains + New Item button and opens dialog', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'Flats': [
          SampleRateSize('F 25x3', 0, 5.0),
          SampleRateSize('F 50x6', 0, 14.0),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('+ New Item'), findsOneWidget);

      // Tap + New Item
      await tester.tap(find.text('+ New Item'));
      await tester.pumpAndSettle();

      // Verify dialog is shown with both options
      expect(find.text('Add Item / Size'), findsOneWidget);
      expect(find.text('Add to Flats'), findsOneWidget);
      expect(find.text('New Category'), findsOneWidget);
      expect(find.text('Save Size'), findsOneWidget);

      // Fill in form: Size label, weight, SD
      await tester.enterText(find.widgetWithText(TextFormField, 'e.g. F 65x6, 2.5" 60x60(3.2), 12MM'), 'F 65x6');
      await tester.enterText(find.widgetWithText(TextFormField, 'e.g. 18.5'), '18.5');
      await tester.enterText(find.widgetWithText(TextFormField, '0 for Base'), '0');

      // Submit
      await tester.tap(find.text('Save Size'));
      await tester.pumpAndSettle();

      // Verify F 65x6 is now visible in the table
      expect(find.text('F 65x6'), findsOneWidget);
    });
  });

  group('Database Materials Dropdown & Dynamic Size Previews', () {
    test('SampleRateService.fetchAllDatabaseMaterials returns sorted materials from cache and master list', () async {
      DataRepository.sheetDataNotifier.value = {
        'items': [
          {'id': 101, 'name': 'HR PIPE'},
          {'id': 102, 'name': 'BEAMS'},
          {'id': 103, 'name': 'GATE CHANNEL'},
        ]
      };

      final materials = await SampleRateService.fetchAllDatabaseMaterials();
      expect(materials.isNotEmpty, isTrue);
      final names = materials.map((m) => m['name']?.toString()).toList();
      expect(names, contains('BEAMS'));
      expect(names, contains('GATE CHANNEL'));
      expect(names, contains('HR PIPE'));
    });

    test('SampleRateService.fetchSizesForMaterial extracts sizes from sheetData and itemSizes', () async {
      DataRepository.sheetDataNotifier.value = {
        'items': [
          {
            'id': 102,
            'name': 'BEAMS',
            'sizes': [
              {'size_label': 'ISMB 100', 'unit_weight_kg': 11.5, 'size_difference': 500},
              {'size_label': 'ISMB 150', 'unit_weight_kg': 15.0, 'size_difference': 0},
            ]
          }
        ]
      };

      final sizes = await SampleRateService.fetchSizesForMaterial(categoryName: 'BEAMS');
      expect(sizes.length, equals(2));
      expect(sizes.first.label, equals('ISMB 100'));
      expect(sizes.first.weight, equals(11.5));
      expect(sizes.first.sd, equals(500));
    });

    test('InventoryProvider.addMultipleSizesToCategory adds bulk sizes and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryProvider();
      await inv.fetchSampleRateData(force: true);

      final sizesToAdd = [
        SampleRateSize('ISMB 100', 500, 11.5, isCustom: true),
        SampleRateSize('ISMB 150', 0, 15.0, isCustom: true),
      ];

      await inv.addMultipleSizesToCategory('BEAMS', sizesToAdd, isNewCategory: true);

      expect(inv.sampleRateCategories.containsKey('BEAMS'), isTrue);
      expect(inv.sampleRateCategories['BEAMS']!.length, equals(2));
      expect(inv.sampleRateCategories['BEAMS']!.map((s) => s.label).toList(), equals(['ISMB 100', 'ISMB 150']));

      // Verify custom categories persisted
      final customCats = await SampleRateService.loadCustomCategories();
      expect(customCats, contains('BEAMS'));
    });

    testWidgets('New Category tab displays database materials dropdown and size chips', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      DataRepository.sheetDataNotifier.value = {
        'items': [
          {
            'id': 102,
            'name': 'BEAMS',
            'sizes': [
              {'size_label': 'ISMB 100', 'unit_weight_kg': 11.5, 'size_difference': 500},
              {'size_label': 'ISMB 150', 'unit_weight_kg': 15.0, 'size_difference': 0},
            ]
          }
        ]
      };

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'Flats': [
          SampleRateSize('F 25x3', 0, 5.0),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Open Add Item modal
      await tester.tap(find.text('+ New Item'));
      await tester.pumpAndSettle();

      // Switch to New Category tab
      await tester.tap(find.text('New Category'));
      await tester.pumpAndSettle();

      // Verify dropdown for Category / Material Source is rendered
      expect(find.text('Category / Material Source'), findsOneWidget);
    });
  });

  group('Category and Size Symmetrical Removal Workflow', () {
    test('SampleRateService.isCoreCategory accurately identifies core vs custom categories', () {
      expect(SampleRateService.isCoreCategory('MS Pipe'), isTrue);
      expect(SampleRateService.isCoreCategory('MS Angle'), isTrue);
      expect(SampleRateService.isCoreCategory('MS Channel'), isTrue);
      expect(SampleRateService.isCoreCategory('Sqr Bar'), isTrue);
      expect(SampleRateService.isCoreCategory('Round Bar'), isTrue);
      expect(SampleRateService.isCoreCategory('Flats'), isTrue);

      expect(SampleRateService.isCoreCategory('BEAMS'), isFalse);
      expect(SampleRateService.isCoreCategory('GATE CHANNEL'), isFalse);
      expect(SampleRateService.isCoreCategory('HR PIPE'), isFalse);
      expect(SampleRateService.isCoreCategory('Custom Category'), isFalse);
    });

    test('InventoryProvider.removeCustomCategory deletes custom category but protects core categories', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryProvider();
      await inv.fetchSampleRateData(force: true);

      // Add a custom category
      await inv.addNewItemSize(
        category: 'GATE CHANNEL',
        sizeLabel: '125x65',
        weight: 12.0,
        sd: 0.0,
        isNewCategory: true,
      );

      expect(inv.sampleRateCategories.containsKey('GATE CHANNEL'), isTrue);

      // Attempt to delete core category -> should be guarded and ignored
      await inv.removeCustomCategory('MS Pipe');
      expect(inv.sampleRateCategories.containsKey('MS Pipe'), isTrue);

      // Delete the custom category
      await inv.removeCustomCategory('GATE CHANNEL');
      expect(inv.sampleRateCategories.containsKey('GATE CHANNEL'), isFalse);

      // Verify custom categories in SharedPreferences
      final customCats = await SampleRateService.loadCustomCategories();
      expect(customCats.contains('GATE CHANNEL'), isFalse);
    });

    testWidgets('Custom category tab displays (x) badge in removal mode and shows confirmation on tap',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('0.75" 19x19(1.6)', 6500, 5.0),
        ],
        'BEAMS': [
          SampleRateSize('ISMB 100', 500, 11.5, isCustom: true),
        ],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify tabs are present
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('BEAMS'), findsWidgets);

      // In normal mode, no close badge on BEAMS tab
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Toggle removal mode
      await tester.tap(find.text('- Remove'));
      await tester.pump();

      // Done button and close badge appear on custom category tab BEAMS
      expect(find.text('Done'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Tap on close badge of BEAMS
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Verify confirmation dialog appears
      expect(find.text('Remove Category?'), findsOneWidget);
      expect(find.textContaining("Are you sure you want to remove 'BEAMS'"), findsOneWidget);
      expect(find.text('Remove Tab'), findsOneWidget);

      // Confirm removal
      await tester.tap(find.text('Remove Tab'));
      await tester.pumpAndSettle();

      // Verify BEAMS tab is removed
      expect(find.text('BEAMS'), findsNothing);
    });

    test('InventoryProvider.resetAllCategoriesToDefaults clears custom categories and custom sizes', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryProvider();
      await inv.fetchSampleRateData(force: true);

      // Add a custom size to MS Pipe and a custom category
      await inv.addNewItemSize(category: 'MS Pipe', sizeLabel: 'Custom 99x99', weight: 10, sd: 0);
      await inv.addNewItemSize(category: 'HR PIPE', sizeLabel: '50x50', weight: 10, sd: 0, isNewCategory: true);

      expect(inv.sampleRateCategories.containsKey('HR PIPE'), isTrue);
      expect(inv.isCategoryModified('MS Pipe'), isTrue);

      // Reset all
      await inv.resetAllCategoriesToDefaults();

      expect(inv.sampleRateCategories.containsKey('HR PIPE'), isFalse);
      expect(inv.isCategoryModified('MS Pipe'), isFalse);
      expect(inv.sampleRateCategories['MS Pipe']!.length, equals(18));
    });
  });

  group('Dynamic Base Rate Input & Interactive Header Base Rate Setting', () {
    testWidgets('Rate Settings panel dynamically renders basic input for custom categories on desktop', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [SampleRateSize('1" 25x25(1.6)', 4500, 7.0)],
        'GATE CHANNEL': [SampleRateSize('GC 100x50', 2000, 12.0)],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify core 5 inputs are rendered
      expect(find.text('Pipe Basic'), findsOneWidget);
      expect(find.text('Angle Basic'), findsOneWidget);
      expect(find.text('Channel Basic'), findsOneWidget);
      expect(find.text('SQR Bar Basic'), findsOneWidget);
      expect(find.text('Round/Flats Basic'), findsOneWidget);

      // Verify dynamic custom category input is rendered
      expect(find.text('GATE CHANNEL Basic'), findsOneWidget);
    });

    testWidgets('Interactive header chip opens Set Base Rate dialog and updates rate and calculations', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'GATE CHANNEL': [SampleRateSize('GC 100x50', 2000, 12.0)],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Select GATE CHANNEL tab
      await tester.tap(find.text('GATE CHANNEL').first);
      await tester.pumpAndSettle();

      // Initial state: Base rate not set
      expect(find.text('+ Set Base Rate'), findsOneWidget);

      // Tap + Set Base Rate chip
      await tester.tap(find.text('+ Set Base Rate'));
      await tester.pumpAndSettle();

      // Verify dialog is open
      expect(find.text('Set Base Rate: GATE CHANNEL'), findsOneWidget);

      // Enter base rate 52000
      final textFieldFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(textFieldFinder, '52000');
      await tester.pump();

      // Tap Apply Rate
      await tester.tap(find.text('Apply Rate'));
      await tester.pumpAndSettle();

      // Verify header chip updated to Base: ₹52,000
      expect(find.text('Base: ₹52,000'), findsOneWidget);

      // Verify net computed rate is calculated:
      // Base: 52000 + SD: 2000 + LC: 255 = 54255. GST 18%: 54255 * 1.18 = 64020.9 -> ₹64,021
      expect(find.text('₹64,021'), findsOneWidget);
    });

    testWidgets('Apply Pipe Rate to All also broadcasts base rate to dynamic custom categories', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [SampleRateSize('1" 25x25(1.6)', 0, 7.0)],
        'BEAMS': [SampleRateSize('ISMB 100', 0, 11.5)],
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryProvider>.value(
          value: invProvider,
          child: const MaterialApp(
            home: SampleRateCalcScreen(),
          ),
        ),
      );
      await tester.pump();

      // Enter 48000 into Pipe Basic
      final pipeInput = find.widgetWithText(TextField, '').first;
      await tester.enterText(pipeInput, '48000');
      await tester.pump();

      // Tap Apply Pipe Rate to All
      await tester.tap(find.text('Apply Pipe Rate to All'));
      await tester.pump();

      // Switch to BEAMS
      await tester.tap(find.text('BEAMS').first);
      await tester.pumpAndSettle();

      // Verify BEAMS header has Base: ₹48,000
      expect(find.text('Base: ₹48,000'), findsOneWidget);
    });
  });

  group('Sample Rate Persistence & Re-fetch Restoration', () {
    test('Removing a benchmark size drops count to 17, persists to SharedPreferences, and survives re-fetches', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryProvider();
      await inv.fetchSampleRateData(force: true);

      // Verify initial MS Pipe count is 18
      expect(inv.sampleRateCategories['MS Pipe']!.length, equals(18));
      final sizeToRemove = inv.sampleRateCategories['MS Pipe']!.first;
      expect(sizeToRemove.label, equals('0.75" 19x19(1.6)'));

      // Remove the size
      await inv.removeSizeFromCategory('MS Pipe', sizeToRemove);

      // In-memory list drops to 17
      expect(inv.sampleRateCategories['MS Pipe']!.length, equals(17));
      expect(inv.sampleRateCategories['MS Pipe']!.any((s) => s.label == '0.75" 19x19(1.6)'), isFalse);
      expect(inv.isCategoryModified('MS Pipe'), isTrue);

      // Verify SharedPreferences has persisted active sizes
      final prefs = await SharedPreferences.getInstance();
      final key = SampleRateService.getStorageKey('MS Pipe');
      final storedList = prefs.getStringList(key);
      expect(storedList, isNotNull);
      expect(storedList!.length, equals(17));

      // Simulate a page reload / fresh load / force fetch
      final freshInv = InventoryProvider();
      await freshInv.fetchSampleRateData(force: true);

      // Verify 17 sizes are restored and removed size does not reappear
      expect(freshInv.sampleRateCategories['MS Pipe']!.length, equals(17));
      expect(freshInv.sampleRateCategories['MS Pipe']!.any((s) => s.label == '0.75" 19x19(1.6)'), isFalse);

      // Reset to defaults restores all 18 sizes and clears SharedPreferences
      await freshInv.resetCategoryToDefaults('MS Pipe');
      expect(freshInv.sampleRateCategories['MS Pipe']!.length, equals(18));
      expect(freshInv.sampleRateCategories['MS Pipe']!.first.label, equals('0.75" 19x19(1.6)'));
      expect(freshInv.isCategoryModified('MS Pipe'), isFalse);

      final clearedList = prefs.getStringList(key);
      expect(clearedList, isNull);
    });

    test('Restores active sizes when SharedPreferences contains plain string labels', () async {
      final prefs = await SharedPreferences.getInstance();
      // Set saved active sizes with 2 labels only
      final key = SampleRateService.getStorageKey('MS Pipe');
      await prefs.setStringList(key, [
        '1" 25x25(1.6)',
        '2" 50x50(2.0)',
      ]);

      final categories = await SampleRateService.fetchSampleRateCategories(force: true);
      expect(categories['MS Pipe']!.length, equals(2));
      expect(categories['MS Pipe']![0].label, equals('1" 25x25(1.6)'));
      expect(categories['MS Pipe']![0].sd, equals(4500));
      expect(categories['MS Pipe']![0].weight, equals(7.0));
      expect(categories['MS Pipe']![1].label, equals('2" 50x50(2.0)'));
      expect(categories['MS Pipe']![1].sd, equals(3500));
      expect(categories['MS Pipe']![1].weight, equals(18.0));
    });
  });
}
