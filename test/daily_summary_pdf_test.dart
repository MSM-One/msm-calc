import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:msm_calc/models/report_models.dart';
import 'package:msm_calc/services/pdf_report_service.dart';

int _indexOf(List<int> source, List<int> pattern, int fromIndex) {
  if (pattern.isEmpty) return fromIndex;
  outer:
  for (int i = fromIndex; i <= source.length - pattern.length; i++) {
    for (int j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

List<String> extractPdfTextTokens(Uint8List bytes) {
  List<String> tokens = [];
  final streamHeader = 'stream'.codeUnits;
  final endStreamHeader = 'endstream'.codeUnits;

  int idx = 0;
  while (idx < bytes.length) {
    final start = _indexOf(bytes, streamHeader, idx);
    if (start == -1) break;
    var contentStart = start + streamHeader.length;
    while (contentStart < bytes.length &&
        (bytes[contentStart] == 10 || bytes[contentStart] == 13)) {
      contentStart++;
    }
    final end = _indexOf(bytes, endStreamHeader, contentStart);
    if (end == -1) break;
    var contentEnd = end;
    while (contentEnd > contentStart &&
        (bytes[contentEnd - 1] == 10 || bytes[contentEnd - 1] == 13)) {
      contentEnd--;
    }

    try {
      final slice = bytes.sublist(contentStart, contentEnd);
      final decompressed = zlib.decode(slice);
      final decompressedStr = String.fromCharCodes(decompressed);
      final matches = RegExp(r'\((.*?)\)').allMatches(decompressedStr);
      for (var m in matches) {
        final val = m.group(1);
        if (val != null && val.isNotEmpty) {
          tokens.add(val);
        }
      }
    } catch (_) {}

    idx = end + endStreamHeader.length;
  }
  return tokens;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Daily Summary PDF Generator Tests', () {
    test('generateDailySummaryPdf generates valid Summary mode PDF with ASCII hyphens', () async {
      final entries = [
        DailyMovementEntry(
          itemName: 'MS Pipe',
          category: 'MS Pipe',
          size: '1" (1.2mm)',
          openingQty: 10.0,
          inQty: 27.240,
          outQty: 56.170,
          closingQty: 0.0,
        ),
        DailyMovementEntry(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x3',
          openingQty: 5.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 5.0,
        ),
      ];

      final pdfBytes = await PdfReportService.generateDailySummaryPdf(
        date: DateTime(2026, 9, 2),
        entries: entries,
        selectedMode: 'Summary',
        flowMode: 'Summary',
        location: 'YARD',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, true);

      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, '%PDF');

      final tokens = extractPdfTextTokens(pdfBytes);
      final combined = tokens.join(' ');

      expect(combined.contains('\u2014'), isFalse,
          reason: 'PDF should not contain Unicode em-dash U+2014');
      expect(combined.contains('\u2013'), isFalse,
          reason: 'PDF should not contain Unicode en-dash U+2013');
      expect(combined.contains('DAILY STOCK MOVEMENT SUMMARY'), isTrue);
      expect(combined.contains('MS PIPE'), isTrue);
      expect(combined.contains('MS ANGLE'), isTrue);
    });

    test('generateDailySummaryPdf in Detailed mode generates 5-column compact PDF with zero-movement category handling', () async {
      final entries = [
        // Category 1: MS Pipe with activity
        DailyMovementEntry(
          itemName: 'MS Pipe',
          category: 'MS Pipe',
          size: '1" (1.2mm)',
          openingQty: 10.0,
          inQty: 27.240,
          outQty: 56.170,
          closingQty: 0.0,
        ),
        // Category 1 inactive size (should be filtered out in multi-category detailed PDF)
        DailyMovementEntry(
          itemName: 'MS Pipe',
          category: 'MS Pipe',
          size: '2" (2.0mm)',
          openingQty: 15.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 15.0,
        ),
        // Category 2: MS Angle with zero movements today (should generate compact 1-line summary)
        DailyMovementEntry(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x3',
          openingQty: 5.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 5.0,
        ),
      ];

      final pdfBytes = await PdfReportService.generateDailySummaryPdf(
        date: DateTime(2026, 9, 2),
        entries: entries,
        selectedMode: 'Detailed',
        flowMode: 'Detailed',
        location: 'ALL',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, true);

      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, '%PDF');

      final tokens = extractPdfTextTokens(pdfBytes);
      final combined = tokens.join(' ');

      expect(combined.contains('\u2014'), isFalse);
      expect(combined.contains('\u2013'), isFalse);
      // Contains compact no-transaction summary text
      expect(combined.contains('MS ANGLE - No Transactions Today'), isTrue);
      // Contains overall total movement text
      expect(combined.contains('OVERALL TOTAL MOVEMENT'), isTrue);
      // Inactive size in multi-category should NOT be rendered in table
      expect(combined.contains('2" (2.0mm)'), isFalse);
      // Active size should be rendered
      expect(combined.contains('+27.240'), isTrue);
      expect(combined.contains('-56.170'), isTrue);
      expect(combined.contains('-28.930'), isTrue);
    });

    test('generateDailySummaryPdf with activeOnly: false exports all registered sizes across categories', () async {
      final entries = [
        DailyMovementEntry(
          itemName: 'MS Pipe',
          category: 'MS Pipe',
          size: '1" (1.2mm)',
          openingQty: 10.0,
          inQty: 27.240,
          outQty: 56.170,
          closingQty: 0.0,
        ),
        DailyMovementEntry(
          itemName: 'MS Pipe',
          category: 'MS Pipe',
          size: '2" (2.0mm)',
          openingQty: 15.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 15.0,
        ),
        DailyMovementEntry(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x3',
          openingQty: 5.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 5.0,
        ),
      ];

      final pdfBytes = await PdfReportService.generateDailySummaryPdf(
        date: DateTime(2026, 9, 2),
        entries: entries,
        selectedMode: 'Detailed',
        flowMode: 'Detailed',
        location: 'ALL',
        activeOnly: false,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, true);

      final tokens = extractPdfTextTokens(pdfBytes);
      final combined = tokens.join(' ');

      // In All Sizes mode, the inactive sizes are preserved in the table
      expect(combined.contains('2"'), isTrue);
      expect(combined.contains('25x3'), isTrue);
      expect(combined.contains('+27.240'), isTrue);
      expect(combined.contains('-56.170'), isTrue);
      expect(combined.contains('OVERALL TOTAL MOVEMENT'), isTrue);
    });

    test('generateDailySummaryPdf in Detailed mode for single category preserves registered sizes', () async {
      final singleCatEntries = [
        DailyMovementEntry(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x3',
          openingQty: 5.0,
          inQty: 0.0,
          outQty: 0.0,
          closingQty: 5.0,
        ),
        DailyMovementEntry(
          itemName: 'MS Angle',
          category: 'MS Angle',
          size: '25x5',
          openingQty: 10.0,
          inQty: 1.5,
          outQty: 0.5,
          closingQty: 11.0,
        ),
      ];

      final pdfBytes = await PdfReportService.generateDailySummaryPdf(
        date: DateTime(2026, 9, 2),
        entries: singleCatEntries,
        selectedMode: 'Detailed',
        flowMode: 'Detailed',
        location: 'YARD',
        activeOnly: false,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, true);

      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, '%PDF');

      final tokens = extractPdfTextTokens(pdfBytes);
      final combined = tokens.join(' ');

      expect(combined.contains('\u2014'), isFalse);
      expect(combined.contains('\u2013'), isFalse);
      // Single category includes the zero-movement size
      expect(combined.contains('25x3'), isTrue);
      expect(combined.contains('25x5'), isTrue);
      expect(combined.contains('CATEGORY TOTAL'), isTrue);
      expect(combined.contains('+1.500'), isTrue);
      expect(combined.contains('-0.500'), isTrue);
      expect(combined.contains('+1.000'), isTrue);
    });
  });
}
