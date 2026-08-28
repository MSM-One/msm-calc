import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/file_download_helper.dart' as download_helper;

import '../utils/formatters.dart';

import '../models/report_models.dart';
import '../models/stock_models.dart';
import '../services/data_repository.dart';
import '../utils/sorting_utils.dart';

class PdfReportService {
  static final PdfColor logoRed = PdfColor.fromHex('#C61A22');

  static Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/dashboard_logo.jpg');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      // Suppress logo loading errors as per user request
      return null;
    }
  }

  static Future<pw.ImageProvider?> _loadBrandLogo() async {
    try {
      final data = await rootBundle.load('assets/sTEEL MART .jpg');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      return null;
    }
  }

  static Future<pw.ImageProvider?> _loadLetterhead() async {
    try {
      final data = await rootBundle.load('assets/Steel Marat Letterhead.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      return null;
    }
  }

  static pw.Document _createDocument() {
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
    );
  }

  static Future<Uint8List> generateMovementReport({
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required List<StockMovementEntry> entries,
    bool isDetailed = true,
    String? reportTitle,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');
    final dateRange = '${df.format(startDate)} to ${df.format(endDate)}';

    // Summary Stats
    final double totalBalance = entries.fold(0, (sum, e) => sum + e.closing);

    // Grouping: Category -> Item Entry
    Map<String, List<StockMovementEntry>> nested = {};
    for (var e in entries) {
      final String cat = DataRepository.canonicalizeCategory(e.category);
      nested.putIfAbsent(cat, () => []);
      nested[cat]!.add(e);
    }
    final categories = nested.keys.toList()
      ..sort(SortingUtils.compareCategories);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            reportTitle ??
                (isDetailed
                    ? 'DETAILED STOCK MOVEMENT REPORT'
                    : 'STOCK MOVEMENT SUMMARY'),
            'Location: $location | Period: $dateRange',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          content.add(pw.Center(
              child: pw.Column(children: [
            pw.Text('TOTAL INVENTORY',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text('${totalBalance.toStringAsFixed(3)} MT',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: totalBalance < 0 ? PdfColors.red700 : logoRed)),
          ])));
          content.add(pw.SizedBox(height: 15));

          if (!isDetailed) {
            List<List<String>> summaryData = [];
            for (var cat in categories) {
              double catTotal = 0;
              for (var e in nested[cat]!) {
                catTotal += e.closing;
              }
              summaryData.add([cat.toUpperCase(), _pFormat(catTotal, cat)]);
            }

            content.add(
              pw.Center(
                child: pw.SizedBox(
                  width: 250,
                  child: pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey300, width: 0.5),
                    headerDecoration: pw.BoxDecoration(color: logoRed),
                    headerStyle: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    cellPadding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 8),
                    rowDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey50),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(
                          160), // Item Name Category (e.g., MS PIPE, MS ANGLE)
                      1: const pw.FixedColumnWidth(90), // Closing (MT)
                    },
                    headers: ['ITEM NAME', 'Closing (MT)'],
                    data: summaryData,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerRight
                    },
                  ),
                ),
              ),
            );
          } else {
            for (var cat in categories) {
              final items = nested[cat]!;
              items.sort(
                  (a, b) => SortingUtils.compareCategories(a.item, b.item));

              content.add(
                pw.Center(
                  child: pw.SizedBox(
                    width: 400,
                    child: pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      child: pw.Text(cat.toUpperCase(),
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                              color: PdfColors.red900)),
                    ),
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 5));

              List<List<dynamic>> tableData = [];
              double catCl = 0;

              for (var itemEntry in items) {
                itemEntry.sizes.sort(
                    (a, b) => SortingUtils.compareSizes(a.label, b.label));
                for (var s in itemEntry.sizes) {
                  tableData.add([
                    pw.Text('${itemEntry.item} ${_pSizeLabel(cat, s.label)}',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.normal,
                            fontSize: 10,
                            color: PdfColors.black)),
                    pw.Text(s.opening.toStringAsFixed(3),
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.black)),
                    pw.Text(s.inQty.toStringAsFixed(3),
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.black)),
                    pw.Text(s.outQty.toStringAsFixed(3),
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.black)),
                    pw.Text(s.closing.toStringAsFixed(3),
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                            color: PdfColors.black)),
                  ]);
                  catCl += s.closing;
                }
              }

              content.add(
                pw.Center(
                  child: pw.SizedBox(
                    width: 450,
                    child: pw.TableHelper.fromTextArray(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey200, width: 0.5),
                      headerDecoration: pw.BoxDecoration(color: logoRed),
                      headerStyle: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10),
                      cellStyle: const pw.TextStyle(fontSize: 10),
                      cellPadding: const pw.EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      oddRowDecoration:
                          const pw.BoxDecoration(color: PdfColors.grey50),
                      headerAlignment: pw.Alignment.centerRight,
                      cellAlignment: pw.Alignment.centerRight,
                      columnWidths: {
                        0: const pw.FixedColumnWidth(170), // Size Description
                        1: const pw.FixedColumnWidth(65), // Opening (MT)
                        2: const pw.FixedColumnWidth(65), // Inward (MT)
                        3: const pw.FixedColumnWidth(65), // Outward (MT)
                        4: const pw.FixedColumnWidth(70), // Closing (MT)
                      },
                      headers: [
                        'Size Description',
                        'Opening',
                        'Inward',
                        'Outward',
                        'Closing'
                      ],
                      data: tableData,
                      cellAlignments: {
                        0: pw.Alignment.centerLeft,
                        1: pw.Alignment.centerRight,
                        2: pw.Alignment.centerRight,
                        3: pw.Alignment.centerRight,
                        4: pw.Alignment.centerRight,
                      },
                    ),
                  ),
                ),
              );

              content.add(
                pw.Center(
                  child: pw.SizedBox(
                    width: 450,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border:
                            pw.Border.all(color: PdfColors.grey400, width: 1.5),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                              flex: 3,
                              child: pw.Text('TOTAL CATEGORY',
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 11,
                                      color: PdfColors.black))),
                          pw.Spacer(),
                          pw.Expanded(
                              flex: 1,
                              child: pw.Text(catCl.toStringAsFixed(3),
                                  textAlign: pw.TextAlign.right,
                                  style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 11,
                                      color: PdfColors.black))),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 15));
            }
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateInventorySummaryPdf({
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required List<StockMovementEntry> entries,
  }) async {
    return generateMovementReport(
      startDate: startDate,
      endDate: endDate,
      location: location,
      entries: entries,
      isDetailed: false,
    );
  }

  static String _pFormat(double val, String cat) {
    final lower = cat.toLowerCase();
    bool isUnit = lower.contains('tape') ||
        lower.contains('wheel') ||
        lower.contains('safety') ||
        lower.contains('packing');
    if (isUnit) return val.toInt().toString();
    return val.toStringAsFixed(3);
  }

  /// Returns the size label with a conditional " kg" suffix.
  /// Excluded categories: Sqr Bar, Round Bar, Flats, Barbed Wire, GATE Channel.
  static String _pSizeLabel(String category, String sizeLabel,
      [double? unitWeight]) {
    const excluded = [
      'sqr bar',
      'round bar',
      'flats',
      'barbed wire',
      'gate channel',
    ];
    final lower = category.toLowerCase();
    if (excluded.any((ex) => lower.contains(ex))) return sizeLabel;
    if (category.trim() == 'MS Angle') {
      final double w = unitWeight ?? lookupSizeWeight(sizeLabel);
      return formatSizeLabel(sizeLabel, category, w);
    }
    return getFormattedSizeDisplay(sizeLabel, unitWeight);
  }

  static Future<Uint8List> generateLowStockCategoryPdf({
    required String categoryName,
    required List<ItemVariant> items,
    bool isDetailed = true,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    double total = items.fold(0.0, (sum, e) => sum + e.availableStockMT);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            'LOW STOCK REPORT: ${categoryName.toUpperCase()}',
            'Generated on ${df.format(now)}',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          content.add(
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: const pw.BoxDecoration(color: PdfColors.red50),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                      'CATEGORY: ${categoryName.toUpperCase()} | Total: ${total.abs().toStringAsFixed(3)} MT',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 11,
                          color: PdfColors.red900)),
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('TOTAL STOCK',
                            style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700)),
                        pw.Text('${total.abs().toStringAsFixed(3)} MT',
                            style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: logoRed)),
                      ])
                ],
              ),
            ),
          );
          content.add(pw.SizedBox(height: 15));

          if (isDetailed) {
            List<List<String>> tableData = items.map((e) {
              double unitWeight = lookupSizeWeight(e.size);
              if (unitWeight == 0) {
                unitWeight = _extractUnitWeight(e.size);
              }
              final String formattedSize =
                  _pSizeLabel(e.itemName, e.size, unitWeight);
              return [
                '${e.itemName} - $formattedSize',
                (e.availableStockMT).toStringAsFixed(3),
              ];
            }).toList();

            content.add(
              pw.TableHelper.fromTextArray(
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerDecoration: pw.BoxDecoration(color: logoRed),
                headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellPadding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey100),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                headers: ['Size Description', 'Low Stock Qty'],
                data: tableData,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight
                },
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.5),
                  1: const pw.FlexColumnWidth(1)
                },
              ),
            );
          } else {
            content.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SUMMARY VIEW',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('All items combined in this category',
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            );
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateCategoryMovementPdf({
    required String categoryName,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required Map<String, List<StockMovementEntry>> items,
    required double totalClosing,
    bool isDetailed = true,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final df = DateFormat('dd MMM yyyy');
    final dateRange = '${df.format(startDate)} to ${df.format(endDate)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            'CATEGORY STOCK REPORT: ${categoryName.toUpperCase()}',
            'Location: $location | Period: $dateRange',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          content.add(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('CATEGORY: ${categoryName.toUpperCase()}',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey900)),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('TOTAL CLOSING',
                          style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700)),
                      pw.Text('${totalClosing.toStringAsFixed(3)} MT',
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: totalClosing < 0
                                  ? PdfColors.red700
                                  : logoRed)),
                    ])
              ]));
          content.add(pw.SizedBox(height: 15));

          if (!isDetailed) {
            // Summary view only shows the category total
            content.add(pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Category Summary Total',
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${totalClosing.toStringAsFixed(3)} MT',
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: logoRed)),
                    ])));
            return content;
          }

          double catIn = 0;
          double catOut = 0;
          double catCl = 0;

          List<List<String>> tableData = [];

          final sortedItems = items.keys.toList()
            ..sort(SortingUtils.compareCategories);

          for (var itemName in sortedItems) {
            final entries = items[itemName]!;
            for (var entry in entries) {
              entry.sizes
                  .sort((a, b) => SortingUtils.compareSizes(a.label, b.label));
              for (var size in entry.sizes) {
                catIn += size.inQty.abs();
                catOut += size.outQty.abs();
                catCl += size.closing.abs();
                tableData.add([
                  _pSizeLabel(categoryName, size.label),
                  _pFormat(size.inQty.abs(), categoryName),
                  _pFormat(size.outQty.abs(), categoryName),
                  _pFormat(size.closing.abs(), categoryName),
                ]);
              }
            }
          }

          if (tableData.isEmpty) {
            tableData.add(['No size-wise movement data found', '-', '-', '-']);
          }

          content.add(
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerDecoration: pw.BoxDecoration(color: logoRed),
              headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding:
                  const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
              },
              headers: ['ITEM SPECIFICATION', 'IN', 'OUT', 'CLOSE'],
              data: tableData,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
            ),
          );

          content.add(
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CATEGORY TOTAL',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                          color: PdfColors.black)),
                  pw.Text('${catCl.abs().toStringAsFixed(3)} MT',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                          color: PdfColors.black)),
                ],
              ),
            ),
          );

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, DateTime.now()),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateDeadStockPdf({
    required List<DeadStockEntry> entries,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            'NON-MOVING STOCK REPORT', 'Generated on ${df.format(now)}', logo),
        build: (context) {
          List<pw.Widget> content = [];

          // Group by category
          Map<String, List<DeadStockEntry>> grouped = {};
          for (var e in entries) {
            grouped.putIfAbsent(e.category, () => []);
            grouped[e.category]!.add(e);
          }
          final sortedCats = grouped.keys.toList()
            ..sort(SortingUtils.compareCategories);

          for (var cat in sortedCats) {
            final catItems = grouped[cat]!;
            catItems.sort((a, b) {
              int cmp = SortingUtils.compareCategories(a.itemName, b.itemName);
              if (cmp != 0) return cmp;
              return SortingUtils.compareSizes(a.size, b.size);
            });

            content.add(
              pw.Center(
                child: pw.SizedBox(
                  width: 460,
                  child: pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 4, horizontal: 8),
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    child: pw.Text(cat.toUpperCase(),
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                            color: PdfColors.red900)),
                  ),
                ),
              ),
            );
            content.add(pw.SizedBox(height: 5));

            List<List<String>> tableData = catItems
                .map((e) => [
                      e.itemName,
                      _pSizeLabel(e.category, e.size),
                      e.currentQty.toStringAsFixed(3),
                      e.daysSinceLastMovement == -1
                          ? '-'
                          : '${e.daysSinceLastMovement} Days'
                    ])
                .toList();

            content.add(
              pw.Center(
                child: pw.SizedBox(
                  width: 460,
                  child: pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey200, width: 0.5),
                    headerDecoration: pw.BoxDecoration(color: logoRed),
                    headerStyle: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8),
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    cellPadding: const pw.EdgeInsets.symmetric(
                        vertical: 2, horizontal: 4),
                    oddRowDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey50),
                    headers: [
                      'Item Name',
                      'Size Spec',
                      'Dead Stock (MT)',
                      'Duration'
                    ],
                    data: tableData,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerRight,
                      3: pw.Alignment.center,
                    },
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2.0),
                      2: const pw.FlexColumnWidth(1.2),
                      3: const pw.FlexColumnWidth(1.0),
                    },
                  ),
                ),
              ),
            );
            content.add(pw.SizedBox(height: 15));
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateDeadStockCategoryPdf({
    required String categoryName,
    required List<DeadStockEntry> entries,
    bool isDetailed = true,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            'NON-MOVING STOCK REPORT: ${categoryName.toUpperCase()}',
            'Generated on ${df.format(now)}',
            logo),
        build: (context) {
          if (isDetailed) {
            List<List<String>> tableData = entries.map((e) {
              double unitWeight = lookupSizeWeight(e.size);
              if (unitWeight == 0) {
                unitWeight = _extractUnitWeight(e.size);
              }
              final String formattedSize =
                  _pSizeLabel(e.itemName, e.size, unitWeight);
              return [
                '${e.itemName} - $formattedSize',
                e.currentQty.toStringAsFixed(3),
              ];
            }).toList();

            return [
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerDecoration: pw.BoxDecoration(color: logoRed),
                headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey50),
                headers: ['Size Description', 'Non-Moving Qty'],
                data: tableData,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                },
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.2),
                },
              ),
            ];
          } else {
            double total = entries.fold(0, (sum, e) => sum + e.currentQty);
            return [
              pw.SizedBox(height: 10),
              pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('SUMMARY TOTAL:',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('${total.toStringAsFixed(3)} MT',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: logoRed,
                                fontSize: 14)),
                      ])),
              pw.SizedBox(height: 10),
              pw.Text('Items in this category: ${entries.length}',
                  style: const pw.TextStyle(fontSize: 10)),
            ];
          }
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateDailySummaryPdf({
    required DateTime date,
    required List<DailyMovementEntry> entries,
    String selectedMode = 'Summary',
    bool isOutward = false,
    String flowMode = 'Inward',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    // Determine if this is a single-day or range report
    final DateTime effectiveStart = startDate ?? date;
    final DateTime effectiveEnd = endDate ?? date;
    final bool isSameDay = effectiveStart.year == effectiveEnd.year &&
        effectiveStart.month == effectiveEnd.month &&
        effectiveStart.day == effectiveEnd.day;

    final bool isNetQty = flowMode == 'Net Qty';
    final String headerTitle = isNetQty
        ? "NET QUANTITY REPORT (MT)"
        : selectedMode == 'Summary'
            ? (isOutward ? "OUTWARD SUMMARY" : "INWARD SUMMARY")
            : 'DETAILED REPORT';
    final String dateSubtitle = isSameDay
        ? 'Date: ${df.format(effectiveStart)}'
        : 'Period: ${df.format(effectiveStart)} - ${df.format(effectiveEnd)}';

    pw.Widget buildSummaryCell(String text,
        {bool isHeader = false,
        pw.TextAlign align = pw.TextAlign.center,
        bool isBold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 9,
            color: isHeader ? PdfColors.white : PdfColors.black,
            fontWeight: (isHeader || isBold)
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      );
    }

    double extractUnitWeight(String sizeLabel) {
      if (sizeLabel.isEmpty) return 0.0;
      try {
        final RegExp regex = RegExp(r'\(([^)]+)\)');
        final match = regex.firstMatch(sizeLabel);
        if (match != null) {
          final String val = match.group(1)!.replaceAll(RegExp(r'[^0-9.]'), '');
          if (sizeLabel.contains("1.2")) return 4.0;
          if (sizeLabel.contains("1.6")) return 4.0;
          if (sizeLabel.contains("2.0")) return 5.0;
          return double.tryParse(val) ?? 0.0;
        }
      } catch (_) {}
      return 0.0;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) =>
            _buildProfessionalHeader(headerTitle, dateSubtitle, logo),
        build: (context) {
          List<pw.Widget> content = [];
          content.add(pw.SizedBox(height: 10));

          if (selectedMode == 'Summary') {
            // Group by Category uniquely
            Map<String, double> summaryMap = {};
            for (var e in entries) {
              final String rawCat = e.itemName.isNotEmpty
                  ? e.itemName
                  : (e.category.isNotEmpty ? e.category : 'Other');
              final String categoryGroup =
                  DataRepository.canonicalizeCategory(rawCat);
              final double qty = isNetQty
                  ? (e.inQty - e.outQty)
                  : isOutward
                      ? e.outQty.abs()
                      : e.inQty.abs();
              final bool include =
                  isNetQty ? (e.inQty > 0 || e.outQty > 0) : (qty > 0);
              if (include) {
                summaryMap[categoryGroup] =
                    (summaryMap[categoryGroup] ?? 0.0) + qty;
              }
            }
            final summaryCategories = summaryMap.entries.toList()
              ..sort((a, b) => SortingUtils.compareCategories(a.key, b.key));

            final double grandTotal = summaryCategories.fold(
                0.0, (sum, entry) => sum + entry.value);
            final String formattedGrandTotal = isNetQty
                ? "${grandTotal < 0 ? '-' : ''}${grandTotal.abs().toStringAsFixed(3)} MT"
                : "${grandTotal.abs().toStringAsFixed(3)} MT";

            content.add(
              pw.Center(
                child: pw.Table(
                  tableWidth: pw.TableWidth.min,
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: const {
                    0: pw.IntrinsicColumnWidth(), // Item Category
                    1: pw.IntrinsicColumnWidth(), // Total Quantity
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: logoRed),
                      children: [
                        buildSummaryCell('Item Category',
                            isHeader: true, align: pw.TextAlign.left),
                        buildSummaryCell(
                            isNetQty
                                ? 'Net Quantity (MT)'
                                : (isOutward
                                    ? 'Outward Quantity (MT)'
                                    : 'Inward Quantity (MT)'),
                            isHeader: true,
                            align: pw.TextAlign.right),
                      ],
                    ),
                    ...summaryCategories.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      final rowBg =
                          idx % 2 == 1 ? PdfColors.grey50 : PdfColors.white;
                      final double val = item.value;
                      final String formattedVal = isNetQty
                          ? "${val < 0 ? '-' : ''}${val.abs().toStringAsFixed(3)} MT"
                          : "${val.abs().toStringAsFixed(3)} MT";
                      return pw.TableRow(
                        decoration: pw.BoxDecoration(color: rowBg),
                        children: [
                          buildSummaryCell(item.key.toUpperCase(),
                              align: pw.TextAlign.left),
                          buildSummaryCell(formattedVal,
                              align: pw.TextAlign.right, isBold: true),
                        ],
                      );
                    }),
                    // Prominent TOTAL Summary Row at Table Bottom
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F1F5F9'),
                      ),
                      children: [
                        buildSummaryCell('TOTAL',
                            align: pw.TextAlign.left, isBold: true),
                        buildSummaryCell(formattedGrandTotal,
                            align: pw.TextAlign.right, isBold: true),
                      ],
                    ),
                  ],
                ),
              ),
            );
          } else {
            // Detailed Mode
            // Group by category
            Map<String, List<DailyMovementEntry>> detailedMap = {};
            for (var e in entries) {
              final String rawCat = e.itemName.isNotEmpty
                  ? e.itemName
                  : (e.category.isNotEmpty ? e.category : 'Other');
              final String categoryGroup =
                  DataRepository.canonicalizeCategory(rawCat);
              detailedMap.putIfAbsent(categoryGroup, () => []);
              detailedMap[categoryGroup]!.add(e);
            }
            final sortedCategories = detailedMap.keys.toList()
              ..sort(SortingUtils.compareCategories);

            for (var cat in sortedCategories) {
              final catEntries = detailedMap[cat]!;
              catEntries
                  .sort((a, b) => SortingUtils.compareSizes(a.size, b.size));

              double catIn = 0;
              double catOut = 0;
              for (var e in catEntries) {
                catIn += e.inQty.abs();
                catOut += e.outQty.abs();
              }
              final double catNet = (catIn - catOut).abs();

              content.add(
                pw.Center(
                  child: pw.SizedBox(
                    width: 290,
                    child: pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      child: pw.Text(
                          '${cat.toUpperCase()} | Total: ${catNet.toStringAsFixed(3)} MT',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                              color: PdfColors.red900)),
                    ),
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 5));

              List<pw.TableRow> tableRows = [];

              // Sub-header Row
              tableRows.add(
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: logoRed),
                  children: [
                    buildSummaryCell('Size Description',
                        isHeader: true, align: pw.TextAlign.left),
                    buildSummaryCell('Inward (MT)',
                        isHeader: true, align: pw.TextAlign.right),
                    buildSummaryCell('Outward (MT)',
                        isHeader: true, align: pw.TextAlign.right),
                  ],
                ),
              );

              for (var i = 0; i < catEntries.length; i++) {
                final e = catEntries[i];
                double weight = lookupSizeWeight(e.size);
                if (weight == 0) {
                  weight = extractUnitWeight(e.size);
                }
                final formattedWeight = weight % 1 == 0
                    ? weight.toInt().toString()
                    : weight.toStringAsFixed(1);
                final String weightStr =
                    weight != 0 ? " ${formattedWeight}kg" : "";
                final String sizeDesc = cat.trim() == 'MS Angle'
                    ? formatSizeLabel(e.size, cat, weight)
                    : "${e.size}$weightStr";
                final rowBg = i % 2 == 1 ? PdfColors.grey50 : PdfColors.white;

                tableRows.add(
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBg),
                    children: [
                      buildSummaryCell(sizeDesc, align: pw.TextAlign.left),
                      buildSummaryCell(
                          e.inQty.abs() > 0
                              ? e.inQty.abs().toStringAsFixed(3)
                              : '-',
                          align: pw.TextAlign.right),
                      buildSummaryCell(
                          e.outQty.abs() > 0
                              ? e.outQty.abs().toStringAsFixed(3)
                              : '-',
                          align: pw.TextAlign.right),
                    ],
                  ),
                );
              }

              // Dedicated CATEGORY TOTAL row
              tableRows.add(
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  children: [
                    buildSummaryCell('CATEGORY TOTAL',
                        align: pw.TextAlign.left, isBold: true),
                    buildSummaryCell(catIn.toStringAsFixed(3),
                        align: pw.TextAlign.right, isBold: true),
                    buildSummaryCell(catOut.toStringAsFixed(3),
                        align: pw.TextAlign.right, isBold: true),
                  ],
                ),
              );

              content.add(
                pw.Center(
                  child: pw.SizedBox(
                    width: 290,
                    child: pw.Table(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey200, width: 0.5),
                      columnWidths: const {
                        0: pw.FixedColumnWidth(
                            150), // Size Description + Suffix (Compact fit)
                        1: pw.FixedColumnWidth(
                            70), // Inward (MT) (Pulled tight)
                        2: pw.FixedColumnWidth(
                            70), // Outward (MT) (Pulled tight)
                      },
                      children: tableRows,
                    ),
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 15));
            }

            // Overall Total Row for Detailed Mode
            double overallIn = 0;
            double overallOut = 0;
            for (var e in entries) {
              overallIn += e.inQty.abs();
              overallOut += e.outQty.abs();
            }

            content.add(
              pw.Center(
                child: pw.SizedBox(
                  width: 290,
                  child: pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColor.fromHex('#94A3B8'), width: 1.0),
                    columnWidths: const {
                      0: pw.FixedColumnWidth(150),
                      1: pw.FixedColumnWidth(70),
                      2: pw.FixedColumnWidth(70),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#F1F5F9'),
                        ),
                        children: [
                          buildSummaryCell('OVERALL TOTAL',
                              align: pw.TextAlign.left, isBold: true),
                          buildSummaryCell('${overallIn.toStringAsFixed(3)} MT',
                              align: pw.TextAlign.right, isBold: true),
                          buildSummaryCell('${overallOut.toStringAsFixed(3)} MT',
                              align: pw.TextAlign.right, isBold: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateConsolidatedStockPdf({
    required List<ConsolidatedStockEntry> entries,
    required String location,
    required String dateRange,
    String? reportTitle,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();

    // Summary Stats
    final double totalInv = entries.fold(0, (sum, e) => sum + e.totalQty);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            reportTitle ?? 'STOCK OVERVIEW REPORT',
            'Location: $location | Date: $dateRange',
            logo),
        build: (context) => [
          pw.Center(
              child: pw.Column(children: [
            pw.Text('TOTAL INVENTORY',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text('${totalInv.toStringAsFixed(3)} MT',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: totalInv < 0 ? PdfColors.red700 : logoRed)),
          ])),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerDecoration: pw.BoxDecoration(color: logoRed),
            headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding:
                const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
            },
            headers: ['ITEM NAME', 'YARD (MT)', 'FACTORY (MT)', 'TOTAL (MT)'],
            data: entries
                .map((e) => [
                      e.item.toUpperCase(),
                      pw.Text(e.yardQty.toStringAsFixed(3),
                          style: pw.TextStyle(
                              color: e.yardQty < 0
                                  ? PdfColors.red700
                                  : PdfColors.black)),
                      pw.Text(e.factoryQty.toStringAsFixed(3),
                          style: pw.TextStyle(
                              color: e.factoryQty < 0
                                  ? PdfColors.red700
                                  : PdfColors.black)),
                      pw.Text(e.totalQty.toStringAsFixed(3),
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color:
                                  e.totalQty < 0 ? PdfColors.red700 : logoRed)),
                    ])
                .toList(),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
        ],
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateLowStockPdf({
    required List<Map<String, dynamic>> lowStockItemsList,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            'LOW STOCK REPORT', 'Generated on ${df.format(now)}', logo),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.red700),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text("Item / Size Description",
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text("Category",
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text("Status",
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text("Available Qty",
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ),
                ],
              ),
              ...lowStockItemsList.map((item) {
                final qty =
                    double.tryParse(item['net_stock_mt'].toString()) ?? 0.0;
                final statusText =
                    qty == 0.0 ? "Out of Stock" : "Critical Limit";

                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text((() {
                        final String label = (item['size_label'] ??
                                item['size_description'] ??
                                '')
                            .toString()
                            .trim();
                        final String category =
                            (item['item_name'] ?? 'General').toString();
                        double weight = double.tryParse(
                                item['weight']?.toString() ?? '0') ??
                            0.0;
                        if (weight == 0) {
                          weight = lookupSizeWeight(label);
                        }
                        if (weight == 0) {
                          weight = _extractUnitWeight(label);
                        }
                        final formattedWeight = weight % 1 == 0
                            ? weight.toInt().toString()
                            : weight.toStringAsFixed(1);
                        final String suffix =
                            (weight > 0) ? " ${formattedWeight}kg" : "";
                        return (category.trim() == 'MS Angle')
                            ? formatSizeLabel(label, category, weight)
                            : "$label$suffix".trim();
                      })(),
                          style: pw.TextStyle(
                              font: pw.Font.helvetica(),
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(item['item_name'] ?? 'General',
                          style: pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(statusText,
                          style: pw.TextStyle(
                              fontSize: 10,
                              color: qty == 0.0
                                  ? pdf.PdfColors.grey
                                  : pdf.PdfColors.red)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("${qty.toStringAsFixed(3)} MT",
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 10)),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Note: Critical status indicates stock level is below 30% of the reorder threshold.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildProfessionalHeader(String title, String subtitle,
      [pw.ImageProvider? logo]) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('MSM One',
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: logoRed)),
                pw.SizedBox(height: 2),
                pw.Container(
                  margin: (title
                              .toUpperCase()
                              .contains('DETAILED STOCK MOVEMENT REPORT') ||
                          title.toUpperCase().contains('DETAILED STOCK REPORT'))
                      ? const pw.EdgeInsets.only(bottom: 2)
                      : pw.EdgeInsets.zero,
                  child: pw.Text(title,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black)),
                ),
                pw.Text(subtitle,
                    style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                        fontWeight: pw.FontWeight.normal)),
              ],
            ),
            pw.Container(
              width: 30,
              height: 30,
              decoration: pw.BoxDecoration(
                color: logoRed,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('MSM',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 8)),
                    pw.Text('One',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 6)),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 4),
      ],
    );
  }

  static pw.Widget _buildSalesHeader(String title, String date, String refNo,
      [pw.ImageProvider? logo]) {
    final now = DateTime.now();
    final time = DateFormat('HH:mm').format(now);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Brand logo top left
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Container(
                height: 55,
                child: pw.AspectRatio(
                  aspectRatio: 4.88,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              )
            else
              pw.Container(
                height: 55,
                width: 100,
                child: pw.Center(
                  child: pw.Text('METAROLL',
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: logoRed)),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        // Center title & Right metadata
        pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date : $date | $time',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 2),
                  pw.Text(refNo,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
      ],
    );
  }

  static pw.Widget _buildProfessionalFooter(pw.Context context, DateTime now) {
    final df = DateFormat('dd MMM yyyy, hh:mm a');
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Generated by MSM One | ${df.format(now)}',
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.grey600)),
                pw.SizedBox(height: 2),
                pw.Text(
                    'Prepared By: Relationship Manager | Measurement Units: Metric Tons (MT)',
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.grey600)),
              ],
            ),
            pw.Text('From steel to structure',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
      ],
    );
  }

  static Future<Uint8List> generateLowStockReport({
    required List<ItemVariant> items,
    bool isDetailed = true,
    String? reportTitle,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    // Grouping
    Map<String, List<ItemVariant>> grouped = {};
    for (var item in items) {
      grouped.putIfAbsent(item.category, () => []);
      grouped[item.category]!.add(item);
    }
    final categories = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            isDetailed
                ? 'LOW STOCK DETAILED REPORT'
                : 'LOW STOCK SUMMARY REPORT',
            'Generated on ${df.format(now)}',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          if (!isDetailed) {
            // Summary view: Just categories and totals
            List<List<String>> summaryData = [];
            for (var cat in categories) {
              final catItems = grouped[cat]!;
              double total =
                  catItems.fold(0, (sum, e) => sum + e.availableStockMT);
              summaryData.add([cat, total.toStringAsFixed(3)]);
            }

            content.add(
              pw.TableHelper.fromTextArray(
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerDecoration: pw.BoxDecoration(color: logoRed),
                headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellPadding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1)
                },
                headers: ['Item', 'Stock (MT)'],
                data: summaryData,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight
                },
              ),
            );
          } else {
            // Detailed view: Category sections with item tables
            for (var cat in categories) {
              final catItems = grouped[cat]!;
              double total =
                  catItems.fold(0, (sum, e) => sum + e.availableStockMT);

              content.add(
                pw.Container(
                  width: double.infinity,
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: const pw.BoxDecoration(color: PdfColors.red50),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(cat.toUpperCase(),
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                              color: PdfColors.red900)),
                      pw.Text('${total.toStringAsFixed(3)} MT',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                              color: PdfColors.red900)),
                    ],
                  ),
                ),
              );

              List<List<String>> tableData = catItems
                  .map((e) => [
                        '${e.itemName} - ${e.size}',
                        (e.availableStockMT).toStringAsFixed(3),
                      ])
                  .toList();

              content.add(
                pw.TableHelper.fromTextArray(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.red700),
                  headerStyle: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1)
                  },
                  headers: ['Item', 'Stock (MT)'],
                  data: tableData,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight
                  },
                ),
              );
              content.add(pw.SizedBox(height: 10));
            }
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateLowStockEnhancedPdf({
    required List<Map<String, dynamic>> rows,
    required String type, // 'itemWise', 'sizeWise', 'combined'
    required String location,
    required String dateRange,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    String reportTitle = 'LOW STOCK REPORT';
    if (type == 'itemWise') reportTitle = 'LOW STOCK ITEM-WISE QTY REPORT';
    if (type == 'sizeWise') reportTitle = 'LOW STOCK SIZE-WISE QTY REPORT';
    if (type == 'combined') reportTitle = 'LOW STOCK COMBINED REPORT';

    // Calculate item-wise summary
    Map<String, double> itemSummary = {};
    for (var row in rows) {
      final cat = row['category'] as String;
      final qty = row['qty'] as double;
      itemSummary[cat] = (itemSummary[cat] ?? 0) + qty;
    }
    final sortedCats = itemSummary.keys.toList()
      ..sort(SortingUtils.compareCategories);
    final double totalLowStock =
        itemSummary.values.fold(0, (sum, v) => sum + v);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(reportTitle,
            'Location: $location | Generated: ${df.format(now)}', logo),
        build: (context) {
          List<pw.Widget> content = [];

          // Total Stats
          content.add(pw.Center(
              child: pw.Column(children: [
            pw.Text('TOTAL LOW STOCK QUANTITY',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text('${totalLowStock.toStringAsFixed(3)} MT',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: totalLowStock < 0 ? PdfColors.red700 : logoRed)),
          ])));
          content.add(pw.SizedBox(height: 20));

          // 1. Item-wise Section (for Item-wise and Combined)
          if (type == 'itemWise' || type == 'combined') {
            if (type == 'combined') {
              content.add(_buildSectionHeader('ITEM-WISE SUMMARY'));
              content.add(pw.SizedBox(height: 10));
            }

            List<List<String>> summaryTable = sortedCats
                .map((cat) => [
                      cat,
                      itemSummary[cat]!.toStringAsFixed(3),
                    ])
                .toList();

            content.add(
              pw.TableHelper.fromTextArray(
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerDecoration: pw.BoxDecoration(color: logoRed),
                headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellPadding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                headers: ['Item', 'Stock (MT)'],
                data: summaryTable,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight
                },
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.2)
                },
              ),
            );
            content.add(pw.SizedBox(height: 20));
          }

          // 2. Size-wise Section (for Size-wise and Combined)
          if (type == 'sizeWise' || type == 'combined') {
            if (type == 'combined') {
              content.add(_buildSectionHeader('SIZE-WISE DETAILS'));
              content.add(pw.SizedBox(height: 10));
            }

            // Group rows by category for cleaner tables
            Map<String, List<Map<String, dynamic>>> groupedRows = {};
            for (var row in rows) {
              final cat = row['category'] as String;
              groupedRows.putIfAbsent(cat, () => []);
              groupedRows[cat]!.add(row);
            }

            for (var cat in sortedCats) {
              final catRows = groupedRows[cat]!;

              List<List<String>> sizeTable = catRows
                  .map((r) => [
                        '${r['item']} ${r['size']}',
                        (r['qty'] as double).toStringAsFixed(3),
                      ])
                  .toList();

              content.add(
                pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Center(
                        child: pw.SizedBox(
                          width:
                              240, // Matches the data grid envelope perfectly
                          child: pw.Container(
                            alignment: pw.Alignment.centerLeft,
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex(
                                  '#F5F5F5'), // Standard light grey background
                            ),
                            padding: const pw.EdgeInsets.symmetric(
                                vertical: 4, horizontal: 6),
                            child: pw.Text(
                              cat.toUpperCase(),
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex(
                                    '#C61A22'), // Corporate brand red
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Center(
                        child: pw.SizedBox(
                          width: 240,
                          child: pw.TableHelper.fromTextArray(
                            border: pw.TableBorder.all(
                                color: PdfColors.grey200, width: 0.5),
                            headerDecoration:
                                const pw.BoxDecoration(color: PdfColors.red700),
                            headerStyle: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 8),
                            cellStyle: const pw.TextStyle(fontSize: 8),
                            cellPadding: const pw.EdgeInsets.symmetric(
                                vertical: 2, horizontal: 4),
                            oddRowDecoration: const pw.BoxDecoration(
                                color: PdfColors.grey100),
                            rowDecoration:
                                const pw.BoxDecoration(color: PdfColors.white),
                            headers: ['Size Description', 'Low Stock Qty'],
                            data: sizeTable,
                            cellAlignments: {
                              0: pw.Alignment.centerLeft,
                              1: pw.Alignment.centerRight
                            },
                            columnWidths: {
                              0: const pw.FixedColumnWidth(
                                  175), // Size Description
                              1: const pw.FixedColumnWidth(
                                  65), // Low Stock Qty (MT)
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 15));
            }
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildKpiCard(
      String title, String value, PdfColor valueColor) {
    return pw.Container(
      width: 125,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 6.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor)),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: logoRed, width: 3)),
        color: PdfColors.grey50,
      ),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: 11, color: logoRed)),
    );
  }

  static Future<Uint8List> generateCombinedLowStockPdf({
    required List<ItemVariant> entries,
    required String location,
    bool isDetailed = true,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    double totalLowStock =
        entries.fold(0.0, (sum, e) => sum + e.availableStockMT);

    Map<String, List<ItemVariant>> grouped = {};
    for (var e in entries) {
      final String cat = DataRepository.canonicalizeCategory(e.category);
      grouped.putIfAbsent(cat, () => []);
      grouped[cat]!.add(e);
    }
    final categories = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            isDetailed
                ? 'LOW STOCK DETAILED REPORT'
                : 'LOW STOCK SUMMARY REPORT',
            'Period: As of ${df.format(now)} | Location: $location | Generated: ${df.format(now)}',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          content.add(pw.Center(
              child: pw.Column(children: [
            pw.Text('TOTAL LOW STOCK QUANTITY',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text('${totalLowStock.toStringAsFixed(3)} MT',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: totalLowStock < 0 ? PdfColors.red700 : logoRed)),
          ])));
          content.add(pw.SizedBox(height: 20));

          if (isDetailed) {
            for (var cat in categories) {
              final items = grouped[cat]!;
              final uniqueItemsMap = <String, ItemVariant>{};
              for (var item in items) {
                double unitWeight = lookupSizeWeight(item.size);
                if (unitWeight == 0) {
                  unitWeight = _extractUnitWeight(item.size);
                }
                String uniqueKey = "${item.itemName}_${item.size}_$unitWeight";
                if (!uniqueItemsMap.containsKey(uniqueKey)) {
                  uniqueItemsMap[uniqueKey] = item;
                } else {
                  if (item.availableStockMT >
                      uniqueItemsMap[uniqueKey]!.availableStockMT) {
                    uniqueItemsMap[uniqueKey] = item;
                  }
                }
              }
              final filteredItems = uniqueItemsMap.values
                  .where((item) => item.availableStockMT > 0)
                  .toList();
              filteredItems.sort((a, b) {
                int cmp =
                    SortingUtils.compareCategories(a.itemName, b.itemName);
                if (cmp != 0) return cmp;
                return SortingUtils.compareSizes(a.size, b.size);
              });
              if (filteredItems.isEmpty) continue;
              double catTotal =
                  filteredItems.fold(0.0, (sum, e) => sum + e.availableStockMT);

              List<List<String>> tableData = filteredItems.map((e) {
                double unitWeight = lookupSizeWeight(e.size);
                if (unitWeight == 0) {
                  unitWeight = _extractUnitWeight(e.size);
                }
                final String formattedSize =
                    _pSizeLabel(e.itemName, e.size, unitWeight);
                return [
                  '${e.itemName} - $formattedSize',
                  e.availableStockMT.toStringAsFixed(3),
                ];
              }).toList();

              content.add(
                pw.Inseparable(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Center(
                        child: pw.SizedBox(
                          width:
                              240, // Matches the data grid envelope perfectly
                          child: pw.Container(
                            alignment: pw.Alignment.centerLeft,
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex(
                                  '#F5F5F5'), // Standard light grey background
                            ),
                            padding: const pw.EdgeInsets.symmetric(
                                vertical: 4, horizontal: 6),
                            child: pw.Text(
                              cat.toUpperCase(),
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex(
                                    '#C61A22'), // Corporate brand red
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Center(
                        child: pw.SizedBox(
                          width: 240,
                          child: pw.TableHelper.fromTextArray(
                            border: pw.TableBorder.all(
                                color: PdfColors.grey200, width: 0.5),
                            headerDecoration: pw.BoxDecoration(color: logoRed),
                            headerStyle: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 8),
                            cellStyle: const pw.TextStyle(fontSize: 8),
                            cellPadding: const pw.EdgeInsets.symmetric(
                                vertical: 2, horizontal: 4),
                            oddRowDecoration: const pw.BoxDecoration(
                                color: PdfColors.grey100),
                            rowDecoration:
                                const pw.BoxDecoration(color: PdfColors.white),
                            headers: ['Size Description', 'Low Stock Qty'],
                            data: tableData,
                            cellAlignments: {
                              0: pw.Alignment.centerLeft,
                              1: pw.Alignment.centerRight
                            },
                            columnWidths: {
                              0: const pw.FixedColumnWidth(
                                  175), // Size Description (Snug layout for items like 'MS Pipe 0.75" 19x19(1.6) 5kg')
                              1: const pw.FixedColumnWidth(
                                  65), // Low Stock Qty (MT) (Pulled tight against description text)
                            },
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Center(
                        child: pw.SizedBox(
                          width: 240,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                vertical: 4, horizontal: 8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey100,
                              border: pw.Border.all(
                                  color: PdfColors.grey300, width: 0.5),
                            ),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('TOTAL CATEGORY',
                                    style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 8,
                                        color: PdfColors.black)),
                                pw.Text('${catTotal.toStringAsFixed(3)} MT',
                                    style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 8,
                                        color: PdfColors.black)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 15));
            }
          } else {
            // Summary Table
            List<List<String>> summaryData = categories.map((cat) {
              double total =
                  grouped[cat]!.fold(0.0, (sum, e) => sum + e.availableStockMT);
              return [cat, total.toStringAsFixed(3)];
            }).toList();

            content.add(
              pw.Center(
                child: pw.SizedBox(
                  width: 250,
                  child: pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey200, width: 0.5),
                    headerDecoration: pw.BoxDecoration(color: logoRed),
                    headerStyle: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    cellPadding: const pw.EdgeInsets.symmetric(
                        vertical: 4, horizontal: 8),
                    oddRowDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey100),
                    rowDecoration:
                        const pw.BoxDecoration(color: PdfColors.white),
                    headers: ['Category', 'Total Qty (MT)'],
                    data: summaryData,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerRight
                    },
                    columnWidths: {
                      0: const pw.FixedColumnWidth(
                          160), // Category Name (e.g., MS Pipe, MS Angle)
                      1: const pw.FixedColumnWidth(90), // Total Qty (MT)
                    },
                  ),
                ),
              ),
            );
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateCombinedDeadStockPdf({
    required List<DeadStockEntry> entries,
    required String location,
    bool isDetailed = true,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');

    double totalDeadStock = entries.fold(0.0, (sum, e) => sum + e.currentQty);

    Map<String, List<DeadStockEntry>> grouped = {};
    for (var e in entries) {
      final String cat = DataRepository.canonicalizeCategory(e.category);
      grouped.putIfAbsent(cat, () => []);
      grouped[cat]!.add(e);
    }
    final categories = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);

    final String periodStr = (startDate != null && endDate != null)
        ? 'Period: ${df.format(startDate)} to ${df.format(endDate)} | '
        : '';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            isDetailed
                ? 'NON-MOVING STOCK DETAILED REPORT'
                : 'NON-MOVING STOCK SUMMARY REPORT',
            '${periodStr}Location: $location | Generated: ${df.format(now)}',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          content.add(pw.Center(
              child: pw.Column(children: [
            pw.Text('TOTAL NON-MOVING STOCK QUANTITY',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text('${totalDeadStock.toStringAsFixed(3)} MT',
                style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: totalDeadStock < 0 ? PdfColors.red700 : logoRed)),
          ])));
          content.add(pw.SizedBox(height: 20));

          if (isDetailed) {
            for (var cat in categories) {
              final items = grouped[cat]!;
              items.sort((a, b) {
                int cmp =
                    SortingUtils.compareCategories(a.itemName, b.itemName);
                if (cmp != 0) return cmp;
                return SortingUtils.compareSizes(a.size, b.size);
              });
              double catTotal = items.fold(0.0, (sum, e) => sum + e.currentQty);

              content.add(
                pw.Container(
                  width: double.infinity,
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  child: pw.Text(cat.toUpperCase(),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: PdfColors.red900)),
                ),
              );

              List<List<String>> tableData = items.map((e) {
                double unitWeight = lookupSizeWeight(e.size);
                if (unitWeight == 0) {
                  unitWeight = _extractUnitWeight(e.size);
                }
                final String formattedSize =
                    _pSizeLabel(e.itemName, e.size, unitWeight);
                return [
                  '${e.itemName} - $formattedSize',
                  e.currentQty.toStringAsFixed(3),
                ];
              }).toList();

              content.add(
                pw.TableHelper.fromTextArray(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
                  headerDecoration: pw.BoxDecoration(color: logoRed),
                  headerStyle: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  cellPadding:
                      const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  oddRowDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey50),
                  headers: ['Size Description', 'Non-Moving Qty'],
                  data: tableData,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight
                  },
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3.5),
                    1: const pw.FlexColumnWidth(1)
                  },
                ),
              );

              content.add(
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: const pw.BoxDecoration(
                      color: PdfColor(0.89, 0.117, 0.14, 0.1)),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL $cat',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text('${catTotal.toStringAsFixed(3)} MT',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 8,
                              color:
                                  catTotal < 0 ? PdfColors.red700 : logoRed)),
                    ],
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 15));
            }
          } else {
            // Summary Table
            List<List<String>> summaryData = categories.map((cat) {
              double total =
                  grouped[cat]!.fold(0.0, (sum, e) => sum + e.currentQty);
              return [cat, total.toStringAsFixed(3)];
            }).toList();

            content.add(
              pw.TableHelper.fromTextArray(
                border:
                    pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
                headerDecoration: pw.BoxDecoration(color: logoRed),
                headerStyle: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellPadding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey50),
                headers: ['Category', 'Total Qty (MT)'],
                data: summaryData,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight
                },
              ),
            );
          }

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, now),
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateSalesDocumentPdf({
    required SalesDocumentModel model,
  }) async {
    final doc = _createDocument();
    final brandLogo = await _loadBrandLogo();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 0,
          marginRight: 0,
          marginTop: 32,
          marginBottom: 75,
        ),
        margin:
            const pw.EdgeInsets.only(left: 0, right: 0, top: 32, bottom: 75),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 32),
              child: _buildSalesHeader(
                  model.title.toUpperCase(), model.date, model.srNo, brandLogo),
            );
          } else {
            return pw.Padding(
              padding:
                  const pw.EdgeInsets.only(left: 32, right: 32, bottom: 20),
              child: brandLogo != null
                  ? pw.Container(
                      height: 55,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.AspectRatio(
                        aspectRatio: 4.88,
                        child: pw.Image(brandLogo, fit: pw.BoxFit.contain),
                      ),
                    )
                  : pw.SizedBox(height: 55),
            );
          }
        },
        footer: (context) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Center(
                child: pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFCCCCCC),
                  ),
                  child: pw.Text(
                    '***This is a system-generated ${model.title.toLowerCase()} and does not require a signature.***',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              _buildInvoiceFooter(context, model),
            ],
          );
        },
        build: (context) {
          return [
            // Client Section
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 32),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('To,',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    model.firmName.endsWith(',')
                        ? model.firmName
                        : '${model.firmName},',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10),
                  ),
                  pw.Text('Address: ${model.address}',
                      style: const pw.TextStyle(fontSize: 10)),
                  if (model.email.isNotEmpty)
                    pw.Text('E: ${model.email}',
                        style: const pw.TextStyle(fontSize: 10)),
                  if (model.mobile.isNotEmpty)
                    pw.Text('M: ${model.mobile}',
                        style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // Subject
            if (model.subject.isNotEmpty) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 32),
                child: pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: 'Sub: ',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                      pw.TextSpan(
                        text: model.subject,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.normal, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 15),
            ],

            // Inquiry Reference Block
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 32),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Sir/Ma\'am,',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'With reference to the above subject, we sincerely thank you for your valued inquiry.',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 8),
                      pw.Text('-   Our ${model.title} detailed below:',
                          style: const pw.TextStyle(fontSize: 10)),
                    ])),
            pw.SizedBox(height: 15),

            // Custom Integrated Items & Summary Table
            ..._buildCustomInvoiceTableRows(model),

            // Force Terms & Conditions onto a new page
            pw.NewPage(),

            _buildTermsAndConditionsGrid(model),
          ];
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateProformaInvoiceReplicaPdf({
    required SalesDocumentModel model,
  }) async {
    final doc = _createDocument();
    final brandLogo = await _loadBrandLogo();
    final now = DateTime.now();
    final time = DateFormat('HH:mm').format(now);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 0,
          marginRight: 0,
          marginTop: 32,
          marginBottom: 75,
        ),
        margin:
            const pw.EdgeInsets.only(left: 0, right: 0, top: 32, bottom: 75),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 32),
              child: _buildReplicaHeader(model.title.toUpperCase(), model.date,
                  time, model.srNo, brandLogo),
            );
          } else {
            return pw.Padding(
              padding:
                  const pw.EdgeInsets.only(left: 32, right: 32, bottom: 20),
              child: brandLogo != null
                  ? pw.Container(
                      height: 55,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.AspectRatio(
                        aspectRatio: 4.88,
                        child: pw.Image(brandLogo, fit: pw.BoxFit.contain),
                      ),
                    )
                  : pw.SizedBox(height: 55),
            );
          }
        },
        footer: (context) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Center(
                child: pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFCCCCCC),
                  ),
                  child: pw.Text(
                    '***This is a system-generated ${model.title.toLowerCase()} and does not require a signature.***',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              _buildInvoiceFooter(context, model),
            ],
          );
        },
        build: (context) {
          return [
            // Recipient Section
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 32),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('To,',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    model.firmName.endsWith(',')
                        ? model.firmName
                        : '${model.firmName},',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10),
                  ),
                  pw.Text('Address: ${model.address}',
                      style: const pw.TextStyle(fontSize: 10)),
                  if (model.email.isNotEmpty)
                    pw.Text('E: ${model.email}',
                        style: const pw.TextStyle(fontSize: 10)),
                  if (model.mobile.isNotEmpty)
                    pw.Text('M: ${model.mobile}',
                        style: const pw.TextStyle(fontSize: 10)),
                  if (model.gstNo.isNotEmpty)
                    pw.Text('GSTIN: ${model.gstNo}',
                        style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // Subject
            if (model.subject.isNotEmpty) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 32),
                child: pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: 'Sub: ',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                      pw.TextSpan(
                        text: model.subject,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.normal, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 15),
            ],

            // Inquiry Reference Block
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 32),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Sir/Ma\'am,',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'With reference to the above subject, we sincerely thank you for your valued inquiry.',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 8),
                      pw.Text('-   Our ${model.title} detailed below:',
                          style: const pw.TextStyle(fontSize: 10)),
                    ])),
            pw.SizedBox(height: 15),

            // Custom Integrated Items & Summary Table
            ..._buildCustomInvoiceTableRows(model),

            // Force Terms & Conditions onto a new page
            pw.NewPage(),

            _buildTermsAndConditionsGrid(model),
          ];
        },
      ),
    );

    return doc.save();
  }

  static List<pw.Widget> _buildCustomInvoiceTableRows(
      SalesDocumentModel model) {
    const headerRed =
        PdfColor.fromInt(0xFFDE2030); // Bright red from screenshot
    const rowGrey = PdfColor.fromInt(0xFFF2F2F2);
    const amountBg = PdfColor.fromInt(
        0xFFFFEBEE); // Light pink/red background for amount in words
    const borderColor = PdfColors.white;

    bool isQuotation = model.title.toLowerCase().contains('quotation');
    bool hasNos = model.items.any((item) => item.nos > 0);

    final columnWidths = isQuotation
        ? (hasNos
            ? {
                0: const pw.FlexColumnWidth(6),
                1: const pw.FlexColumnWidth(22),
                2: const pw.FlexColumnWidth(24),
                3: const pw.FlexColumnWidth(13),
                4: const pw.FlexColumnWidth(13),
                5: const pw.FlexColumnWidth(17),
              }
            : {
                0: const pw.FlexColumnWidth(6),
                1: const pw.FlexColumnWidth(30),
                2: const pw.FlexColumnWidth(20),
                3: const pw.FlexColumnWidth(15),
                4: const pw.FlexColumnWidth(20),
              })
        : {
            0: const pw.FlexColumnWidth(6),
            1: const pw.FlexColumnWidth(22),
            2: const pw.FlexColumnWidth(24),
            3: const pw.FlexColumnWidth(13),
            4: const pw.FlexColumnWidth(13),
            5: const pw.FlexColumnWidth(17),
          };

    pw.Widget cell(
      String text, {
      bool isHeader = false,
      bool isBold = false,
      pw.TextAlign align = pw.TextAlign.center,
      PdfColor? textColor,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        alignment: align == pw.TextAlign.left
            ? pw.Alignment.centerLeft
            : (align == pw.TextAlign.right
                ? pw.Alignment.centerRight
                : pw.Alignment.center),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            color: textColor ?? (isHeader ? PdfColors.white : PdfColors.black),
            fontWeight: (isHeader || isBold)
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
            fontSize: 9,
          ),
        ),
      );
    }

    double totalQty = 0;
    bool hasBindingWire = false;
    for (var item in model.items) {
      totalQty += item.qty;
      if (item.description.toLowerCase().contains('binding wire')) {
        hasBindingWire = true;
      }
    }

    List<pw.TableRow> tableRows = [];

    if (isQuotation) {
      if (hasNos) {
        tableRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: headerRed),
            children: [
              cell('Sr.\nNo.', isHeader: true),
              cell('Description of\nGoods', isHeader: true),
              cell('Sizes', isHeader: true),
              cell('NOS', isHeader: true),
              cell('QTY', isHeader: true),
              cell('Net Rate', isHeader: true),
            ],
          ),
        );
      } else {
        tableRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: headerRed),
            children: [
              cell('Sr.\nNo.', isHeader: true),
              cell('Description of\nGoods', isHeader: true),
              cell('Sizes', isHeader: true),
              cell('QTY', isHeader: true),
              cell('Net Rate', isHeader: true),
            ],
          ),
        );
      }
    } else {
      tableRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: headerRed),
          children: [
            cell('Sr.\nNo.', isHeader: true),
            cell('Description of\nGoods', isHeader: true),
            cell(hasBindingWire ? 'Gauge' : 'Sizes', isHeader: true),
            cell('QTY\n(MT)', isHeader: true),
            cell('Rate\n(MT)', isHeader: true),
            cell('Total', isHeader: true),
          ],
        ),
      );
    }

    for (int i = 0; i < model.items.length; i++) {
      final item = model.items[i];
      if (isQuotation) {
        if (hasNos) {
          tableRows.add(
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: rowGrey),
              children: [
                cell((i + 1).toString()),
                cell(item.description, align: pw.TextAlign.left),
                cell(_pSizeLabel(item.description, item.size, item.unitWeight)),
                cell(item.nos == 0 ? '-' : item.nos.toString()),
                cell(item.qty.toStringAsFixed(3)),
                cell(item.rate.toStringAsFixed(2), align: pw.TextAlign.right),
              ],
            ),
          );
        } else {
          tableRows.add(
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: rowGrey),
              children: [
                cell((i + 1).toString()),
                cell(item.description, align: pw.TextAlign.left),
                cell(_pSizeLabel(item.description, item.size, item.unitWeight)),
                cell(item.qty.toStringAsFixed(3)),
                cell(item.rate.toStringAsFixed(2), align: pw.TextAlign.right),
              ],
            ),
          );
        }
      } else {
        tableRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: rowGrey),
            children: [
              cell((i + 1).toString()),
              cell(item.description, align: pw.TextAlign.left),
              cell(_pSizeLabel(item.description, item.size, item.unitWeight)),
              cell(item.qty.toStringAsFixed(3)),
              cell(item.rate.toStringAsFixed(2), align: pw.TextAlign.right),
              cell(item.total.toStringAsFixed(2), align: pw.TextAlign.right),
            ],
          ),
        );
      }
    }

    if (!isQuotation) {
      tableRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: rowGrey),
          children: [
            cell(''),
            cell(''),
            cell('Total', isBold: true, align: pw.TextAlign.right),
            cell(totalQty.toStringAsFixed(3), isBold: true),
            cell(''),
            cell(model.subtotal.toStringAsFixed(2),
                isBold: true, align: pw.TextAlign.right),
          ],
        ),
      );
      if (model.freight > 0) {
        tableRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: rowGrey),
            children: [
              cell(''),
              cell(''),
              cell(''),
              cell(''),
              cell('Freight', isBold: true, align: pw.TextAlign.right),
              cell(model.freight.toStringAsFixed(2),
                  isBold: true, align: pw.TextAlign.right),
            ],
          ),
        );
      }
      tableRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: rowGrey),
          children: [
            cell(''),
            cell(''),
            cell(''),
            cell(''),
            cell('GST @18%', isBold: true, align: pw.TextAlign.right),
            cell(model.gst.toStringAsFixed(2),
                isBold: true, align: pw.TextAlign.right),
          ],
        ),
      );
      tableRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: rowGrey),
          children: [
            cell(''),
            cell(''),
            cell(''),
            cell(''),
            cell('Total', isBold: true, align: pw.TextAlign.right),
            cell(model.grandTotal.toStringAsFixed(2),
                isBold: true, align: pw.TextAlign.right),
          ],
        ),
      );
    }

    // Assemble the Table wrapped in padding
    final tableWidget = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 32),
      child: pw.Table(
        columnWidths: columnWidths,
        border: const pw.TableBorder(
          left: pw.BorderSide(color: borderColor, width: 1),
          right: pw.BorderSide(color: borderColor, width: 1),
          top: pw.BorderSide(color: borderColor, width: 1),
          bottom: pw.BorderSide(color: borderColor, width: 1),
          horizontalInside: pw.BorderSide(color: borderColor, width: 1),
          verticalInside: pw.BorderSide(color: borderColor, width: 1),
        ),
        children: tableRows,
      ),
    );

    // Amount in words block wrapped in padding
    final amountInWordsWidget = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 32),
      child: pw.Container(
        width: double.infinity,
        decoration: const pw.BoxDecoration(
          color: amountBg,
          border: pw.Border(
            left: pw.BorderSide(color: borderColor, width: 1),
            right: pw.BorderSide(color: borderColor, width: 1),
            bottom: pw.BorderSide(color: borderColor, width: 1),
          ),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Amount in Words:',
                style: pw.TextStyle(
                    color: PdfColors.red700,
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(model.amountInWords,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                    color: PdfColors.black)),
          ],
        ),
      ),
    );

    return [
      tableWidget,
      amountInWordsWidget,
    ];
  }

  static pw.Widget _buildReplicaHeader(
      String title, String date, String time, String refNo,
      [pw.ImageProvider? logo]) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Brand logo top left
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Container(
                height: 55,
                child: pw.AspectRatio(
                  aspectRatio: 4.88,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              )
            else
              pw.Container(
                height: 55,
                width: 100,
                child: pw.Center(
                  child: pw.Text('METAROLL',
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: logoRed)),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        // Center title & Right metadata
        pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date : $date | $time',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 2),
                  pw.Text(refNo,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
      ],
    );
  }

  static Map<String, String> _parseTermsAndConditions(String termsText) {
    final Map<String, String> result = {
      'Rates': 'FOR',
      'Payment Terms': '100% Payment in Advance.',
      'Unloading': 'At your end at your cost.',
      'Weight Tolerance':
          'You should allow Weight tolerance of + 0.5% between your & our Scale no deduction should be made for such tolerance.',
      'Delivery':
          'FOR, Delivery will be made within 4-6 days from the receipt of your confirmed order and advance payment.',
      'Transport': 'Inclusive above rate',
    };

    if (termsText.trim().isEmpty) {
      return result;
    }

    final lines = termsText.split('\n');
    bool hasParsedAny = false;
    final Map<String, String> parsed = {};

    for (var line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      trimmed = trimmed.replaceFirst(RegExp(r'^\d+[\.\-\s]+'), '');
      trimmed = trimmed.replaceFirst(RegExp(r'^[\-\*•]\s*'), '');

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx != -1) {
        final key = trimmed.substring(0, colonIdx).trim();
        final val = trimmed.substring(colonIdx + 1).trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          hasParsedAny = true;
          String normalizedKey = key;
          final lowerKey = key.toLowerCase();
          if (lowerKey == 'rates' || lowerKey == 'rate') {
            normalizedKey = 'Rates';
          } else if (lowerKey.contains('payment')) {
            normalizedKey = 'Payment Terms';
          } else if (lowerKey == 'unloading') {
            normalizedKey = 'Unloading';
          } else if (lowerKey.contains('tolerance')) {
            normalizedKey = 'Weight Tolerance';
          } else if (lowerKey == 'delivery') {
            normalizedKey = 'Delivery';
          } else if (lowerKey == 'transport') {
            normalizedKey = 'Transport';
          }
          parsed[normalizedKey] = val;
        }
      }
    }

    if (hasParsedAny) {
      for (var key in parsed.keys) {
        result[key] = parsed[key]!;
      }
    }

    return result;
  }

  static pw.Widget _buildTermsAndConditionsGrid(SalesDocumentModel model) {
    final termsMap = _parseTermsAndConditions(model.terms);

    final freightVal = model.freightRatePerMt;
    termsMap['Transport'] =
        (freightVal > 0) ? 'Inclusive above rate' : 'Exclusive above rate';

    termsMap['Weight Tolerance'] =
        'You should allow Weight tolerance of + 0.5% between your & our Scale no deduction should be made for such tolerance.';

    termsMap['Delivery'] =
        'FOR, Delivery will be made within 4-6 days from the receipt of your confirmed order and advance payment.';

    pw.Widget buildGridRow(String label, pw.Widget valueWidget) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(
                label,
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.normal),
              ),
            ),
            pw.SizedBox(
              width: 15,
              child: pw.Text(
                ':',
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.normal),
              ),
            ),
            pw.Expanded(
              child: valueWidget,
            ),
          ],
        ),
      );
    }

    pw.Widget buildTextValue(String text) {
      return pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.normal),
      );
    }

    pw.Widget buildNestedBankRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.Text(' : ', style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(
              child: pw.Text(
                value,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
      );
    }

    final List<pw.Widget> rows = [];

    rows.add(
      pw.Center(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE0E0E0),
          ),
          child: pw.Text(
            '!! Terms & Conditions !!',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: PdfColors.black,
            ),
          ),
        ),
      ),
    );

    termsMap.forEach((key, value) {
      rows.add(buildGridRow(key, buildTextValue(value)));
    });

    rows.add(pw.SizedBox(height: 8));

    rows.add(
      buildGridRow(
        'Bank Details',
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            buildNestedBankRow(
                'Name of Company', 'Metarolls Steel Mart Private Limited'),
            buildNestedBankRow('Name of Bank',
                model.bankName.isNotEmpty ? model.bankName : 'ICICI Bank'),
            buildNestedBankRow('Account No.',
                model.accNo.isNotEmpty ? model.accNo : '777705854699'),
            buildNestedBankRow('IFSC Code',
                model.ifsc.isNotEmpty ? model.ifsc : 'ICIC0006469'),
            buildNestedBankRow('Branch',
                model.branch.isNotEmpty ? model.branch : 'Jalna Branch'),
          ],
        ),
      ),
    );

    rows.add(pw.SizedBox(height: 8));

    rows.add(
      buildGridRow(
        'Billing Details',
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Metarolls Steel Mart Private Limited,',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text(
                'Gut No. 48, Adjacent to MIDC, Phase II, Daregaon, Jalna - 431203',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text('GSTIN/UIN: 27AARCM5928R1ZB            PAN: AARCM5928R',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text('State Name: Maharashtra  State Code: 27',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text('CIN: U24109MH2023PTC415890',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Text('Email: ', style: const pw.TextStyle(fontSize: 9)),
                pw.Text(
                  'metarollssteelmart@metarolls.com',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.blue700,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 32),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  static pw.Widget _buildInvoiceFooter(
      pw.Context context, SalesDocumentModel model) {
    final PdfColor brandRed = PdfColor.fromHex('#DE2030');
    final PdfColor lightPink = PdfColor.fromHex('#E57373');
    final PdfColor greyText = PdfColor.fromHex('#555555');
    final PdfColor darkGrey = PdfColor.fromHex('#333333');

    // Custom Map Pin Painter
    final mapPin = pw.CustomPaint(
      size: const PdfPoint(8, 12),
      painter: (PdfGraphics canvas, PdfPoint size) {
        final double cx = size.x / 2;
        final double r = size.x / 2;
        final double cy = size.y - r;

        // Outer Pin Shape
        canvas.drawEllipse(cx, cy, r, r);
        canvas.setFillColor(brandRed);
        canvas.fillPath();

        canvas.moveTo(cx - r * 0.8, cy);
        canvas.lineTo(cx, 0);
        canvas.lineTo(cx + r * 0.8, cy);
        canvas.closePath();
        canvas.setFillColor(brandRed);
        canvas.fillPath();

        // Inner white dot
        canvas.drawEllipse(cx, cy, r * 0.4, r * 0.4);
        canvas.setFillColor(PdfColors.white);
        canvas.fillPath();
      },
    );

    // Custom Mail Envelope Painter
    final mailEnvelope = pw.Container(
      width: 11,
      height: 8,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: brandRed, width: 0.8),
      ),
      child: pw.CustomPaint(
        painter: (PdfGraphics canvas, PdfPoint size) {
          canvas
            ..moveTo(0, size.y)
            ..lineTo(size.x / 2, size.y / 2)
            ..lineTo(size.x, size.y)
            ..setStrokeColor(brandRed)
            ..setLineWidth(0.8)
            ..strokePath();
        },
      ),
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 32),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Column 1: Red Block + Company Name & CIN
          pw.Expanded(
            flex: 4,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 45,
                  height: 22,
                  decoration: pw.BoxDecoration(
                    color: lightPink,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Metarolls Steel Mart Private Limited',
                        style: pw.TextStyle(
                          color: brandRed,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8.5,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '[CIN No: U24109MH2023PTC415890]',
                        style: pw.TextStyle(
                          color: darkGrey,
                          fontSize: 7.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 15),

          // Column 2: Map Pin + Reg Office
          pw.Expanded(
            flex: 4,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: mapPin,
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Reg Office & Manufacturing Unit',
                        style: pw.TextStyle(
                          color: darkGrey,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 7.5,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Gut no. 48 Adjacent to, MIDC, Phase II,',
                        style: pw.TextStyle(
                          color: greyText,
                          fontSize: 7.5,
                        ),
                      ),
                      pw.Text(
                        'Daregaon, Jalna - 431203 (MH) INDIA.',
                        style: pw.TextStyle(
                          color: greyText,
                          fontSize: 7.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 15),

          // Column 3: Mail Icon + Email
          pw.Expanded(
            flex: 3,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: mailEnvelope,
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    'metarollssteelmart@metarolls.com',
                    style: pw.TextStyle(
                      color: greyText,
                      fontSize: 7.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> generateStockLedgerReport({
    required List<StockTransaction> transactions,
    required DateTime currentDate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final doc = _createDocument();
    final logo = await _loadLogo();
    final df = DateFormat('dd MMM yyyy HH:mm');
    final dfShort = DateFormat('dd MMM yyyy');

    // 1. Group transactions by Category, and within category group by Item & Size variant
    final Map<String, List<StockTransaction>> groupedByCat = {};
    for (var tx in transactions) {
      final String rawCat =
          tx.category.trim().isNotEmpty && tx.category != 'General'
              ? tx.category.trim()
              : tx.itemName.trim();
      final String cat = DataRepository.canonicalizeCategory(rawCat);
      groupedByCat.putIfAbsent(cat, () => []);
      groupedByCat[cat]!.add(tx);
    }

    final sortedCategories = groupedByCat.keys.toList()
      ..sort(SortingUtils.compareCategories);

    // Compute Executive KPI Cards data & per-category rows
    double globalTotalOpen = 0.0;
    double globalTotalIn = 0.0;
    double globalTotalOut = 0.0;
    double globalTotalNetClosing = 0.0;

    final Map<String, List<Map<String, dynamic>>> categoryRowsMap = {};
    final Map<String, Map<String, double>> categorySubtotalsMap = {};

    for (var cat in sortedCategories) {
      final catTxs = groupedByCat[cat]!;
      final Map<String, List<StockTransaction>> variantMap = {};
      for (var tx in catTxs) {
        final key = "${tx.itemName}_${tx.size}";
        variantMap.putIfAbsent(key, () => []);
        variantMap[key]!.add(tx);
      }

      double catTotalOpen = 0.0;
      double catTotalIn = 0.0;
      double catTotalOut = 0.0;
      double catTotalClosing = 0.0;

      List<Map<String, dynamic>> rows = [];

      for (var variantKey in variantMap.keys) {
        final variantTxs = variantMap[variantKey]!
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        double runningStock = 0.0;

        for (var txn in variantTxs) {
          double opening = runningStock;
          double inward = 0.0;
          double outward = 0.0;

          if (txn.type == 'IN' || txn.type == 'RETURN') {
            inward = txn.qtyMT;
          } else if (txn.type == 'OUT' || txn.type == 'TRANSFER') {
            outward = txn.qtyMT;
          } else if (txn.type == 'ADJUSTMENT') {
            if (txn.qtyMT >= 0) {
              inward = txn.qtyMT;
            } else {
              outward = -txn.qtyMT;
            }
          }

          double closing = opening + inward - outward;
          runningStock = closing;

          catTotalOpen += opening;
          catTotalIn += inward;
          catTotalOut += outward;
          catTotalClosing += closing;

          // Handle size label formatting
          final String sizeLabel = txn.size;
          double unitWeight = lookupSizeWeight(sizeLabel);
          if (unitWeight == 0) {
            unitWeight = _extractUnitWeight(sizeLabel);
          }
          final String formattedSize =
              _pSizeLabel(txn.itemName, sizeLabel, unitWeight);

          rows.add({
            'dateTime': txn.dateTime,
            'date': DateFormat('dd-MM-yy').format(txn.dateTime),
            'item': "${txn.itemName} - $formattedSize",
            'open': opening,
            'in': inward,
            'out': outward,
            'closing': closing,
            'isNeg': closing < 0,
          });
        }
      }

      // Sort category rows chronologically (or by date descending)
      rows.sort((a, b) =>
          (b['dateTime'] as DateTime).compareTo(a['dateTime'] as DateTime));
      categoryRowsMap[cat] = rows;
      categorySubtotalsMap[cat] = {
        'open': catTotalOpen,
        'in': catTotalIn,
        'out': catTotalOut,
        'closing': catTotalClosing,
      };

      globalTotalOpen += catTotalOpen;
      globalTotalIn += catTotalIn;
      globalTotalOut += catTotalOut;
      globalTotalNetClosing += catTotalClosing;
    }

    final String periodStr = (startDate != null && endDate != null)
        ? 'Period: ${dfShort.format(startDate)} to ${dfShort.format(endDate)} | '
        : '';

    final primaryThemeColor = PdfColor.fromHex('#C81E1E');
    final zebraBg = PdfColor.fromHex('#F9FAFB');
    final softGreen = PdfColor.fromHex('#1B5E20');
    final softCrimson = PdfColor.fromHex('#B71C1C');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (context) => _buildProfessionalHeader(
            'STOCK LEDGER & RECONCILIATION REPORT',
            '${periodStr}Generated: ${df.format(currentDate)}',
            logo),
        build: (context) {
          List<pw.Widget> content = [];

          // 1. Executive KPI Header Cards (4 Columns)
          content.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildKpiCard(
                    'TOTAL OPENING STOCK',
                    '${globalTotalOpen.toStringAsFixed(3)} MT',
                    PdfColors.grey700),
                _buildKpiCard('TOTAL INWARD STOCK',
                    '${globalTotalIn.toStringAsFixed(3)} MT', softGreen),
                _buildKpiCard('TOTAL OUTWARD STOCK',
                    '${globalTotalOut.toStringAsFixed(3)} MT', softCrimson),
                _buildKpiCard(
                    'TOTAL NET CLOSING',
                    '${globalTotalNetClosing.toStringAsFixed(3)} MT',
                    primaryThemeColor),
              ],
            ),
          );
          content.add(pw.SizedBox(height: 14));

          // 2. Render Categories with Headers, Tables, Subtotals
          for (var cat in sortedCategories) {
            final catRows = categoryRowsMap[cat]!;
            final subtotals = categorySubtotalsMap[cat]!;

            content.add(
              pw.Container(
                width: double.infinity,
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: pw.BoxDecoration(color: primaryThemeColor),
                child: pw.Text(
                  cat.toUpperCase(),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9.5,
                    color: PdfColors.white,
                  ),
                ),
              ),
            );
            content.add(pw.SizedBox(height: 4));

            List<List<dynamic>> tableData = [];
            for (int i = 0; i < catRows.length; i++) {
              final r = catRows[i];
              final bool isNeg = r['isNeg'] == true;
              final double inVal = (r['in'] is num)
                  ? (r['in'] as num).toDouble()
                  : (double.tryParse(r['in']?.toString() ?? '') ?? 0.0);
              final double outVal = (r['out'] is num)
                  ? (r['out'] as num).toDouble()
                  : (double.tryParse(r['out']?.toString() ?? '') ?? 0.0);
              final double openVal = (r['open'] is num)
                  ? (r['open'] as num).toDouble()
                  : (double.tryParse(r['open']?.toString() ?? '') ?? 0.0);
              final double closingVal = (r['closing'] is num)
                  ? (r['closing'] as num).toDouble()
                  : (double.tryParse(r['closing']?.toString() ?? '') ?? 0.0);

              tableData.add([
                r['date'] as String,
                r['item'] as String,
                openVal.toStringAsFixed(3),
                inVal.toStringAsFixed(3),
                outVal.toStringAsFixed(3),
                closingVal.toStringAsFixed(3),
                isNeg ? "Negative Stock" : "Normal",
              ]);
            }

            content.add(
              pw.TableHelper.fromTextArray(
                border:
                    pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                headerStyle: pw.TextStyle(
                    color: PdfColors.black,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                cellPadding:
                    const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                oddRowDecoration: pw.BoxDecoration(color: zebraBg),
                headers: [
                  'Date',
                  'Item & Sizes',
                  'Open (MT)',
                  'Inward (MT)',
                  'Outward (MT)',
                  'Closing (MT)',
                  'Status'
                ],
                data: tableData,
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.center,
                },
                columnWidths: {
                  0: const pw.FixedColumnWidth(60),
                  1: const pw.FixedColumnWidth(170),
                  2: const pw.FixedColumnWidth(55),
                  3: const pw.FixedColumnWidth(55),
                  4: const pw.FixedColumnWidth(55),
                  5: const pw.FixedColumnWidth(55),
                  6: const pw.FixedColumnWidth(70),
                },
              ),
            );

            // Category Subtotal Row
            content.add(pw.SizedBox(height: 2));
            content.add(
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CATEGORY SUBTOTAL (${cat.toUpperCase()})',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 7.5,
                            color: PdfColors.black)),
                    pw.Row(
                      children: [
                        pw.Text(
                            'In: ${subtotals['in']!.toStringAsFixed(3)} MT  |  ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 7.5,
                                color: softGreen)),
                        pw.Text(
                            'Out: ${subtotals['out']!.toStringAsFixed(3)} MT  |  ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 7.5,
                                color: softCrimson)),
                        pw.Text(
                            'Closing: ${subtotals['closing']!.toStringAsFixed(3)} MT',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 7.5,
                                color: primaryThemeColor)),
                      ],
                    ),
                  ],
                ),
              ),
            );

            content.add(pw.SizedBox(height: 12));
          }

          // 3. Authorized Signature Block
          content.add(pw.SizedBox(height: 20));
          content.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                        width: 140, height: 1, color: PdfColors.grey400),
                    pw.SizedBox(height: 4),
                    pw.Text('Prepared By',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                        width: 140, height: 1, color: PdfColors.grey400),
                    pw.SizedBox(height: 4),
                    pw.Text('Authorized Signature',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          );

          return content;
        },
        footer: (context) => _buildProfessionalFooter(context, currentDate),
      ),
    );

    final bytes = await doc.save();
    final filename =
        "MSM_Stock_Ledger_${DateFormat('yyyyMMdd').format(currentDate)}.pdf";

    if (kIsWeb) {
      download_helper.downloadFile(bytes, filename);
    } else {
      final directory = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File("${directory.path}/$filename");
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Stock Ledger Report');
    }
  }
}

double _extractUnitWeight(String sizeLabel) {
  if (sizeLabel.isEmpty) return 0.0;
  try {
    final RegExp regex = RegExp(r'\(([^)]+)\)');
    final match = regex.firstMatch(sizeLabel);
    if (match != null) {
      final String val = match.group(1)!.replaceAll(RegExp(r'[^0-9.]'), '');
      if (sizeLabel.contains("1.2")) return 4.0;
      if (sizeLabel.contains("1.6")) return 4.0;
      if (sizeLabel.contains("2.0")) return 5.0;
      return double.tryParse(val) ?? 0.0;
    }
  } catch (_) {}
  return 0.0;
}
