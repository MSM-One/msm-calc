import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/utils/formatters.dart';

void main() {
  setUp(() {
    globalSizeWeightCache.clear();
  });

  group('Size Label Deduplication & Dynamic Weight Display Tests', () {
    test('renders clean singular labels for standard sizes with weights', () {
      expect(getFormattedSizeDisplay('18G 25kg', 25.0), equals('18G 25kg'));
      expect(getFormattedSizeDisplay('20G 25kg', 25.0), equals('20G 25kg'));
      expect(getFormattedSizeDisplay('18G Random 50kg', 50.0), equals('18G Random 50kg'));
      expect(getFormattedSizeDisplay('18G 10kg', 10.0), equals('18G 10kg'));
    });

    test('deduplicates repetitive duplicate weight labels', () {
      expect(getFormattedSizeDisplay('18G 25kg 25kg', null), equals('18G 25kg'));
      expect(getFormattedSizeDisplay('18G 25kg 25kg', 25.0), equals('18G 25kg'));
      expect(getFormattedSizeDisplay('18G 10kg 10kg', null), equals('18G 10kg'));
      expect(getFormattedSizeDisplay('18G 10kg 10kg', 10.0), equals('18G 10kg'));
      expect(getFormattedSizeDisplay('18G Random 50kg 50kg', null), equals('18G Random 50kg'));
      expect(getFormattedSizeDisplay('20G 25kg 25kg', 25.0), equals('20G 25kg'));
    });

    test('handles parentheses and spacing variations in size labels', () {
      expect(getFormattedSizeDisplay('18G (25kg)', 25.0), equals('18G (25kg)'));
      expect(getFormattedSizeDisplay('18G ( 25 kg )', null), equals('18G ( 25 kg )'));
      expect(getFormattedSizeDisplay('18G 25 kg', null), equals('18G 25 kg'));
      expect(getFormattedSizeDisplay('18G (10kg)', 10.0), equals('18G (10kg)'));
      expect(getFormattedSizeDisplay('18G (10kg) 10kg', 10.0), equals('18G (10kg)'));
    });

    test('overrides conflicting embedded weight with explicit row unit_weight_kg', () {
      expect(getFormattedSizeDisplay('18G 25kg', 10.0), equals('18G 10kg'));
      expect(getFormattedSizeDisplay('18G (25kg)', 10.0), equals('18G 10kg'));
      expect(getFormattedSizeDisplay('20G 25kg', 10.0), equals('20G 10kg'));
      expect(getFormattedSizeDisplay('18G 10kg', 25.0), equals('18G 25kg'));
      expect(getFormattedSizeDisplay('18G 25kg 25kg', 10.0), equals('18G 10kg'));
    });

    test('appends weight suffix when size label does not contain weight', () {
      expect(getFormattedSizeDisplay('18G', 25.0), equals('18G 25kg'));
      expect(getFormattedSizeDisplay('20G', 10.0), equals('20G 10kg'));
      expect(getFormattedSizeDisplay('20G', 25.0), equals('20G 25kg'));
      expect(getFormattedSizeDisplay('18G Random', 50.0), equals('18G Random 50kg'));
      expect(getFormattedSizeDisplay('18G', 10.0), equals('18G 10kg'));
      expect(getFormattedSizeDisplay('1" 25x25(1.2)', 6.0), equals('1" 25x25(1.2) 6kg'));
    });

    test('preserves label when weight is 0 or not available', () {
      expect(getFormattedSizeDisplay('50x50', 0), equals('50x50'));
      expect(getFormattedSizeDisplay('70x35', null), equals('70x35'));
      expect(getFormattedSizeDisplay('', 25.0), equals(''));
    });

    test('formatSizeDisplay strips category prefix and dynamically resolves', () {
      expect(formatSizeDisplay('MS Pipe', 'MS PIPE 18G 25kg 25kg'), equals('18G 25kg'));
      expect(formatSizeDisplay('MS Pipe', '18G 10kg 10kg'), equals('18G 10kg'));
      expect(formatSizeDisplay('MS Pipe', '20G 25kg'), equals('20G 25kg'));
      expect(formatSizeDisplay('MS Pipe', '18G Random 50kg'), equals('18G Random 50kg'));
      expect(formatSizeDisplay('Binding Wire', '18G (10kg) 10kg'), equals('18G (10kg)'));
      expect(formatSizeDisplay('Binding Wire', '18G (10kg)'), equals('18G (10kg)'));
      expect(formatSizeDisplay('Binding Wire', '18G 25kg'), equals('18G 25kg'));
      expect(formatSizeDisplay('Binding Wire', '18G Random 50kg'), equals('18G Random 50kg'));
    });

    test('formatSizeLabel correctly formats labels dynamically', () {
      expect(formatSizeLabel('18G 25kg 25kg', 'MS Pipe', 25.0), equals('18G 25kg'));
      expect(formatSizeLabel('18G 10kg 10kg', 'MS Pipe', 10.0), equals('18G 10kg'));
      expect(formatSizeLabel('18G (10kg) 10kg', 'Binding Wire', 10.0), equals('18G (10kg)'));
      expect(formatSizeLabel('18G (10kg)', 'Binding Wire', 10.0), equals('18G (10kg)'));
      expect(formatSizeLabel('18G', 'MS Pipe', 25.0), equals('18G 25kg'));
      expect(formatSizeLabel('25x3', 'MS Angle', 6.2), equals('25x3 6.2kg'));
      expect(formatSizeLabel('25x3 6.2kg', 'MS Angle', 6.2), equals('25x3 6.2kg'));
      expect(formatSizeLabel('25x3 (6.2kg)', 'MS Angle', 6.2), equals('25x3 (6.2kg)'));
      expect(formatSizeLabel('25x3', 'Flats', 0.0), equals('25x3'));
    });

    test('resolveDynamicSizeTitle handles raw database labels and dynamic weights', () {
      expect(
          resolveDynamicSizeTitle(rawLabel: '18G', unitWeightKg: 25.0),
          equals('18G 25kg'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '18G 25kg', unitWeightKg: 25.0),
          equals('18G 25kg'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '18G (25kg)', unitWeightKg: 25.0),
          equals('18G (25kg)'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '20G', unitWeightKg: 10),
          equals('20G 10kg'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '25x3', unitWeightKg: 6.25),
          equals('25x3 6.25kg'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '50x50', unitWeightKg: null),
          equals('50x50'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '50x50', unitWeightKg: 0),
          equals('50x50'));
      expect(
          resolveDynamicSizeTitle(rawLabel: '', unitWeightKg: 25.0),
          equals(''));
    });

    test('StockItem and ItemVariant correctly map unit_weight_kg and produce dynamic title', () {
      final stockItemJson = {
        'item_size_id': 101,
        'material_id': 1,
        'item_name': 'MS Pipe',
        'category_name': 'MS Pipe',
        'size_label': '18G',
        'unit_weight_kg': 25.0,
        'net_stock_mt': 15.500,
        'min_stock': 5.0,
        'location': 'YARD',
      };
      final stockItem = StockItem.fromJson(stockItemJson);
      expect(stockItem.itemSizeId, equals(101));
      expect(stockItem.unitWeightKg, equals(25.0));
      expect(stockItem.displayTitle, equals('18G 25kg'));

      final variant = ItemVariant.fromSupabaseStockMap({
        'item_size_id': 102,
        'item_name': 'MS Pipe',
        'category': 'MS Pipe',
        'size_label': '20G',
        'unit_weight_kg': 10.0,
        'net_stock_mt': 8.250,
        'yard_total': 8.250,
        'factory_total': 0.0,
        'location': 'YARD',
      });
      expect(variant.itemSizeId, equals(102));
      expect(variant.unitWeightKg, equals(10.0));
      expect(variant.displayTitle, equals('20G 10kg'));
    });
  });
}

