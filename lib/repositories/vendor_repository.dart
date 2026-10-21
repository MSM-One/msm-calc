import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import '../services/data_repository.dart';

class VendorRepository {
  static final VendorRepository instance = VendorRepository._internal();
  factory VendorRepository() => instance;
  VendorRepository._internal();

  /// Query master view 'v_vendor_summary' for vendor totals and averages
  Future<List<Map<String, dynamic>>> fetchVendorSummary() async {
    try {
      final response = await SupabaseService.client
          .from('v_vendor_summary')
          .select('*')
          .limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[VendorRepository] Error querying v_vendor_summary: $e');
      return DataRepository.fetchVendorSummaryView();
    }
  }

  /// Query recent vendor purchase ledger from 'vw_daily_transactions'
  Future<List<Map<String, dynamic>>> fetchVendorPurchaseLedger({
    String? vendorName,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 500,
  }) async {
    try {
      var query = SupabaseService.client
          .from('vw_daily_transactions')
          .select('*')
          .eq('normalized_type', 'INWARD');

      if (vendorName != null && vendorName.isNotEmpty) {
        query =
            query.or('party_name.eq.$vendorName,vendor_name.eq.$vendorName');
      }

      if (startDate != null) {
        final startStr = startDate.toIso8601String().split('T')[0];
        query = query.gte('transaction_date', startStr);
      }
      if (endDate != null) {
        final endStr = endDate.toIso8601String().split('T')[0];
        query = query.lte('transaction_date', endStr);
      }

      final response =
          await query.order('transaction_date', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint(
          '[VendorRepository] Error querying vendor purchase ledger from vw_daily_transactions: $e');
      return [];
    }
  }
}
