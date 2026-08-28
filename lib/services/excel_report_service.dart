import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/report_models.dart';

class ExcelReportService {
  static List<int>? generateStockMovementExcel({
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required List<StockMovementEntry> entries,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Stock Movement'];

    final df = DateFormat('dd MMM yyyy');

    // Header
    sheet.appendRow([TextCellValue('Metaroll STEEL MART')]);
    sheet.appendRow([TextCellValue('Stock Movement')]);
    sheet.appendRow([
      TextCellValue('Period: ${df.format(startDate)} to ${df.format(endDate)}')
    ]);
    sheet.appendRow([TextCellValue('Location: $location')]);
    sheet.appendRow([]); // Empty row

    // Table Headers
    sheet.appendRow([
      TextCellValue('Item Name'),
      TextCellValue('Size'),
      TextCellValue('Opening (MT)'),
      TextCellValue('In (MT)'),
      TextCellValue('Out (MT)'),
      TextCellValue('Closing (MT)')
    ]);

    // Data
    for (var e in entries) {
      if (e.sizes.isNotEmpty) {
        for (var s in e.sizes) {
          sheet.appendRow([
            TextCellValue(e.itemName),
            TextCellValue(s.label),
            DoubleCellValue(s.opening),
            DoubleCellValue(s.inQty),
            DoubleCellValue(s.outQty),
            DoubleCellValue(s.closing),
          ]);
        }
      } else {
        sheet.appendRow([
          TextCellValue(e.itemName),
          TextCellValue(e.size),
          DoubleCellValue(e.opening),
          DoubleCellValue(e.inQty),
          DoubleCellValue(e.outQty),
          DoubleCellValue(e.closing),
        ]);
      }
    }

    return excel.encode();
  }

  static List<int>? generateDeadStockExcel({
    required List<DeadStockEntry> entries,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Non-Moving Stock'];

    sheet.appendRow([TextCellValue('Metaroll STEEL MART')]);
    sheet.appendRow([TextCellValue('Non-Moving Stock')]);
    sheet.appendRow([TextCellValue('Items with zero movement in 60+ days')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('Item Name'),
      TextCellValue('Size'),
      TextCellValue('Current Qty (MT)'),
      TextCellValue('Days Since Last Movement')
    ]);

    for (var e in entries) {
      sheet.appendRow([
        TextCellValue(e.itemName),
        TextCellValue(e.size),
        DoubleCellValue(e.currentQty),
        IntCellValue(e.daysSinceLastMovement),
      ]);
    }

    return excel.encode();
  }

  static List<int>? generateDailySummaryExcel({
    required DateTime date,
    required List<DailyMovementEntry> entries,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Today’s Summary'];
    final df = DateFormat('dd MMM yyyy');

    sheet.appendRow([TextCellValue('Metaroll STEEL MART')]);
    sheet.appendRow([TextCellValue('Today’s Summary')]);
    sheet.appendRow([TextCellValue('Date: ${df.format(date)}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('Item Name'),
      TextCellValue('Size'),
      TextCellValue('Inward (MT)'),
      TextCellValue('Outward (MT)'),
      TextCellValue('Net Change (MT)'),
    ]);

    for (var e in entries) {
      sheet.appendRow([
        TextCellValue(e.itemName),
        TextCellValue(e.size),
        DoubleCellValue(e.inQty),
        DoubleCellValue(e.outQty),
        DoubleCellValue(e.netQty),
      ]);
    }

    return excel.encode();
  }

  static List<int>? generateConsolidatedStockExcel({
    required List<ConsolidatedStockEntry> entries,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Stock Overview'];
    final df = DateFormat('dd MMM yyyy');

    sheet.appendRow([TextCellValue('Metaroll STEEL MART')]);
    sheet.appendRow([TextCellValue('Stock Overview')]);
    sheet.appendRow([TextCellValue('Date: ${df.format(DateTime.now())}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('Item Name'),
      TextCellValue('Yard Qty (MT)'),
      TextCellValue('Factory Qty (MT)'),
      TextCellValue('Total (MT)'),
    ]);

    for (var e in entries) {
      sheet.appendRow([
        TextCellValue(e.itemName),
        DoubleCellValue(e.yardQty),
        DoubleCellValue(e.factoryQty),
        DoubleCellValue(e.totalMT),
      ]);
    }

    return excel.encode();
  }
}
