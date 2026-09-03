import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/services/report_calculators.dart';
import 'package:msm_calc/services/pdf_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Low Stock Calculations & Filtering Engine', () {
    final sampleInventory = [
      // MS Angle - 25x3 is at 0.000 MT (min: 3.5 MT) -> OUT OF STOCK
      ItemVariant(
        itemName: 'MS Angle',
        category: 'MS Angle',
        size: '25x3',
        currentStockMT: 0.000,
        minStock: 3.500,
        location: 'YARD',
      ),
      // MS Angle - 25x5 is at 10.500 MT (min: 3.5 MT) -> Normal (Not low stock)
      ItemVariant(
        itemName: 'MS Angle',
        category: 'MS Angle',
        size: '25x5',
        currentStockMT: 10.500,
        minStock: 3.500,
        location: 'YARD',
      ),
      // MS Angle - 32x3 is at 1.200 MT (min: 3.5 MT) -> LOW STOCK
      ItemVariant(
        itemName: 'MS Angle',
        category: 'MS Angle',
        size: '32x3',
        currentStockMT: 1.200,
        minStock: 3.500,
        location: 'YARD',
      ),
      // MS Channel - 95x45 is at -0.320 MT (min: 2.0 MT) -> DEFICIT
      ItemVariant(
        itemName: 'MS Channel',
        category: 'MS Channel',
        size: '95x45',
        currentStockMT: -0.320,
        minStock: 2.000,
        location: 'YARD',
      ),
      // MS Channel - 75x40 is at 0.500 MT (min: 2.0 MT) -> LOW STOCK
      ItemVariant(
        itemName: 'MS Channel',
        category: 'MS Channel',
        size: '75x40',
        currentStockMT: 0.500,
        minStock: 2.000,
        location: 'YARD',
      ),
      // MS Pipe - 1" is at 5.000 MT (min: 2.0 MT) -> Normal
      ItemVariant(
        itemName: 'MS Pipe',
        category: 'MS Pipe',
        size: '1"',
        currentStockMT: 5.000,
        minStock: 2.000,
        location: 'FACTORY',
      ),
      // MS Pipe - 0.75" is at 0.000 MT (min: 2.0 MT) -> OUT OF STOCK in FACTORY
      ItemVariant(
        itemName: 'MS Pipe',
        category: 'MS Pipe',
        size: '0.75"',
        currentStockMT: 0.000,
        minStock: 2.000,
        location: 'FACTORY',
      ),
    ];

    test('retains 0.000 MT and negative deficit items in low stock calculation', () {
      final lowStock = ReportCalculators.calculateLowStock(
        inventory: sampleInventory,
        locationFilter: 'ALL',
      );

      // Low stock should include:
      // MS Pipe 0.75" (0.000 MT)
      // MS Angle 25x3 (0.000 MT)
      // MS Angle 32x3 (1.200 MT)
      // MS Channel 95x45 (-0.320 MT)
      // MS Channel 75x40 (0.500 MT)
      // Total: 5 items
      expect(lowStock.length, 5);

      final hasAngle25x3 = lowStock.any((item) =>
          item.itemName == 'MS Angle' &&
          item.size == '25x3' &&
          item.currentStockMT == 0.0);
      expect(hasAngle25x3, isTrue, reason: 'MS Angle 25x3 (0.000 MT) must be present');

      final hasChannel95x45 = lowStock.any((item) =>
          item.itemName == 'MS Channel' &&
          item.size == '95x45' &&
          item.currentStockMT == -0.320);
      expect(hasChannel95x45, isTrue, reason: 'MS Channel 95x45 (-0.320 MT) must be present');
    });

    test('sorts canonical categories in order and puts 0.000 MT and deficit items first within category', () {
      final lowStock = ReportCalculators.calculateLowStock(
        inventory: sampleInventory,
        locationFilter: 'ALL',
      );

      // Category order: MS Pipe -> MS Angle -> MS Channel
      expect(lowStock[0].category, 'MS Pipe');
      expect(lowStock[0].size, '0.75"');
      expect(lowStock[0].currentStockMT, 0.000);

      // In MS Angle: 25x3 (0.000 MT) must come before 32x3 (1.200 MT)
      final angleItems = lowStock.where((e) => e.category == 'MS Angle').toList();
      expect(angleItems.length, 2);
      expect(angleItems[0].size, '25x3');
      expect(angleItems[0].currentStockMT, 0.000);
      expect(angleItems[1].size, '32x3');
      expect(angleItems[1].currentStockMT, 1.200);

      // In MS Channel: 95x45 (-0.320 MT) must come before 75x40 (0.500 MT)
      final channelItems = lowStock.where((e) => e.category == 'MS Channel').toList();
      expect(channelItems.length, 2);
      expect(channelItems[0].size, '95x45');
      expect(channelItems[0].currentStockMT, -0.320);
      expect(channelItems[1].size, '75x40');
      expect(channelItems[1].currentStockMT, 0.500);
    });

    test('correctly filters by location', () {
      final yardLowStock = ReportCalculators.calculateLowStock(
        inventory: sampleInventory,
        locationFilter: 'YARD',
      );
      expect(yardLowStock.length, 4);
      expect(yardLowStock.every((i) => i.location == 'YARD'), isTrue);

      final factoryLowStock = ReportCalculators.calculateLowStock(
        inventory: sampleInventory,
        locationFilter: 'FACTORY',
      );
      expect(factoryLowStock.length, 1);
      expect(factoryLowStock.first.size, '0.75"');
    });

    test('correctly filters by searchQuery', () {
      final searchResult = ReportCalculators.calculateLowStock(
        inventory: sampleInventory,
        locationFilter: 'ALL',
        searchQuery: 'Angle',
      );
      expect(searchResult.length, 2);
      expect(searchResult.every((i) => i.category == 'MS Angle'), isTrue);
    });

    test('PDF generation supports 0.000 MT and negative deficit items', () async {
      final lowStock = ReportCalculators.calculateLowStock(
        inventory: sampleInventory,
        locationFilter: 'ALL',
      );

      final pdfBytes = await PdfReportService.generateCombinedLowStockPdf(
        entries: lowStock,
        location: 'ALL',
        isDetailed: true,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });
}
