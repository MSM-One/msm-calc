import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/utils/formatters.dart';
import 'package:msm_calc/utils/steel_helper.dart';

void main() {
  group('Binding Wire & Variant Resolution Tests', () {
    test('formatSizeDisplay preserves weight variants without stripping', () {
      expect(formatSizeDisplay('Binding Wire', '18G 10kg'), '18G 10kg');
      expect(formatSizeDisplay('Binding Wire', '18G 25kg'), '18G 25kg');
      expect(formatSizeDisplay('Binding Wire', '20G 5kg'), '20G 5kg');
      expect(formatSizeDisplay('Binding Wire', '18G 10 kg'), '18G 10 kg');
    });

    test('formatMaterialSize overrides conflicting embedded weight with row weight', () {
      expect(formatMaterialSize('18G 10kg', 25.0), '18G 25kg');
      expect(formatMaterialSize('18G 25kg', 10.0), '18G 10kg');
      expect(formatMaterialSize('18G (10kg)', 25.0), '18G 25kg');
      expect(formatMaterialSize('18G 10kg', 10.0), '18G 10kg');
      expect(formatMaterialSize('18G 25kg', 25.0), '18G 25kg');
      expect(formatMaterialSize('100x50', 6.2), '100x50 6.2kg');
    });

    test('getFormattedSizeDisplay overrides conflicting embedded weight with row weight', () {
      expect(getFormattedSizeDisplay('18G 10kg', 25.0), '18G 25kg');
      expect(getFormattedSizeDisplay('18G 25kg', 10.0), '18G 10kg');
      expect(getFormattedSizeDisplay('18G (10kg)', 25.0), '18G 25kg');
      expect(getFormattedSizeDisplay('18G 10kg', 10.0), '18G 10kg');
      expect(getFormattedSizeDisplay('18G 25kg', 25.0), '18G 25kg');
      expect(getFormattedSizeDisplay('100x50', 6.2), '100x50 6.2kg');
    });

    test('SteelHelper.normalizeSizeText normalizes whitespace without collapsing variants', () {
      final norm10 = SteelHelper.normalizeSizeText('18G 10kg');
      final norm25 = SteelHelper.normalizeSizeText('18G 25kg');
      final norm10Spaced = SteelHelper.normalizeSizeText(' 18g   10 kg ');

      expect(norm10, isNot(equals(norm25)));
      expect(norm10, equals(norm10Spaced));
      expect(norm10, '18g 10kg');
      expect(norm25, '18g 25kg');
    });

    test('findSupabaseSizeId simulation preserves exact variant IDs', () {
      final masterSizes = [
        {'id': 110, 'size_label': '18G 25kg', 'material_id': 12},
        {'id': 489, 'size_label': '18G 10kg', 'material_id': 12},
        {'id': 490, 'size_label': '20G 25kg', 'material_id': 12},
      ];

      int? findSizeId(String rawText) {
        final target = rawText.trim();
        final normTarget = SteelHelper.normalizeSizeText(target);

        for (final s in masterSizes) {
          final lbl = (s['size_label'] ?? '').toString().trim();
          if (lbl.toLowerCase() == target.toLowerCase() ||
              SteelHelper.normalizeSizeText(lbl) == normTarget) {
            return s['id'] as int?;
          }
        }
        return null;
      }

      expect(findSizeId('18G 10kg'), 489);
      expect(findSizeId('18G 10 kg'), 489);
      expect(findSizeId('18G 25kg'), 110);
      expect(findSizeId('18G 25 kg'), 110);
      expect(findSizeId('20G 25kg'), 490);
    });
  });
}
