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

    testWidgets('supports dynamic + Add modal, - Remove removal mode, and Reset Defaults',
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

      // Initial state: 2 sizes in MS Pipe
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsOneWidget);
      expect(find.text('1" 25x25(1.6) 7kg'), findsOneWidget);
      expect(find.text('2" 50x50(2.5) 23kg'), findsNothing);

      // Verify Header Action Buttons
      expect(find.text('+ Add'), findsWidgets);
      expect(find.text('- Remove'), findsOneWidget);
      expect(find.byTooltip('Reset Defaults'), findsNothing);

      // ── TEST 1: TAP "+ Add" AND SELECT NEW MASTER SIZE ──
      await tester.tap(find.text('+ Add').first);
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
      expect(find.byTooltip('Reset Defaults'), findsOneWidget);

      // ── TEST 2: TAP "- Remove" TOGGLE TO ENTER REMOVAL MODE ──
      await tester.tap(find.text('- Remove'));
      await tester.pump();

      // Button changes to "Done"
      expect(find.text('Done'), findsOneWidget);

      // Inline red remove icons appear
      expect(find.byIcon(Icons.remove_circle), findsNWidgets(3));

      // Remove the first benchmark item ('0.75" 19x19(1.6) 5kg')
      await tester.tap(find.byIcon(Icons.remove_circle).first);
      await tester.pump();

      // Count should now be 2 sizes
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsNothing);

      // Tap "Done" to exit removal mode
      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(find.text('- Remove'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle), findsNothing);

      // ── TEST 3: TAP "Reset Defaults" TO RESTORE INITIAL WHITELIST ──
      await tester.tap(find.byTooltip('Reset Defaults'));
      await tester.pump();

      // Should reset back to canonical 2 benchmark sizes
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('0.75" 19x19(1.6) 5kg'), findsOneWidget);
      expect(find.text('1" 25x25(1.6) 7kg'), findsOneWidget);
      expect(find.text('2" 50x50(2.5) 23kg'), findsNothing);
      expect(find.byTooltip('Reset Defaults'), findsNothing);
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

      // Verify collapsible card
      expect(find.text('Rate Settings & Inputs'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);

      // Verify compact header row
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('+ Add'), findsOneWidget);
      expect(find.text('- Remove'), findsOneWidget);
      expect(find.text('Base: —'), findsOneWidget);

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
}
