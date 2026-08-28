import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static SupabaseClient? mockClient;
  static SupabaseClient get client => mockClient ?? Supabase.instance.client;
  SupabaseClient get _client => mockClient ?? Supabase.instance.client;

  // 1. Fetch Materials Categories (MS Angle, MS Pipe etc.)
  Future<List<Map<String, dynamic>>> fetchMaterials() async {
    final response = await _client.from('materials').select('id, item_name');
    return List<Map<String, dynamic>>.from(response);
  }

  // 2. Fetch Item Sizes linked with standard weights
  Future<List<Map<String, dynamic>>> fetchItemSizes() async {
    final response = await _client
        .from('item_sizes')
        .select('id, material_id, size_label, unit_weight_kg, size_difference, current_stock_in')
        .limit(10000);
    return List<Map<String, dynamic>>.from(response);
  }

  // 3. Real-time Stream for calculated absolute stock (Zero Mismatch)
  Stream<List<Map<String, dynamic>>> streamCurrentStock() {
    return _client.from('v_current_stock').stream(primaryKey: ['size_label']);
  }

  // 4. Insert a new Transaction Ledger Entry (IN/OUT Sauda)
  Future<void> insertTransaction(Map<String, dynamic> txnData) async {
    await _client.from('transactions').insert(txnData);
  }
}
