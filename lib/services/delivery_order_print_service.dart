import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  /// Helper to format date into DD/MM/YYYY format
  static String formatDateDdMmYyyy(String rawDate) {
    if (rawDate.trim().isEmpty) return '';
    final s = rawDate.trim();
    if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(s)) return s;

    try {
      final parsed = DateTime.tryParse(s);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy').format(parsed);
      }
    } catch (_) {}

    try {
      final parts = s.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          // yyyy-mm-dd
          return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
        } else if (parts[2].length == 4) {
          // dd-mm-yyyy
          return '${parts[0].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[2]}';
        }
      }
    } catch (_) {}

    return s;
  }

  /// Formats the size column for the Delivery Order PDF items table.
  /// Directly takes `item.sizeLabel` (or `size.sizeLabel` / `size.size` / `item.name`)
  /// which ALREADY contains the thickness in parentheses (e.g., `0.75" 19×19(1.2)`),
  /// and appends the clean piece weight / unit weight if not already ending with it.
  static String formatDeliveryOrderSize(
    dynamic itemOrSize, {
    double? unitWeight,
    String? category,
  }) {
    String baseLabel = '';
    num? weight = unitWeight;

    if (itemOrSize is DeliveryOrderSizeModel) {
      baseLabel = itemOrSize.size.trim();
      weight ??= itemOrSize.unitWeight;
    } else if (itemOrSize is String) {
      baseLabel = itemOrSize.trim();
    } else if (itemOrSize != null) {
      try {
        baseLabel = (itemOrSize.sizeLabel ??
                itemOrSize.name ??
                itemOrSize.size ??
                '')
            .toString()
            .trim();
        weight ??= (itemOrSize.unitWeightKg ??
            itemOrSize.pieceWeight ??
            itemOrSize.unitWeight);
      } catch (_) {
        baseLabel = itemOrSize.toString().trim();
      }
    }

    if (baseLabel.isEmpty) return '';

    // Strip category name prefix if present (e.g., "MS PIPE 1" 25x25(1.2)" -> "1" 25x25(1.2)")
    if (category != null && category.trim().isNotEmpty) {
      final cat = category.trim();
      final catRegex =
          RegExp('^${RegExp.escape(cat)}[:\\s-]*', caseSensitive: false);
      baseLabel = baseLabel.replaceFirst(catRegex, '').trim();
    }
    baseLabel = baseLabel.replaceFirst(
        RegExp(r'^(MS\s+PIPE|PIPE|MS\s+TUBE|ANGLE|CHANNELS?|ROUNDS?|SQUARE\s+BAR|SQR\s+BAR)\s*',
            caseSensitive: false),
        '').trim();

    // Check Flat category prefix
    bool isFlat = false;
    if (category != null && category.toLowerCase().contains('flat')) {
      isFlat = true;
    }
    if (baseLabel.toLowerCase().startsWith('flat ') ||
        baseLabel.toLowerCase().startsWith('flats ')) {
      isFlat = true;
      baseLabel = baseLabel
          .replaceFirst(RegExp(r'^(flat|flats)\s*', caseSensitive: false), '')
          .trim();
    }

    if (isFlat &&
        baseLabel.isNotEmpty &&
        !baseLabel.toUpperCase().startsWith('F ') &&
        !baseLabel.toUpperCase().startsWith('FLAT')) {
      baseLabel = 'F $baseLabel';
    }

    // Normalize thickness in parentheses e.g. " (1.2mm)" -> "(1.2)", " (1.2)" -> "(1.2)"
    baseLabel = baseLabel.replaceAllMapped(
        RegExp(r'\s*\(\s*(\d+(?:\.\d+)?)\s*(?:mm)?\s*\)', caseSensitive: false),
        (match) => '(${match.group(1)})');

    // If weight was not provided explicitly, check if baseLabel ends with an explicit kg suffix (e.g. "6.0kg", "8.5kg", "6kg")
    if (weight == null || weight <= 0) {
      final kgMatch = RegExp(r'\(?\s*(\d+(?:\.\d+)?)\s*kg\s*\)?$', caseSensitive: false).firstMatch(baseLabel);
      if (kgMatch != null) {
        final parsed = double.tryParse(kgMatch.group(1)!);
        if (parsed != null && parsed > 0) {
          final cleanW = parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toString();
          final prefix = baseLabel.substring(0, kgMatch.start).trim();
          return prefix.isNotEmpty ? '$prefix $cleanW' : cleanW;
        }
      }
      return baseLabel;
    }

    final weightStr =
        weight % 1 == 0 ? weight.toInt().toString() : weight.toString();

    // Check if baseLabel already has the weight at the end (e.g. "25x3 6.2", "1" 25x25(1.2) 6", "1" 25x25(1.2) 6kg")
    if (baseLabel.endsWith(weightStr) ||
        baseLabel.endsWith('${weightStr}kg') ||
        baseLabel.endsWith(' $weightStr') ||
        baseLabel.endsWith('(${weightStr}kg)')) {
      return baseLabel
          .replaceAll(
              RegExp(
                  r'\s*\(?\s*' +
                      RegExp.escape(weightStr) +
                      r'\s*kg\s*\)?$',
                  caseSensitive: false),
              ' $weightStr')
          .replaceAll(RegExp(r'kg$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    return '$baseLabel $weightStr'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Formats size with backwards compatibility for legacy/component invocations.
  static String formatIndustrySize(
    String rawSize, {
    double? unitWeight,
    String? category,
    String? inch,
    String? dimension,
    dynamic thickness,
    dynamic weight,
  }) {
    if (inch != null || dimension != null || thickness != null || weight != null) {
      return formatFromComponents(
        inch: inch,
        dimension: dimension,
        thickness: thickness,
        weight: weight ?? unitWeight,
      );
    }
    return formatDeliveryOrderSize(
      rawSize,
      unitWeight: unitWeight,
      category: category,
    );
  }

  /// Combine inch, dimension, thickness, and piece weight into:
  /// final inch = (item.inchSize != null && item.inchSize.isNotEmpty) ? '${item.inchSize}" ' : '';
  /// final dim = item.dimension ?? '';
  /// final thickness = (item.thickness != null && item.thickness.toString().isNotEmpty) ? '(${item.thickness})' : '';
  /// final weight = (item.pieceWeight != null && item.pieceWeight.toString().isNotEmpty) ? ' ${item.pieceWeight}' : '';
  /// final formattedSize = '$inch$dim$thickness$weight'.replaceAll(RegExp(r'\s+'), ' ').trim();
  static String formatFromComponents({
    String? inch,
    String? dimension,
    dynamic thickness,
    dynamic weight,
  }) {
    final cleanInch = (inch ?? '').trim().replaceAll('"', '');
    final inchStr = cleanInch.isNotEmpty ? '$cleanInch" ' : '';

    final dimStr = (dimension ?? '').trim();

    final cleanThick = (thickness?.toString() ?? '')
        .trim()
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll(RegExp(r'mm$', caseSensitive: false), '')
        .trim();
    final thickStr = cleanThick.isNotEmpty ? '($cleanThick)' : '';

    String wtStr = '';
    if (weight != null) {
      if (weight is num && weight > 0) {
        final val = (weight % 1 == 0) ? '${weight.toInt()}' : weight.toString();
        wtStr = ' $val';
      } else {
        final s = weight.toString().trim();
        final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
        if (match != null) {
          final numVal = double.tryParse(match.group(1)!);
          if (numVal != null && numVal > 0) {
            final val = (numVal % 1 == 0) ? '${numVal.toInt()}' : numVal.toString();
            wtStr = ' $val';
          }
        }
      }
    }

    return '$inchStr$dimStr$thickStr$wtStr'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Builds a high-precision, automated A4 Delivery Order PDF matching the technical specification.
  static Future<Uint8List> generatePdf(DeliveryOrderDataModel model) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
    );

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

  /// 1. Title Banner: "Delivery Order" (Bold, Centered or Left)
  static pw.Widget _buildTitleBanner(DeliveryOrderDataModel model) {
    final String title = model.documentTitle.isNotEmpty
        ? model.documentTitle.toUpperCase()
        : 'DELIVERY ORDER';
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

  /// 1. Header Grid (Top of Document):
  /// - Top metadata row/table:
  ///   * PO Order No. | Date (DD/MM/YYYY)
  ///   * Freight | Lorry No (from vehicleNo) | OB | PO Date
  ///   * Bill Type (e.g., NC / BILL)
  /// - Party Details Block (Full 2-column format):
  ///   * Dealer Name: dealerName
  ///   * Billing Name: billingName ?? dealerName
  ///   * Billing Address: billingAddress
  ///   * Consignee Name: consigneeName ?? dealerName
  ///   * Shipping Address: shippingAddress
  ///   (If any of these fields are completely empty, omit the empty line cleanly).
  static pw.Widget _buildHeaderGrid(DeliveryOrderDataModel model) {
    // 1. Top Metadata Fields
    final String poNo = model.poNo.trim();
    final String formattedDate = formatDateDdMmYyyy(model.orderDate);
    final String freight =
        model.freight != null ? model.freight.toString().trim() : '';
    final String lorryNo = model.lorryNo.trim().toUpperCase();
    final String ob = model.ob != null ? model.ob.toString().trim() : '';
    final String formattedPoDate = formatDateDdMmYyyy(model.poDate);
    final String billType = model.billType.trim();

    // 2. Party Details (exact manual entries, fallback only if empty)
    final String dealerName = model.dealerName.trim();
    final String billingName = model.billingName.trim().isNotEmpty
        ? model.billingName.trim()
        : dealerName;
    final String billingAddress = model.billingAddress.trim();

    final String consigneeName = model.consigneeName.trim().isNotEmpty
        ? model.consigneeName.trim()
        : dealerName;
    final String shippingAddress = model.shippingAddress.trim().isNotEmpty
        ? model.shippingAddress.trim()
        : (model.dispatchAddress.trim().isNotEmpty
            ? model.dispatchAddress.trim()
            : '');

    // 3. Build Party Details Columns (omitting completely empty lines)
    final List<pw.Widget> leftPartyRows = [];
    if (dealerName.isNotEmpty) {
      leftPartyRows.add(_buildPartyField("Dealer Name:", dealerName));
    }
    if (billingName.isNotEmpty) {
      if (leftPartyRows.isNotEmpty) leftPartyRows.add(pw.SizedBox(height: 2));
      leftPartyRows.add(_buildPartyField("Billing Name:", billingName));
    }
    if (billingAddress.isNotEmpty) {
      if (leftPartyRows.isNotEmpty) leftPartyRows.add(pw.SizedBox(height: 2));
      leftPartyRows.add(_buildPartyField("Billing Address:", billingAddress));
    }

    final List<pw.Widget> rightPartyRows = [];
    if (consigneeName.isNotEmpty) {
      rightPartyRows.add(_buildPartyField("Consignee Name:", consigneeName));
    }
    if (shippingAddress.isNotEmpty) {
      if (rightPartyRows.isNotEmpty) rightPartyRows.add(pw.SizedBox(height: 2));
      rightPartyRows.add(_buildPartyField("Shipping Address:", shippingAddress));
    }
    if (model.note.trim().isNotEmpty) {
      if (rightPartyRows.isNotEmpty) rightPartyRows.add(pw.SizedBox(height: 2));
      rightPartyRows.add(_buildPartyField("Remarks:", model.note.trim()));
    }

    return pw.Column(
      children: [
        // Top Metadata Table
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.8),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(1.0),
          },
          children: [
            // Row 1: PO Order No. | Date (DD/MM/YYYY)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _headerBg),
              children: [
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: _buildMetaFieldSpan(
                      "PO Order No.:", poNo.isNotEmpty ? poNo : "-"),
                ),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: _buildMetaFieldSpan("Date:",
                      formattedDate.isNotEmpty ? formattedDate : "-"),
                ),
              ],
            ),
            // Row 2: Freight | Lorry No | OB | PO Date
            pw.TableRow(
              children: [
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetaFieldSpan(
                          "Freight:", freight.isNotEmpty ? freight : "-"),
                      _buildMetaFieldSpan(
                          "Lorry No:", lorryNo.isNotEmpty ? lorryNo : "-"),
                    ],
                  ),
                ),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetaFieldSpan("OB:", ob.isNotEmpty ? ob : "-"),
                      _buildMetaFieldSpan("PO Date:",
                          formattedPoDate.isNotEmpty ? formattedPoDate : "-"),
                    ],
                  ),
                ),
              ],
            ),
            // Row 3: Bill Type (e.g., NC / BILL)
            pw.TableRow(
              children: [
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: _buildMetaFieldSpan(
                      "Bill Type:", billType.isNotEmpty ? billType : "-"),
                ),
                pw.Container(),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        // Party Details Block Table (2-column format)
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.8),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(1.0),
          },
          children: [
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: leftPartyRows.isNotEmpty
                        ? leftPartyRows
                        : [pw.Text("-", style: const pw.TextStyle(fontSize: 8))],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: rightPartyRows.isNotEmpty
                        ? rightPartyRows
                        : [pw.Text("-", style: const pw.TextStyle(fontSize: 8))],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildMetaFieldSpan(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: "$label ",
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPartyField(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: "$label ",
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
          ),
        ],
      ),
    );
  }

  /// 2. Item & Sauda Rates Summary Table (Right below Header):
  /// - Grid layout with 3 columns: [Item, Rate, Qty (MT)]
  /// - Do NOT display the "Rate Type" column in this summary grid.
  /// - If multiple items, display side-by-side (2 pairs of [Item, Rate, Qty (MT)] = 6 columns)
  static pw.Widget _buildItemSaudaRatesTable(DeliveryOrderDataModel model) {
    final validItems = model.items
        .where((i) => i.totalQty > 0 || i.sizes.isNotEmpty)
        .toList()
      ..sort((a, b) => ItemOrderUtil.compare(a.item, b.item));

    final isSingleItem = validItems.length == 1;

    final List<pw.TableRow> rows = [
      // Sub-headers Row
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _headerBg),
        children: isSingleItem
            ? [
                _buildTableCell("Item", isHeader: true),
                _buildTableCell("Rate",
                    isHeader: true, align: pw.TextAlign.right),
                _buildTableCell("Qty (MT)",
                    isHeader: true, align: pw.TextAlign.right),
              ]
            : [
                _buildTableCell("Item", isHeader: true),
                _buildTableCell("Rate",
                    isHeader: true, align: pw.TextAlign.right),
                _buildTableCell("Qty (MT)",
                    isHeader: true, align: pw.TextAlign.right),
                _buildTableCell("Item", isHeader: true),
                _buildTableCell("Rate",
                    isHeader: true, align: pw.TextAlign.right),
                _buildTableCell("Qty (MT)",
                    isHeader: true, align: pw.TextAlign.right),
              ],
      ),
    ];

    if (isSingleItem) {
      final single = validItems.first;
      String rate = single.saudaRate?.toString() ?? "-";
      if (rate.isNotEmpty && rate != "-" && double.tryParse(rate) != null) {
        rate = NumberFormat("#,##,##0").format(double.parse(rate));
      }
      String qty = "${single.totalQty.toStringAsFixed(3)} MT";

      rows.add(
        pw.TableRow(
          children: [
            _buildTableCell(single.item, isBold: true),
            _buildTableCell(rate, align: pw.TextAlign.right),
            _buildTableCell(qty, align: pw.TextAlign.right, isBold: true),
          ],
        ),
      );
    } else {
      // Group items into pairs of 2 per row (6 columns)
      for (int i = 0; i < validItems.length; i += 2) {
        final left = validItems[i];
        final right = (i + 1 < validItems.length) ? validItems[i + 1] : null;

        String leftRate = left.saudaRate?.toString() ?? "-";
        if (leftRate.isNotEmpty &&
            leftRate != "-" &&
            double.tryParse(leftRate) != null) {
          leftRate = NumberFormat("#,##,##0").format(double.parse(leftRate));
        }
        String leftQty = "${left.totalQty.toStringAsFixed(3)} MT";

        String rightItem = "";
        String rightRate = "";
        String rightQty = "";
        if (right != null) {
          rightItem = right.item;
          rightRate = right.saudaRate?.toString() ?? "-";
          if (rightRate.isNotEmpty &&
              rightRate != "-" &&
              double.tryParse(rightRate) != null) {
            rightRate = NumberFormat("#,##,##0").format(double.parse(rightRate));
          }
          rightQty = "${right.totalQty.toStringAsFixed(3)} MT";
        }

        rows.add(
          pw.TableRow(
            children: [
              _buildTableCell(left.item, isBold: true),
              _buildTableCell(leftRate, align: pw.TextAlign.right),
              _buildTableCell(leftQty, align: pw.TextAlign.right, isBold: true),
              _buildTableCell(rightItem, isBold: right != null),
              _buildTableCell(rightRate, align: pw.TextAlign.right),
              _buildTableCell(rightQty,
                  align: pw.TextAlign.right, isBold: right != null),
            ],
          ),
        );
      }
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
          columnWidths: isSingleItem
              ? const {
                  0: pw.FlexColumnWidth(2.0), // Item
                  1: pw.FlexColumnWidth(1.2), // Rate
                  2: pw.FlexColumnWidth(1.3), // Qty (MT)
                }
              : const {
                  0: pw.FlexColumnWidth(2.0), // Item 1
                  1: pw.FlexColumnWidth(1.2), // Rate 1
                  2: pw.FlexColumnWidth(1.3), // Qty 1
                  3: pw.FlexColumnWidth(2.0), // Item 2
                  4: pw.FlexColumnWidth(1.2), // Rate 2
                  5: pw.FlexColumnWidth(1.3), // Qty 2
                },
          children: rows,
        ),
      ],
    );
  }

  /// 4. Items Table Columns: [Sr, Item, Sizes, Qty (MT), Breakdown, Net Rate]
  /// Summary Row: "Total" on left, total metric tonnes with "MT" unit.
  static pw.Widget _buildDetailsTable(DeliveryOrderDataModel model) {
    final List<pw.TableRow> rows = [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _headerBg),
        children: [
          _buildTableCell("Sr", isHeader: true, align: pw.TextAlign.center),
          _buildTableCell("Item", isHeader: true),
          _buildTableCell("Sizes", isHeader: true),
          _buildTableCell("Qty (MT)",
              isHeader: true, align: pw.TextAlign.right),
          _buildTableCell("Breakdown", isHeader: true),
          _buildTableCell("Net Rate",
              isHeader: true, align: pw.TextAlign.right),
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

        // Apply industry size formatting with space separators
        String sizeDisplay = formatDeliveryOrderSize(
          size,
          unitWeight: size.unitWeight,
          category: item.item,
        );
        if (sizeDisplay.isEmpty) {
          sizeDisplay = size.size.isNotEmpty ? size.size : "Standard";
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
              _buildTableCell(netRateStr,
                  align: pw.TextAlign.right, isBold: true),
            ],
          ),
        );
        srNo++;
      }
    }

    // Summary Row: "Total" on left, total metric tonnes with "MT" unit
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
            0: pw.FixedColumnWidth(22), // Sr
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

  /// 5. Footer:
  /// - Left side: Note section matching original reference sheet.
  /// - Right side: Signature boxes for "Order Signed" and "Approved By".
  /// - (Redundant Date/Vehicle/Bill Type lines removed since they are now in top header).
  static pw.Widget _buildFooterBlock(DeliveryOrderDataModel model) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2), // Bottom-Left: Note
        1: pw.FlexColumnWidth(0.8), // Bottom-Right: Signatures
      },
      children: [
        pw.TableRow(
          children: [
            // Bottom-Left: Note
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: "Note: ",
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                        if (model.note.trim().isNotEmpty)
                          pw.TextSpan(
                            text: model.note.trim(),
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.black,
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Container(
                    width: double.infinity,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom:
                            pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 7),
                  pw.Container(
                    width: double.infinity,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom:
                            pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 7),
                  pw.Container(
                    width: double.infinity,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom:
                            pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom-Right: Signatures Table
            pw.Table(
              border: const pw.TableBorder(
                left: pw.BorderSide(color: _borderColor, width: 0.8),
                verticalInside:
                    pw.BorderSide(color: _borderColor, width: 0.8),
              ),
              children: [
                pw.TableRow(
                  children: [
                    pw.Container(
                      height: 56,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            "Order Signed",
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (model.signedBy.isNotEmpty)
                            pw.Text(
                              model.signedBy,
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                        ],
                      ),
                    ),
                    pw.Container(
                      height: 56,
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            "Approved By",
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (model.approvedBy.isNotEmpty)
                            pw.Text(
                              model.approvedBy,
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
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
    // 1. Top Metadata
    final String poNo = model.poNo.trim();
    final String formattedDate = formatDateDdMmYyyy(model.orderDate);
    final String freight =
        model.freight != null ? model.freight.toString().trim() : '';
    final String lorryNo = model.lorryNo.trim().toUpperCase();
    final String ob = model.ob != null ? model.ob.toString().trim() : '';
    final String formattedPoDate = formatDateDdMmYyyy(model.poDate);
    final String billType = model.billType.trim();

    // 2. Party details (exact user entered manual fields)
    final String dealerName = model.dealerName.trim();
    final String billingName = model.billingName.trim().isNotEmpty
        ? model.billingName.trim()
        : dealerName;
    final String billingAddress = model.billingAddress.trim();

    final String consigneeName = model.consigneeName.trim().isNotEmpty
        ? model.consigneeName.trim()
        : dealerName;
    final String shippingAddress = model.shippingAddress.trim().isNotEmpty
        ? model.shippingAddress.trim()
        : (model.dispatchAddress.trim().isNotEmpty
            ? model.dispatchAddress.trim()
            : '');

    final StringBuffer leftPartyHtml = StringBuffer();
    if (dealerName.isNotEmpty) {
      leftPartyHtml.writeln('<strong>Dealer Name:</strong> $dealerName<br>');
    }
    if (billingName.isNotEmpty) {
      leftPartyHtml.writeln('<strong>Billing Name:</strong> $billingName<br>');
    }
    if (billingAddress.isNotEmpty) {
      leftPartyHtml
          .writeln('<strong>Billing Address:</strong> $billingAddress<br>');
    }

    final StringBuffer rightPartyHtml = StringBuffer();
    if (consigneeName.isNotEmpty) {
      rightPartyHtml
          .writeln('<strong>Consignee Name:</strong> $consigneeName<br>');
    }
    if (shippingAddress.isNotEmpty) {
      rightPartyHtml
          .writeln('<strong>Shipping Address:</strong> $shippingAddress<br>');
    }
    if (model.note.trim().isNotEmpty) {
      rightPartyHtml.writeln('<strong>Remarks:</strong> ${model.note.trim()}<br>');
    }

    final validItems = model.items
        .where((i) => i.totalQty > 0 || i.sizes.isNotEmpty)
        .toList()
      ..sort((a, b) => ItemOrderUtil.compare(a.item, b.item));

    final isSingleItem = validItems.length == 1;
    final StringBuffer saudaSummaryHtml = StringBuffer();

    if (isSingleItem) {
      final single = validItems.first;
      String rate = single.saudaRate?.toString() ?? "-";
      if (rate.isNotEmpty && rate != "-" && double.tryParse(rate) != null) {
        rate = NumberFormat("#,##,##0").format(double.parse(rate));
      }
      String qty = "${single.totalQty.toStringAsFixed(3)} MT";

      saudaSummaryHtml.writeln('''
        <tr>
          <td><strong>${single.item}</strong></td>
          <td style="text-align:right;">$rate</td>
          <td style="text-align:right;"><strong>$qty</strong></td>
        </tr>
      ''');
    } else {
      for (int i = 0; i < validItems.length; i += 2) {
        final left = validItems[i];
        final right = (i + 1 < validItems.length) ? validItems[i + 1] : null;

        String leftRate = left.saudaRate?.toString() ?? "-";
        if (leftRate.isNotEmpty &&
            leftRate != "-" &&
            double.tryParse(leftRate) != null) {
          leftRate = NumberFormat("#,##,##0").format(double.parse(leftRate));
        }
        String leftQty = "${left.totalQty.toStringAsFixed(3)} MT";

        String rightItem = "";
        String rightRate = "";
        String rightQty = "";
        if (right != null) {
          rightItem = right.item;
          rightRate = right.saudaRate?.toString() ?? "-";
          if (rightRate.isNotEmpty &&
              rightRate != "-" &&
              double.tryParse(rightRate) != null) {
            rightRate =
                NumberFormat("#,##,##0").format(double.parse(rightRate));
          }
          rightQty = "${right.totalQty.toStringAsFixed(3)} MT";
        }

        saudaSummaryHtml.writeln('''
          <tr>
            <td><strong>${left.item}</strong></td>
            <td style="text-align:right;">$leftRate</td>
            <td style="text-align:right;"><strong>$leftQty</strong></td>
            <td><strong>$rightItem</strong></td>
            <td style="text-align:right;">$rightRate</td>
            <td style="text-align:right;"><strong>$rightQty</strong></td>
          </tr>
        ''');
      }
    }

    final StringBuffer rowsHtml = StringBuffer();
    int srNo = 1;
    double grandTotalQty = 0;
    final charges = DataRepository.instance.globalCharges;
    final double freightVal =
        double.tryParse(model.freight?.toString() ?? '0') ?? 0.0;
    final double obVal = double.tryParse(model.ob?.toString() ?? '0') ?? 0.0;

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

        String sizeDisplay = formatDeliveryOrderSize(
          size,
          unitWeight: size.unitWeight,
          category: item.item,
        );
        if (sizeDisplay.isEmpty) {
          sizeDisplay = size.size.isNotEmpty ? size.size : "Standard";
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
            freight: freightVal,
            ob: obVal,
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

    final docTitle = model.documentTitle.isNotEmpty
        ? model.documentTitle.toUpperCase()
        : "DELIVERY ORDER";

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
    .header-table { width: 100%; border-collapse: collapse; margin-top: 3px; }
    .header-table td { border: 1px solid #000; padding: 4px 5px; vertical-align: top; }
    .footer-table { width: 100%; border-collapse: collapse; margin-top: 4px; }
    .footer-table td { border: 1px solid #000; padding: 5px; vertical-align: top; }
  </style>
</head>
<body>
  <div id="printTableLayout" class="print-only do-page">
    <div class="do-title">$docTitle</div>
    
    <!-- Top Metadata Table -->
    <table class="header-table">
      <tr style="background:#f0f0f0;">
        <td style="width:50%;"><strong>PO Order No.:</strong> ${poNo.isNotEmpty ? poNo : "-"}</td>
        <td style="width:50%;"><strong>Date:</strong> ${formattedDate.isNotEmpty ? formattedDate : "-"}</td>
      </tr>
      <tr>
        <td style="width:50%;">
          <div style="display:flex; justify-content:space-between;">
            <span><strong>Freight:</strong> ${freight.isNotEmpty ? freight : "-"}</span>
            <span><strong>Lorry No:</strong> ${lorryNo.isNotEmpty ? lorryNo : "-"}</span>
          </div>
        </td>
        <td style="width:50%;">
          <div style="display:flex; justify-content:space-between;">
            <span><strong>OB:</strong> ${ob.isNotEmpty ? ob : "-"}</span>
            <span><strong>PO Date:</strong> ${formattedPoDate.isNotEmpty ? formattedPoDate : "-"}</span>
          </div>
        </td>
      </tr>
      <tr>
        <td colspan="2"><strong>Bill Type:</strong> ${billType.isNotEmpty ? billType : "-"}</td>
      </tr>
    </table>

    <!-- Party Details Block Table -->
    <table class="header-table">
      <tr>
        <td style="width:50%;">
          $leftPartyHtml
        </td>
        <td style="width:50%;">
          $rightPartyHtml
        </td>
      </tr>
    </table>

    ${saudaSummaryHtml.isNotEmpty ? '''
    <table class="do-table" style="margin-top:4px;">
      <thead>
        <tr style="background:#f0f0f0;">
          <th colspan="${isSingleItem ? '3' : '6'}" style="text-align:center; font-weight:bold; color:#C61A22;">Item &amp; Sauda Rates</th>
        </tr>
        <tr style="background:#f0f0f0;">
          <th style="${isSingleItem ? 'width:40%;' : 'width:20%;'}">Item</th>
          <th style="${isSingleItem ? 'width:30%;' : 'width:15%;'} text-align:right;">Rate</th>
          <th style="${isSingleItem ? 'width:30%;' : 'width:15%;'} text-align:right;">Qty (MT)</th>
          ${!isSingleItem ? '''
          <th style="width:20%;">Item</th>
          <th style="width:15%; text-align:right;">Rate</th>
          <th style="width:15%; text-align:right;">Qty (MT)</th>
          ''' : ''}
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

    <table class="footer-table" style="margin-top:4px;">
      <tr>
        <td style="width:60%;">
          <div style="font-weight:bold; margin-top:2px;">Note: ${model.note.trim()}</div>
          <div style="border-bottom:1px solid #ccc; height:10px; margin-top:4px;"></div>
          <div style="border-bottom:1px solid #ccc; height:10px; margin-top:4px;"></div>
          <div style="border-bottom:1px solid #ccc; height:10px; margin-top:4px;"></div>
        </td>
        <td style="width:20%; height:56px;">
          <strong>Order Signed</strong>
          ${model.signedBy.isNotEmpty ? "<br><br><span style='font-size:9px;'>${model.signedBy}</span>" : ""}
        </td>
        <td style="width:20%; height:56px;">
          <strong>Approved By</strong>
          ${model.approvedBy.isNotEmpty ? "<br><br><span style='font-size:9px;'>${model.approvedBy}</span>" : ""}
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
