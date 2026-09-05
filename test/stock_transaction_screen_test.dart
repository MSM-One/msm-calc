import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/screens/stock_transaction_screen.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
      'user_display_name': 'Admin User',
    });
    DataRepository.currentUserNotifier.value = UserModel(
      email: 'test@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {},
    );
    DataRepository.sheetDataNotifier.value = {
      'items': [
        {
          'id': 1,
          'name': 'MS PIPE',
          'sizes': [
            {'id': 101, 'label': '25x25 (1")', 'weight': 6.5, 'sd': 0.0},
            {'id': 102, 'label': '32x32 (1.25")', 'weight': 8.5, 'sd': 0.0},
          ]
        },
        {
          'id': 2,
          'name': 'MS ANGLE',
          'sizes': [
            {'id': 201, 'label': '25x3 6.2kg', 'weight': 6.2, 'sd': 0.0},
          ]
        }
      ]
    };
  });

  group('StockTransactionScreen Root Layout and Components Test', () {
    testWidgets('renders Scaffold, AppBar, Scrollable Sections, and Pinned Bottom Bar',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: StockTransactionScreen(
            initialType: 'IN',
            initialItem: 'MS PIPE',
            initialSize: '25x25 (1")',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Check AppBar
      expect(find.text('MSM ONE'), findsOneWidget);
      expect(find.text('Stock In Transaction'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // 2. Check Type Switcher
      expect(find.text('IN'), findsOneWidget);
      expect(find.text('OUT'), findsOneWidget);
      expect(find.text('TRANSFER'), findsOneWidget);
      expect(find.text('ADJUSTMENT'), findsOneWidget);

      // 3. Check Details Card Fields
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Bill/Invoice Number'), findsOneWidget);
      expect(find.text('Lorry Number'), findsWidgets);

      // 4. Check Transport Accordion
      expect(find.text('Advanced Transport Details'), findsOneWidget);

      // 5. Check Products Section
      expect(find.text('Products & Items'), findsOneWidget);
      expect(find.text('ADD ITEM'), findsOneWidget);

      // 6. Check Split Loading Card
      expect(find.text('Split Loading (Hand vs Crane)'), findsOneWidget);

      // 7. Check Pinned Sticky Bottom Bar
      expect(find.text('TOTAL WEIGHT'), findsOneWidget);
      expect(find.text('0.000 MT'), findsWidgets);
      expect(find.text('Proceed'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    });

    testWidgets('switches transaction type dynamically to Stock Out and Stock Transfer',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: StockTransactionScreen(
            initialType: 'IN',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stock In Transaction'), findsOneWidget);

      // Switch to OUT
      await tester.tap(find.text('OUT'));
      await tester.pumpAndSettle();
      expect(find.text('Stock Out Transaction'), findsOneWidget);

      // Switch to TRANSFER
      await tester.tap(find.text('TRANSFER'));
      await tester.pumpAndSettle();
      expect(find.text('Stock Transfer'), findsOneWidget);
      expect(find.text('From Location'), findsOneWidget);
      expect(find.text('To Location'), findsOneWidget);
    });
  });
}
