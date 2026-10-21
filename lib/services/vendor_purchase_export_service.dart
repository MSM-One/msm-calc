import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

class VendorPurchaseExportService {
  static Future<Uint8List> generatePdf({
    required List<dynamic> reports,
    required double totalQty,
    required double avgRate,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = DateFormat('dd-MMM-yyyy').format(now);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Metaroll Steel Mart VENDOR PURCHASE REPORT',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.Divider(thickness: 2, color: PdfColors.red),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
        ),
        build: (context) => [
          // Summary Section
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                _buildSummaryItem('Total Order Qty',
                    '${totalQty.toStringAsFixed(3)} MT', PdfColors.black),
                pw.VerticalDivider(color: PdfColors.grey400),
                _buildSummaryItem('Weighted Avg Rate',
                    'Rs. ${avgRate.toStringAsFixed(2)}', PdfColors.red),
              ],
            ),
          ),

          // Table
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerHeight: 25,
            cellHeight: 22,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(1), // Sr.No
              1: const pw.FlexColumnWidth(2), // Date
              2: const pw.FlexColumnWidth(3), // Party Name
              3: const pw.FlexColumnWidth(2.5), // Items
              4: const pw.FlexColumnWidth(1.5), // Rate
              5: const pw.FlexColumnWidth(1.5), // Ord Qty
              6: const pw.FlexColumnWidth(1.5), // Received
              7: const pw.FlexColumnWidth(1.5), // Balance Qty
              8: const pw.FlexColumnWidth(2), // Remark
            },
            headers: [
              'Sr.No',
              'Date',
              'Party Name',
              'Items',
              'Rate',
              'Ord Qty',
              'Received',
              'Balance Qty',
              'Remark'
            ],
            data: (() {
              double totalOrd = 0;
              double totalRec = 0;
              double totalBal = 0;

              final rows = reports.asMap().entries.map((entry) {
                final int index = entry.key;
                final dynamic r = entry.value;
                final String item = r['item']?.toString() ?? "";
                final String size = r['size']?.toString() ?? "";
                final String combinedItem =
                    size.isNotEmpty ? "$item ($size)" : item;
                final double ord = (r['ord'] as num?)?.toDouble() ?? 0.0;
                final double rec = (r['rec'] as num?)?.toDouble() ?? 0.0;
                final double bal = ord - rec;

                totalOrd += ord.abs();
                totalRec += rec.abs();
                totalBal += bal.abs();

                return [
                  (index + 1).toString(),
                  r['date']?.toString() ?? "",
                  r['party']?.toString() ?? "",
                  combinedItem,
                  "Rs. ${r['rate']}",
                  ord.abs().toStringAsFixed(3),
                  rec.abs().toStringAsFixed(3),
                  bal.abs().toStringAsFixed(3),
                  r['remark']?.toString() ?? "",
                ];
              }).toList();

              rows.add([
                'TOTAL',
                '',
                '',
                '',
                '',
                totalOrd.abs().toStringAsFixed(3),
                totalRec.abs().toStringAsFixed(3),
                totalBal.abs().toStringAsFixed(3),
                '',
              ]);

              return rows;
            })(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSummaryItem(
      String label, String value, PdfColor textColor) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: textColor)),
      ],
    );
  }

  static Future<Uint8List> generateExcel(
      {required List<dynamic> reports}) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Vendor_Purchase_Report'];
    excel.delete('Sheet1'); // Remove default sheet

    // Header Style
    final CellStyle headerStyle = CellStyle(
      bold: true,
      fontFamily: getFontFamily(FontFamily.Arial),
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.red,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Headers
    final headers = [
      'ID',
      'Date',
      'Vendor Name',
      'Item',
      'Size',
      'Order Qty (MT)',
      'Rate (INR)',
      'Received Qty',
      'Balance Qty',
      'Remark'
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Apply header styling
    for (var i = 0; i < headers.length; i++) {
      var cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.cellStyle = headerStyle;
    }

    // Data Rows
    for (var r in reports) {
      sheet.appendRow([
        TextCellValue(r['srNo']?.toString() ?? ""),
        TextCellValue(r['date']?.toString() ?? ""),
        TextCellValue(r['party']?.toString() ?? ""),
        TextCellValue(r['item']?.toString() ?? ""),
        TextCellValue(r['size']?.toString() ?? ""),
        DoubleCellValue((r['ord'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((r['rate'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((r['rec'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((r['bal'] as num?)?.toDouble() ?? 0.0),
        TextCellValue(r['remark']?.toString() ?? ""),
      ]);
    }

    final bytes = excel.save();
    return Uint8List.fromList(bytes!);
  }
}
