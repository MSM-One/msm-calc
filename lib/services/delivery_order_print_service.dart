import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/delivery_order_model.dart';
import '../services/data_repository.dart';
import '../utils/file_download_helper.dart' as download_helper;
import '../utils/item_order_util.dart';
import '../utils/sauda_rate_calculator.dart';
import '../utils/sorting_utils.dart';

class DeliveryOrderPrintService {
  static const PdfColor _borderColor = PdfColors.black;
  static final PdfColor _headerBg = PdfColor.fromHex('#F0F0F0');
  static final PdfColor _brandRed = PdfColor.fromHex('#C61A22');

  static Future<pw.ImageProvider?> _loadBrandLogo() async {
    try {
      final data = await rootBundle.load('assets/sTEEL MART .jpg');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      try {
        final data2 = await rootBundle.load('assets/dashboard_logo.jpg');
        return pw.MemoryImage(data2.buffer.asUint8List());
      } catch (_) {
        return null;
      }
    }
  }

  /// Builds a high-precision, automated A4 Delivery Order PDF matching the technical specification.
  static Future<Uint8List> generatePdf(DeliveryOrderDataModel model) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
    );

    final brandLogo = await _loadBrandLogo();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 14,
          marginRight: 14,
          marginTop: 14,
          marginBottom: 14,
        ),
        margin: const pw.EdgeInsets.all(14),
        build: (context) {
          return [
            _buildCompanyHeader(brandLogo),
            pw.SizedBox(height: 4),
            _buildTitleBanner(model),
            pw.SizedBox(height: 4),
            _buildHeaderGrid(model),
            pw.SizedBox(height: 6),
            if (model.items.isNotEmpty) ...[
              _buildItemSaudaRatesTable(model),
              pw.SizedBox(height: 6),
            ],
            _buildDetailsTable(model),
            pw.SizedBox(height: 6),
            _buildFooterBlock(model),
          ];
        },
      ),
    );

    return doc.save();
  }

  /// Header with Company Logo / Branding
  static pw.Widget _buildCompanyHeader(pw.ImageProvider? brandLogo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "METAROLL STEEL MART",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _brandRed,
              ),
            ),
            pw.Text(
              "Iron & Steel Merchants | Structural Steel Specialists",
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
        if (brandLogo != null)
          pw.Container(
            height: 32,
            child: pw.Image(brandLogo, fit: pw.BoxFit.contain),
          ),
      ],
    );
  }

  /// Document Title Banner
  static pw.Widget _buildTitleBanner(DeliveryOrderDataModel model) {
    final String title = model.documentTitle.isNotEmpty
        ? model.documentTitle.toUpperCase()
        : 'SAUDA BOOK / DELIVERY ORDER';
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: pw.BoxDecoration(
        color: _brandRed,
        border: pw.Border.all(color: _borderColor, width: 0.8),
      ),
      child: pw.Center(
        child: pw.Text(
          title,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  /// Grid 1: Header Table (Split into 66% left Firm & Remarks & 34% right Date, Vehicle)
  static pw.Widget _buildHeaderGrid(DeliveryOrderDataModel model) {
    final firm = model.dealerName.isNotEmpty
        ? model.dealerName
        : (model.billingName.isNotEmpty ? model.billingName : "-");
    final date = model.orderDate.isNotEmpty ? model.orderDate : "-";
    final vehicle =
        model.lorryNo.isNotEmpty ? model.lorryNo.toUpperCase() : "-";

    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.0), // 66% Firm Name & Remarks
        1: pw.FlexColumnWidth(1.0), // 34% Date & Vehicle
      },
      children: [
        pw.TableRow(
          children: [
            // Left Column (Firm Name & Remarks)
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPartyField("Firm Name:", firm),
                  if (model.note.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    _buildPartyField("Remarks:", model.note),
                  ],
                ],
              ),
            ),
            // Right Column (Date, Vehicle No)
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildOrderField("Date:", date),
                  pw.SizedBox(height: 4),
                  _buildOrderField("Vehicle No:", vehicle),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPartyField(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: "$label ",
            style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black),
          ),
          pw.TextSpan(
            text: value.isNotEmpty ? value : "-",
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildOrderField(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }

  /// Grid 2: Item & Sauda Rates Table (Horizontal 2-Item Pairing with 8 columns)
  static pw.Widget _buildItemSaudaRatesTable(DeliveryOrderDataModel model) {
    final validItems = model.items
        .where((i) => i.totalQty > 0 || i.sizes.isNotEmpty)
        .toList()
      ..sort((a, b) => ItemOrderUtil.compare(a.item, b.item));

    final List<pw.TableRow> rows = [
      // Sub-headers Row
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _headerBg),
        children: [
          _buildTableCell("Item", isHeader: true),
          _buildTableCell("Rate", isHeader: true, align: pw.TextAlign.right),
          _buildTableCell("Rate Type", isHeader: true, align: pw.TextAlign.center),
          _buildTableCell("Qty", isHeader: true, align: pw.TextAlign.right),
          _buildTableCell("Item", isHeader: true),
          _buildTableCell("Rate", isHeader: true, align: pw.TextAlign.right),
          _buildTableCell("Rate Type", isHeader: true, align: pw.TextAlign.center),
          _buildTableCell("Qty", isHeader: true, align: pw.TextAlign.right),
        ],
      ),
    ];

    // Group items into pairs of 2 per row
    for (int i = 0; i < validItems.length; i += 2) {
      final left = validItems[i];
      final right = (i + 1 < validItems.length) ? validItems[i + 1] : null;

      // Format left
      String leftRate = left.saudaRate?.toString() ?? "-";
      if (leftRate.isNotEmpty &&
          leftRate != "-" &&
          double.tryParse(leftRate) != null) {
        leftRate = NumberFormat("#,##,##0").format(double.parse(leftRate));
      }
      String leftRateType = left.rateType.isNotEmpty
          ? left.rateType
          : (model.billType.isNotEmpty ? model.billType : "-");
      String leftQty = "${left.totalQty.toStringAsFixed(3)} MT";

      // Format right
      String rightItem = "";
      String rightRate = "";
      String rightRateType = "";
      String rightQty = "";
      if (right != null) {
        rightItem = right.item;
        rightRate = right.saudaRate?.toString() ?? "-";
        if (rightRate.isNotEmpty &&
            rightRate != "-" &&
            double.tryParse(rightRate) != null) {
          rightRate = NumberFormat("#,##,##0").format(double.parse(rightRate));
        }
        rightRateType = right.rateType.isNotEmpty
            ? right.rateType
            : (model.billType.isNotEmpty ? model.billType : "-");
        rightQty = "${right.totalQty.toStringAsFixed(3)} MT";
      }

      rows.add(
        pw.TableRow(
          children: [
            // Left Item
            _buildTableCell(left.item, isBold: true),
            _buildTableCell(leftRate, align: pw.TextAlign.right),
            _buildTableCell(leftRateType, align: pw.TextAlign.center),
            _buildTableCell(leftQty, align: pw.TextAlign.right, isBold: true),
            // Right Item
            _buildTableCell(rightItem, isBold: right != null),
            _buildTableCell(rightRate, align: pw.TextAlign.right),
            _buildTableCell(rightRateType, align: pw.TextAlign.center),
            _buildTableCell(rightQty, align: pw.TextAlign.right, isBold: right != null),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Spanning Header Banner: "Item & Sauda Rates"
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          decoration: pw.BoxDecoration(
            color: _headerBg,
            border: pw.Border.all(color: _borderColor, width: 0.8),
          ),
          child: pw.Center(
            child: pw.Text(
              "Item & Sauda Rates",
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _brandRed,
              ),
            ),
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.8),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.0), // Item 1
            1: pw.FlexColumnWidth(1.2), // Rate 1
            2: pw.FlexColumnWidth(1.2), // Rate Type 1
            3: pw.FlexColumnWidth(1.3), // Qty 1
            4: pw.FlexColumnWidth(2.0), // Item 2
            5: pw.FlexColumnWidth(1.2), // Rate 2
            6: pw.FlexColumnWidth(1.2), // Rate Type 2
            7: pw.FlexColumnWidth(1.3), // Qty 2
          },
          children: rows,
        ),
      ],
    );
  }

  /// Grid 3: Specification Breakdown Table [Sr | Item | Sizes | Qty (MT) | Breakdown | Net Rate]
  static pw.Widget _buildDetailsTable(DeliveryOrderDataModel model) {
    final List<pw.TableRow> rows = [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _headerBg),
        children: [
          _buildTableCell("Sr", isHeader: true, align: pw.TextAlign.center),
          _buildTableCell("Item", isHeader: true),
          _buildTableCell("Sizes", isHeader: true),
          _buildTableCell("Qty (MT)", isHeader: true, align: pw.TextAlign.right),
          _buildTableCell("Breakdown", isHeader: true),
          _buildTableCell("Net Rate", isHeader: true, align: pw.TextAlign.right),
        ],
      ),
    ];

    int srNo = 1;
    double grandTotalQty = 0;
    final charges = DataRepository.instance.globalCharges;
    final double freight =
        double.tryParse(model.freight?.toString() ?? '0') ?? 0.0;
    final double ob = double.tryParse(model.ob?.toString() ?? '0') ?? 0.0;

    final sortedItems = List<DeliveryOrderItemModel>.from(model.items)
      ..sort((a, b) => ItemOrderUtil.compare(a.item, b.item));

    for (var item in sortedItems) {
      final double saudaRate =
          double.tryParse(item.saudaRate?.toString() ?? '0') ?? 0.0;
      final String itemBillType =
          item.rateType.isNotEmpty ? item.rateType : model.billType;

      final sortedSizes = List<DeliveryOrderSizeModel>.from(item.sizes)
        ..sort((a, b) => SortingUtils.compareSizes(a.size, b.size));

      for (var size in sortedSizes) {
        if (size.qty <= 0 && size.size.isEmpty) continue;
        grandTotalQty += size.qty;

        String sizeDisplay = size.size.isNotEmpty ? size.size : "Standard";
        if (size.unitWeight != null &&
            size.unitWeight! > 0 &&
            !sizeDisplay.contains(size.unitWeight!.toStringAsFixed(1))) {
          sizeDisplay = "$sizeDisplay ${size.unitWeight!.toStringAsFixed(1)}";
        }

        final double sd = DataRepository.getSizeSD(item.item, size.size);

        String breakdownStr = size.bd;
        String netRateStr = "-";

        if (saudaRate > 0) {
          final calcResult = SaudaRateCalculator.calculate(
            saudaRate: saudaRate,
            sd: sd,
            charges: charges,
            billType: itemBillType,
            itemType: item.item,
            freight: freight,
            ob: ob,
          );
          breakdownStr = calcResult.breakdownString;
          netRateStr = calcResult.netRate % 1 == 0
              ? "${calcResult.netRate.toInt()}"
              : NumberFormat("#,##0").format(calcResult.netRate);
        } else if (size.rate > 0) {
          netRateStr = size.rate % 1 == 0
              ? "${size.rate.toInt()}"
              : NumberFormat("#,##0").format(size.rate);
        }

        rows.add(
          pw.TableRow(
            children: [
              _buildTableCell("$srNo", align: pw.TextAlign.center),
              _buildTableCell(item.item, isBold: true),
              _buildTableCell(sizeDisplay),
              _buildTableCell(
                size.qty.toStringAsFixed(3),
                align: pw.TextAlign.right,
                isBold: true,
              ),
              _buildTableCell(breakdownStr.isNotEmpty ? breakdownStr : "-"),
              _buildTableCell(netRateStr, align: pw.TextAlign.right, isBold: true),
            ],
          ),
        );
        srNo++;
      }
    }

    // Footer Row: Total, Grand Total Tonnage, MT Unit Label
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _headerBg),
        children: [
          _buildTableCell("", isHeader: true),
          _buildTableCell("Total", isHeader: true, isBold: true),
          _buildTableCell("", isHeader: true),
          _buildTableCell(
            grandTotalQty.toStringAsFixed(3),
            isHeader: true,
            isBold: true,
            align: pw.TextAlign.right,
          ),
          _buildTableCell("MT", isHeader: true, isBold: true),
          _buildTableCell("", isHeader: true),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.8),
          columnWidths: const {
            0: pw.FixedColumnWidth(22),  // Sr
            1: pw.FlexColumnWidth(1.6), // Item
            2: pw.FlexColumnWidth(2.0), // Sizes
            3: pw.FlexColumnWidth(1.4), // Qty (MT)
            4: pw.FlexColumnWidth(2.6), // Breakdown
            5: pw.FlexColumnWidth(1.4), // Net Rate
          },
          children: rows,
        ),
      ],
    );
  }

  /// Footer: Note Section & Signatures Section
  static pw.Widget _buildFooterBlock(DeliveryOrderDataModel model) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Note Section: Bordered Box with "Note:" and 3 blank horizontal guide lines
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderColor, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "Note: ",
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (model.note.isNotEmpty)
                    pw.Expanded(
                      child: pw.Text(
                        model.note,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  ),
                ),
              ),
              pw.SizedBox(height: 2),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        // Signatures Grid: 2 equal-width columns (Left: Order Signed, Right: Approved By)
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.8),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(1.0),
          },
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  height: 48,
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        "Order Signed",
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        model.signedBy.isNotEmpty
                            ? model.signedBy
                            : "Authorized Signatory",
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  height: 48,
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        "Approved By",
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        model.approvedBy.isNotEmpty
                            ? model.approvedBy
                            : "For METAROLL STEEL MART",
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            "*** This is a computer generated Delivery Order and subject to Jalna Jurisdiction ***",
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isHeader ? 7.5 : 8,
          fontWeight: (isHeader || isBold)
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Generates the standard HTML layout string with CSS & JS auto-scaling for Web printing
  static String generateHtml(DeliveryOrderDataModel model) {
    final validItems = model.items
        .where((i) => i.totalQty > 0 || i.sizes.isNotEmpty)
        .toList()
      ..sort((a, b) => ItemOrderUtil.compare(a.item, b.item));

    final StringBuffer saudaSummaryHtml = StringBuffer();
    for (int i = 0; i < validItems.length; i += 2) {
      final left = validItems[i];
      final right = (i + 1 < validItems.length) ? validItems[i + 1] : null;

      String leftRate = left.saudaRate?.toString() ?? "-";
      if (leftRate.isNotEmpty &&
          leftRate != "-" &&
          double.tryParse(leftRate) != null) {
        leftRate = NumberFormat("#,##,##0").format(double.parse(leftRate));
      }
      String leftRateType = left.rateType.isNotEmpty
          ? left.rateType
          : (model.billType.isNotEmpty ? model.billType : "-");
      String leftQty = "${left.totalQty.toStringAsFixed(3)} MT";

      String rightItem = "";
      String rightRate = "";
      String rightRateType = "";
      String rightQty = "";
      if (right != null) {
        rightItem = right.item;
        rightRate = right.saudaRate?.toString() ?? "-";
        if (rightRate.isNotEmpty &&
            rightRate != "-" &&
            double.tryParse(rightRate) != null) {
          rightRate = NumberFormat("#,##,##0").format(double.parse(rightRate));
        }
        rightRateType = right.rateType.isNotEmpty
            ? right.rateType
            : (model.billType.isNotEmpty ? model.billType : "-");
        rightQty = "${right.totalQty.toStringAsFixed(3)} MT";
      }

      saudaSummaryHtml.writeln('''
        <tr>
          <td><strong>${left.item}</strong></td>
          <td style="text-align:right;">$leftRate</td>
          <td style="text-align:center;">$leftRateType</td>
          <td style="text-align:right;"><strong>$leftQty</strong></td>
          <td><strong>$rightItem</strong></td>
          <td style="text-align:right;">$rightRate</td>
          <td style="text-align:center;">$rightRateType</td>
          <td style="text-align:right;"><strong>$rightQty</strong></td>
        </tr>
      ''');
    }

    final StringBuffer rowsHtml = StringBuffer();
    int srNo = 1;
    double grandTotalQty = 0;
    final charges = DataRepository.instance.globalCharges;
    final double freight =
        double.tryParse(model.freight?.toString() ?? '0') ?? 0.0;
    final double ob = double.tryParse(model.ob?.toString() ?? '0') ?? 0.0;

    final sortedItems = List<DeliveryOrderItemModel>.from(model.items)
      ..sort((a, b) => ItemOrderUtil.compare(a.item, b.item));

    for (var item in sortedItems) {
      final double saudaRate =
          double.tryParse(item.saudaRate?.toString() ?? '0') ?? 0.0;
      final String itemBillType =
          item.rateType.isNotEmpty ? item.rateType : model.billType;

      final sortedSizes = List<DeliveryOrderSizeModel>.from(item.sizes)
        ..sort((a, b) => SortingUtils.compareSizes(a.size, b.size));

      for (var size in sortedSizes) {
        if (size.qty <= 0 && size.size.isEmpty) continue;
        grandTotalQty += size.qty;

        String sizeDisplay = size.size.isNotEmpty ? size.size : "Standard";
        if (size.unitWeight != null &&
            size.unitWeight! > 0 &&
            !sizeDisplay.contains(size.unitWeight!.toStringAsFixed(1))) {
          sizeDisplay = "$sizeDisplay ${size.unitWeight!.toStringAsFixed(1)}";
        }

        final double sd = DataRepository.getSizeSD(item.item, size.size);

        String breakdownStr = size.bd;
        String netRateStr = "-";

        if (saudaRate > 0) {
          final calcResult = SaudaRateCalculator.calculate(
            saudaRate: saudaRate,
            sd: sd,
            charges: charges,
            billType: itemBillType,
            itemType: item.item,
            freight: freight,
            ob: ob,
          );
          breakdownStr = calcResult.breakdownString;
          netRateStr = calcResult.netRate % 1 == 0
              ? "${calcResult.netRate.toInt()}"
              : NumberFormat("#,##0").format(calcResult.netRate);
        } else if (size.rate > 0) {
          netRateStr = size.rate % 1 == 0
              ? "${size.rate.toInt()}"
              : NumberFormat("#,##0").format(size.rate);
        }

        rowsHtml.writeln('''
          <tr>
            <td style="text-align:center;">$srNo</td>
            <td><strong>${item.item}</strong></td>
            <td>$sizeDisplay</td>
            <td style="text-align:right;"><strong>${size.qty.toStringAsFixed(3)}</strong></td>
            <td>${breakdownStr.isNotEmpty ? breakdownStr : "-"}</td>
            <td style="text-align:right;"><strong>$netRateStr</strong></td>
          </tr>
        ''');
        srNo++;
      }
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Delivery Order - ${model.poNo.isNotEmpty ? model.poNo : model.lorryNo}</title>
  <style>
    .print-only { display: block; }
    @page { size: A4 portrait; margin: 5mm; }
    body { background: #fff !important; margin: 0; padding: 0; font-family: Arial, sans-serif; font-size: 11px; }
    .do-page { 
      width: 100%; 
      --print-scale: 1; 
      transform: scale(var(--print-scale)); 
      transform-origin: top left; 
    }
    .do-title {
      background: #C61A22;
      color: #fff;
      font-weight: bold;
      text-align: center;
      padding: 6px;
      font-size: 14px;
      letter-spacing: 1px;
      border: 1px solid #000;
    }
    .do-table { width: 100%; border-collapse: collapse; table-layout: fixed; margin-top: 4px; }
    .do-table td, .do-table th { border: 1px solid #000; padding: 4px 5px; vertical-align: top; font-size: 10px; }
    .header-table { width: 100%; border-collapse: collapse; margin-top: 4px; }
    .header-table td { border: 1px solid #000; padding: 5px; vertical-align: top; }
    .footer-table { width: 100%; border-collapse: collapse; margin-top: 4px; }
    .footer-table td { border: 1px solid #000; padding: 6px; height: 48px; vertical-align: top; }
  </style>
</head>
<body>
  <div id="printTableLayout" class="print-only do-page">
    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
      <div>
        <h2 style="color:#C61A22; margin:0; font-size:16px;">METAROLL STEEL MART</h2>
        <small>Iron & Steel Merchants | Structural Steel Specialists</small>
      </div>
    </div>
    <div class="do-title">${model.documentTitle.isNotEmpty ? model.documentTitle.toUpperCase() : "SAUDA BOOK / DELIVERY ORDER"}</div>
    
    <table class="header-table">
      <tr>
        <td style="width:66%;">
          <strong>Firm Name:</strong> ${model.dealerName.isNotEmpty ? model.dealerName : (model.billingName.isNotEmpty ? model.billingName : "-")}<br>
          ${model.note.isNotEmpty ? "<strong>Remarks:</strong> ${model.note}" : ""}
        </td>
        <td style="width:34%;">
          <strong>Date:</strong> ${model.orderDate.isNotEmpty ? model.orderDate : "-"}<br>
          <strong>Vehicle No:</strong> ${model.lorryNo.isNotEmpty ? model.lorryNo.toUpperCase() : "-"}
        </td>
      </tr>
    </table>

    ${saudaSummaryHtml.isNotEmpty ? '''
    <table class="do-table" style="margin-top:4px;">
      <thead>
        <tr style="background:#f0f0f0;">
          <th colspan="8" style="text-align:center; font-weight:bold; color:#C61A22;">Item &amp; Sauda Rates</th>
        </tr>
        <tr style="background:#f0f0f0;">
          <th style="width:16%;">Item</th>
          <th style="width:10%; text-align:right;">Rate</th>
          <th style="width:10%; text-align:center;">Rate Type</th>
          <th style="width:14%; text-align:right;">Qty</th>
          <th style="width:16%;">Item</th>
          <th style="width:10%; text-align:right;">Rate</th>
          <th style="width:10%; text-align:center;">Rate Type</th>
          <th style="width:14%; text-align:right;">Qty</th>
        </tr>
      </thead>
      <tbody>
        $saudaSummaryHtml
      </tbody>
    </table>
    ''' : ''}

    <table class="do-table" style="margin-top:4px;">
      <thead>
        <tr style="background:#f0f0f0;">
          <th style="width:25px; text-align:center;">Sr</th>
          <th>Item</th>
          <th>Sizes</th>
          <th style="text-align:right;">Qty (MT)</th>
          <th>Breakdown</th>
          <th style="text-align:right;">Net Rate</th>
        </tr>
      </thead>
      <tbody>
        $rowsHtml
        <tr style="background:#f0f0f0; font-weight:bold;">
          <td></td>
          <td>Total</td>
          <td></td>
          <td style="text-align:right;">${grandTotalQty.toStringAsFixed(3)}</td>
          <td>MT</td>
          <td></td>
        </tr>
      </tbody>
    </table>

    <div style="border:1px solid #000; padding:6px; margin-top:4px;">
      <div style="font-weight:bold; margin-bottom:4px;">Note: ${model.note}</div>
      <div style="border-bottom:1px solid #ccc; height:12px; margin-bottom:4px;"></div>
      <div style="border-bottom:1px solid #ccc; height:12px; margin-bottom:4px;"></div>
      <div style="border-bottom:1px solid #ccc; height:12px;"></div>
    </div>

    <table class="footer-table" style="margin-top:4px;">
      <tr>
        <td style="width:50%;">
          <strong>Order Signed</strong><br><br>
          ${model.signedBy.isNotEmpty ? model.signedBy : "Authorized Signatory"}
        </td>
        <td style="width:50%;">
          <strong>Approved By</strong><br><br>
          ${model.approvedBy.isNotEmpty ? model.approvedBy : "For METAROLL STEEL MART"}
        </td>
      </tr>
    </table>
  </div>

  <script>
    function applyPrintScale() {
      const page = document.getElementById("printTableLayout");
      if (!page) return;
      page.style.setProperty("--print-scale", "1");
      page.style.height = "auto";
      const availablePx = 1085;
      const h = page.getBoundingClientRect().height;
      if (h > 0 && h > availablePx) {
        const scaleFactor = Math.min(1, availablePx / h);
        page.style.setProperty("--print-scale", String(scaleFactor));
        page.style.height = (h * scaleFactor) + "px";
      }
    }
    window.onload = function() {
      applyPrintScale();
      window.print();
    };
  </script>
</body>
</html>
''';
  }

  /// Trigger native Print Flow (compatible with Web, Windows, Android, iOS)
  static Future<void> printOrder(
      BuildContext context, DeliveryOrderDataModel model) async {
    final pdfBytes = await generatePdf(model);
    final String fileName =
        "Delivery_Order_${model.poNo.isNotEmpty ? model.poNo : (model.lorryNo.isNotEmpty ? model.lorryNo : DateFormat('yyyyMMdd_HHmm').format(DateTime.now()))}.pdf";

    download_helper.setDocumentTitle(fileName);

    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: fileName,
    );
  }

  /// Trigger PDF Share Flow
  static Future<void> shareOrderPdf(
      BuildContext context, DeliveryOrderDataModel model) async {
    final pdfBytes = await generatePdf(model);
    final String fileName =
        "Delivery_Order_${model.poNo.isNotEmpty ? model.poNo : (model.lorryNo.isNotEmpty ? model.lorryNo : DateFormat('yyyyMMdd_HHmm').format(DateTime.now()))}.pdf";

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: fileName,
    );
  }
}
