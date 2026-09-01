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
    test('calculates basic net rate without NC discount', () {
      const double basic = 50000.0;
      const double sd = 500.0;
      const double lc = 255.0;
      const double gst = 0.18;

      const double subtotal = basic + sd + lc;
      const double finalRate = subtotal * (1 + gst);

      expect(finalRate, closeTo(59890.90, 0.01));
      expect(finalRate.round(), equals(59891));
    });

    test('calculates net rate with NC discount enabled', () {
      const double basic = 50000.0;
      const double sd = 500.0;
      const double lc = 255.0;
      const double nc = 3000.0;
      const double gst = 0.18;

      const double subtotal = basic + sd + lc - nc;
      const double finalRate = subtotal * (1 + gst);

      expect(finalRate, closeTo(56350.90, 0.01));
      expect(finalRate.round(), equals(56351));
    });
  });

  group('SampleRateCalcScreen Widget Tests', () {
    testWidgets('renders desktop layout with left sidebar, canonical category tabs, and table',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('70x35', 500, 22.0),
          SampleRateSize('50x50', 0, 18.0),
        ],
        'MS Angle': [
          SampleRateSize('50x50x6', 300, 27.0),
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

      // Verify Left Sidebar Form
      expect(find.text('Base Rates Config'), findsOneWidget);
      expect(find.text('Pipe Basic'), findsOneWidget);
      expect(find.text('Angle Basic'), findsOneWidget);
      expect(find.text('Channel Basic'), findsOneWidget);
      expect(find.text('SQR Bar Basic'), findsOneWidget);
      expect(find.text('Round/Flats Basic'), findsOneWidget);
      expect(find.text('Apply Pipe Rate to All'), findsOneWidget);

      // Verify NC Discount Toggle
      expect(find.textContaining('NC Discount'), findsOneWidget);

      // Verify Canonical Category Tabs
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('MS ANGLE'), findsWidgets);

      // Verify Pricing Table Headers
      expect(find.text('SIZE DIMENSION'), findsOneWidget);
      expect(find.text('SD VALUE'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);

      // Verify Sizes Rendered
      expect(find.text('70x35 22kg'), findsOneWidget);
      expect(find.text('+₹500'), findsOneWidget);

      // Enter Pipe Basic rate and verify dynamic calculation
      final pipeInput = find.widgetWithText(TextField, '');
      await tester.enterText(pipeInput.first, '50000');
      await tester.pump();

      // Net rate should now be displayed (59,891)
      expect(find.textContaining('59,891'), findsOneWidget);
    });

    testWidgets('filters out Binding Wire, Nails, HR Pipe, and MS Structure ISMC and falls back gracefully',
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
          SampleRateSize('70x35', 500, 22.0),
        ],
        'MS Channel': [
          SampleRateSize('C 75x40', 300, 36.0),
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
      expect(find.text('70x35 22kg'), findsOneWidget);

      // Switch to MS Channel
      await tester.tap(find.text('MS CHANNEL').first);
      await tester.pump();
      expect(find.text('C 75x40 36kg'), findsOneWidget);
    });

    testWidgets('renders mobile layout on narrow viewport with collapsible card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invProvider = InventoryProvider();
      invProvider.setSampleRateCategoriesForTesting({
        'MS Pipe': [
          SampleRateSize('70x35', 500, 22.0),
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
      expect(find.text('Base Rates Config'), findsOneWidget);
      expect(find.text('MS PIPE'), findsWidgets);
      expect(find.text('SIZE DIMENSION'), findsOneWidget);
      expect(find.text('SD VALUE'), findsOneWidget);
      expect(find.text('NET COMPUTED RATE'), findsOneWidget);
    });
  });
}
