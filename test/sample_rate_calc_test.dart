import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:msm_calc/core/app_permissions.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/providers/inventory_provider.dart';
import 'package:msm_calc/screens/quick_rate_calculator_screen.dart';
import 'package:msm_calc/services/data_repository.dart';
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
    test('InventoryProvider loads 6 core categories with benchmark sizes and dynamic SD values', () async {
      final invProvider = InventoryProvider();

      // Mock catalog data in DataRepository sheetDataNotifier & itemSizesNotifier
      DataRepository.sheetDataNotifier.value = {
        'items': [
          {
            'name': 'MS PIPE',
            'sizes': [
              {
                'size_label': '1" 25x25(1.2)',
                'size_difference': 5500, // Dynamic SD from catalog
                'unit_weight_kg': 6.0,
              },
            ],
          },
          {
            'name': 'MS ANGLE',
            'sizes': [
              {
                'label': '25x3',
                'diffRate': 3200, // Dynamic SD from catalog using diffRate key
                'std_weight': 6.5,
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

      // 1. MS PIPE: 12 Benchmark sizes matching master item_sizes table
      expect(categories['MS Pipe']!.length, equals(12));
      final pipe1 = categories['MS Pipe']!.first;
      expect(pipe1.label, equals('1" 25x25(1.2)'));
      expect(pipe1.sd, equals(5500)); // Matched dynamic SD
      expect(pipe1.weight, equals(6.0)); // Matched dynamic weight

      // 2. MS ANGLE: 4 Benchmark sizes
      expect(categories['MS Angle']!.length, equals(4));
      final angle1 = categories['MS Angle']!.first;
      expect(angle1.label, equals('25x3'));
      expect(angle1.sd, equals(3200)); // Matched dynamic diffRate

      // 3. MS CHANNEL: 3 Benchmark sizes
      expect(categories['MS Channel']!.length, equals(3));

      // 4. SQR BAR: 2 Benchmark sizes
      expect(categories['Sqr Bar']!.length, equals(2));
      expect(categories['Sqr Bar']!.map((s) => s.label).toList(), equals(['10MM', '12MM']));

      // 5. ROUND BAR: 2 Benchmark sizes
      expect(categories['Round Bar']!.length, equals(2));
      expect(categories['Round Bar']!.map((s) => s.label).toList(), equals(['10MM', '12MM']));

      // 6. FLATS: 2 Benchmark sizes
      expect(categories['Flats']!.length, equals(2));
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
          SampleRateSize('1" 25x25(1.2)', 5500, 6.0),
          SampleRateSize('1.25" 41OD (1.2)', 5000, 7.0),
          SampleRateSize('1.5" 38x38(1.2)', 4500, 8.5),
          SampleRateSize('1.5" 48.3OD (1.2)', 4500, 8.5),
          SampleRateSize('2"x1" 50x25 (1.2)', 4500, 8.5),
          SampleRateSize('2" 50x50(1.2)', 4500, 11.0),
          SampleRateSize('2" 60.3OD (1.2)', 4500, 10.0),
          SampleRateSize('2.5"x1.5" 60x40 (1.2)', 4500, 10.0),
          SampleRateSize('2.5" 60x60(1.6)', 4500, 17.0),
          SampleRateSize('3"x1.5" 80x40 (1.6)', 4500, 17.0),
          SampleRateSize('3" 72x72(1.6)', 5500, 21.0),
          SampleRateSize('4"x2" 96x48 (1.6)', 5500, 21.0),
        ],
        'MS Angle': [
          SampleRateSize('25x3', 3000, 6.2),
          SampleRateSize('35x5', 2000, 14.5),
          SampleRateSize('40x5', 1000, 18.0),
          SampleRateSize('50x5', 0, 21.5),
        ],
        'MS Channel': [
          SampleRateSize('70x35 (3"X1.5")', 2500, 22.0),
          SampleRateSize('75x40 (3"X1.5")', 1500, 36.0),
          SampleRateSize('100x50 (4"x 2")', 0, 56.0),
        ],
        'Sqr Bar': [
          SampleRateSize('10MM', 1500, 0.0),
          SampleRateSize('12MM', 0, 0.0),
        ],
        'Round Bar': [
          SampleRateSize('10MM', 1500, 0.0),
          SampleRateSize('12MM', 0, 0.0),
        ],
        'Flats': [
          SampleRateSize('F 25x5', 2000, 0.0),
          SampleRateSize('F 32x5', 1000, 0.0),
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

      // Verify MS Pipe displays 12 sizes and count pill
      expect(find.text('12 sizes'), findsOneWidget);
      expect(find.text('1" 25x25(1.2) 6kg'), findsOneWidget);
      expect(find.text('4"x2" 96x48 (1.6) 21kg'), findsOneWidget);

      // Enter Pipe Basic rate and verify dynamic calculation
      final pipeInput = find.widgetWithText(TextField, '');
      await tester.enterText(pipeInput.first, '50000');
      await tester.pump();

      // Net rate should now be displayed
      expect(find.textContaining('65,791'), findsWidgets);

      // Switch to MS Angle
      await tester.tap(find.text('MS ANGLE').first);
      await tester.pump();
      expect(find.text('4 sizes'), findsOneWidget);
      expect(find.text('25x3 6.2kg'), findsOneWidget);
      expect(find.text('50x5 21.5kg'), findsOneWidget);

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
      expect(find.text('10MM'), findsOneWidget);
      expect(find.text('12MM'), findsOneWidget);

      // Switch to Round Bar
      await tester.tap(find.text('ROUND BAR').first);
      await tester.pump();
      expect(find.text('2 sizes'), findsOneWidget);

      // Switch to Flats
      await tester.tap(find.text('FLATS').first);
      await tester.pump();
      expect(find.text('2 sizes'), findsOneWidget);
      expect(find.text('F 25x5'), findsOneWidget);
      expect(find.text('F 32x5'), findsOneWidget);
    });

    testWidgets('renders mobile layout on narrow viewport with single share button in AppBar and no FAB',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('1" 25x25(1.2)', 5500, 6.0),
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
  });
}
