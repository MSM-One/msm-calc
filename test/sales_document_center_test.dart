import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/core/app_permissions.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/screens/sales_document_center_screen.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:msm_calc/models/stock_role.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_email': 'admin@msm.com',
      'user_role': 'Admin',
    });

    UserSession.userEmail = 'admin@msm.com';
    UserSession.currentRole = StockRole.ADMIN;

    DataRepository.currentUserNotifier.value = UserModel(
      email: 'admin@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {
        AppPermissions.screensReports: true,
      },
    );
  });

  group('Sales Document Center Calculations & Logic', () {
    test('AmountToWords converts correctly to Indian English currency words', () {
      expect(AmountToWords.convert(0), equals('Zero'));
      expect(AmountToWords.convert(1500), equals('One Thousand Five Hundred'));
      expect(AmountToWords.convert(54321),
          equals('Fifty Four Thousand Three Hundred and Twenty One'));
      expect(AmountToWords.convert(1234567),
          equals('Twelve Lakh Thirty Four Thousand Five Hundred and Sixty Seven'));
    });

    test('SalesSizeRow and SalesProductGroup dynamic calculations', () {
      final group = SalesProductGroup(productName: 'MS Pipe');
      group.basicRateController.text = '50000';

      final size1 = SalesSizeRow(
        sizeLabel: '70x35',
        sd: 500,
        unitWeight: 22.0,
        nos: 100,
        qty: 2.2,
        rate: 50500,
      );

      final size2 = SalesSizeRow(
        sizeLabel: '50x50',
        sd: 0,
        unitWeight: 18.0,
        nos: 50,
        qty: 0.9,
        rate: 50000,
      );

      group.sizes.addAll([size1, size2]);

      expect(group.totalQty, closeTo(3.1, 0.001));
      expect(group.totalAmount, equals((50500 * 2.2).roundToDouble() + (50000 * 0.9).roundToDouble()));
    });
  });

  group('SalesDocumentCenterScreen Widget Tests', () {
    testWidgets('renders document switcher, document info, customer fields, line items, and PDF action',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: SalesDocumentCenterScreen(),
        ),
      );
      await tester.pump();

      // Screen title
      expect(find.text('Sales Document Center'), findsOneWidget);

      // Segmented Switcher buttons
      expect(find.text('Proforma Invoice'), findsOneWidget);
      expect(find.text('Quotation'), findsOneWidget);

      // Sections
      expect(find.text('Document Information'), findsOneWidget);
      expect(find.text('Products & Items'), findsOneWidget);
      expect(find.text('Financial Summary'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('Bank Details'), findsWidgets);

      // Customer fields
      expect(find.text('Sr No / Reference'), findsOneWidget);
      expect(find.text('Firm Name (To:)'), findsOneWidget);
      expect(find.text('Address'), findsWidgets);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Mobile No'), findsOneWidget);
      expect(find.text('GSTIN'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);

      // PDF button
      expect(find.text('Generate PDF'), findsOneWidget);

      // Switch to Quotation mode
      await tester.tap(find.text('Quotation'));
      await tester.pump();

      // Verify Sr No updated to QT
      final srNoField = find.widgetWithText(TextFormField, 'MSMPL/26-27/QT/05');
      expect(srNoField, findsOneWidget);

      // Switch back to Proforma Invoice
      await tester.tap(find.text('Proforma Invoice'));
      await tester.pump();

      final piSrNoField = find.widgetWithText(TextFormField, 'MSMPL/26-27/PI/05');
      expect(piSrNoField, findsOneWidget);
    });

    testWidgets('renders mobile layout on narrow viewport cleanly without overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: SalesDocumentCenterScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Sales Document Center'), findsOneWidget);
      expect(find.text('Proforma Invoice'), findsOneWidget);
      expect(find.text('Quotation'), findsOneWidget);
      expect(find.text('Document Information'), findsOneWidget);
      expect(find.text('Products & Items'), findsOneWidget);
      expect(find.text('Financial Summary'), findsOneWidget);
      expect(find.text('Generate PDF'), findsOneWidget);
    });
  });
}
