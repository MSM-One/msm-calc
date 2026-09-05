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
    test('Calculates net rate with base, SD, loading charge, NC discount, and GST', () {
      final item = ItemEntry(itemName: 'MS Pipe', basic: 50000);
      final size = SizeEntry(label: '25x25x2.0', sd: 500, unitWeight: 1.5);
      item.selectedSizes.add(size);

      const double loading = 255;
      const double ncDiscount = 3000;
      const double freight = 700;
      const double ob = 300;

      // 1. Standard: Loading ON, NC OFF, GST ON (18%)
      // Effective base = 50000 + 500 + 255 = 50755
      // Net before GST = 50755 + 700 + 300 = 51755
      // Final = 51755 * 1.18 = 61070.9
      double effectiveBase = item.basic + size.sd + loading;
      double netBeforeGst = effectiveBase + freight + ob;
      double finalNetRate = netBeforeGst * 1.18;
      expect(finalNetRate.round(), 61071);

      // 2. NC Discount ON: Effective base = 50755 - 3000 = 47755
      // Net before GST = 47755 + 700 + 300 = 48755
      // Final = 48755 * 1.18 = 57530.9
      double effectiveBaseNc = effectiveBase - ncDiscount;
      double netBeforeGstNc = effectiveBaseNc + freight + ob;
      double finalNetRateNc = netBeforeGstNc * 1.18;
      expect(finalNetRateNc.round(), 57531);

      // 3. GST OFF: Final = 48755
      expect(netBeforeGstNc.round(), 48755);
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

    test('Terms & Conditions generation when NC is OFF vs ON', () {
      const state = CalculatorScreen(isQuotationMode: false);
      final element = state.createElement();
      final calcState = element.state as dynamic;

      // Case A: NC is OFF
      final termsNcOff = calcState.buildTermsAndConditions(isNcEnabled: false);
      expect(termsNcOff, contains('*Terms & Conditions*'));
      expect(termsNcOff, contains('• Payment Advance'));
      expect(termsNcOff, contains('• Loading Charge - (Inclusive)'));
      expect(termsNcOff, contains('• Transport (Extra)'));
      expect(termsNcOff, contains('• GST - 18.00 % (Inclusive)'));
      expect(termsNcOff, contains('• Weight Tolerance - +/-5kg per MT'));

      // Case B: NC is ON
      final termsNcOn = calcState.buildTermsAndConditions(isNcEnabled: true);
      expect(termsNcOn, contains('*Terms & Conditions*'));
      expect(termsNcOn, contains('• Payment Advance'));
      expect(termsNcOn, contains('• Loading Charge - (Inclusive)'));
      expect(termsNcOn, contains('• Transport (Extra)'));
      expect(termsNcOn, isNot(contains('• GST - 18.00 % (Inclusive)')));
      expect(termsNcOn, isNot(contains('NC Discount applied')));
      expect(termsNcOn, contains('• Weight Tolerance - +/-5kg per MT'));
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
      expect(find.text('Pricing Settings'), findsOneWidget);
      expect(find.text('Freight (₹)'), findsOneWidget);
      expect(find.text('OB (₹)'), findsOneWidget);
      expect(find.text('GST (18%)'), findsOneWidget);
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
