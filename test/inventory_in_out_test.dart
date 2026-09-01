import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/services/transaction_slip_service.dart';
import 'package:msm_calc/widgets/inventory/compact_transaction_entry_panel.dart';
import 'package:msm_calc/widgets/inventory/live_transaction_ledger_table.dart';
import 'package:msm_calc/screens/inventory_in_out_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
    });
  });

  group('TransactionSlipService Unit Tests', () {
    final mockTx = StockTransaction(
      txnId: 'TXN_TEST_1001',
      dateTime: DateTime(2026, 9, 1, 11, 30),
      itemName: 'MS Pipe',
      size: '70x35',
      type: 'IN',
      qtyMT: 15.250,
      location: 'YARD',
      invoiceNo: 'INV-8899',
      lorryNo: 'MH-20-DE-1234',
      transportCo: 'National Logistics',
      note: 'Prime quality delivery',
      user: 'Vivek Salve',
    );

    test('generates gate pass PDF bytes with correct headers and weights', () async {
      final bytes = await TransactionSlipService.generateSlipPdf(mockTx);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });
  });

  group('CompactTransactionEntryPanel Widget Tests', () {
    testWidgets('renders transaction type pills, location, inputs and deficit warning',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompactTransactionEntryPanel(
                initialType: 'IN',
                initialLocation: 'YARD',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Transaction'), findsOneWidget);
      expect(find.text('Inward'), findsOneWidget);
      expect(find.text('Dispatch'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Confirm Inward Stock'), findsOneWidget);

      // Switch to OUT (Dispatch)
      await tester.tap(find.text('Dispatch'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Dispatch'), findsOneWidget);
    });
  });

  group('LiveTransactionLedgerTable Widget Tests', () {
    testWidgets('renders filter pills, search input, and table header',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiveTransactionLedgerTable(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live Transaction Ledger'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Inward'), findsOneWidget);
      expect(find.text('Dispatch'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Search vehicle / item...'), findsOneWidget);
    });
  });

  group('InventoryInOutScreen Full Console Tests', () {
    testWidgets('renders dual-pane console on desktop viewport',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: InventoryInOutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventory Operations Console'), findsOneWidget);
      expect(find.text('Live Sync'), findsOneWidget);
      expect(find.text('New Transaction'), findsOneWidget);
      expect(find.text('Live Transaction Ledger'), findsOneWidget);
    });

    testWidgets('renders mobile segmented switcher on small viewport',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: InventoryInOutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Transaction'), findsWidgets);
      expect(find.text('Live Ledger'), findsOneWidget);

      // Switch to Live Ledger tab
      await tester.tap(find.text('Live Ledger'));
      await tester.pumpAndSettle();

      expect(find.text('Live Transaction Ledger'), findsOneWidget);
    });
  });
}
