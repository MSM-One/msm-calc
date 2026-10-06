import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/delivery_order_model.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:msm_calc/services/delivery_order_print_service.dart';

void main() {
  setUp(() {
    // Seed test customer address cache
    DataRepository.customerAddressCache['apex steel'] =
        'Plot 44, MIDC Bhosari, Pune';
    DataRepository.customerAddressCache['shree traders'] =
        'Sector 10, Gandhinagar, Gujarat';
  });

  group('Requirement 3: Size String Formatting (Industry Pattern)', () {
    test('constructs size labels directly from components with space separation', () {
      // 1" 25x25(1.2) 6
      expect(
        DeliveryOrderPrintService.formatFromComponents(
          inch: '1',
          dimension: '25x25',
          thickness: '1.2',
          weight: 6,
        ),
        '1" 25x25(1.2) 6',
      );

      // 1.5" 38x38(1.2) 8.5
      expect(
        DeliveryOrderPrintService.formatFromComponents(
          inch: '1.5',
          dimension: '38x38',
          thickness: '1.2',
          weight: 8.5,
        ),
        '1.5" 38x38(1.2) 8.5',
      );

      // 25x3 6.2
      expect(
        DeliveryOrderPrintService.formatFromComponents(
          dimension: '25x3',
          weight: 6.2,
        ),
        '25x3 6.2',
      );

      // F 40x5
      expect(
        DeliveryOrderPrintService.formatFromComponents(
          dimension: 'F 40x5',
        ),
        'F 40x5',
      );
    });

    test('parses and formats composite size strings to industry standard', () {
      expect(
        DeliveryOrderPrintService.formatIndustrySize('1" 25x25(1.2) 6'),
        '1" 25x25(1.2) 6',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize('1.5" 38x38(1.2) 8.5'),
        '1.5" 38x38(1.2) 8.5',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize('25x3 6.2'),
        '25x3 6.2',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize('F 40x5'),
        'F 40x5',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize(
          'MS Pipe 1" 25x25 (1.2mm)',
          unitWeight: 6.0,
          category: 'MS Pipe',
        ),
        '1" 25x25(1.2) 6',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize(
          '1.5" 38x38 (1.2) 8.5kg',
        ),
        '1.5" 38x38(1.2) 8.5',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize(
          'Angle 25x3 6.2kg',
          category: 'Angle',
        ),
        '25x3 6.2',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize(
          'Flat 40x5',
          category: 'Flats',
        ),
        'F 40x5',
      );

      expect(
        DeliveryOrderPrintService.formatIndustrySize(
          'Flats 40x5 6.0kg',
          category: 'Flats',
        ),
        'F 40x5 6',
      );
    });

    test('formatDeliveryOrderSize preserves thickness in parentheses from Supabase size_label', () {
      // 0.75" 19×19(1.2) with unit_weight_kg = 4
      expect(
        DeliveryOrderPrintService.formatDeliveryOrderSize(
          '0.75" 19×19(1.2)',
          unitWeight: 4,
        ),
        '0.75" 19×19(1.2) 4',
      );

      // 0.75" 19×19(1.6) with unit_weight_kg = 5
      expect(
        DeliveryOrderPrintService.formatDeliveryOrderSize(
          '0.75" 19×19(1.6)',
          unitWeight: 5,
        ),
        '0.75" 19×19(1.6) 5',
      );

      // 1" 25×25(1.2) with unit_weight_kg = 6
      expect(
        DeliveryOrderPrintService.formatDeliveryOrderSize(
          '1" 25×25(1.2)',
          unitWeight: 6,
        ),
        '1" 25×25(1.2) 6',
      );

      // With DeliveryOrderSizeModel
      final sizeModel = DeliveryOrderSizeModel(
        size: '0.75" 19×19(1.2)',
        qty: 1.5,
        rate: 54000,
        bd: '375 Pcs x 4.00 kg = 1.500 MT',
        unitWeight: 4.0,
      );
      expect(
        DeliveryOrderPrintService.formatDeliveryOrderSize(sizeModel),
        '0.75" 19×19(1.2) 4',
      );

      // When weight is already present at the end
      expect(
        DeliveryOrderPrintService.formatDeliveryOrderSize(
          '0.75" 19×19(1.2) 4',
          unitWeight: 4,
        ),
        '0.75" 19×19(1.2) 4',
      );

      expect(
        DeliveryOrderPrintService.formatDeliveryOrderSize(
          '0.75" 19×19(1.2) 4kg',
          unitWeight: 4,
        ),
        '0.75" 19×19(1.2) 4',
      );
    });
  });

  group('Requirement 1 & 2: Header Grid & Item Summary (No Rate Type)', () {
    test('Header metadata and party address fallbacks resolve correctly', () {
      final model = DeliveryOrderDataModel(
        documentTitle: 'Delivery Order',
        poNo: 'DO-20261005-01',
        poDate: '2026-10-04',
        dealerName: 'Apex Steel',
        billingName: 'Apex Steel Industries',
        billingAddress: 'Plot 44, MIDC Bhosari, Pune',
        consigneeName: 'Apex Warehouse',
        dispatchAddress: 'Plot 44, MIDC Bhosari, Pune',
        shippingAddress: 'Plot 44, MIDC Bhosari, Pune',
        orderDate: '2026-10-05',
        billType: 'BILL',
        ob: '150',
        freight: 'To Pay',
        lorryNo: 'MH-12-AB-1234',
        note: 'Urgent site dispatch',
        signedBy: 'Supervisor',
        approvedBy: 'Manager',
        items: [
          DeliveryOrderItemModel(
            item: 'MS Pipe',
            saudaRate: 54000,
            rateType: 'BILL',
            balanceQty: 5.0,
            sizes: [
              DeliveryOrderSizeModel(
                size: '1" 25x25(1.2) 6',
                qty: 2.4,
                rate: 54000,
                bd: '400 Pcs x 6.00 kg = 2.400 MT',
                nos: 400,
                unitWeight: 6.0,
              ),
              DeliveryOrderSizeModel(
                size: '1.5" 38x38(1.2) 8.5',
                qty: 2.6,
                rate: 54000,
                bd: '305 Pcs x 8.50 kg = 2.600 MT',
                nos: 305,
                unitWeight: 8.5,
              ),
            ],
          ),
          DeliveryOrderItemModel(
            item: 'Angle',
            saudaRate: 51000,
            rateType: 'BILL',
            balanceQty: 3.1,
            sizes: [
              DeliveryOrderSizeModel(
                size: '25x3 6.2',
                qty: 3.1,
                rate: 51000,
                bd: '500 Pcs x 6.20 kg = 3.100 MT',
                nos: 500,
                unitWeight: 6.2,
              ),
            ],
          ),
        ],
      );

      final html = DeliveryOrderPrintService.generateHtml(model);

      // Title Condition
      expect(html, contains('DELIVERY ORDER'));

      // 1. Top Metadata Row
      expect(html, contains('PO Order No.:'));
      expect(html, contains('DO-20261005-01'));
      expect(html, contains('Date:'));
      expect(html, contains('05/10/2026'));
      expect(html, contains('Freight:'));
      expect(html, contains('To Pay'));
      expect(html, contains('Lorry No:'));
      expect(html, contains('MH-12-AB-1234'));
      expect(html, contains('OB:'));
      expect(html, contains('150'));
      expect(html, contains('PO Date:'));
      expect(html, contains('04/10/2026'));
      expect(html, contains('Bill Type:'));
      expect(html, contains('BILL'));

      // 1. Party Details Block
      expect(html, contains('Dealer Name:'));
      expect(html, contains('Apex Steel'));
      expect(html, contains('Billing Name:'));
      expect(html, contains('Apex Steel Industries'));
      expect(html, contains('Billing Address:'));
      expect(html, contains('Plot 44, MIDC Bhosari, Pune'));
      expect(html, contains('Consignee Name:'));
      expect(html, contains('Apex Warehouse'));
      expect(html, contains('Shipping Address:'));

      // 2. Item & Sauda Rates Summary Table (No Rate Type column)
      expect(html, contains('Item &amp; Sauda Rates'));
      expect(html, contains('5.000 MT'));
      expect(html, contains('3.100 MT'));
      expect(html, isNot(contains('<th style="width:10%; text-align:center;">Rate Type</th>')));

      // 4. Main Grid Columns
      expect(html, contains('Qty (MT)'));
      expect(html, contains('Breakdown'));
      expect(html, contains('Net Rate'));
      expect(html, contains('1" 25x25(1.2) 6'));
      expect(html, contains('1.5" 38x38(1.2) 8.5'));
      expect(html, contains('25x3 6.2'));

      // 4. Bottom Summary: Total MT
      expect(html, contains('Total'));
      expect(html, contains('8.100'));
      expect(html, contains('MT'));

      // 5. Footer: Clean Note & Signatures (Document ID removed completely)
      expect(html, isNot(contains('Document ID:')));
      expect(html, contains('Note: Urgent site dispatch'));
      expect(html, contains('Order Signed'));
      expect(html, contains('Approved By'));
      expect(html, contains('Supervisor'));
      expect(html, contains('Manager'));
    });

    test('Cleanly omits empty address fields and never prints hardcoded N.D.: Del At', () {
      final model = DeliveryOrderDataModel(
        documentTitle: 'Delivery Order',
        poNo: 'DO-100',
        poDate: '',
        dealerName: 'Unknown Trader',
        billingName: '',
        billingAddress: '', // empty
        consigneeName: '',
        dispatchAddress: '',
        shippingAddress: '', // empty
        orderDate: '2026-10-05',
        billType: 'NC',
        ob: '',
        freight: '',
        lorryNo: '',
        note: '',
        signedBy: '',
        approvedBy: '',
        items: [
          DeliveryOrderItemModel(
            item: 'Flats',
            saudaRate: 48000,
            balanceQty: 1.0,
            sizes: [
              DeliveryOrderSizeModel(
                size: 'F 40x5',
                qty: 1.0,
                rate: 48000,
                bd: '1.000 MT',
              ),
            ],
          ),
        ],
      );

      final html = DeliveryOrderPrintService.generateHtml(model);
      expect(html, isNot(contains('N.D.: Del At')));
      expect(html, isNot(contains('Billing Address:')));
      expect(html, isNot(contains('Shipping Address:')));
      expect(html, contains('Dealer Name:'));
      expect(html, contains('Unknown Trader'));
    });

    test('generates valid PDF document without throwing', () async {
      final model = DeliveryOrderDataModel(
        documentTitle: 'Delivery Order',
        poNo: 'DO-999',
        poDate: '2026-10-05',
        dealerName: 'Shree Traders',
        billingName: 'Shree Infra Pvt Ltd',
        billingAddress: 'Sector 10, Gandhinagar, Gujarat',
        consigneeName: 'Site Project Alpha',
        dispatchAddress: 'Site Project Alpha, Ahmedabad',
        shippingAddress: 'Site Project Alpha, Ahmedabad',
        orderDate: '2026-10-05',
        billType: 'BILL',
        ob: 100,
        freight: 450,
        lorryNo: 'GJ-01-XX-5555',
        note: 'Check bundle tags',
        signedBy: 'Despatch In-Charge',
        approvedBy: 'Director',
        items: [
          DeliveryOrderItemModel(
            item: 'Flats',
            saudaRate: 48000,
            rateType: 'BILL',
            balanceQty: 2.0,
            sizes: [
              DeliveryOrderSizeModel(
                size: 'F 40x5',
                qty: 2.0,
                rate: 48000,
                bd: '2.000 MT',
              ),
            ],
          ),
        ],
      );

      final Uint8List pdfBytes =
          await DeliveryOrderPrintService.generatePdf(model);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });
}
