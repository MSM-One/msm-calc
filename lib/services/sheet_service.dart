import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'data_repository.dart';
import '../utils/formatters.dart';

class SyncResult {
  final bool success;
  final String errorMessage;
  final String? technicalDetails;
  final bool isConflict;
  final String? conflictBy;
  final Map<String, dynamic>? updatedUser;

  SyncResult({
    required this.success,
    this.errorMessage = "",
    this.technicalDetails,
    this.isConflict = false,
    this.conflictBy,
    this.updatedUser,
  });
}

class SavePermissionsResult {
  final bool success;
  final String errorMessage;
  final bool isConflict;
  final String? conflictBy;
  final Map<String, dynamic>? updatedUser;
  const SavePermissionsResult(
      {required this.success,
      this.errorMessage = '',
      this.isConflict = false,
      this.conflictBy,
      this.updatedUser});
}

class SheetService {
  static Future<bool> checkConnectivity() async => true;
  static Future<void> savePendingTransactions(List<dynamic> txs) async {}
  static Future<List<dynamic>> getPendingTransactions() async => [];
  static Future<void> setPendingTransactions(List<dynamic> txs) async {}
  static Future<void> clearPendingTransactions() async {}
  static Future<SyncResult> syncPendingTransactions() async =>
      SyncResult(success: true);

  static Future<List<dynamic>> fetchTransactions(
          {int limit = 20,
          int offset = 0,
          String? type,
          String? startDate,
          String? endDate,
          String? userEmail}) async =>
      [];
  static Future<SyncResult> postTransactions(
          List<dynamic> transactions) async =>
      SyncResult(success: true);

  static Future<List<dynamic>> fetchStock() async => [];

  static Future<List<dynamic>> fetchUsers() async => [];
  static Future<bool> resetDashboard() async => false;
  static Future<SyncResult> updateUserPermissions(
          Map<String, dynamic> data) async =>
      SyncResult(success: false, errorMessage: "Legacy Sheets Deprecated");
  static Future<SyncResult> deleteUser(String email) async =>
      SyncResult(success: false, errorMessage: "Legacy Sheets Deprecated");
  static Future<Map<String, dynamic>?> fetchUserByEmail(String email) async =>
      null;
  static Future<SavePermissionsResult> savePermissions(String email,
          List<String> permissions, String updatedBy, int version) async =>
      SavePermissionsResult(
          success: false, errorMessage: "Legacy Sheets Deprecated");

  static Future<List<dynamic>> getSaudas() async => [];
  static Future<SyncResult> postSauda(Map<String, dynamic> data) async =>
      SyncResult(success: false, errorMessage: "Legacy Sheets Deprecated");
  static Future<SyncResult> updateSaudaStatus(
          String saudaId, String status) async =>
      SyncResult(success: false, errorMessage: "Legacy Sheets Deprecated");

  // New stubs to satisfy the compiler
  static Future<Map<String, dynamic>> fetchData() async => {};
  static Future<SyncResult> post(dynamic payload) async =>
      SyncResult(success: true);
  static Future<Map<String, dynamic>> fetchERPStock() async => {};

  static const String _hiddenSaudaIdsKey = 'hidden_vendor_sauda_ids';

