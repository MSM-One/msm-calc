import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/report_models.dart';

class MonthReportExportService {
  static String monthLabel(DateTime selectedMonth) {
    return '${selectedMonth.month}/${selectedMonth.year}';
  }

  static String fileName(DateTime selectedMonth) {
    final mm = selectedMonth.month.toString().padLeft(2, '0');
    return 'month_report_${selectedMonth.year}_$mm.pdf';
  }

  static Future<Uint8List> buildPdf({
    required DateTime selectedMonth,
    required List<MonthReportEntry> entries,
    required double totalIn,
    required double totalOut,
  }) async {
    final doc = pw.Document();
    final monthText = monthLabel(selectedMonth);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (context) => [
          pw.Text(
            'Metaroll Steel Mart Month Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Month: $monthText',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _metricBlock('Total IN', totalIn),
                _metricBlock('Total OUT', totalOut),
                _metricBlock('Net Movement', totalIn - totalOut),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.8),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.0),
              5: const pw.FlexColumnWidth(1.0),
            },
            headers: const [
              'Category',
              'Item',
              'Opening',
              'IN (MT)',
              'OUT (MT)',
              'Closing'
            ],
            data: [
              ...entries.map(
                (e) => [
                  e.category,
                  e.item,
                  e.openingQty.abs().toStringAsFixed(3),
                  e.inQty.abs().toStringAsFixed(3),
                  e.outQty.abs().toStringAsFixed(3),
                  e.closingQty.abs().toStringAsFixed(3),
                ],
              ),
              [
                'TOTAL',
                '',
                entries
                    .fold(0.0, (s, e) => s + e.openingQty.abs())
                    .toStringAsFixed(3),
                totalIn.abs().toStringAsFixed(3),
                totalOut.abs().toStringAsFixed(3),
                (totalIn - totalOut).abs().toStringAsFixed(3),
              ],
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static String buildTextSummary({
    required DateTime selectedMonth,
    required List<MonthReportEntry> entries,
    required double totalIn,
    required double totalOut,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Metaroll Steel Mart Month Report (${monthLabel(selectedMonth)})');
    buffer.writeln('Total IN: ${totalIn.toStringAsFixed(3)} MT');
    buffer.writeln('Total OUT: ${totalOut.toStringAsFixed(3)} MT');
    buffer
        .writeln('Net Movement: ${(totalIn - totalOut).toStringAsFixed(3)} MT');
    buffer.writeln('');
    buffer.writeln('Category | Item | Opening | IN | OUT | Closing');
    buffer.writeln('------------------------------------------------');
    for (final e in entries) {
      buffer.writeln(
        '${e.category} | ${e.item} | ${e.openingQty.toStringAsFixed(3)} | ${e.inQty.toStringAsFixed(3)} | ${e.outQty.toStringAsFixed(3)} | ${e.closingQty.toStringAsFixed(3)}',
      );
    }
    return buffer.toString();
  }

  static pw.Widget _metricBlock(String label, double value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(value.toStringAsFixed(3),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
