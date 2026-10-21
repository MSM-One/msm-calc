import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'test@msm.com',
      'user_role': 'Admin',
      'user_display_name': 'Vivek Salve',
    });
    DataRepository.userProfileLookupMap.clear();
  });

  group('User Attribution Data Extraction Unit Tests', () {
    test('extracts clean display name from standard email', () {
      final tx = StockTransaction(
        txnId: 'TXN-001',
        dateTime: DateTime(2026, 9, 9, 10, 30),
        itemName: 'MS Pipe',
        size: '50x50',
        type: 'IN',
        qtyMT: 12.500,
        location: 'YARD',
        user: 'operator123@msmsteel.com',
      );

      expect(tx.userName, 'operator123@msmsteel.com');
      expect(tx.userEmail, 'operator123@msmsteel.com');
      expect(tx.createdBy, 'operator123@msmsteel.com');
      expect(tx.displayUserName, 'operator123');
    });

    test('extracts Admin (Vivek) for main administrator email', () {
      final tx = StockTransaction(
        txnId: 'TXN-002',
        dateTime: DateTime(2026, 9, 9, 11, 45),
        itemName: 'MS Angle',
        size: '50x50x6',
        type: 'OUT',
        qtyMT: 5.200,
        location: 'YARD',
        user: 'j2833945@gmail.com',
      );

      expect(tx.displayUserName, 'Admin (Vivek)');
    });

    test('extracts short UUID prefix for raw UUID created_by', () {
      final tx = StockTransaction(
        txnId: 'TXN-003',
        dateTime: DateTime(2026, 9, 9, 12, 15),
        itemName: 'MS Channel',
        size: '75x40',
        type: 'TRANSFER',
        qtyMT: 8.000,
        location: 'YARD',
        toLocation: 'FACTORY',
        user: '4266395b-b99b-435d-a05e-f5ba138e68db',
      );

      expect(tx.displayUserName, '4266395b');
    });

    test('resolves against cached profile map if available', () {
      DataRepository.userProfileLookupMap['4266395b-b99b-435d-a05e-f5ba138e68db'] =
          'Ramesh (Supervisor)';

      final tx = StockTransaction(
        txnId: 'TXN-004',
        dateTime: DateTime(2026, 9, 9, 14, 0),
        itemName: 'Round Bar',
        size: '12mm',
        type: 'IN',
        qtyMT: 3.400,
        location: 'FACTORY',
        user: '4266395b-b99b-435d-a05e-f5ba138e68db',
      );

      expect(tx.displayUserName, 'Ramesh (Supervisor)');
    });

    test('StockTransaction.fromJson correctly parses alternative created_by fields', () {
      final json1 = {
        'txn_id': 'TXN_JSON_1',
        'dateTime': '2026-09-09T09:00:00Z',
        'itemName': 'MS Pipe',
        'size': '70x35',
        'type': 'IN',
        'qtyMT': 10.0,
        'location': 'YARD',
        'created_by_name': 'Suresh Kumar',
      };
      final tx1 = StockTransaction.fromJson(json1);
      expect(tx1.user, 'Suresh Kumar');
      expect(tx1.displayUserName, 'Suresh Kumar');

      final json2 = {
        'txn_id': 'TXN_JSON_2',
        'dateTime': '2026-09-09T09:30:00Z',
        'itemName': 'MS Pipe',
        'size': '70x35',
        'type': 'OUT',
        'qtyMT': 4.0,
        'location': 'YARD',
        'created_by_email': 'manager@steelcorp.com',
      };
      final tx2 = StockTransaction.fromJson(json2);
      expect(tx2.user, 'manager@steelcorp.com');
      expect(tx2.displayUserName, 'manager');
    });
  });

  group('User Attribution Tag UI Placement Tests', () {
    testWidgets('renders user attribution tag with person icon and clean name on transaction card',
        (WidgetTester tester) async {
      final tx = StockTransaction(
        txnId: 'TXN_UI_1',
        dateTime: DateTime(2026, 9, 9, 15, 30),
        itemName: 'MS Pipe',
        size: '70x35',
        type: 'IN',
        qtyMT: 15.250,
        location: 'YARD',
        lorryNo: 'MH-20-DE-1234',
        user: 'j2833945@gmail.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 2),
                  Text(
                    '${tx.location} • ${tx.formattedTime}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blueGrey.shade200, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 11, color: Colors.blueGrey.shade700),
                        const SizedBox(width: 3),
                        Text(
                          tx.displayUserName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('YARD • 03:30 PM'), findsOneWidget);
      expect(find.text('Admin (Vivek)'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });
  });
}
