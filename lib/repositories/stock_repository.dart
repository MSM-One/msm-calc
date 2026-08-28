import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import '../services/data_repository.dart';

class StockRepository {
  static final StockRepository instance = StockRepository._internal();
  factory StockRepository() => instance;
  StockRepository._internal();

  /// Queries master view 'v_current_stock' directly from Supabase
  Future<List<Map<String, dynamic>>> fetchCurrentStockView(
      [String locationFilter = 'ALL']) async {
    try {
      var query = SupabaseService.client.from('v_current_stock').select('*');
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter);
      }
      final response = await query.limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[StockRepository] Error querying v_current_stock: $e');
      return DataRepository.fetchCurrentStock(locationFilter);
    }
  }

  /// Fetches low stock items using 'v_current_stock'
  Future<List<Map<String, dynamic>>> fetchLowStockView(
      [String locationFilter = 'ALL', double defaultMinStock = 5.0]) async {
    try {
      final rows = await fetchCurrentStockView(locationFilter);
      final List<Map<String, dynamic>> lowStock = [];

      for (final row in rows) {
        final double netStock = DataRepository.resolveItemName(row) != ''
            ? ((row['net_stock_mt'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final double minStock =
            (row['min_stock'] as num?)?.toDouble() ?? defaultMinStock;
        if (netStock <= minStock) {
          lowStock.add(row);
        }
      }
      return lowStock;
    } catch (e) {
      debugPrint('[StockRepository] Error fetching low stock: $e');
      return DataRepository.fetchLowStockItems(
          locationFilter: locationFilter, defaultMinStock: defaultMinStock);
    }
  }

  /// Fetches non-moving stock using 'v_current_stock'
  Future<List<Map<String, dynamic>>> fetchNonMovingStockView(
      [String locationFilter = 'ALL']) async {
    return DataRepository.fetchNonMovingStockView(locationFilter);
  }

  /// Inventory Dashboard summary derived from 'v_current_stock'
  Future<Map<String, dynamic>> fetchDashboardSummary(
      [String locationFilter = 'ALL']) async {
    final rows = await fetchCurrentStockView(locationFilter);
    double totalMT = 0.0;
    double yardMT = 0.0;
    double factoryMT = 0.0;

    for (final row in rows) {
      final double stock = (row['net_stock_mt'] as num?)?.toDouble() ?? 0.0;
      final String loc = (row['location']?.toString() ?? 'YARD').toUpperCase();
      totalMT += stock;
      if (loc == 'YARD') yardMT += stock;
      if (loc == 'FACTORY') factoryMT += stock;
    }

    return {
      'totalMT': totalMT,
      'yardMT': yardMT,
      'factoryMT': factoryMT,
      'rawRows': rows,
    };
  }
}
