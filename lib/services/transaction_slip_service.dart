import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/stock_models.dart';
import '../utils/formatters.dart';

/// Enterprise Gate Pass & Weighment Slip Printing Service.
/// Generates thermal / A5 / A4 printable slips for Inward, Outward, and Yard Transfers.
class TransactionSlipService {
  TransactionSlipService._();

  /// Prints or previews a professional transaction gate pass / weighment slip
  static Future<void> printSlip(BuildContext context, StockTransaction tx) async {
    try {
      final bytes = await generateSlipPdf(tx);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'Gate_Pass_${tx.txnId}.pdf',
      );
    } catch (e) {
      debugPrint('[TransactionSlipService] Error printing slip: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate gate pass: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generates the raw PDF bytes for a transaction gate pass
  static Future<Uint8List> generateSlipPdf(StockTransaction tx) async {
    final pdf = pw.Document(
      title: 'Gate Pass - ${tx.txnId}',
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
    );

    final brandRed = PdfColor.fromHex('#DC2626');
    final darkSlate = PdfColor.fromHex('#0F172A');
    final mediumSlate = PdfColor.fromHex('#475569');
    final gridBorder = PdfColor.fromHex('#CBD5E1');
    final zebraBg = PdfColor.fromHex('#F8FAFC');

    final String typeLabel = tx.type == 'IN'
        ? 'INWARD GATE PASS (RECEIPT)'
        : tx.type == 'OUT'
            ? 'OUTWARD GATE PASS (DISPATCH)'
            : 'YARD TRANSFER PASS';

    final PdfColor typeColor = tx.type == 'IN'
        ? PdfColor.fromHex('#059669')
        : tx.type == 'OUT'
            ? PdfColor.fromHex('#0F172A')
            : PdfColor.fromHex('#D97706');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: darkSlate, width: 1.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ── HEADER ──
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'METAROLL / MSM ONE',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: brandRed,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Precision Steel Yard & Warehouse Operations',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            color: mediumSlate,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: typeColor,
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        typeLabel,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(color: gridBorder, thickness: 1),
                pw.SizedBox(height: 8),

                // ── METADATA GRID ──
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetaBlock('TRANSACTION ID', tx.txnId),
                    _buildMetaBlock('DATE & TIME', formatTransactionDateTime(tx.dateTime)),
                    _buildMetaBlock('LOCATION', tx.location.toUpperCase()),
                    if (tx.toLocation != null)
                      _buildMetaBlock('DESTINATION', tx.toLocation!.toUpperCase()),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetaBlock(
                        'VEHICLE / LORRY NO',
                        (tx.lorryNo != null && tx.lorryNo!.isNotEmpty)
                            ? tx.lorryNo!
                            : '—'),
                    _buildMetaBlock(
                        'INVOICE / REF NO',
                        (tx.invoiceNo != null && tx.invoiceNo!.isNotEmpty)
                            ? tx.invoiceNo!
                            : '—'),
                    _buildMetaBlock(
                        'TRANSPORT CO',
                        (tx.transportCo != null && tx.transportCo!.isNotEmpty)
                            ? tx.transportCo!
                            : '—'),
                    _buildMetaBlock(
                        'OPERATOR',
                        tx.user != null && tx.user!.isNotEmpty
                            ? tx.user!
                            : 'System Admin'),
                  ],
                ),
                pw.SizedBox(height: 14),

                // ── ITEM SPECIFICATION TABLE ──
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: gridBorder, width: 0.8),
                  ),
                  child: pw.Table(
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3.5),
                      1: const pw.FlexColumnWidth(2.5),
                      2: const pw.FlexColumnWidth(2.0),
                      3: const pw.FlexColumnWidth(2.0),
                    },
                    children: [
                      // Header
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: zebraBg),
                        children: [
                          _buildTableCell('MATERIAL / ITEM', isHeader: true),
                          _buildTableCell('SIZE / SECTION', isHeader: true),
                          _buildTableCell('WEIGHT (MT)', isHeader: true, alignRight: true),
                          _buildTableCell('WEIGHT (KG)', isHeader: true, alignRight: true),
                        ],
                      ),
                      // Data Row
                      pw.TableRow(
                        children: [
                          _buildTableCell(tx.itemName),
                          _buildTableCell(formatSizeDisplay(tx.itemName, tx.size)),
                          _buildTableCell(
                            '${tx.qtyMT.toStringAsFixed(3)} MT',
                            alignRight: true,
                            isBold: true,
                          ),
                          _buildTableCell(
                            '${(tx.qtyMT * 1000).toStringAsFixed(0)} kg',
                            alignRight: true,
                            isBold: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // ── NOTES & REMARKS ──
                if (tx.note != null && tx.note!.isNotEmpty) ...[
                  pw.Text(
                    'REMARKS / INSTRUCTIONS: ${tx.note}',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: mediumSlate,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],

                pw.Spacer(),

                // ── SIGNATURES FOOTER ──
                pw.Divider(color: gridBorder, thickness: 0.8),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSigLine('Weighbridge Operator'),
                    _buildSigLine('Driver Signature'),
                    _buildSigLine('Security Gate Pass Officer'),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Generated via MSM ERP Precision Warehouse Console · Official Audit Copy',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: mediumSlate,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildMetaBlock(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#64748B'),
          ),
        ),
        pw.SizedBox(height: 1.5),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#0F172A'),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool alignRight = false,
    bool isBold = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      alignment:
          alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 7.5 : 8.5,
          fontWeight: isHeader || isBold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          color: isHeader
              ? PdfColor.fromHex('#475569')
              : PdfColor.fromHex('#0F172A'),
        ),
      ),
    );
  }

  static pw.Widget _buildSigLine(String title) {
    return pw.Column(
      children: [
        pw.Container(
          width: 90,
          height: 1,
          color: PdfColor.fromHex('#94A3B8'),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 7.5,
            color: PdfColor.fromHex('#475569'),
          ),
        ),
      ],
    );
  }
}
