import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/report_models.dart';
import '../models/stock_models.dart';
import '../utils/file_download_helper.dart' as download_helper;

/// Enterprise CSV Export Service for Metaroll Steel Mart ERP.
/// Provides RFC-4180 compliant CSV generation with UTF-8 BOM encoding for Excel.
class CsvReportService {
  /// Escapes a CSV field according to RFC-4180.
  static String _escapeField(dynamic value) {
    if (value == null) return '""';
    String str = value.toString();
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      str = '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  /// Converts a matrix of rows to a UTF-8 BOM CSV byte array.
  static Uint8List _buildCsvBytes(List<List<dynamic>> rows) {
    final StringBuffer buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map(_escapeField).join(','));
    }
    // Prepend UTF-8 BOM (0xEF, 0xBB, 0xBF) so Excel correctly parses special characters
    final List<int> utf8Bom = [0xEF, 0xBB, 0xBF];
    final List<int> csvEncoded = utf8.encode(buffer.toString());
    return Uint8List.fromList([...utf8Bom, ...csvEncoded]);
  }

  /// Downloads or saves & shares the CSV file.
  static Future<void> exportAndDownload({
    required Uint8List bytes,
    required String filename,
    String? shareSubject,
  }) async {
    try {
      if (kIsWeb) {
        download_helper.downloadFile(bytes, filename);
      } else {
        final directory = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: shareSubject ?? filename,
        );
      }
    } catch (e, st) {
      debugPrint('[CsvReportService] export error: $e');
      debugPrint('[CsvReportService] stackTrace: $st');
      rethrow;
    }
  }

  /// Generates CSV for Stock Movement report.
  static Future<void> exportStockMovementCsv({
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required List<StockMovementEntry> entries,
  }) async {
    final df = DateFormat('dd-MMM-yyyy');
    final rows = <List<dynamic>>[
      ['METAROLL STEEL MART - STOCK MOVEMENT REPORT'],
      ['Period', '${df.format(startDate)} to ${df.format(endDate)}'],
      ['Location', location],
      ['Generated On', DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())],
      [],
      [
        'Category',
        'Item Name',
        'Size',
        'Opening (MT)',
        'Inward (MT)',
        'Outward (MT)',
        'Closing (MT)',
      ],
    ];

    for (final e in entries) {
      if (e.sizes.isNotEmpty) {
        for (final s in e.sizes) {
          rows.add([
            e.category,
            e.itemName,
            s.label,
            s.opening.toStringAsFixed(3),
            s.inQty.toStringAsFixed(3),
            s.outQty.toStringAsFixed(3),
            s.closing.toStringAsFixed(3),
          ]);
        }
      } else {
        rows.add([
          e.category,
          e.itemName,
          e.size,
          e.opening.toStringAsFixed(3),
          e.inQty.toStringAsFixed(3),
          e.outQty.toStringAsFixed(3),
          e.closing.toStringAsFixed(3),
        ]);
      }
    }

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'stock_movement_${location.toLowerCase()}_$timestamp.csv';
    final bytes = _buildCsvBytes(rows);
    await exportAndDownload(
      bytes: bytes,
      filename: filename,
      shareSubject: 'MSM Stock Movement Report',
    );
  }

  /// Generates CSV for Today's Summary report.
  static Future<void> exportTodaySummaryCsv({
    required String flowMode,
    required List<DailyMovementEntry> entries,
    required String location,
  }) async {
    final rows = <List<dynamic>>[
      ['METAROLL STEEL MART - DAILY SUMMARY REPORT'],
      ['Flow Mode', flowMode],
      ['Location', location],
      ['Generated On', DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())],
      [],
      [
        'Category',
        'Item Name',
        'Size',
        'Opening (MT)',
        'Inward (MT)',
        'Outward (MT)',
        'Net Qty (MT)',
        'Closing (MT)',
      ],
    ];

    for (final e in entries) {
      rows.add([
        e.category,
        e.itemName,
        e.size,
        e.openingQty.toStringAsFixed(3),
        e.inQty.toStringAsFixed(3),
        e.outQty.toStringAsFixed(3),
        e.netQty.toStringAsFixed(3),
        e.closingQty.toStringAsFixed(3),
      ]);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'daily_summary_${flowMode.toLowerCase()}_$timestamp.csv';
    final bytes = _buildCsvBytes(rows);
    await exportAndDownload(
      bytes: bytes,
      filename: filename,
      shareSubject: 'MSM Daily Summary Report',
    );
  }

  /// Generates CSV for Low Stock report.
  static Future<void> exportLowStockCsv({
    required List<ItemVariant> items,
    required String location,
  }) async {
    final rows = <List<dynamic>>[
      ['METAROLL STEEL MART - LOW STOCK REPORT'],
      ['Location', location],
      ['Generated On', DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())],
      [],
      [
        'Category',
        'Item Name',
        'Size',
        'Current Stock (MT)',
        'Min Stock (MT)',
        'Location',
      ],
    ];

    for (final item in items) {
      rows.add([
        item.category,
        item.itemName,
        item.size,
        item.currentStockMT.toStringAsFixed(3),
        item.minStock.toStringAsFixed(3),
        item.location,
      ]);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'low_stock_report_$timestamp.csv';
    final bytes = _buildCsvBytes(rows);
    await exportAndDownload(
      bytes: bytes,
      filename: filename,
      shareSubject: 'MSM Low Stock Report',
    );
  }

  /// Generates CSV for Non-Moving Stock report.
  static Future<void> exportDeadStockCsv({
    required List<DeadStockEntry> entries,
    required String location,
  }) async {
    final df = DateFormat('dd-MMM-yyyy');
    final rows = <List<dynamic>>[
      ['METAROLL STEEL MART - NON-MOVING STOCK REPORT'],
      ['Location', location],
      ['Generated On', DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())],
      [],
      [
        'Category',
        'Item Name',
        'Size',
        'Last Movement Date',
        'Days Since Movement',
        'Current Stock (MT)',
      ],
    ];

    for (final e in entries) {
      rows.add([
        e.category,
        e.itemName,
        e.size,
        e.lastMovementDate != null
            ? df.format(e.lastMovementDate!)
            : 'No Movement',
        e.daysSinceLastMovement,
        e.currentQty.toStringAsFixed(3),
      ]);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'non_moving_stock_report_$timestamp.csv';
    final bytes = _buildCsvBytes(rows);
    await exportAndDownload(
      bytes: bytes,
      filename: filename,
      shareSubject: 'MSM Non-Moving Stock Report',
    );
  }

  /// Generates CSV for Stock Ledger report.
  static Future<void> exportStockLedgerCsv({
    required List<StockTransaction> transactions,
    required String location,
  }) async {
    final df = DateFormat('dd-MMM-yyyy HH:mm');
    final rows = <List<dynamic>>[
      ['METAROLL STEEL MART - STOCK LEDGER REPORT'],
      ['Location', location],
      ['Generated On', DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())],
      [],
      [
        'Date & Time',
        'Txn ID',
        'Type',
        'Category',
        'Item Name',
        'Size',
        'Location',
        'Quantity (MT)',
        'Remarks / Partner',
      ],
    ];

    for (final tx in transactions) {
      rows.add([
        df.format(tx.dateTime),
        tx.txnId,
        tx.type,
        tx.category,
        tx.itemName,
        tx.size,
        tx.location,
        tx.qtyMT.toStringAsFixed(3),
        tx.partyName ?? tx.note ?? tx.reason ?? '',
      ]);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'stock_ledger_report_$timestamp.csv';
    final bytes = _buildCsvBytes(rows);
    await exportAndDownload(
      bytes: bytes,
      filename: filename,
      shareSubject: 'MSM Stock Ledger Report',
    );
  }
}
