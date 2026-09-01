import 'package:intl/intl.dart';
import '../utils/item_order_util.dart';
import '../utils/formatters.dart';

/// Professional WhatsApp Share Service for MSM ERP Dealer Stock Sheet.
/// Formats trade availability and pricing into clean, emoji-styled WhatsApp broadcasts.
class WhatsappShareService {
  WhatsappShareService._();

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');

  /// Formats all or selected categories into an enterprise WhatsApp stock broadcast
  static String formatFullStockBroadcast({
    required String location,
    required Map<String, List<Map<String, dynamic>>> groupedStock,
    DateTime? timestamp,
    Set<String>? selectedItemKeys,
  }) {
    final now = timestamp ?? DateTime.now();
    final dateStr = _dateFormat.format(now);
    final timeStr = _timeFormat.format(now);

    final StringBuffer buffer = StringBuffer();

    // ── 1. HEADER ──
    buffer.writeln('🏢 *METAROLL / MSM ONE*');
    buffer.writeln('📋 *AVAILABLE DEALER STOCK SHEET*');
    buffer.writeln('📍 *Location:* ${location.toUpperCase()} | 📅 *Date:* $dateStr ($timeStr)');
    buffer.writeln('═══════════════════════════');
    buffer.writeln();

    // ── 2. SORT CATEGORIES IN CANONICAL SEQUENCE ──
    final sortedCategories = groupedStock.keys.toList()
      ..sort(ItemOrderUtil.compare);

    double grandTotalMT = 0.0;
    int totalItemsCount = 0;

    for (final category in sortedCategories) {
      final allRows = groupedStock[category] ?? [];
      final activeRows = selectedItemKeys == null
          ? allRows
          : allRows.where((r) {
              final key = '${r['category_name']}_${r['size_label']}';
              return selectedItemKeys.contains(key);
            }).toList();

      if (activeRows.isEmpty) continue;

      double catTotalMT = 0.0;
      for (final r in activeRows) {
        catTotalMT += (r['current_stock_mt'] as num?)?.toDouble() ?? 0.0;
      }
      grandTotalMT += catTotalMT;
      totalItemsCount += activeRows.length;

      // Category Header
      buffer.writeln('📦 *${category.toUpperCase()}* [Total: ${catTotalMT.toStringAsFixed(3)} MT]');

      for (final row in activeRows) {
        final sizeLabel = row['size_label']?.toString() ?? '';
        final double stockMT = (row['current_stock_mt'] as num?)?.toDouble() ?? 0.0;
        final double unitWt = (row['unit_weight_kg'] as num?)?.toDouble() ?? 0.0;
        final double sd = (row['size_difference'] as num?)?.toDouble() ?? 0.0;

        final formattedSize = formatSizeDisplay(category, sizeLabel);
        final StringBuffer itemLine = StringBuffer('  • $formattedSize');

        if (unitWt > 0) {
          itemLine.write(' (${unitWt.toStringAsFixed(2)} kg)');
        }

        if (stockMT < 0) {
          itemLine.write(' ➔ ⚠️ *${stockMT.toStringAsFixed(3)} MT* (Deficit)');
        } else {
          itemLine.write(' ➔ *${stockMT.toStringAsFixed(3)} MT*');
        }

        if (sd != 0) {
          final sdSign = sd > 0 ? '+₹' : '-₹';
          itemLine.write(' [SD: $sdSign${sd.abs().toStringAsFixed(0)}/MT]');
        }

        buffer.writeln(itemLine.toString());
      }
      buffer.writeln('───────────────────────────');
    }

    // ── 3. FOOTER SUMMARY ──
    buffer.writeln();
    buffer.writeln('📊 *TOTAL AVAILABLE STOCK:* ${grandTotalMT.toStringAsFixed(3)} MT');
    buffer.writeln('🔢 *TOTAL SIZES LISTED:* $totalItemsCount');
    buffer.writeln('⚡ *Rates:* Standard Base Rate + SD applicable as per terms.');
    buffer.writeln('📞 *MSM Sales & Yard Dispatch Desk*');
    buffer.writeln('_Generated via MSM ERP Precision Console_');

    return buffer.toString();
  }

  /// Formats a single category for quick category copy
  static String formatCategoryBroadcast({
    required String category,
    required List<Map<String, dynamic>> rows,
    required String location,
    DateTime? timestamp,
    Set<String>? selectedItemKeys,
  }) {
    final now = timestamp ?? DateTime.now();
    final dateStr = _dateFormat.format(now);

    final activeRows = selectedItemKeys == null
        ? rows
        : rows.where((r) {
            final key = '${r['category_name']}_${r['size_label']}';
            return selectedItemKeys.contains(key);
          }).toList();

    double catTotalMT = 0.0;
    for (final r in activeRows) {
      catTotalMT += (r['current_stock_mt'] as num?)?.toDouble() ?? 0.0;
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('🏢 *MSM ONE* | 📍 *${location.toUpperCase()}* ($dateStr)');
    buffer.writeln('📦 *${category.toUpperCase()}* — *${catTotalMT.toStringAsFixed(3)} MT*');
    buffer.writeln('───────────────────────────');

    for (final row in activeRows) {
      final sizeLabel = row['size_label']?.toString() ?? '';
      final double stockMT = (row['current_stock_mt'] as num?)?.toDouble() ?? 0.0;
      final double unitWt = (row['unit_weight_kg'] as num?)?.toDouble() ?? 0.0;
      final double sd = (row['size_difference'] as num?)?.toDouble() ?? 0.0;

      final formattedSize = formatSizeDisplay(category, sizeLabel);
      final StringBuffer itemLine = StringBuffer('• $formattedSize');

      if (unitWt > 0) {
        itemLine.write(' (${unitWt.toStringAsFixed(2)} kg)');
      }

      if (stockMT < 0) {
        itemLine.write(' ➔ ⚠️ *${stockMT.toStringAsFixed(3)} MT*');
      } else {
        itemLine.write(' ➔ *${stockMT.toStringAsFixed(3)} MT*');
      }

      if (sd != 0) {
        final sdSign = sd > 0 ? '+₹' : '-₹';
        itemLine.write(' [SD: $sdSign${sd.abs().toStringAsFixed(0)}]');
      }

      buffer.writeln(itemLine.toString());
    }
    buffer.writeln('───────────────────────────');
    buffer.writeln('📞 Contact MSM Sales for Bookings');

    return buffer.toString();
  }
}