  static Future<Set<String>> _getHiddenSaudaIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_hiddenSaudaIdsKey) ?? [];
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveHiddenSaudaId(String saudaId, bool isHidden) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList(_hiddenSaudaIdsKey) ?? []).toSet();
      if (isHidden) {
        set.add(saudaId);
      } else {
        set.remove(saudaId);
      }
      await prefs.setStringList(_hiddenSaudaIdsKey, set.toList());
    } catch (e) {
      debugPrint("Error saving hidden sauda id: $e");
    }
  }

  static Future<List<dynamic>> fetchSaudaReports() async {
    try {
      final hiddenIds = await _getHiddenSaudaIds();
      final response = await SupabaseService.client
          .from('transactions')
          .select('*, materials(item_name), item_sizes(size_label)')
          .eq('txn_type', 'PURCHASE')
          .order('created_at', ascending: false);

      return response.map((row) {
        final double ord = (row['qty_mt'] as num?)?.toDouble() ?? 0.0;
        final double rec = (row['rec_qty'] as num?)?.toDouble() ?? 0.0;
        final String rowTxnId = row['txn_id']?.toString() ?? "";
        final String rowId = row['id']?.toString() ?? "";
        final String saudaId = rowTxnId.isNotEmpty ? rowTxnId : rowId;
        final bool dbHidden = row['is_hidden'] == true;
        final bool isHidden = dbHidden ||
            hiddenIds.contains(saudaId) ||
            (rowTxnId.isNotEmpty && hiddenIds.contains(rowTxnId)) ||
            (rowId.isNotEmpty && hiddenIds.contains(rowId));

        return {
          'id': rowId,
          'txn_id': rowTxnId,
          'srNo': saudaId,
          'party': row['party_name'] ?? "",
          'item': DataRepository.resolveItemName(row),
          'size': DataRepository.resolveSizeLabel(row),
          'ord': ord,
          'rec': rec,
          'bal': ord - rec,
          'rate': (row['rate'] as num?)?.toDouble() ?? 0.0,
          'region': row['region'] ?? "YARD",
          'location': row['location'] ?? "YARD",
          'is_hidden': isHidden,
          'date': row['date_time'] != null
              ? formatTransactionDate(parseSupabaseDateTime(row['date_time']))
              : "",
        };
      }).toList();
    } catch (e) {
      debugPrint("fetchSaudaReports error: $e");
      return [];
    }
  }

  static Future<SyncResult> toggleSaudaHiddenStatus({
    required String saudaId,
    required bool isHidden,
  }) async {
    try {
      if (saudaId.isEmpty) {
        return SyncResult(success: false, errorMessage: "Invalid ID");
      }

      // Save to local SharedPreferences for guaranteed persistence
      await _saveHiddenSaudaId(saudaId, isHidden);

      try {
        await SupabaseService.client
            .from('transactions')
            .update({'is_hidden': isHidden}).eq('txn_id', saudaId);
      } catch (e) {
        debugPrint("[SheetService] toggleHidden by txn_id error: $e");
      }

      if (int.tryParse(saudaId) != null) {
        try {
          await SupabaseService.client
              .from('transactions')
              .update({'is_hidden': isHidden}).eq('id', int.parse(saudaId));
        } catch (_) {}
      }

      // Update local cache
      final currentList =
          List<dynamic>.from(DataRepository.vendorSaudaListNotifier.value);
      for (var item in currentList) {
        if ((item['srNo']?.toString() == saudaId) ||
            (item['id']?.toString() == saudaId) ||
            (item['txn_id']?.toString() == saudaId)) {
          item['is_hidden'] = isHidden;
          break;
        }
      }
      DataRepository.vendorSaudaListNotifier.value = currentList;

      return SyncResult(success: true);
    } catch (e) {
      debugPrint("[SheetService] toggleSaudaHiddenStatus error: $e");
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  static Future<SyncResult> updatePurchaseEntry({
    required String saudaId,
    required double qtyMt,
    required double rate,
    String? vendorName,
    String? itemName,
    String? size,
    String? region,
    String? location,
    String? date,
  }) async {
    try {
      if (saudaId.isEmpty) {
        return SyncResult(success: false, errorMessage: "Invalid ID");
      }

      final Map<String, dynamic> updateData = {
        'qty_mt': qtyMt,
        'rate': rate,
      };
      if (vendorName != null && vendorName.trim().isNotEmpty) {
        updateData['party_name'] = vendorName.trim();
        updateData['vendor_name'] = vendorName.trim();
        await ensureVendorExists(vendorName.trim());
      }
      if (itemName != null && itemName.trim().isNotEmpty) {
        updateData['item_name'] = itemName.trim();
      }
      if (size != null) {
        updateData['size_label'] = size.trim();
      }
      if (region != null && region.trim().isNotEmpty) {
        updateData['region'] = region.trim();
      }
      if (location != null && location.trim().isNotEmpty) {
        updateData['location'] = location.trim();
      }
      if (date != null && date.trim().isNotEmpty) {
        try {
          final parsedDate = DateFormat('dd/MM/yyyy').parse(date.trim());
          updateData['date_time'] = parsedDate.toIso8601String();
        } catch (_) {}
      }

      try {
        await SupabaseService.client
            .from('transactions')
            .update(updateData)
            .eq('txn_id', saudaId);
      } catch (e) {
        debugPrint("[SheetService] updatePurchaseEntry by txn_id error: $e");
      }

      if (int.tryParse(saudaId) != null) {
        try {
          await SupabaseService.client
              .from('transactions')
              .update(updateData)
              .eq('id', int.parse(saudaId));
        } catch (_) {}
      }

      // Update local cache
      final currentList =
          List<dynamic>.from(DataRepository.vendorSaudaListNotifier.value);
      for (var item in currentList) {
        if ((item['srNo']?.toString() == saudaId) ||
            (item['id']?.toString() == saudaId) ||
            (item['txn_id']?.toString() == saudaId)) {
          if (vendorName != null && vendorName.trim().isNotEmpty) {
            item['party'] = vendorName.trim();
          }
          if (itemName != null && itemName.trim().isNotEmpty) {
            item['item'] = itemName.trim();
          }
          if (size != null) {
            item['size'] = size.trim();
          }
          if (region != null && region.trim().isNotEmpty) {
            item['region'] = region.trim();
          }
          if (location != null && location.trim().isNotEmpty) {
            item['location'] = location.trim();
          }
          if (date != null && date.trim().isNotEmpty) {
            item['date'] = date.trim();
          }
          item['ord'] = qtyMt;
          item['rate'] = rate;
          final double rec = (item['rec'] as num?)?.toDouble() ?? 0.0;
          item['bal'] = qtyMt - rec;
          break;
        }
      }
      DataRepository.vendorSaudaListNotifier.value = currentList;

      return SyncResult(success: true);
    } catch (e) {
      debugPrint("[SheetService] updatePurchaseEntry error: $e");
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  static Future<SyncResult> manualSaudaReceive(
      {required String saudaId,
      double? mtReceived,
      double? enteredQty,
      String? location,
      String? userEmail}) async {
    try {
      final saudaRow = await SupabaseService.client
          .from('transactions')
          .select()
          .eq('txn_id', saudaId)
          .maybeSingle();

      if (saudaRow == null) {
        return SyncResult(
            success: false, errorMessage: "Purchase record not found");
      }

      final double currentRec =
          (saudaRow['rec_qty'] as num?)?.toDouble() ?? 0.0;
      final double qtyToReceive = enteredQty ?? mtReceived ?? 0.0;
      final double newRec = currentRec + qtyToReceive;

      await SupabaseService.client
          .from('transactions')
          .update({'rec_qty': newRec}).eq('txn_id', saudaId);

      return SyncResult(success: true);
    } catch (e) {
      debugPrint("manualSaudaReceive error: $e");
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  static Future<void> ensureVendorExists(String vendorName) async {
    final name = vendorName.trim();
    if (name.isEmpty) return;
    try {
      final existing = await SupabaseService.client
          .from('vendors')
          .select('id')
          .eq('name', name)
          .maybeSingle();

      if (existing == null) {
        await SupabaseService.client.from('vendors').insert({'name': name});
      }
    } catch (e) {
      try {
        await SupabaseService.client.from('parties').insert({
          'name': name,
          'type': 'VENDOR',
        });
      } catch (_) {
        debugPrint("[SheetService] ensureVendorExists info: $e");
      }
    }
  }

  static Future<SyncResult> submitSauda(Map<String, dynamic> sauda) async {
    try {
      final double orderQty = (sauda['orderQty'] as num?)?.toDouble() ?? 0.0;
      final double basicRate = (sauda['basicRate'] as num?)?.toDouble() ?? 0.0;
      final String vendor = sauda['vendor']?.toString() ?? "";
      final String item = sauda['item']?.toString() ?? "";
      final String size = sauda['size']?.toString() ?? "";
      final String specificSize = sauda['specificSize']?.toString() ?? "";
      final String remark = sauda['remark']?.toString() ?? "";
      final String region = sauda['region']?.toString() ?? "";
      final String location = sauda['location']?.toString() ?? "YARD";

      if (vendor.isNotEmpty) {
        await ensureVendorExists(vendor);
      }

      // 1. Resolve material_id
      int? materialId;
      final matRow = await SupabaseService.client
          .from('materials')
          .select('id')
          .eq('item_name', item)
          .maybeSingle();
      if (matRow != null) {
        materialId = matRow['id'] as int?;
      }

      if (materialId == null) {
        return SyncResult(
            success: false, errorMessage: "Invalid product category: $item");
      }

      // 2. Resolve size_id
      int? sizeId;
      final String actualSize = size.isNotEmpty ? size : specificSize;

      String normalize(String s) {
        String cleaned = s.trim();
        final parts = cleaned.split(' ');
        if (parts.length > 1) {
          final lastPart = parts.last;
          if (RegExp(r'^\d+(\.\d+)?(kg|mt)?$', caseSensitive: false)
              .hasMatch(lastPart)) {
            parts.removeLast();
            cleaned = parts.join(' ');
          }
        }
        return cleaned.toLowerCase().replaceAll(' ', '');
      }

      final normLookup = normalize(actualSize);
      final sizeResponse = await SupabaseService.client
          .from('item_sizes')
          .select('id, size_label')
          .eq('material_id', materialId);

      for (var row in sizeResponse) {
        final dbSize = row['size_label']?.toString() ?? '';
        if (normalize(dbSize) == normLookup) {
          sizeId = row['id'] as int?;
          break;
        }
      }

      if (sizeId == null) {
        for (var row in sizeResponse) {
          final dbSize = row['size_label']?.toString() ?? '';
          if (dbSize.toLowerCase().trim() == actualSize.toLowerCase().trim()) {
            sizeId = row['id'] as int?;
            break;
          }
        }
      }

      if (sizeId == null) {
        if (sizeResponse.isNotEmpty) {
          sizeId = sizeResponse.first['id'] as int?;
        }
      }

      if (sizeId == null && actualSize.isNotEmpty) {
        return SyncResult(
            success: false,
            errorMessage: "Could not find size mapping for size: $actualSize");
      }

      final timestampMs = DateTime.now().millisecondsSinceEpoch;
      final txnId = "S-$timestampMs";

      final txnData = {
        'txn_id': txnId,
        'txn_type': 'PURCHASE',
        'type': 'PURCHASE',
        'item_name': item,
        'size': actualSize,
        'qty_mt': orderQty,
        'rate': basicRate,
        'party_name': vendor,
        'location': location,
        'region': region,
        'note': remark,
        'date_time': DateTime.now().toIso8601String(),
        'is_reversed': false,
        'material_id': materialId,
        'size_id': sizeId,
      };

      await SupabaseService.client.from('transactions').insert(txnData);
      return SyncResult(success: true);
    } catch (e) {
      debugPrint("CRITICAL VENDOR SAVE ERROR: $e");
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  static Future<SyncResult> deletePurchaseEntry(String id) async {
    return DataRepository.deletePurchaseEntry(id);
  }

  static Future<SyncResult> requestAccess(String email) async =>
      SyncResult(success: true);
  static Future<List<dynamic>> fetchTransactionsCached(
          {bool forceRefresh = false,
          void Function(List<dynamic>)? onRefreshed}) async =>
      [];
  static Future<dynamic> fetchCurrentUser() async => null;
}
