import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/stock_models.dart';

void main() {
  group('Factory Stock Calculation & Location Normalization Tests', () {
    test('StockUtils.normalizeLocation correctly handles all location variations', () {
      expect(StockUtils.normalizeLocation('factory'), equals('FACTORY'));
      expect(StockUtils.normalizeLocation('Factory'), equals('FACTORY'));
      expect(StockUtils.normalizeLocation('FACTORY'), equals('FACTORY'));
      expect(StockUtils.normalizeLocation('Plant'), equals('FACTORY'));
      expect(StockUtils.normalizeLocation('PLANT'), equals('FACTORY'));
      expect(StockUtils.normalizeLocation('  factory  '), equals('FACTORY'));
      expect(StockUtils.normalizeLocation('Factory Unit 1'), equals('FACTORY'));

      expect(StockUtils.normalizeLocation('yard'), equals('YARD'));
      expect(StockUtils.normalizeLocation('Yard'), equals('YARD'));
      expect(StockUtils.normalizeLocation('YARD'), equals('YARD'));
      expect(StockUtils.normalizeLocation('WH'), equals('YARD'));
      expect(StockUtils.normalizeLocation('Warehouse'), equals('YARD'));
      expect(StockUtils.normalizeLocation('  yard  '), equals('YARD'));

      expect(StockUtils.normalizeLocation(null), equals(''));
      expect(StockUtils.normalizeLocation(''), equals(''));
    });

    test('Factory and Yard stock summation accurately computes positive MT values', () {
      final mockItems = [
        ItemVariant(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x3',
          currentStockMT: 50.250,
          location: 'Yard',
        ),
        ItemVariant(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '35x3',
          currentStockMT: 45.455,
          location: 'YARD',
        ),
        ItemVariant(
          itemName: 'MS Flat',
          category: 'MS Flat',
          size: '20x5',
          currentStockMT: 100.000,
          location: 'WH',
        ),
        ItemVariant(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x3',
          currentStockMT: 80.500,
          location: 'Factory',
        ),
        ItemVariant(
          itemName: 'MS Channel',
          category: 'MS Channel',
          size: '75x40',
          currentStockMT: 55.205,
          location: 'FACTORY',
        ),
        ItemVariant(
          itemName: 'MS Round',
          category: 'MS Round',
          size: '12mm',
          currentStockMT: 25.100,
          location: 'Plant',
        ),
      ];

      final yardItems = mockItems.where((v) {
        final loc = StockUtils.normalizeLocation(v.location);
        return loc == 'YARD';
      }).toList();

      final factoryItems = mockItems.where((v) {
        final loc = StockUtils.normalizeLocation(v.location);
        return loc == 'FACTORY';
      }).toList();

      final double yardTotal = yardItems.fold(0.0, (s, v) => s + v.currentStockMT);
      final double factoryTotal = factoryItems.fold(0.0, (s, v) => s + v.currentStockMT);
      final double grandTotal = mockItems.fold(0.0, (s, v) => s + v.currentStockMT);

      expect(yardTotal, closeTo(195.705, 0.001));
      expect(factoryTotal, closeTo(160.805, 0.001));
      expect(grandTotal, closeTo(356.510, 0.001));

      // Category counts
      final int yardCatCount = yardItems
          .where((v) => v.currentStockMT > 0)
          .map((v) => v.category)
          .toSet()
          .length;

      final int factoryCatCount = factoryItems
          .where((v) => v.currentStockMT > 0)
          .map((v) => v.category)
          .toSet()
          .length;

      expect(yardCatCount, equals(2)); // MS Angle, MS Flat
      expect(factoryCatCount, equals(3)); // MS Angle, MS Channel, MS Round

      // Formatting validation
      expect('${factoryTotal.toStringAsFixed(3)} MT', equals('160.805 MT'));
      expect('${yardTotal.toStringAsFixed(3)} MT', equals('195.705 MT'));
    });

    test('Zero/Negative stock items are filtered from category counts', () {
      final mockItems = [
        ItemVariant(
          itemName: 'MS Pipe',
          category: 'MS Pipe',
          size: '1 inch',
          currentStockMT: 0.0,
          location: 'Factory',
        ),
        ItemVariant(
          itemName: 'MS Square',
          category: 'MS Square',
          size: '10mm',
          currentStockMT: -2.5,
          location: 'Factory',
        ),
        ItemVariant(
          itemName: 'MS Beam',
          category: 'MS Beam',
          size: '100x50',
          currentStockMT: 15.750,
          location: 'Factory',
        ),
      ];

      final factoryItems = mockItems.where((v) =>
          StockUtils.normalizeLocation(v.location) == 'FACTORY').toList();

      final double factoryTotal = factoryItems.fold(0.0, (s, v) => s + v.currentStockMT);
      final int factoryCatCount = factoryItems
          .where((v) => v.currentStockMT > 0)
          .map((v) => v.category)
          .toSet()
          .length;

      expect(factoryCatCount, equals(1)); // Only MS Beam has positive stock
      expect(factoryTotal, closeTo(13.250, 0.001));
    });
  });
}
