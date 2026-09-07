import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:msm_calc/providers/inventory_provider.dart';
import 'package:msm_calc/screens/sauda_booking_screen.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/models/delivery_order_model.dart';
import 'package:msm_calc/core/app_permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
      'sauda_firm': 'Test Steel Traders',
      'sauda_shipping_address': 'Plot 42, MIDC Industrial Area, Nagpur',
      'sauda_vehicle': 'MH-20-AA-1234',
      'sauda_remarks': 'Urgent dispatch required',
      'customer_addresses_cache':
          '{"Test Steel Traders":"Plot 42, MIDC Industrial Area, Nagpur","Apex Builders":"Sector 5, Pune"}',
    });

    DataRepository.customerAddressCache.clear();
    DataRepository.customerAddressCache['Test Steel Traders'] =
        'Plot 42, MIDC Industrial Area, Nagpur';
    DataRepository.customerAddressCache['Apex Builders'] = 'Sector 5, Pune';

    DataRepository.currentUserNotifier.value = UserModel(
      email: 'test@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {
        AppPermissions.screensSaudaBooking: true,
      },
    );
  });

  group('SaudaItem and SaudaSize Unit Tests', () {
    test('calculates total quantity across multiple size rows', () {
      final item = SaudaItem();
      item.itemType = 'MS Pipe';

      final size1 = SaudaSize()
        ..size = '70x35'
        ..weight = 22.0
        ..nos = 10
        ..total = 0.220;

      final size2 = SaudaSize()
        ..size = '50x50'
        ..weight = 18.0
        ..nos = 20
        ..total = 0.360;

      item.sizes = [size1, size2];

      expect(item.getTotalQty(), closeTo(0.580, 0.001));
    });

    test('manual mode quantity overrides size calculations', () {
      final item = SaudaItem();
      item.itemType = 'MS Angle';
      item.manualMode = true;
      item.manualQty = 12.500;

      expect(item.getTotalQty(), equals(12.500));
    });

    test('calculates basic rate for Net rate type with GST and loading', () {
      final item = SaudaItem();
      item.itemType = 'MS Pipe';
      item.orderType = 'Bill';
      item.rateType = 'Net';
      item.rate = 59000.0;

      // Net formula: (rate / (1 + 0.18)) - 450
      item.calculateAll(450.0, 0.18);

      expect(item.basicRate, closeTo((59000.0 / 1.18) - 450.0, 0.1));
    });
  });

  group('DeliveryOrderDataModel Unit Tests', () {
    test('serializes and deserializes shippingAddress correctly', () {
      final order = DeliveryOrderDataModel(
        poNo: 'PO-101',
        poDate: '07/09/2026',
        dealerName: 'Apex Builders',
        billingName: 'Apex Builders',
        billingAddress: 'Sector 5, Pune',
        consigneeName: 'Apex Site 1',
        dispatchAddress: 'Sector 5, Pune',
        shippingAddress: 'Sector 5, Warehouse B, Pune',
        orderDate: '07/09/2026',
        billType: 'BILL',
        ob: '',
        freight: '',
        lorryNo: 'MH-12-PQ-9999',
        note: 'Handle with care',
        signedBy: 'Admin',
        approvedBy: 'Lead',
        items: [],
      );

      final json = order.toJson();
      expect(json['shippingAddress'], 'Sector 5, Warehouse B, Pune');

      final deserialized = DeliveryOrderDataModel.fromJson(json);
      expect(deserialized.shippingAddress, 'Sector 5, Warehouse B, Pune');
    });

    test('falls back to dispatchAddress if shippingAddress is empty in json', () {
      final json = {
        'poNo': 'PO-102',
        'dealerName': 'Test Traders',
        'dispatchAddress': 'MIDC Wardha',
        'items': <dynamic>[],
      };

      final deserialized = DeliveryOrderDataModel.fromJson(json);
      expect(deserialized.shippingAddress, 'MIDC Wardha');
    });
  });

  group('SaudaBookingScreen Widget Tests', () {
    testWidgets(
        'renders basic details with Shipping / Delivery Address on desktop',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final inventoryProvider = InventoryProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryProvider>.value(
              value: inventoryProvider,
            ),
          ],
          child: const MaterialApp(
            home: SaudaBookingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sauda & Delivery Order'), findsOneWidget);
      expect(find.text('Basic Details'), findsOneWidget);
      expect(find.text('Firm / Customer Name'), findsOneWidget);
      expect(find.text('Shipping / Delivery Address'), findsOneWidget);
      expect(find.text('Items & Rates'), findsOneWidget);
      expect(find.text('+ Add Material Item'), findsOneWidget);
      expect(find.text('Other Details'), findsOneWidget);
      expect(find.text('Booking Summary'), findsOneWidget);
      expect(find.text('Print Delivery Order'), findsOneWidget);
      expect(find.text('Share Order Text'), findsOneWidget);
    });

    testWidgets('renders mobile layout with sleek footer strip',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final inventoryProvider = InventoryProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryProvider>.value(
              value: inventoryProvider,
            ),
          ],
          child: const MaterialApp(
            home: SaudaBookingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total Quantity Booked'), findsOneWidget);
      expect(find.text('Share Order'), findsOneWidget);
      expect(find.text('Print Order'), findsOneWidget);
      expect(find.text('Shipping / Delivery Address'), findsOneWidget);
    });
  });
}
