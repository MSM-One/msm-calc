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

  group('Sample Rate Specification & Strict Filtering', () {
    test('InventoryProvider filters sample sizes strictly to designated representative sizes', () async {
      final invProvider = InventoryProvider();
      await invProvider.fetchSampleRateData();

      final categories = invProvider.sampleRateCategories;
      expect(categories.keys, containsAll([
        'MS Pipe',
        'MS Angle',
        'MS Channel',
        'Sqr Bar',
        'Round Bar',
        'Flats',
      ]));

      // Check MS Angle has strictly 4 sizes
      expect(categories['MS Angle']!.length, equals(4));
      expect(categories['MS Angle']!.map((s) => s.label).toList(),
          equals(['25x3', '35x5', '40x5', '50x5']));

      // Check MS Channel has strictly 3 sizes
      expect(categories['MS Channel']!.length, equals(3));
      expect(categories['MS Channel']!.map((s) => s.label).toList(),
          equals(['70x35 (3"X1.5")', '75x40 (3"X1.5")', '100x50 (4"x 2")']));

      // Check Sqr Bar has strictly 2 sizes
      expect(categories['Sqr Bar']!.length, equals(2));
      expect(categories['Sqr Bar']!.map((s) => s.label).toList(),
          equals(['10MM', '12MM']));

      // Check Round Bar has strictly 2 sizes
      expect(categories['Round Bar']!.length, equals(2));
      expect(categories['Round Bar']!.map((s) => s.label).toList(),
          equals(['10MM', '12MM']));

      // Check Flats has strictly 2 sizes
      expect(categories['Flats']!.length, equals(2));
      expect(categories['Flats']!.map((s) => s.label).toList(),
          equals(['F 25x5', 'F 32x5']));

      // Check MS Pipe has strictly 12 representative sizes
      expect(categories['MS Pipe']!.length, equals(12));
    });
  });

  group('SampleRateCalcScreen Widget Tests', () {
    testWidgets('renders desktop layout with single AppBar share icon and no redundant share buttons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('1" 25x25 (1.6)', 4500, 7.0),
          SampleRateSize('2" 50x50 (1.6)', 3500, 15.0),
        ],
        'MS Angle': [
          SampleRateSize('25x3', 3000, 6.2),
          SampleRateSize('35x5', 2000, 14.5),
          SampleRateSize('40x5', 1000, 18.0),
          SampleRateSize('50x5', 0, 21.5),
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

      // Verify NO "Preview & Share Rates" button in Config Card
      expect(find.text('Preview & Share Rates'), findsNothing);

      // Verify NO Table Header "Share" badge button
      expect(find.text('Share'), findsNothing);

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

      // Verify Canonical Category Tabs
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('MS ANGLE'), findsWidgets);

      // Verify Pricing Table Headers
      expect(find.text('SIZE DIMENSION'), findsOneWidget);
      expect(find.text('SD VALUE'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);

      // Verify Sizes Rendered
      expect(find.text('1" 25x25 (1.6) 7kg'), findsOneWidget);
      expect(find.text('+₹4500'), findsOneWidget);

      // Enter Pipe Basic rate and verify dynamic calculation
      final pipeInput = find.widgetWithText(TextField, '');
      await tester.enterText(pipeInput.first, '50000');
      await tester.pump();

      // Net rate should now be displayed
      expect(find.textContaining('64,611'), findsOneWidget);
    });

    testWidgets('filters out non-structural categories and shows only allowed sample categories',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'Binding Wire': [
          SampleRateSize('BW 18G', 0, 25.0),
        ],
        'Nails': [
          SampleRateSize('2 Inch', 0, 50.0),
        ],
        'HR Pipe': [
          SampleRateSize('HR 50x50', 200, 15.0),
        ],
        'MS Structure ISMC': [
          SampleRateSize('ISMC 100', 400, 55.0),
        ],
        'MS Pipe': [
          SampleRateSize('1" 25x25 (1.6)', 4500, 7.0),
        ],
        'MS Channel': [
          SampleRateSize('70x35 (3"X1.5")', 2500, 22.0),
          SampleRateSize('75x40 (3"X1.5")', 1500, 36.0),
          SampleRateSize('100x50 (4"x 2")', 0, 56.0),
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

      // Ensure excluded categories are not in category pills
      expect(find.text('BINDING WIRE'), findsNothing);
      expect(find.text('NAILS'), findsNothing);
      expect(find.text('HR PIPE'), findsNothing);
      expect(find.text('MS STRUCTURE ISMC'), findsNothing);

      // Ensure allowed categories are rendered
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('MS CHANNEL'), findsWidgets);

      // Verify active category fell back to MS Pipe
      expect(find.text('1" 25x25 (1.6) 7kg'), findsOneWidget);

      // Switch to MS Channel
      await tester.tap(find.text('MS CHANNEL').first);
      await tester.pump();
      expect(find.text('70x35 (3"X1.5") 22kg'), findsOneWidget);
      expect(find.text('75x40 (3"X1.5") 36kg'), findsOneWidget);
      expect(find.text('100x50 (4"x 2") 56kg'), findsOneWidget);
    });

    testWidgets('renders mobile layout on narrow viewport with single share button in AppBar and no FAB',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('1" 25x25 (1.6)', 4500, 7.0),
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
