import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import '../models/stock_models.dart';
import '../services/data_repository.dart';
import '../utils/formatters.dart';

class ReportsRepository {
  static final ReportsRepository instance = ReportsRepository._internal();
  factory ReportsRepository() => instance;
  ReportsRepository._internal();

  /// Query master view 'vw_daily_transactions' or 'transactions' matching local date range.
  /// Converts start and end of local day to UTC ISO-8601 strings for Supabase querying,
  /// and validates exact local calendar date matching on result rows.
  Future<List<Map<String, dynamic>>> fetchDailyTransactions({
    required DateTime startDate,
    required DateTime endDate,
    String? normalizedType, // 'INWARD', 'OUTWARD', or null for ALL
    String locationFilter = 'ALL',
  }) async {
    final startOfLocalDayUtc = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    ).toUtc().toIso8601String();

    final endOfLocalDayUtc = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    ).toUtc().toIso8601String();

    final startLocal =
        DateTime(startDate.year, startDate.month, startDate.day);
    final endLocal =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    try {
      var query =
          SupabaseService.client.from('vw_daily_transactions').select('*');

      query = query
          .gte('created_at', startOfLocalDayUtc)
          .lte('created_at', endOfLocalDayUtc);

      if (normalizedType != null &&
          normalizedType.isNotEmpty &&
          normalizedType != 'ALL') {
        query = query.eq('normalized_type', normalizedType.toUpperCase());
      }

      final response =
          await query.order('created_at', ascending: true).limit(10000);
      final list = List<Map<String, dynamic>>.from(response as List);

      final filtered = list.where((row) {
        final txDate = parseRowDateTime(row);
        final inRange =
            !txDate.isBefore(startLocal) && !txDate.isAfter(endLocal);
        if (!inRange) return false;

        if (locationFilter != 'ALL') {
          final loc = (row['location'] ?? '').toString().toUpperCase();
          final toLoc = (row['to_location'] ?? '').toString().toUpperCase();
          final filterLoc = locationFilter.toUpperCase();
          return loc == filterLoc || toLoc == filterLoc;
        }
        return true;
      }).toList();

      return filtered;
    } catch (e) {
      debugPrint(
          '[ReportsRepository] Error fetching daily transactions from view: $e');
      // Fallback directly to 'transactions' table with UTC range
      try {
        var fallbackQuery =
            SupabaseService.client.from('transactions').select('*');

        fallbackQuery = fallbackQuery
            .gte('created_at', startOfLocalDayUtc)
            .lte('created_at', endOfLocalDayUtc);

        if (normalizedType != null &&
            normalizedType.isNotEmpty &&
            normalizedType != 'ALL') {
          fallbackQuery =
              fallbackQuery.eq('txn_type', normalizedType.toUpperCase());
        }

        final res = await fallbackQuery
            .order('created_at', ascending: true)
            .limit(10000);
        final list = List<Map<String, dynamic>>.from(res as List);

        return list.where((row) {
          final txDate = parseRowDateTime(row);
          final inRange =
              !txDate.isBefore(startLocal) && !txDate.isAfter(endLocal);
          if (!inRange) return false;

          if (locationFilter != 'ALL') {
            final loc = (row['location'] ?? '').toString().toUpperCase();
            final toLoc = (row['to_location'] ?? '').toString().toUpperCase();
            final filterLoc = locationFilter.toUpperCase();
            return loc == filterLoc || toLoc == filterLoc;
          }
          return true;
        }).toList();
      } catch (fallbackErr) {
        debugPrint(
            '[ReportsRepository] Fallback query error: $fallbackErr');
        return [];
      }
    }
  }

  /// Convenience helper to fetch single day transactions with defaults
  Future<List<Map<String, dynamic>>> fetchSingleDayTransactions({
    DateTime? targetDate,
    String? normalizedType,
    String locationFilter = 'ALL',
  }) {
    final target = targetDate ?? DateTime.now();
    return fetchDailyTransactions(
      startDate: DateTime(target.year, target.month, target.day),
      endDate: DateTime(target.year, target.month, target.day),
      normalizedType: normalizedType,
      locationFilter: locationFilter,
    );
  }

  /// Today's Summary helper method — aggregates inward & outward transactions for the selected local date
  Future<List<Map<String, dynamic>>> fetchTodaysSummary({
    DateTime? selectedDate,
    String? normalizedType,
    String locationFilter = 'ALL',
  }) async {
    final target = selectedDate ?? DateTime.now();
    return fetchDailyTransactions(
      startDate: DateTime(target.year, target.month, target.day),
      endDate: DateTime(target.year, target.month, target.day),
      normalizedType: normalizedType,
      locationFilter: locationFilter,
    );
  }

  /// Robustly parses row DateTime converting Supabase UTC timestamps into local IST DateTime.
  /// Works with both:
  ///  - `vw_daily_transactions` rows (have `created_at`, `transaction_date` column)
  ///  - Raw `transactions` table rows (have `created_at`, `date_time`, etc.)
  static DateTime parseRowDateTime(dynamic row) {
    if (row == null) return DateTime.now();

    final rawTs = row['created_at'] ??
        row['date_time'] ??
        row['effective_timestamp'] ??
        row['transaction_date'] ??
        row['date'];

    return parseSupabaseDateTime(rawTs);
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
      final startOfLocalDayUtc = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).toUtc().toIso8601String();

      final endOfLocalDayUtc = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
        999,
      ).toUtc().toIso8601String();

      var query =
          SupabaseService.client.from('vw_daily_transactions').select('*');

      query = query
          .gte('created_at', startOfLocalDayUtc)
          .lte('created_at', endOfLocalDayUtc);

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
      final startOfLocalDayUtc = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).toUtc().toIso8601String();

      final endOfLocalDayUtc = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
        999,
      ).toUtc().toIso8601String();

      var query = SupabaseService.client
          .from('vw_daily_transactions')
          .select('*')
          .gte('created_at', startOfLocalDayUtc)
          .lte('created_at', endOfLocalDayUtc);

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

