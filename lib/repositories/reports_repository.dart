import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/stock_models.dart';
import '../services/data_repository.dart';

class ReportsRepository {
  static final ReportsRepository instance = ReportsRepository._internal();
  factory ReportsRepository() => instance;
  ReportsRepository._internal();

  /// Query master view 'vw_daily_transactions' matching 'transaction_date' ('yyyy-MM-dd')
  Future<List<Map<String, dynamic>>> fetchDailyTransactions({
    required DateTime startDate,
    required DateTime endDate,
    String? normalizedType, // 'INWARD', 'OUTWARD', or null for ALL
    String locationFilter = 'ALL',
  }) async {
    try {
      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      final String startStr = formatter.format(startDate);
      final String endStr = formatter.format(endDate);

      var query =
          SupabaseService.client.from('vw_daily_transactions').select('*');

      if (startStr == endStr) {
        query = query.eq('transaction_date', startStr);
      } else {
        query = query
            .gte('transaction_date', startStr)
            .lte('transaction_date', endStr);
      }

      if (normalizedType != null && normalizedType != 'ALL') {
        query = query.eq('normalized_type', normalizedType.toUpperCase());
      }

      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter.toUpperCase());
      }

      final response =
          await query.order('transaction_date', ascending: false).limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint(
          '[ReportsRepository] Error querying vw_daily_transactions: $e');
      return [];
    }
  }

  /// Today's Summary helper method — queries view v_todays_summary
  Future<List<Map<String, dynamic>>> fetchTodaysSummary({
    String? normalizedType,
    String locationFilter = 'ALL',
  }) async {
    try {
      var query = SupabaseService.client.from('v_todays_summary').select('*');
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter.toUpperCase());
      }
      if (normalizedType != null && normalizedType != 'ALL') {
        query = query.eq('txn_type', normalizedType.toUpperCase());
      }
      final response = await query.limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[ReportsRepository] Error querying v_todays_summary: $e');
      final now = DateTime.now();
      return fetchDailyTransactions(
        startDate: DateTime(now.year, now.month, now.day),
        endDate: DateTime(now.year, now.month, now.day),
        normalizedType: normalizedType,
        locationFilter: locationFilter,
      );
    }
  }

  /// Robustly parses row DateTime using raw transaction_date (yyyy-MM-dd) to prevent +5:30 timezone date spill.
  ///
  /// Works with both:
  ///  - `vw_daily_transactions` rows (have `transaction_date` column — uses it directly)
  ///  - Raw `transactions` table rows (no `transaction_date` — extracts date from the raw timestamp string)
  ///
  /// NEVER calls `.toLocal()` on the date portion. IST time is computed manually (+5:30).
  static DateTime parseRowDateTime(dynamic row) {
    if (row == null) return DateTime.now();

    final txDateStr = row['transaction_date']?.toString();
    final rawTs = row['effective_timestamp']?.toString() ??
        row['date_time']?.toString() ??
        row['created_at']?.toString();

    int year = DateTime.now().year;
    int month = DateTime.now().month;
    int day = DateTime.now().day;
    int hour = 0;
    int minute = 0;
    int second = 0;

    // --- Extract DATE ---
    if (txDateStr != null && txDateStr.length >= 10) {
      // View row: use the pre-computed transaction_date directly
      final parts = txDateStr.substring(0, 10).split('-');
      if (parts.length == 3) {
        year = int.tryParse(parts[0]) ?? year;
        month = int.tryParse(parts[1]) ?? month;
        day = int.tryParse(parts[2]) ?? day;
      }
    } else if (rawTs != null && rawTs.length >= 10) {
      // Raw table row: extract yyyy-MM-dd from the ISO string directly.
      // DO NOT call .toLocal() — that would shift late-night UTC dates forward by +5:30.
      final datePart = rawTs.substring(0, 10);
      final parts = datePart.split('-');
      if (parts.length == 3) {
        year = int.tryParse(parts[0]) ?? year;
        month = int.tryParse(parts[1]) ?? month;
        day = int.tryParse(parts[2]) ?? day;
      }
    }

    // --- Extract TIME (IST = UTC + 5:30) ---
    if (rawTs != null) {
      final parsedTs = DateTime.tryParse(rawTs);
      if (parsedTs != null) {
        // Convert UTC time to IST (+5:30) for display purposes.
        // The DATE is already fixed above; this only adjusts the time-of-day display.
        final utc = parsedTs.toUtc();
        final istMinutes = utc.hour * 60 + utc.minute + 330; // +5:30 = +330 min
        hour = (istMinutes ~/ 60) % 24;
        minute = istMinutes % 60;
        second = utc.second;
      }
    }

    return DateTime(year, month, day, hour, minute, second);
  }

  /// Transaction History query using 'vw_daily_transactions'
  Future<List<StockTransaction>> fetchTransactionHistory({
    required DateTime startDate,
    required DateTime endDate,
    String filterType = 'ALL',
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      final String startStr = formatter.format(startDate);
      final String endStr = formatter.format(endDate);

      var query =
          SupabaseService.client.from('vw_daily_transactions').select('*');

      if (startStr == endStr) {
        query = query.eq('transaction_date', startStr);
      } else {
        query = query
            .gte('transaction_date', startStr)
            .lte('transaction_date', endStr);
      }

      if (filterType != 'ALL') {
        query = query.eq('normalized_type', filterType.toUpperCase());
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List).map((row) {
        final dt = parseRowDateTime(row);

        return StockTransaction(
          txnId: row['txn_id']?.toString() ?? row['id']?.toString() ?? '',
          dateTime: dt,
          itemName: row['item_name']?.toString() ?? 'Unknown',
          size: row['size_label']?.toString() ??
              row['size']?.toString() ??
              'General',
          type: row['normalized_type']?.toString() ??
              row['txn_type']?.toString() ??
              row['type']?.toString() ??
              'IN',
          qtyMT: (row['qty_mt'] as num?)?.toDouble() ?? 0.0,
          location: row['location']?.toString() ?? 'YARD',
          toLocation: row['to_location']?.toString(),
          reason: row['reason']?.toString(),
          note: row['note']?.toString(),
          partyName:
              row['party_name']?.toString() ?? row['vendor_name']?.toString(),
          invoiceNo: row['invoice_no']?.toString(),
          lorryNo: row['lorry_no']?.toString(),
          user: row['user_name']?.toString() ?? row['user']?.toString(),
          isReversed: row['is_reversed'] == true,
        );
      }).toList();
    } catch (e) {
      debugPrint('[ReportsRepository] Error querying transaction history: $e');
      return DataRepository.fetchStockMovement(
          startDate: startDate, endDate: endDate);
    }
  }

  /// Stock Movement query using 'vw_daily_transactions'
  Future<List<Map<String, dynamic>>> fetchStockMovement({
    required DateTime startDate,
    required DateTime endDate,
    String locationFilter = 'ALL',
  }) async {
    return fetchDailyTransactions(
      startDate: startDate,
      endDate: endDate,
      locationFilter: locationFilter,
    );
  }

  /// Stock Ledger query using 'vw_daily_transactions'
  Future<List<Map<String, dynamic>>> fetchStockLedger({
    required DateTime startDate,
    required DateTime endDate,
    String? itemName,
    String? size,
    String locationFilter = 'ALL',
  }) async {
    try {
      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      final String startStr = formatter.format(startDate);
      final String endStr = formatter.format(endDate);

      var query = SupabaseService.client
          .from('vw_daily_transactions')
          .select('*')
          .gte('transaction_date', startStr)
          .lte('transaction_date', endStr);

      if (itemName != null && itemName.isNotEmpty) {
        query = query.eq('item_name', itemName);
      }
      if (size != null && size.isNotEmpty) {
        query = query.eq('size_label', size);
      }
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter.toUpperCase());
      }

      final response =
          await query.order('created_at', ascending: true).limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint(
          '[ReportsRepository] Error querying stock ledger from vw_daily_transactions: $e');
      return [];
    }
  }
}
