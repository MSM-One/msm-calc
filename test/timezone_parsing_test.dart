import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:msm_calc/models/stock_models.dart';
import 'package:msm_calc/repositories/reports_repository.dart';
import 'package:msm_calc/utils/formatters.dart';

void main() {
  group('Timezone Parsing & Formatting Tests', () {
    test('parses Supabase ISO string with +00 timezone and formats in IST', () {
      const rawTimestamp = '2026-09-01 15:57:00+00';
      final dt = parseSupabaseDateTime(rawTimestamp);

      // Verify that dt.isUtc is false (converted to local)
      expect(dt.isUtc, isFalse);

      // Verify explicit DateFormat outputs
      final formattedShort = DateFormat('dd/MM hh:mm a').format(dt);
      final formattedFull = DateFormat('dd/MM/yyyy hh:mm a').format(dt);

      // Verify formatTransactionTime and formatTransactionDateTime
      expect(formatTransactionTime(dt), formattedShort);
      expect(formatTransactionDateTime(dt), formattedFull);

      // In local IST (+05:30) environment:
      // UTC 15:57 + 5h30m = 21:27 (09:27 PM)
      // Note: If test environment is in IST (+05:30), verify exact IST values:
      if (dt.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        expect(dt.year, 2026);
        expect(dt.month, 9);
        expect(dt.day, 1);
        expect(dt.hour, 21);
        expect(dt.minute, 27);
        expect(formattedShort, '01/09 09:27 PM');
        expect(formattedFull, '01/09/2026 09:27 PM');
      }
    });

    test('parses ISO string with Z (Zulu) timestamp', () {
      const rawTimestamp = '2026-09-01T15:57:00Z';
      final dt = parseSupabaseDateTime(rawTimestamp);

      expect(dt.isUtc, isFalse);
      if (dt.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        expect(formatTransactionTime(dt), '01/09 09:27 PM');
        expect(formatTransactionDateTime(dt), '01/09/2026 09:27 PM');
      }
    });

    test('parses ISO string with milliseconds and Z', () {
      const rawTimestamp = '2026-09-01T15:57:00.000Z';
      final dt = parseSupabaseDateTime(rawTimestamp);

      expect(dt.isUtc, isFalse);
      if (dt.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        expect(formatTransactionTime(dt), '01/09 09:27 PM');
      }
    });

    test('StockTransaction.fromJson correctly parses Supabase created_at payload', () {
      final json = {
        'txn_id': 'TXN_TEST_1001',
        'created_at': '2026-09-01 15:57:00+00',
        'item_name': 'MS Pipe',
        'size': '70x35',
        'type': 'IN',
        'qty_mt': 15.250,
        'location': 'YARD',
        'user': 'Test User',
      };

      final tx = StockTransaction.fromJson(json);
      expect(tx.txnId, 'TXN_TEST_1001');
      expect(tx.itemName, 'MS Pipe');
      expect(tx.dateTime.isUtc, isFalse);

      if (tx.dateTime.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        expect(formatTransactionTime(tx.dateTime), '01/09 09:27 PM');
        expect(formatTransactionDateTime(tx.dateTime), '01/09/2026 09:27 PM');
      }
    });

    test('ReportsRepository.parseRowDateTime parses Supabase date_time and created_at', () {
      final row1 = {
        'date_time': '2026-09-01 15:57:00+00',
      };
      final dt1 = ReportsRepository.parseRowDateTime(row1);
      expect(dt1.isUtc, isFalse);

      final row2 = {
        'created_at': '2026-09-01 15:57:00+00',
      };
      final dt2 = ReportsRepository.parseRowDateTime(row2);
      expect(dt2.isUtc, isFalse);

      if (dt1.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        // date_time is treated as wall-clock IST time (15:57 = 03:57 PM)
        expect(formatTransactionTime(dt1), '01/09 03:57 PM');
        // created_at is treated as true UTC from PostgreSQL (15:57 UTC + 5:30 = 09:27 PM IST)
        expect(formatTransactionTime(dt2), '01/09 09:27 PM');
      }
    });

    test('handles legacy date formats gracefully without throwing exceptions', () {
      final dtLegacy1 = parseSupabaseDateTime('01/09/2026 21:27:00');
      expect(dtLegacy1.year, 2026);
      expect(dtLegacy1.month, 9);
      expect(dtLegacy1.day, 1);
      expect(dtLegacy1.hour, 21);
      expect(dtLegacy1.minute, 27);

      final dtLegacy2 = parseSupabaseDateTime('01/09/2026');
      expect(dtLegacy2.year, 2026);
      expect(dtLegacy2.month, 9);
      expect(dtLegacy2.day, 1);

      final dtLegacy3 = parseSupabaseDateTime(null);
      expect(dtLegacy3, isNotNull);
    });

    test('local calendar date matching correctly captures 01 Sep transactions in IST', () {
      final selectedDate = DateTime(2026, 9, 1);
      final rawUtcRow = {
        'txn_id': 'TXN_3001',
        'created_at': '2026-09-01 15:57:00+00',
        'item_name': 'MS Pipe',
        'qty_mt': 5.250,
      };

      final txDate = ReportsRepository.parseRowDateTime(rawUtcRow);
      final isSelectedDay = txDate.year == selectedDate.year &&
          txDate.month == selectedDate.month &&
          txDate.day == selectedDate.day;

      expect(isSelectedDay, isTrue);

      final startOfLocalDayUtc = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      ).toUtc().toIso8601String();

      final endOfLocalDayUtc = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        23,
        59,
        59,
        999,
      ).toUtc().toIso8601String();

      expect(startOfLocalDayUtc, isNotEmpty);
      expect(endOfLocalDayUtc, isNotEmpty);
    });

    test('parseIstDateTime prevents double offset on wall-clock IST timestamps tagged with +00', () {
      // Row 3062 from Supabase: date_time = "2026-09-02 18:58:09.804244+00"
      const rawTimestamp = '2026-09-02 18:58:09.804244+00';
      final dt = parseIstDateTime(rawTimestamp);

      // Must remain on Sep 02, NOT jump to Sep 03 12:28 AM!
      expect(dt.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 2);
      expect(dt.hour, 18);
      expect(dt.minute, 58);
      expect(dt.second, 9);

      final displayTime = DateFormat('dd/MM hh:mm a').format(dt);
      expect(displayTime, '02/09 06:58 PM');
    });

    test('StockTransaction.parseIstDateTime static method strips timezone suffix', () {
      const rawTimestamp = '2026-09-02 18:58:09.804244+00';
      final dt = StockTransaction.parseIstDateTime(rawTimestamp);

      expect(dt.day, 2);
      expect(dt.hour, 18);
      expect(dt.minute, 58);
      expect(DateFormat('dd/MM hh:mm a').format(dt), '02/09 06:58 PM');
    });

    test('parseTransactionTimestamp handles MH12DT0460 payload correctly (02/09 06:58 PM)', () {
      final row = {
        'id': 3062,
        'txn_id': '1788355909955_9',
        'lorry_no': 'MH12DT0460',
        'date': '2026-09-02 18:58:09.804244+00',
        'date_time': '2026-09-02 18:58:09.804244+00',
        'created_at': '2026-09-02 13:31:50.275308+00',
        'item_name': 'MS Angle',
        'size': '25x3',
        'type': 'OUT',
        'qty_mt': 1.030,
        'location': 'YARD',
      };

      final dt = parseTransactionTimestamp(row);
      final displayTime = DateFormat('dd/MM hh:mm a').format(dt);
      expect(displayTime, '02/09 06:58 PM');

      final tx = StockTransaction.fromJson(row);
      expect(DateFormat('dd/MM hh:mm a').format(tx.dateTime), '02/09 06:58 PM');
      expect(tx.lorryNo, 'MH12DT0460');
    });

    test('parseTransactionTimestamp falls back to created_at (UTC to local IST: 02/09 07:01 PM)', () {
      final rowWithoutDateTime = {
        'id': 3062,
        'txn_id': '1788355909955_9',
        'lorry_no': 'MH12DT0460',
        'created_at': '2026-09-02 13:31:50.275308+00',
        'item_name': 'MS Angle',
        'size': '25x3',
        'type': 'OUT',
        'qty_mt': 1.030,
        'location': 'YARD',
      };

      final dt = parseTransactionTimestamp(rowWithoutDateTime);
      // In IST (+05:30), 13:31:50 UTC is 19:01:50 (07:01 PM)
      if (dt.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
        expect(dt.day, 2);
        expect(dt.hour, 19);
        expect(dt.minute, 1);
        final displayTime = DateFormat('dd/MM hh:mm a').format(dt);
        expect(displayTime, '02/09 07:01 PM');
      }
    });
  });
}
