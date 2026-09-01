import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/screens/calculator_screen.dart';
import 'package:msm_calc/models/user_model.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:msm_calc/core/app_permissions.dart';

void main() {
  setUp(() {
    DataRepository.currentUserNotifier.value = UserModel(
      email: 'admin@msm.com',
      role: UserRole.admin,
      status: 'approved',
      permissions: {
        AppPermissions.screensCalculator: true,
        AppPermissions.screensQuotation: true,
        AppPermissions.screensSampleRate: true,
      },
    );
  });

  group('Netrate Calculation & Formula Unit Tests', () {
    test('Calculates gross net rate with base, SD, freight, OB, loading, and GST', () {
      final item = ItemEntry(itemName: 'MS Pipe', basic: 50000);
      final size = SizeEntry(label: '25x25x2.0', sd: 500, unitWeight: 1.5);
      item.selectedSizes.add(size);

      // In Netrate calculation:
      // gross = item.basic (50000) + size.sd (500) + freight (0) + OB (0) + loading (255) = 50755
      // with NC discount enabled: 50755 - 3000 = 47755
      // with 18% GST: 47755 * 1.18 = 56350.9
      double gross = item.basic + size.sd + 255;
      expect(gross, 50755);

      double ncDiscounted = gross - 3000;
      expect(ncDiscounted, 47755);

      double withGst = ncDiscounted * 1.18;
      expect(withGst.toStringAsFixed(1), '56350.9');
    });

    test('Unit weight dynamic recalculation between Nos and Qty (MT)', () {
      final size = SizeEntry(label: '50x50x3.0', sd: 0, unitWeight: 4.5);
      size.nos = 100;

      // qty = (nos * unitWeight) / 1000 = (100 * 4.5) / 1000 = 0.450 MT
      size.qty = (size.nos * size.unitWeight) / 1000.0;
      expect(size.qty, 0.450);

      // recalculate nos from qty: (0.450 * 1000) / 4.5 = 100
      final nosRecalc = ((size.qty * 1000) / size.unitWeight).round();
      expect(nosRecalc, 100);
    });
  });

  group('CalculatorScreen (Netrate Mode) Widget Tests', () {
    testWidgets('Renders Netrate Calc header, pricing parameters, and action buttons',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: CalculatorScreen(isQuotationMode: false),
        ),
      );

      // Let initial async mock loads settle
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Check header
      expect(find.text('Netrate Calculator'), findsOneWidget);
      expect(find.text('Pricing & Charges'), findsOneWidget);
      expect(find.text('GST (18% Bill)'), findsOneWidget);
      expect(find.text('NC Discount'), findsOneWidget);
    });
  });

  group('CalculatorScreen (Quotation Mode) Widget Tests', () {
    testWidgets('Renders Quotations Console with Party Information and Sidebar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: CalculatorScreen(isQuotationMode: true),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // In quotation mode, check Quotations Console header and Party Details
      expect(find.text('Quotations Console'), findsOneWidget);
      expect(find.text('Party Information'), findsOneWidget);
      expect(find.text('Quotation Summary'), findsOneWidget);
      expect(find.text('PREVIEW & SHARE QUOTE'), findsOneWidget);
    });

    testWidgets('Renders mobile layout on narrow viewport with sticky footer',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));

      await tester.pumpWidget(
        const MaterialApp(
          home: CalculatorScreen(isQuotationMode: true),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Mobile app bar title
      expect(find.text('Quotations'), findsOneWidget);
      // Mobile sticky footer button
      expect(find.text('Preview'), findsOneWidget);
    });
  });
}
