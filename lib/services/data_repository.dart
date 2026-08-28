import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sheet_service.dart';
import 'supabase_service.dart';
import 'supabase_realtime_service.dart';
import '../repositories/reports_repository.dart';
import '../utils/error_handler.dart';
import '../models/permission_model.dart';
import '../models/stock_role.dart';
import '../models/stock_models.dart';
import '../models/user_model.dart';
import '../models/user_session_notifier.dart';
import '../models/report_models.dart';
import '../utils/sorting_utils.dart';
import '../utils/formatters.dart';

// ---------------------------------------------------------------------------
// TOP-LEVEL ISOLATE FUNCTION — must be outside class for compute() to work
// ---------------------------------------------------------------------------
/// Input: JSON-encoded list of StockTransaction maps.
/// Output: Map with pre-calculated notifier values (all plain types).
String _isolateNormalizeLocation(String? loc) {
  if (loc == null) return 'YARD';
  final trimmed = loc.trim().toUpperCase();
  if (trimmed.contains('YARD') ||
      trimmed.contains('WH') ||
      trimmed.contains('WAREHOUSE') ||
      trimmed.contains('YARD STOCK')) {
    return 'YARD';
  }
  if (trimmed.contains('FACTORY') ||
      trimmed.contains('PLANT') ||
      trimmed.contains('FACTORY STOCK')) {
    return 'FACTORY';
  }
  return trimmed;
}

Map<String, dynamic> _computeStockNotifiersIsolate(String jsonStr) {
  final List<dynamic> decoded = jsonDecode(jsonStr);
  final List<StockTransaction> txs =
      decoded.map((e) => StockTransaction.fromJson(e)).toList();

  double todayIn = 0;
  double todayOut = 0;
  double yardTotal = 0;
  double factoryTotal = 0;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final Map<String, Map<String, dynamic>> variantsMap = {};

  // Process ALL transactions — accumulate raw balance without mid-step clamping.
  // Transactions arrive newest-first from the backend, so iterate in reverse
  // to process chronologically (oldest-first).
  for (int i = txs.length - 1; i >= 0; i--) {
    final tx = txs[i];
    if (tx.isReversed) continue;

    final String txnType = tx.type.trim().toUpperCase();

    // Explicitly ignore PURCHASE transactions for warehouse stock
    if (txnType == 'PURCHASE') {
      continue;
    }

    // Compound key: Item Name + Size + Location
    final String loc = _isolateNormalizeLocation(tx.location);
    final String normalizedSize = formatSizeDisplay(tx.itemName, tx.size);
    final key = '${tx.itemName}|$normalizedSize|$loc';
    variantsMap.putIfAbsent(
        key,
        () => {
              'itemName': tx.itemName,
              'category': tx.itemName,
              'size': normalizedSize,
              'currentStockMT': 0.0,
              'location': loc,
            });

    final v = variantsMap[key]!;
    final double q = (v['currentStockMT'] as double);

    if (txnType == 'IN' ||
        txnType == 'INWARD' ||
        txnType == 'OPENING_STOCK' ||
        txnType == 'OPENING' ||
        txnType == 'RETURN' ||
        txnType == 'ADJUSTMENT') {
      v['currentStockMT'] = q + tx.qtyMT;
      if (!tx.dateTime.isBefore(today) &&
          (txnType == 'IN' || txnType == 'INWARD')) {
        todayIn += tx.qtyMT;
      }
    } else if (txnType == 'OUT' ||
        txnType == 'OUTWARD' ||
        txnType == 'SALE' ||
        txnType == 'RESERVE') {
      v['currentStockMT'] = q - tx.qtyMT;
      if (!tx.dateTime.isBefore(today) &&
          (txnType == 'OUT' || txnType == 'OUTWARD' || txnType == 'SALE')) {
        todayOut += tx.qtyMT;
      }
    } else if (txnType == 'TRANSFER') {
      v['currentStockMT'] = q - tx.qtyMT;
      if (tx.toLocation != null) {
        final String toLoc = _isolateNormalizeLocation(tx.toLocation);
        final toKey = '${tx.itemName}|$normalizedSize|$toLoc';
        variantsMap.putIfAbsent(
            toKey,
            () => {
                  'itemName': tx.itemName,
                  'category': tx.itemName,
                  'size': normalizedSize,
                  'currentStockMT': 0.0,
                  'location': toLoc,
                });
        variantsMap[toKey]!['currentStockMT'] =
            (variantsMap[toKey]!['currentStockMT'] as double) + tx.qtyMT;
      }
    }
  }

  // Final-stage clamp: only clamp at output, never mid-accumulation
  for (final v in variantsMap.values) {
    final double stock = v['currentStockMT'] as double;
    if (stock < 0.0) v['currentStockMT'] = 0.0;
  }

  final nonZero = variantsMap.values
      .where((v) => (v['currentStockMT'] as double) != 0.0)
      .toList();

  double totalMT =
      nonZero.fold(0.0, (s, v) => s + (v['currentStockMT'] as double));

  for (final v in nonZero) {
    final loc = (v['location'] as String).toUpperCase();
    if (loc == 'YARD') yardTotal += v['currentStockMT'] as double;
    if (loc == 'FACTORY') factoryTotal += v['currentStockMT'] as double;
  }

  return {
    'totalMT': totalMT,
    'yardTotal': yardTotal,
    'factoryTotal': factoryTotal,
    'todayIn': todayIn,
    'todayOut': todayOut,
    'inventoryList': nonZero,
  };
}

class DataRepository {
  static const String _boxName = 'msm_cache_box';
  static late Box _box;

  static final DataRepository instance = DataRepository._internal();
  DataRepository._internal();
  factory DataRepository() => instance;

  // Global Sync Indicator
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  // Global Notifier for ERP Stock Data (powers the UI)
  static final ValueNotifier<Map<String, dynamic>> erpStockNotifier =
      ValueNotifier<Map<String, dynamic>>({
    "summary": {"yardStock": 0, "factoryStock": 0, "grandTotal": 0},
    "locations": []
  });

  // Global Notifier for Settings/Sheet Data (powers calculator & forms)
  static final ValueNotifier<Map<String, dynamic>> sheetDataNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'meta': {'gst_rate': '0.18', 'loading_charge': '255'},
    'items': []
  });

  // Live Master Item Sizes Notifier (Single source of truth for all sizes across the app)
  static final ValueNotifier<List<Map<String, dynamic>>> itemSizesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  List<Map<String, dynamic>> get itemSizes => itemSizesNotifier.value;

  // Global Notifier for Transactions (powers the UI)
  static final ValueNotifier<List<StockTransaction>> transactionsNotifier =
      ValueNotifier<List<StockTransaction>>([]);

  // Unified Transactions Notifier (Single Source of Truth)
  static final ValueNotifier<List<StockTransaction>> allTransactionsNotifier =
      ValueNotifier<List<StockTransaction>>([]);

  // Dashboard Specific Notifiers for Manual Wipe/Reset
  static final ValueNotifier<double> totalStockNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<double> yardStockNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<double> factoryStockNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<double> todayInNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<double> todayOutNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<List<ItemVariant>> inventoryListNotifier =
      ValueNotifier<List<ItemVariant>>([]);

  // Non-Moving Stock (Insight for Dashboard)
  static final ValueNotifier<List<DeadStockEntry>> nonMovingStockNotifier =
      ValueNotifier<List<DeadStockEntry>>([]);

  // Vendor Purchase Report Notifiers
  static final ValueNotifier<double> vendorTotalQtyNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<double> vendorAvgRateNotifier =
      ValueNotifier<double>(0.0);
  static final ValueNotifier<List<dynamic>> vendorSaudaListNotifier =
      ValueNotifier<List<dynamic>>([]);

  // Global Notifier for the Currently Logged-in User
  static final ValueNotifier<UserModel?> currentUserNotifier =
      ValueNotifier<UserModel?>(null);

  /// Ensures every known permission slug exists in the user's permissions map.
  /// Missing slugs are filled from staffDefaults so AccessGuard never silently
  /// denies access due to an absent key for a legacy user.
  static UserModel _backfillPermissions(UserModel user) {
    if (user.isAdmin) return user; // Admins bypass all permission checks anyway
    final defaults = PermissionRegistry.staffDefaults;
    final filled = Map<String, bool>.from(user.permissions);
    for (final entry in defaults.entries) {
      filled.putIfAbsent(entry.key, () => entry.value.isAllowed);
    }
    if (filled.length == user.permissions.length)
      return user; // Nothing changed
    return user.copyWith(permissions: filled);
  }

  // In-memory master lookup caches
  static final Map<int, String> materialIdToNameMap = {};
  static final Map<int, String> sizeIdToLabelMap = {};

  static int? getMaterialIdByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final cleanName = name.trim().toLowerCase();
    for (final entry in materialIdToNameMap.entries) {
      if (entry.value.trim().toLowerCase() == cleanName) {
        return entry.key;
      }
    }
    return null;
  }

  static String? getMaterialNameById(int? id) {
    if (id == null) return null;
    return materialIdToNameMap[id];
  }

  /// Ensures master lookup data (materials & item_sizes) is cached in memory.
  static Future<void> ensureMasterLookupData() async {
    if (materialIdToNameMap.isNotEmpty && sizeIdToLabelMap.isNotEmpty) return;
    try {
      final matRows = await SupabaseService.client
          .from('materials')
          .select('id, item_name')
          .order('id');
      for (final row in matRows) {
        final id = row['id'] as int?;
        if (id != null) {
          materialIdToNameMap[id] = row['item_name']?.toString() ?? '';
        }
      }
      SortingUtils.dynamicMasterOrderProvider = () =>
          materialIdToNameMap.values.where((v) => v.trim().isNotEmpty).toList();

      final sizeRows = await SupabaseService.client
          .from('item_sizes')
          .select(
              'id, material_id, size_label, unit_weight_kg, size_difference, current_stock_in')
          .order('id')
          .limit(10000);
      final List<Map<String, dynamic>> allSizesList = [];
      for (final row in sizeRows) {
        final id = row['id'] as int?;
        final matId = row['material_id'] as int?;
        final label = row['size_label']?.toString() ?? '';
        final weight =
            double.tryParse(row['unit_weight_kg']?.toString() ?? '') ?? 0.0;
        updateGlobalSizeWeightCache(label, weight);
        final sd =
            double.tryParse(row['size_difference']?.toString() ?? '0') ?? 0.0;
        final stockIn =
            double.tryParse(row['current_stock_in']?.toString() ?? '0') ?? 0.0;
        final matName =
            matId != null ? (materialIdToNameMap[matId] ?? '') : '';
        if (id != null) {
          sizeIdToLabelMap[id] = label;
        }
        allSizesList.add({
          'id': id,
          'material_id': matId,
          'materialId': matId,
          'material_name': matName,
          'materialName': matName,
          'size_label': label,
          'sizeLabel': label,
          'label': label,
          'unit_weight_kg': weight,
          'weight': weight,
          'size_difference': sd,
          'sd': sd,
          'current_stock_in': stockIn,
          'stock': stockIn,
        });
      }
      itemSizesNotifier.value = allSizesList;
    } catch (e) {
      debugPrint('[DataRepository] Error loading master lookup maps: $e');
    }
  }

  /// Returns the canonical category/material name, case-insensitively matched against materials.
  static String canonicalizeCategory(String? rawCategory) {
    if (rawCategory == null ||
        rawCategory.trim().isEmpty ||
        rawCategory.trim().toUpperCase() == 'UNKNOWN') {
      return 'General';
    }
    final trimmed = rawCategory.trim();
    for (final matName in materialIdToNameMap.values) {
      if (matName.trim().toUpperCase() == trimmed.toUpperCase()) {
        return matName.trim();
      }
    }
    return trimmed;
  }

  /// Returns all dynamic categories currently available in Master Materials, Sheet Data, and Transactions.
  static List<String> getDynamicCategories() {
    final Set<String> categories = {};
    for (final matName in materialIdToNameMap.values) {
      if (matName.trim().isNotEmpty) {
        categories.add(matName.trim());
      }
    }
    final items = sheetDataNotifier.value['items'] as List? ?? [];
    for (final item in items) {
      if (item is Map) {
        final n = item['name']?.toString().trim();
        if (n != null && n.isNotEmpty) {
          categories.add(canonicalizeCategory(n));
        }
      }
    }
    for (final v in inventoryListNotifier.value) {
      if (v.category.trim().isNotEmpty && v.category != 'General') {
        categories.add(canonicalizeCategory(v.category));
      }
    }
    for (final tx in allTransactionsNotifier.value) {
      if (tx.itemName.trim().isNotEmpty && tx.itemName != 'Unknown') {
        categories.add(canonicalizeCategory(tx.itemName));
      }
    }
    final List<String> result = categories.toList();
    result.sort(SortingUtils.compareCategories);
    return result;
  }

  static String resolveItemName(dynamic row) {
    if (row == null) return 'Unknown';
    if (row is Map) {
      final direct = row['item_name']?.toString();
      if (direct != null &&
          direct.isNotEmpty &&
          direct != 'null' &&
          direct != 'Unknown') {
        return direct;
      }
      if (row['materials'] is Map && row['materials']['item_name'] != null) {
        final mName = row['materials']['item_name'].toString();
        if (mName.isNotEmpty && mName != 'null') return mName;
      }
      final matId = int.tryParse(row['material_id']?.toString() ?? '');
      if (matId != null && materialIdToNameMap.containsKey(matId)) {
        return materialIdToNameMap[matId]!;
      }
    }
    return 'Unknown';
  }

  static String resolveSizeLabel(dynamic row) {
    if (row == null) return 'General';
    if (row is Map) {
      final direct = row['size']?.toString() ?? row['size_label']?.toString();
      if (direct != null &&
          direct.isNotEmpty &&
          direct != 'null' &&
          direct != 'Unknown') {
        return direct;
      }
      if (row['item_sizes'] is Map && row['item_sizes']['size_label'] != null) {
        final sLabel = row['item_sizes']['size_label'].toString();
        if (sLabel.isNotEmpty && sLabel != 'null') return sLabel;
      }
      final sizeId = int.tryParse(row['size_id']?.toString() ?? '');
      if (sizeId != null && sizeIdToLabelMap.containsKey(sizeId)) {
        return sizeIdToLabelMap[sizeId]!;
      }
    }
    return 'General';
  }

  /// Must be called after Hive.initFlutter();
  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    await ensureMasterLookupData();

    // Load initial cached data securely into memory
    final cachedERP = _box.get('erp_stock', defaultValue: null);
    if (cachedERP != null) {
      try {
        erpStockNotifier.value = jsonDecode(cachedERP);
      } catch (e) {
        debugPrint('Cache parsing error: $e');
      }
    }

    final cachedSheet = _box.get('sheet_data', defaultValue: null);
    if (cachedSheet != null) {
      try {
        sheetDataNotifier.value = jsonDecode(cachedSheet);
      } catch (e) {
        debugPrint('Cache parsing error: $e');
      }
    }

    // ── Load user session from SharedPreferences ──────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final savedUserJson = prefs.getString('currentUser');
    if (savedUserJson != null) {
      try {
        final Map<String, dynamic> userMap = jsonDecode(savedUserJson);
        final rawUser = UserModel.fromJson(userMap);
        final newUser = _backfillPermissions(rawUser);
        currentUserNotifier.value = newUser;

        // ── Populate legacy UserSession for backward compatibility
        UserSession.userEmail = newUser.email;
        UserSession.currentRole =
            newUser.isAdmin ? StockRole.ADMIN : StockRole.VIEWER;
        UserSession.roleId = newUser.isAdmin ? 'admin' : 'staff';
        UserSession.applyPermissions(newUser.permissions
            .map((k, v) => MapEntry(k, Permission(slug: k, isAllowed: v))));
      } catch (e) {
        debugPrint("[DataRepository] Error loading saved user: $e");
      }
    }

    // Load cached Total Stock for instant startup feedback
    final cachedTotal = prefs.getDouble('cached_total_stock');
    if (cachedTotal != null) {
      totalStockNotifier.value = cachedTotal;
      debugPrint("[DataRepository] Loaded cached total stock: $cachedTotal MT");
    }

    // Set up debounced real-time sync stream listener from SupabaseRealtimeService
    SupabaseRealtimeService.instance.syncStream.listen((event) {
      debugPrint(
          '[DataRepository] Realtime sync event received: ${event.target.name} (${event.eventType}). Refreshing stock data...');
      refreshAllStockData(forceRefresh: true);
    }, onError: (e) {
      debugPrint("[DataRepository] Error in realtime syncStream: $e");
    });

    // Realtime category and size listener for master size configs
    SupabaseService.client.from('item_sizes').stream(primaryKey: ['id']).listen(
        (_) => syncSheetData(null, force: true), onError: (e) {
      debugPrint("[DataRepository] Realtime item_sizes stream error: $e");
    });

    SupabaseService.client.from('materials').stream(primaryKey: ['id']).listen(
        (_) => syncSheetData(null, force: true), onError: (e) {
      debugPrint("[DataRepository] Realtime materials stream error: $e");
    });
  }

  static Future<void> refreshCurrentUser([String? emailOverride]) async {
    await syncCurrentUser(emailOverride);
  }

  static Future<void> syncCurrentUser([String? emailOverride]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEmail = emailOverride ?? prefs.getString('user_email');
      if (rawEmail == null) return;

      // Requirement 4: Normalize email for lookup
      final email = rawEmail.toLowerCase().trim();
      UserSession.userEmail = email;

      UserModel? newUser;

      if (email == 'j2833945@gmail.com') {
        newUser = UserModel(
          email: email,
          role: UserRole.admin,
          status: 'approved',
          permissions: {},
        );
      } else {
        final userMap = await SupabaseService.client
            .from('users')
            .select()
            .eq('email', email)
            .maybeSingle();

        if (userMap != null) {
          // Requirement 5: Normalize role and permissions
          final rawUser = UserModel.fromJson(userMap);
          newUser = _backfillPermissions(rawUser);
        }
      }

      if (newUser != null) {
        // Update legacy session state
        UserSession.currentRole =
            newUser.isAdmin ? StockRole.ADMIN : StockRole.VIEWER;
        UserSession.roleId = newUser.isAdmin ? 'admin' : 'staff';
        UserSession.applyPermissions(newUser.permissions
            .map((k, v) => MapEntry(k, Permission(slug: k, isAllowed: v))));

        // Update global notifier
        currentUserNotifier.value = newUser;

        // Requirement 6: Update LocalStorage ONLY after successful backend fetch
        await prefs.setString('currentUser', jsonEncode(newUser.toJson()));
        await prefs.setString('user_email', email);

        // Notify UI components
        UserSessionNotifier.refreshFromSession();

        // Requirement 8: Exact requested debug log format
        // [AUTH SYNC] platform userEmail role permissionsCount
        final platform = kIsWeb ? "DESKTOP" : "MOBILE";
        debugPrint(
            "[AUTH SYNC] $platform $email ${newUser.role.name} perms=${newUser.permissions.length}");
      } else {
        debugPrint("[AUTH SYNC] User not found on server: $email");
      }
    } catch (e) {
      debugPrint("Sync Current User Error: $e");
    }
  }

  static Future<void> syncERPStock(BuildContext? context,
      {bool force = false}) async {
    await refreshAllStockData(forceRefresh: force);
  }

  /// Drop-in replacement for legacy SheetService.fetchERPStock()
  static Future<Map<String, dynamic>> getERPStockAsync(BuildContext? context,
      {bool forceRefresh = false}) async {
    await refreshAllStockData(forceRefresh: forceRefresh);
    return erpStockNotifier.value;
  }

  static Future<void> syncSheetData(BuildContext? context,
      {bool force = false}) async {
    isSyncing.value = true;
    try {
      // ── 1. Fetch materials & sizes ─────────────────────────────────────
      final matResponse = await SupabaseService.client
          .from('materials')
          .select('id, item_name')
          .order('id');

      final sizeResponse = await SupabaseService.client
          .from('item_sizes')
          .select(
              'id, material_id, size_label, unit_weight_kg, size_difference, current_stock_in')
          .order('id')
          .limit(10000);

      final List<Map<String, dynamic>> itemsList = [];
      final List<Map<String, dynamic>> allSizesList = [];

      for (final row in matResponse) {
        final id = row['id'] as int?;
        if (id == null) continue;
        final name = row['item_name']?.toString() ?? '';
        materialIdToNameMap[id] = name;
      }

      final Map<int, List<Map<String, dynamic>>> sizesByMatId = {};
      for (final row in sizeResponse) {
        final matId = row['material_id'] as int?;
        if (matId == null) continue;
        final id = row['id'] as int?;
        final label = row['size_label']?.toString() ?? '';
        final weight =
            double.tryParse(row['unit_weight_kg']?.toString() ?? '') ?? 0.0;
        updateGlobalSizeWeightCache(label, weight);
        final sd =
            double.tryParse(row['size_difference']?.toString() ?? '0') ?? 0.0;
        final stockIn =
            double.tryParse(row['current_stock_in']?.toString() ?? '0') ?? 0.0;
        final matName = materialIdToNameMap[matId] ?? '';
        if (id != null) sizeIdToLabelMap[id] = label;

        final sizeMap = {
          'id': id,
          'material_id': matId,
          'materialId': matId,
          'material_name': matName,
          'materialName': matName,
          'size_label': label,
          'sizeLabel': label,
          'label': label,
          'unit_weight_kg': weight,
          'weight': weight,
          'size_difference': sd,
          'sd': sd,
          'current_stock_in': stockIn,
          'stock': stockIn,
        };

        allSizesList.add(sizeMap);
        sizesByMatId.putIfAbsent(matId, () => []);
        sizesByMatId[matId]!.add(sizeMap);
      }

      itemSizesNotifier.value = allSizesList;

      for (final row in matResponse) {
        final id = row['id'] as int?;
        if (id == null) continue;
        final name = row['item_name']?.toString() ?? '';
        final sizes = sizesByMatId[id] ?? [];
        itemsList.add({
          'name': name,
          'sizes': sizes,
        });
      }

      // ── 2. Fetch live pricing config from global_charges ────────────────
      Map<String, dynamic> meta = {
        'gst_rate': '0.18',
        'loading_charge': '255',
      };
      try {
        final chargesRow = await SupabaseService.client
            .from('global_charges')
            .select('gst_rate, lc_rate, nc_discount')
            .eq('id', 'singleton')
            .maybeSingle();
        if (chargesRow != null) {
          // DB stores percentage (e.g. 18.00); convert to fraction (0.18) for the calculator
          final double gstPct =
              (chargesRow['gst_rate'] as num?)?.toDouble() ?? 18.0;
          final double lcRate =
              (chargesRow['lc_rate'] as num?)?.toDouble() ?? 255.0;
          final double ncDiscount =
              (chargesRow['nc_discount'] as num?)?.toDouble() ?? 3000.0;
          meta = {
            'gst_rate': (gstPct / 100).toStringAsFixed(4), // '0.1800'
            'loading_charge': lcRate.toStringAsFixed(2), // '255.00'
            'gst_pct': gstPct.toStringAsFixed(2), // '18.00' (for display)
            'nc_discount': ncDiscount.toStringAsFixed(2), // '3000.00'
          };
          debugPrint(
              '[DataRepository] global_charges: GST=$gstPct% LC=₹$lcRate NC=₹$ncDiscount');
        } else {
          debugPrint(
              '[DataRepository] global_charges: singleton row missing — using defaults');
        }
      } catch (chargesErr) {
        // Table may not exist yet; silently fall back to hardcoded defaults
        debugPrint(
            '[DataRepository] global_charges fetch skipped: $chargesErr');
      }

      // ── 3. Assemble and persist ──────────────────────────────────────────
      final Map<String, dynamic> freshData = {
        'meta': meta,
        'items': itemsList,
      };

      if (itemsList.isNotEmpty) {
        await _box.put('sheet_data', jsonEncode(freshData));
        sheetDataNotifier.value = freshData;
        debugPrint(
            '[DataRepository] syncSheetData: loaded ${itemsList.length} product categories from Supabase');
      } else {
        debugPrint(
            '[DataRepository] syncSheetData: empty response from Supabase — using previous cache');
        final cachedSheet = _box.get('sheet_data', defaultValue: null);
        if (cachedSheet != null) {
          try {
            final cached = jsonDecode(cachedSheet) as Map<String, dynamic>;
            // Always overwrite meta with fresh live values, even when items come from cache
            cached['meta'] = meta;
            sheetDataNotifier.value = cached;
          } catch (_) {}
        }
      }
    } catch (e) {
      if (context != null) ErrorHandler.showError(context, e);
      debugPrint('[DataRepository] syncSheetData error: $e');
    } finally {
      isSyncing.value = false;
    }
  }

  /// Drop-in replacement for legacy SheetService.fetchData()
  static Future<Map<String, dynamic>> getSheetDataAsync(BuildContext? context,
      {bool forceRefresh = false}) async {
    await syncSheetData(context, force: forceRefresh);
    return sheetDataNotifier.value;
  }

  /// Admin-only: persist new GST %, Loading Charge, and NC Discount to Supabase,
  /// then immediately refresh the in-memory sheetDataNotifier.
  ///
  /// [gstPct]     — percentage value, e.g. 18.0 (NOT the fraction 0.18)
  /// [lcRate]     — rupees per MT, e.g. 255.0
  /// [ncDiscount] — NC cash-discount per MT, e.g. 3000.0 (optional, omit to keep existing)
  static Future<void> updateGlobalCharges({
    required double gstPct,
    required double lcRate,
    double? ncDiscount,
  }) async {
    final Map<String, dynamic> payload = {
      'id': 'singleton',
      'gst_rate': gstPct,
      'lc_rate': lcRate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (ncDiscount != null) payload['nc_discount'] = ncDiscount;
    await SupabaseService.client.from('global_charges').upsert(payload);
    debugPrint(
        '[DataRepository] global_charges updated: GST=$gstPct% LC=₹$lcRate NC=₹${ncDiscount ?? "(unchanged)"} ');
    // Refresh in-memory meta immediately so the calculator sees the new values
    await syncSheetData(null, force: true);
  }

  static void updateNotifiersFromErpStock() {
    final Map<String, dynamic> erp = erpStockNotifier.value;
    if (erp.isEmpty) return;

    final Map<String, dynamic> summary = erp['summary'] ?? {};
    totalStockNotifier.value =
        (summary['grandTotal'] as num?)?.toDouble() ?? 0.0;

    final Map<String, dynamic> locStocks = summary['locationStocks'] ?? {};
    yardStockNotifier.value = (locStocks['YARD'] as num?)?.toDouble() ?? 0.0;
    factoryStockNotifier.value =
        (locStocks['FACTORY'] as num?)?.toDouble() ?? 0.0;

    todayInNotifier.value = (summary['todayIn'] as num?)?.toDouble() ?? 0.0;
    todayOutNotifier.value = (summary['todayOut'] as num?)?.toDouble() ?? 0.0;

    List<ItemVariant> list = [];
    final List<dynamic> locations = erp['locations'] as List? ?? [];
    for (var loc in locations) {
      if (loc is Map) {
        final String locName = loc['location']?.toString() ?? '';
        final List<dynamic> items = loc['items'] as List? ?? [];
        for (var item in items) {
          if (item is Map) {
            final String itemName = item['itemName']?.toString() ?? '';
            final String category = item['category']?.toString() ?? itemName;
            final List<dynamic> variants = item['variants'] as List? ?? [];
            for (var v in variants) {
              if (v is Map) {
                list.add(ItemVariant(
                  itemName: itemName,
                  category: category,
                  size: v['size']?.toString() ?? '',
                  currentStockMT: (v['qtyMT'] as num?)?.toDouble() ?? 0.0,
                  location: locName,
                ));
              }
            }
          }
        }
      }
    }

    list.sort((a, b) {
      int catComp = SortingUtils.compareCategories(a.category, b.category);
      if (catComp != 0) return catComp;
      int itemComp = a.itemName.compareTo(b.itemName);
      if (itemComp != 0) return itemComp;
      int locComp = a.location.compareTo(b.location);
      if (locComp != 0) return locComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });

    inventoryListNotifier.value = list;
  }

  /// Fetches raw current stock records from Supabase view 'v_current_stock'.
  static Future<List<Map<String, dynamic>>> fetchCurrentStock(
      [String locationFilter = 'ALL']) async {
    try {
      var query = SupabaseService.client.from('v_current_stock').select('*');
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter);
      }
      final response = await query.limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching current stock: $e');
      return [];
    }
  }

  /// Fetches stock chart records for dealer sharing:
  /// Attempts 'v_dealer_stock_chart' first; falls back to 'v_current_stock' (net_stock_mt > 0)
  /// enriched with size_difference and unit_weight_kg from item_sizes table.
  static Future<List<Map<String, dynamic>>> fetchDealerStockChart(
      [String locationFilter = 'ALL']) async {
    try {
      await ensureMasterLookupData();

      // Try v_dealer_stock_chart view first
      try {
        var query = SupabaseService.client
            .from('v_dealer_stock_chart')
            .select('*')
            .gt('net_stock_mt', 0);
        if (locationFilter != 'ALL') {
          query = query.eq('location', locationFilter.toUpperCase());
        }
        final response = await query.limit(10000);
        if (response != null && (response as List).isNotEmpty) {
          return List<Map<String, dynamic>>.from(response);
        }
      } catch (_) {
        // Fall back to v_current_stock + item_sizes lookup
      }

      // Fetch v_current_stock records
      final stockRows = await fetchCurrentStock(locationFilter);

      // Fetch item_sizes for size_difference & unit_weight_kg mapping
      Map<String, Map<String, dynamic>> sizeMetaMap = {};
      try {
        final sizeRows = await SupabaseService.client
            .from('item_sizes')
            .select('size_label, size_difference, unit_weight_kg, material_id')
            .limit(10000);
        for (final sr in sizeRows) {
          final label = sr['size_label']?.toString() ?? '';
          if (label.isNotEmpty) {
            sizeMetaMap[label] = {
              'size_difference': (sr['size_difference'] as num?)?.toDouble() ??
                  double.tryParse(sr['size_difference']?.toString() ?? '0') ??
                  0.0,
              'unit_weight_kg': (sr['unit_weight_kg'] as num?)?.toDouble() ??
                  double.tryParse(sr['unit_weight_kg']?.toString() ?? '0') ??
                  0.0,
            };
          }
        }
      } catch (e) {
        debugPrint('[DataRepository] Error fetching item_sizes meta: $e');
      }

      final List<Map<String, dynamic>> result = [];
      for (final row in stockRows) {
        final double netStock = (row['net_stock_mt'] as num?)?.toDouble() ??
            double.tryParse(row['net_stock_mt']?.toString() ?? '0') ??
            0.0;

        if (netStock <= 0) continue;

        final itemName = resolveItemName(row);
        final sizeLabel = resolveSizeLabel(row);
        final category = canonicalizeCategory(itemName);
        final location = row['location']?.toString().toUpperCase() ?? 'YARD';

        final meta = sizeMetaMap[sizeLabel];
        final double sd = (meta?['size_difference'] as num?)?.toDouble() ??
            (row['size_difference'] as num?)?.toDouble() ??
            0.0;
        final double unitWeight = (meta?['unit_weight_kg'] as num?)?.toDouble() ??
            (row['unit_weight_kg'] as num?)?.toDouble() ??
            0.0;

        result.add({
          'category_name': category,
          'item_name': itemName,
          'size_label': sizeLabel,
          'size_difference': sd,
          'unit_weight_kg': unitWeight,
          'current_stock_mt': netStock,
          'net_stock_mt': netStock,
          'location': location,
        });
      }

      return result;
    } catch (e) {
      debugPrint('[DataRepository] Error fetching dealer stock chart: $e');
      return [];
    }
  }

  /// Fetches summary records for today's transactions from view 'v_todays_summary'.
  static Future<List<Map<String, dynamic>>> fetchTodaysSummaryView(
      [String locationFilter = 'ALL']) async {
    try {
      var query = SupabaseService.client.from('v_todays_summary').select('*');
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter);
      }
      final response = await query.limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching todays summary view: $e');
      return [];
    }
  }

  /// Fetches low stock items from view 'v_low_stock'.
  static Future<List<Map<String, dynamic>>> fetchLowStockView(
      [String locationFilter = 'ALL']) async {
    try {
      var query = SupabaseService.client.from('v_low_stock').select('*');
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter);
      }
      final response = await query.limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching low stock view: $e');
      return [];
    }
  }

  /// Fetches non-moving stock items from view 'v_non_moving_stock'.
  static Future<List<Map<String, dynamic>>> fetchNonMovingStockView(
      [String locationFilter = 'ALL']) async {
    try {
      var query = SupabaseService.client.from('v_non_moving_stock').select('*');
      if (locationFilter != 'ALL') {
        query = query.eq('location', locationFilter);
      }
      final response = await query.limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching non-moving stock view: $e');
      return [];
    }
  }

  /// Fetches vendor purchase summary from view 'v_vendor_summary'.
  static Future<List<Map<String, dynamic>>> fetchVendorSummaryView() async {
    try {
      final response = await SupabaseService.client
          .from('v_vendor_summary')
          .select('*')
          .limit(10000);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching vendor summary view: $e');
      return [];
    }
  }

  /// Calls RPC 'get_vendor_statement' for purchase details of a vendor.
  static Future<List<Map<String, dynamic>>> fetchVendorStatement({
    required String vendorId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final response =
          await SupabaseService.client.rpc('get_vendor_statement', params: {
        'p_vendor_id': vendorId,
        'p_start': (startDate ?? DateTime(1970)).toUtc().toIso8601String(),
        'p_end': (endDate ?? DateTime.now()).toUtc().toIso8601String(),
      });
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching vendor statement RPC: $e');
      return [];
    }
  }

  /// Calls RPC 'get_stock_movement_report' to calculate backend-computed stock movements.
  static Future<List<Map<String, dynamic>>> fetchStockMovementReport({
    required DateTime startDate,
    required DateTime endDate,
    String locationFilter = 'ALL',
  }) async {
    try {
      final response = await SupabaseService.client
          .rpc('get_stock_movement_report', params: {
        'start_date': startDate.toUtc().toIso8601String(),
        'end_date': endDate.toUtc().toIso8601String(),
        'loc_filter': locationFilter,
      });
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint(
          '[DataRepository] Error fetching stock movement report RPC: $e');
      return [];
    }
  }

  /// Calls RPC 'get_stock_ledger' for item transaction history with running balance.
  static Future<List<Map<String, dynamic>>> fetchStockLedgerRpc({
    required int materialId,
    int? sizeId,
  }) async {
    try {
      final params = <String, dynamic>{'p_material_id': materialId};
      if (sizeId != null) params['p_size_id'] = sizeId;
      final response =
          await SupabaseService.client.rpc('get_stock_ledger', params: params);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('[DataRepository] Error fetching stock ledger RPC: $e');
      return [];
    }
  }

  /// Uses backend RPC 'get_stock_movement_report' to compute opening balance,
  /// period inward, period outward, and closing stock per item size.
  static Future<Map<String, Map<String, dynamic>>> fetchStockLedgerDataFromRpc({
    required DateTime startDate,
    required DateTime endDate,
    String selectedLocation = 'ALL',
  }) async {
    final rows = await fetchStockMovementReport(
      startDate: startDate,
      endDate: endDate,
      locationFilter: selectedLocation,
    );

    final Map<String, Map<String, dynamic>> ledgerMap = {};
    for (final row in rows) {
      final itemName = row['item_name']?.toString() ?? '';
      final size = row['size_label']?.toString() ?? '';
      final key = '${itemName}_$size';
      final double op = _parseDouble(row['opening_stock_mt']);
      final double pIn = _parseDouble(row['period_in_mt']);
      final double pOut = _parseDouble(row['period_out_mt']);
      final double cl = _parseDouble(row['closing_stock_mt']);

      if (!ledgerMap.containsKey(key)) {
        ledgerMap[key] = {
          'itemName': itemName,
          'size': size,
          'opening': op,
          'opening_mt': op,
          'opening_balance': op,
          'inward': pIn,
          'outward': pOut,
          'closing': cl,
          'closing_mt': cl,
        };
      } else {
        final existing = ledgerMap[key]!;
        final double newOp = (existing['opening'] as double) + op;
        existing['opening'] = newOp;
        existing['opening_mt'] = newOp;
        existing['opening_balance'] = newOp;
        existing['inward'] = (existing['inward'] as double) + pIn;
        existing['outward'] = (existing['outward'] as double) + pOut;
        final double newCl = (existing['closing'] as double) + cl;
        existing['closing'] = newCl;
        existing['closing_mt'] = newCl;
      }
    }
    return ledgerMap;
  }

  /// Safely converts dynamic values into doubles for stock calculations.
  static double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  /// Fetches low stock items directly from Supabase view 'v_low_stock'.
  static Future<List<Map<String, dynamic>>> fetchLowStockItems({
    String locationFilter = 'ALL',
    double defaultMinStock = 5.0,
  }) async {
    try {
      final viewRows = await fetchLowStockView(locationFilter);
      if (viewRows.isNotEmpty) {
        return viewRows;
      }
      final rawList = await fetchCurrentStock(locationFilter);
      final Map<dynamic, Map<String, dynamic>> uniqueSizesMap = {};

      for (var item in rawList) {
        final loc = item['location']?.toString().toUpperCase() ?? 'YARD';
        if (locationFilter != 'ALL' && loc != locationFilter.toUpperCase()) {
          continue;
        }

        final sizeId = item['size_id'] ??
            item['size_label'] ??
            '${item['item_name'] ?? item['category']}|${item['size']}';

        final double closingMt = _parseDouble(item['closing_mt'] ??
            item['net_stock_mt'] ??
            item['qty_mt'] ??
            item['currentStockMT'] ??
            item['qty']);

        if (!uniqueSizesMap.containsKey(sizeId)) {
          final newItem = Map<String, dynamic>.from(item);
          newItem['closing_mt'] = closingMt;
          newItem['low_stock_qty'] = closingMt;
          newItem['net_stock_mt'] = closingMt;
          newItem['currentStockMT'] = closingMt;
          newItem['size_id'] = sizeId;
          uniqueSizesMap[sizeId] = newItem;
        } else {
          // Aggregate tonnage if multi-location entries exist
          final existingMt =
              _parseDouble(uniqueSizesMap[sizeId]!['closing_mt']);
          final newTotal = existingMt + closingMt;
          uniqueSizesMap[sizeId]!['closing_mt'] = newTotal;
          uniqueSizesMap[sizeId]!['low_stock_qty'] = newTotal;
          uniqueSizesMap[sizeId]!['net_stock_mt'] = newTotal;
          uniqueSizesMap[sizeId]!['currentStockMT'] = newTotal;
        }
      }

      final List<Map<String, dynamic>> result =
          uniqueSizesMap.values.where((item) {
        final double qty = _parseDouble(item['closing_mt']);
        final double minStock = _parseDouble(
            item['min_stock'] ?? item['minStock'] ?? defaultMinStock);
        return qty <= minStock;
      }).toList();

      result.sort((a, b) {
        final catA = (a['category'] ?? a['item_name'] ?? '').toString();
        final catB = (b['category'] ?? b['item_name'] ?? '').toString();
        int catComp = SortingUtils.compareCategories(catA, catB);
        if (catComp != 0) return catComp;
        final double qtyA = _parseDouble(a['closing_mt'] ??
            a['qty_mt'] ??
            a['stock'] ??
            a['low_stock_qty'] ??
            a['currentStockMT']);
        final double qtyB = _parseDouble(b['closing_mt'] ??
            b['qty_mt'] ??
            b['stock'] ??
            b['low_stock_qty'] ??
            b['currentStockMT']);
        int qtyComp = qtyB.compareTo(qtyA);
        if (qtyComp != 0) return qtyComp;
        final sizeA = (a['size_label'] ?? a['size'] ?? '').toString();
        final sizeB = (b['size_label'] ?? b['size'] ?? '').toString();
        return SortingUtils.compareSizes(sizeA, sizeB);
      });

      return result;
    } catch (e) {
      debugPrint('[DataRepository] Error fetching low stock items: $e');
      return [];
    }
  }

  /// Queries 'v_current_stock', groups by 'item_name' (or category),
  /// and aggregates 'net_stock_mt' directly across all size rows
  /// (without filtering out negative size balances).
  static Future<Map<String, double>> fetchLiveStockByCategories(
      [String locationFilter = 'ALL']) async {
    final rows = await fetchCurrentStock(locationFilter);
    final Map<String, double> categoryTotals = {};

    for (final row in rows) {
      final String itemName = row['item_name']?.toString() ??
          row['category']?.toString() ??
          'Other';
      final double netStock = (row['net_stock_mt'] as num?)?.toDouble() ??
          (row['qty_mt'] as num?)?.toDouble() ??
          0.0;
      categoryTotals[itemName] = (categoryTotals[itemName] ?? 0.0) + netStock;
    }

    return categoryTotals;
  }

  static Future<void> refreshAllStockData({bool forceRefresh = false}) async {
    try {
      isSyncing.value = true;
      await ensureMasterLookupData();

      // 1. Authoritative Current Stock from v_current_stock view with direct item_sizes fallback
      final stockRows = await fetchCurrentStock('ALL');
      List<ItemVariant> list = [];
      if (stockRows.isNotEmpty) {
        list = stockRows
            .map((row) {
              final itemName = resolveItemName(row);
              final sizeLabel = resolveSizeLabel(row);
              final location =
                  row['location']?.toString().toUpperCase() ?? 'YARD';
              final netStock = (row['net_stock_mt'] as num?)?.toDouble() ??
                  double.tryParse(row['net_stock_mt']?.toString() ?? '') ??
                  0.0;
              return ItemVariant(
                itemName: itemName,
                category: canonicalizeCategory(itemName),
                size: sizeLabel,
                currentStockMT: netStock,
                location: location,
              );
            })
            .where((v) => v.currentStockMT != 0)
            .toList();
      } else {
        // Fallback: Direct lookup from item_sizes table
        try {
          final sizeRows = await SupabaseService.client
              .from('item_sizes')
              .select('id, material_id, size_label, current_stock_in, materials(item_name)')
              .limit(10000);
          for (final row in sizeRows) {
            final itemName = resolveItemName(row);
            final sizeLabel = row['size_label']?.toString() ?? '';
            final stockIn = _parseDouble(row['current_stock_in']);
            if (stockIn != 0) {
              list.add(ItemVariant(
                itemName: itemName,
                category: canonicalizeCategory(itemName),
                size: sizeLabel,
                currentStockMT: stockIn,
                location: 'YARD',
              ));
            }
          }
        } catch (fallbackErr) {
          debugPrint('[DataRepository] Direct item_sizes fallback error: $fallbackErr');
        }
      }

      list.sort((a, b) {
        int catComp = SortingUtils.compareCategories(a.category, b.category);
        if (catComp != 0) return catComp;
        int itemComp = a.itemName.compareTo(b.itemName);
        if (itemComp != 0) return itemComp;
        int locComp = a.location.compareTo(b.location);
        if (locComp != 0) return locComp;
        return SortingUtils.compareSizes(a.size, b.size);
      });

      totalStockNotifier.value = list.fold(0.0, (s, v) => s + v.currentStockMT);
      yardStockNotifier.value = list
          .where((v) => v.location == 'YARD')
          .fold(0.0, (s, v) => s + v.currentStockMT);
      factoryStockNotifier.value = list
          .where((v) => v.location == 'FACTORY')
          .fold(0.0, (s, v) => s + v.currentStockMT);
      inventoryListNotifier.value = list;
      _updateErpStockNotifierFromInventoryList(list);

      // 2. Transactions list with joined names
      final response = await SupabaseService.client
          .from('transactions')
          .select('*')
          .order('created_at', ascending: false)
          .limit(10000);

      final List<StockTransaction> txns = response.where((row) {
        final txnType = row['txn_type']?.toString().toUpperCase() ?? '';
        final type = row['type']?.toString().toUpperCase() ?? '';
        final txnId = row['txn_id']?.toString() ?? '';
        return txnType != 'PURCHASE' &&
            type != 'PURCHASE' &&
            !txnId.startsWith('IN_V_');
      }).map((row) {
        final itemName = resolveItemName(row);
        return StockTransaction(
          txnId: row['txn_id']?.toString() ?? row['id'].toString(),
          dateTime: ReportsRepository.parseRowDateTime(row),
          itemName: itemName,
          size: resolveSizeLabel(row),
          type: row['txn_type']?.toString() ?? row['type']?.toString() ?? 'IN',
          qtyMT: (row['qty_mt'] as num?)?.toDouble() ?? 0.0,
          location: row['location']?.toString() ?? 'YARD',
          toLocation: row['to_location']?.toString(),
          reason: row['reason']?.toString(),
          note: row['note']?.toString(),
          invoiceNo: row['invoice_no']?.toString(),
          lorryNo: row['lorry_no']?.toString(),
          transportCo: row['transport_co']?.toString(),
          driverName: row['driver_name']?.toString(),
          driverPhone: row['driver_phone']?.toString(),
          partyName: row['party_name']?.toString(),
          contactNo: row['contact_no']?.toString(),
          batchId: row['batch_id']?.toString(),
          user: row['user']?.toString(),
          isReversed: row['is_reversed'] == true,
          category: canonicalizeCategory(itemName),
        );
      }).toList();

      allTransactionsNotifier.value = txns;
      transactionsNotifier.value = txns;
    } catch (e) {
      debugPrint("Error refreshing all stock data from Supabase: $e");
    } finally {
      isSyncing.value = false;
    }
  }

  static void _updateErpStockNotifierFromInventoryList(
      List<ItemVariant> inventoryList) {
    double yardTotal = 0;
    double factoryTotal = 0;

    // Group by location
    final Map<String, List<ItemVariant>> locGroups = {};
    for (var v in inventoryList) {
      final loc = v.location.toUpperCase();
      locGroups.putIfAbsent(loc, () => []);
      locGroups[loc]!.add(v);
      if (loc == 'YARD') yardTotal += v.currentStockMT;
      if (loc == 'FACTORY') factoryTotal += v.currentStockMT;
    }

    final List<Map<String, dynamic>> formattedLocations = [];
    locGroups.forEach((locName, variants) {
      // Group variants by itemName
      final Map<String, List<ItemVariant>> itemGroups = {};
      for (var v in variants) {
        itemGroups.putIfAbsent(v.itemName, () => []);
        itemGroups[v.itemName]!.add(v);
      }

      final List<Map<String, dynamic>> itemsList = [];
      itemGroups.forEach((itemName, itemVariants) {
        final double totalQty =
            itemVariants.fold(0.0, (sum, v) => sum + v.currentStockMT);
        final List<Map<String, dynamic>> formattedVariants =
            itemVariants.map((v) {
          return {
            'size': v.size,
            'qtyMT': v.currentStockMT,
            'stockStatus': v.currentStockMT <= 0
                ? 'Out of Stock'
                : (v.currentStockMT <= v.minStock ? 'Low Stock' : 'In Stock'),
          };
        }).toList();

        itemsList.add({
          'itemName': itemName,
          'category': itemVariants.first.category,
          'totalQty': totalQty,
          'variants': formattedVariants,
        });
      });

      formattedLocations.add({
        'location': locName,
        'totalStock': locName == 'YARD' ? yardTotal : factoryTotal,
        'items': itemsList,
      });
    });

    // Ensure both YARD and FACTORY exist in list
    if (!formattedLocations.any((l) => l['location'] == 'YARD')) {
      formattedLocations
          .add({'location': 'YARD', 'totalStock': 0.0, 'items': []});
    }
    if (!formattedLocations.any((l) => l['location'] == 'FACTORY')) {
      formattedLocations
          .add({'location': 'FACTORY', 'totalStock': 0.0, 'items': []});
    }

    final double grandTotal = yardTotal + factoryTotal;
    final double todayInVal = todayInNotifier.value;
    final double todayOutVal = todayOutNotifier.value;
    final int activeItemsVal =
        inventoryList.map((e) => e.itemName).toSet().length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final erpMap = {
        'summary': {
          'grandTotal': grandTotal,
          'activeItems': activeItemsVal,
          'todayIn': todayInVal,
          'todayOut': todayOutVal,
          'yardStock': yardTotal,
          'factoryStock': factoryTotal,
          'locationStocks': {
            'YARD': yardTotal,
            'FACTORY': factoryTotal,
          }
        },
        'locations': formattedLocations
      };
      _box.put('erp_stock', jsonEncode(erpMap));
      erpStockNotifier.value = erpMap;
    });
  }

  // ignore: unused_element
  static Future<void> _deriveNotifiersViaCompute(
      List<StockTransaction> txs) async {
    try {
      // Use ALL transactions — no reset cutoff for stock calculation.
      debugPrint("Isolate Processing Txs: ${txs.length}");

      final txJsonStr = jsonEncode(txs.map((t) => t.toJson()).toList());
      final result = await compute(_computeStockNotifiersIsolate, txJsonStr);

      final double totalVal = (result['totalMT'] as num).toDouble();
      final double yardVal = (result['yardTotal'] as num).toDouble();
      final double factoryVal = (result['factoryTotal'] as num).toDouble();
      final double todayInVal = (result['todayIn'] as num).toDouble();
      final double todayOutVal = (result['todayOut'] as num).toDouble();

      final rawList = result['inventoryList'] as List<dynamic>;
      final List<ItemVariant> derivedList = rawList.map((v) {
        final m = v as Map<String, dynamic>;
        return ItemVariant(
          itemName: m['itemName'] as String,
          category: m['category'] as String? ?? m['itemName'] as String,
          size: m['size'] as String,
          currentStockMT: (m['currentStockMT'] as num).toDouble(),
          location: m['location'] as String,
        );
      }).toList();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        totalStockNotifier.value = totalVal;
        yardStockNotifier.value = yardVal;
        factoryStockNotifier.value = factoryVal;
        todayInNotifier.value = todayInVal;
        todayOutNotifier.value = todayOutVal;
        inventoryListNotifier.value = derivedList;
        _updateErpStockNotifierFromInventoryList(derivedList);
      });

      // Persist Total Stock for instant launch feedback
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_total_stock', totalVal);
    } catch (e) {
      debugPrint("compute() failed, falling back to sync: $e");
      await _deriveNotifiersFromTransactions(txs);
    }
  }

  static Future<void> _deriveNotifiersFromTransactions(
      List<StockTransaction> txs) async {
    double totalMT = 0;
    double todayIn = 0;
    double todayOut = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<String, ItemVariant> variantsMap = {};

    // No reset cutoff — compute stock from ALL transactions to match Google Sheet.
    // Process chronologically (oldest first) since txs arrive newest-first.
    for (int i = txs.length - 1; i >= 0; i--) {
      final tx = txs[i];
      if (tx.isReversed) continue;

      // Compound key: Item Name + Size + Location
      final String loc = _isolateNormalizeLocation(tx.location);
      final String normalizedSize = formatSizeDisplay(tx.itemName, tx.size);
      final key = "${tx.itemName}|$normalizedSize|$loc";
      variantsMap.putIfAbsent(
          key,
          () => ItemVariant(
                itemName: tx.itemName,
                category: tx.itemName,
                size: normalizedSize,
                currentStockMT: 0,
                location: loc,
              ));

      final v = variantsMap[key]!;
      if (['IN', 'RETURN', 'ADJUSTMENT', 'OPENING'].contains(tx.type)) {
        v.currentStockMT += tx.qtyMT;
        if (!tx.dateTime.isBefore(today)) {
          if (tx.type == 'IN') todayIn += tx.qtyMT;
        }
      } else if (tx.type == 'OUT' || tx.type == 'RESERVE') {
        v.currentStockMT -= tx.qtyMT;
        if (!tx.dateTime.isBefore(today)) {
          if (tx.type == 'OUT') todayOut += tx.qtyMT;
        }
      } else if (tx.type == 'TRANSFER') {
        v.currentStockMT -= tx.qtyMT;
        if (tx.toLocation != null) {
          final String toLoc = _isolateNormalizeLocation(tx.toLocation);
          final toKey = "${tx.itemName}|$normalizedSize|$toLoc";
          variantsMap.putIfAbsent(
              toKey,
              () => ItemVariant(
                    itemName: tx.itemName,
                    category: tx.itemName,
                    size: normalizedSize,
                    currentStockMT: 0,
                    location: toLoc,
                  ));
          variantsMap[toKey]!.currentStockMT += tx.qtyMT;
        }
      }
    }

    // Final-stage clamp: only at output, never mid-accumulation
    for (final v in variantsMap.values) {
      if (v.currentStockMT < 0.0) v.currentStockMT = 0.0;
    }

    final inventoryList =
        variantsMap.values.where((v) => v.currentStockMT != 0).toList();
    inventoryList.sort((a, b) {
      int catComp = SortingUtils.compareCategories(a.category, b.category);
      if (catComp != 0) return catComp;
      int itemComp = a.itemName.compareTo(b.itemName);
      if (itemComp != 0) return itemComp;
      int locComp = a.location.compareTo(b.location);
      if (locComp != 0) return locComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
    totalMT = inventoryList.fold(0.0, (sum, v) => sum + v.currentStockMT);

    double yardTotal = 0;
    double factoryTotal = 0;
    for (var v in inventoryList) {
      if (v.location.toUpperCase() == 'YARD') yardTotal += v.currentStockMT;
      if (v.location.toUpperCase() == 'FACTORY')
        factoryTotal += v.currentStockMT;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      totalStockNotifier.value = totalMT;
      yardStockNotifier.value = yardTotal;
      factoryStockNotifier.value = factoryTotal;
      todayInNotifier.value = todayIn;
      todayOutNotifier.value = todayOut;
      inventoryListNotifier.value = inventoryList;
      _updateErpStockNotifierFromInventoryList(inventoryList);
    });

    // Persist Total Stock for instant launch feedback
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cached_total_stock', totalMT);
  }

  static Future<bool> submitTransactions(
      BuildContext context, List<dynamic> transactions) async {
    isSyncing.value = true;
    try {
      final result = SyncResult(success: true); // Stubbed

      if (!result.success) {
        throw "Unknown Server Error";
      }

      // 1. Refresh ALL Stock Data (Transactions + Derived Metrics)
      await refreshAllStockData(forceRefresh: true);

      return true;
    } catch (e) {
      debugPrint("Transaction failed: $e");
      rethrow;
    } finally {
      isSyncing.value = false;
    }
  }

  static const String _resetTimestampKey = 'stock_dashboard_last_reset';
  static const String _vendorResetTimestampKey = 'vendor_purchase_last_reset';

  static Future<DateTime?> getLastResetTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final tsStr = prefs.getString(_resetTimestampKey);
    if (tsStr == null) return null;
    return DateTime.tryParse(tsStr);
  }

  static Future<void> setLastResetTimestamp(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_resetTimestampKey, dt.toIso8601String());
  }

  static Future<DateTime?> getVendorResetTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final tsStr = prefs.getString(_vendorResetTimestampKey);
    if (tsStr == null) return null;
    return DateTime.tryParse(tsStr);
  }

  static Future<void> setVendorResetTimestamp(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vendorResetTimestampKey, dt.toIso8601String());
  }

  static Future<void> clearLocalCacheOnly() async {
    await _box.clear(); // 🚀 Wipe EVERYTHING in the cache box

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('stock_transactions_v2');
    // await SheetService.clearPendingTransactions();

    final now = DateTime.now();
    await setLastResetTimestamp(now);
    debugPrint("App Reset Triggered. New Cutoff: $now");

    allTransactionsNotifier.value = [];
    transactionsNotifier.value = [];
    totalStockNotifier.value = 0.0;
    yardStockNotifier.value = 0.0;
    factoryStockNotifier.value = 0.0;
    todayInNotifier.value = 0.0;
    todayOutNotifier.value = 0.0;
    inventoryListNotifier.value = [];

    erpStockNotifier.value = {
      "summary": {"yardStock": 0, "factoryStock": 0, "grandTotal": 0},
      "locations": []
    };
    sheetDataNotifier.value = {
      'meta': {'gst_rate': '0.18', 'loading_charge': '255'},
      'items': []
    };

    await refreshAllStockData(forceRefresh: true);
  }

  static Future<void> clearVendorPurchaseCache() async {
    await _box.delete('sauda_reports');
    vendorTotalQtyNotifier.value = 0.0;
    vendorAvgRateNotifier.value = 0.0;
    vendorSaudaListNotifier.value = [];
    await setVendorResetTimestamp(DateTime.now());
  }

  static Future<void> clearLocalStockCache() async {
    if (_box.isOpen) {
      await _box.delete('erp_stock');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_total_stock');

    totalStockNotifier.value = 0.0;
    yardStockNotifier.value = 0.0;
    factoryStockNotifier.value = 0.0;
    todayInNotifier.value = 0.0;
    todayOutNotifier.value = 0.0;
    inventoryListNotifier.value = [];
    erpStockNotifier.value = {
      "summary": {"yardStock": 0, "factoryStock": 0, "grandTotal": 0},
      "locations": []
    };
    debugPrint("[DataRepository] Stock local memory and Hive cache flushed.");
  }

  static Stream<List<StockTransaction>> getSupabaseTransactionsStream() {
    return SupabaseService.client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((list) => list
            .where((row) {
              final txnType = row['txn_type']?.toString().toUpperCase() ?? '';
              final type = row['type']?.toString().toUpperCase() ?? '';
              final txnId = row['txn_id']?.toString() ?? '';
              return txnType != 'PURCHASE' &&
                  type != 'PURCHASE' &&
                  !txnId.startsWith('IN_V_');
            })
            .map((row) {
              final txnType = row['txn_type']?.toString() ??
                  row['type']?.toString() ??
                  'IN';
              final txnId =
                  row['txn_id']?.toString() ?? row['id']?.toString() ?? '';
              return StockTransaction(
                txnId: txnId,
                dateTime: ReportsRepository.parseRowDateTime(row),
                itemName: resolveItemName(row),
                size: resolveSizeLabel(row),
                type: txnType,
                qtyMT: (row['qty_mt'] as num?)?.toDouble() ?? 0.0,
                location: row['location']?.toString() ?? 'YARD',
                toLocation: row['to_location']?.toString(),
                reason: row['reason']?.toString(),
                note: row['note']?.toString(),
                invoiceNo: row['invoice_no']?.toString(),
                lorryNo: row['lorry_no']?.toString(),
                transportCo: row['transport_co']?.toString(),
                driverName: row['driver_name']?.toString(),
                driverPhone: row['driver_phone']?.toString(),
                partyName: row['party_name']?.toString(),
                contactNo: row['contact_no']?.toString(),
                batchId: row['batch_id']?.toString(),
                user: row['user']?.toString(),
                isReversed: row['is_reversed'] == true,
              );
            })
            .whereType<StockTransaction>()
            .toList());
  }

  static Stream<List<ItemVariant>> getSupabaseStockStream() {
    return getSupabaseTransactionsStream().asyncMap((_) async {
      await ensureMasterLookupData();
      final stockRows = await fetchCurrentStock('ALL');
      final List<ItemVariant> stockList = stockRows
          .map((row) {
            final itemName = resolveItemName(row);
            final sizeLabel = resolveSizeLabel(row);
            final location =
                row['location']?.toString().toUpperCase() ?? 'YARD';
            final netStock = _parseDouble(row['net_stock_mt']);
            return ItemVariant(
              itemName: itemName,
              category: canonicalizeCategory(itemName),
              size: sizeLabel,
              currentStockMT: netStock,
              location: location,
            );
          })
          .where((v) => v.currentStockMT != 0)
          .toList();

      stockList.sort((a, b) {
        int catComp = SortingUtils.compareCategories(a.category, b.category);
        if (catComp != 0) return catComp;
        int itemComp = a.itemName.compareTo(b.itemName);
        if (itemComp != 0) return itemComp;
        int locComp = a.location.compareTo(b.location);
        if (locComp != 0) return locComp;
        return SortingUtils.compareSizes(a.size, b.size);
      });

      return stockList;
    });
  }

  static Future<List<MaterialModel>> getSupabaseMaterials() async {
    final list = await SupabaseService().fetchMaterials();
    return list.map((map) => MaterialModel.fromSupabaseMap(map)).toList();
  }

  static Future<SyncResult> deletePurchaseEntry(String id) async {
    try {
      if (id.isEmpty) {
        return SyncResult(
            success: false, errorMessage: "Invalid transaction ID");
      }

      try {
        await SupabaseService.client
            .from('transactions')
            .delete()
            .eq('txn_id', id);
      } catch (e) {
        debugPrint("[DataRepository] Delete by txn_id error: $e");
      }

      if (int.tryParse(id) != null) {
        try {
          await SupabaseService.client
              .from('transactions')
              .delete()
              .eq('id', int.parse(id));
        } catch (e) {
          debugPrint("[DataRepository] Delete by id error: $e");
        }
      }

      // Update local cache notifier
      final currentList = List<dynamic>.from(vendorSaudaListNotifier.value);
      currentList.removeWhere((e) =>
          (e['srNo']?.toString() == id) ||
          (e['id']?.toString() == id) ||
          (e['txn_id']?.toString() == id));
      vendorSaudaListNotifier.value = currentList;

      return SyncResult(success: true);
    } catch (e) {
      debugPrint("[DataRepository] deletePurchaseEntry Error: $e");
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  static Future<SyncResult> toggleSaudaHiddenStatus({
    required String saudaId,
    required bool isHidden,
  }) async {
    return SheetService.toggleSaudaHiddenStatus(
        saudaId: saudaId, isHidden: isHidden);
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
    return SheetService.updatePurchaseEntry(
      saudaId: saudaId,
      qtyMt: qtyMt,
      rate: rate,
      vendorName: vendorName,
      itemName: itemName,
      size: size,
      region: region,
      location: location,
      date: date,
    );
  }

  /// Fetches stock transactions up to [endDate] for calculating date-bounded stock movements.
  static Future<List<StockTransaction>> fetchStockMovement({
    required DateTime startDate,
    required DateTime endDate,
    String? location,
  }) async {
    await ensureMasterLookupData();

    var query = SupabaseService.client
        .from('transactions')
        .select('*')
        .not('txn_id', 'like', 'IN_V_%');

    if (location != null && location != 'ALL') {
      query = query.eq('location', location);
    }

    final response =
        await query.order('created_at', ascending: false).limit(10000);

    final List<StockTransaction> txns = (response as List).where((row) {
      final txnId = row['txn_id']?.toString() ?? '';
      final isReversed = row['is_reversed'] == true;
      final txnType = row['txn_type']?.toString().toUpperCase() ?? '';
      final type = row['type']?.toString().toUpperCase() ?? '';
      return !isReversed &&
          !txnId.startsWith('IN_V_') &&
          txnType != 'PURCHASE' &&
          type != 'PURCHASE';
    }).map((row) {
      final itemName = resolveItemName(row);
      return StockTransaction(
        txnId: row['txn_id']?.toString() ?? row['id'].toString(),
        dateTime: ReportsRepository.parseRowDateTime(row),
        itemName: itemName,
        size: resolveSizeLabel(row),
        type: row['txn_type']?.toString() ?? row['type']?.toString() ?? 'IN',
        qtyMT: (row['qty_mt'] as num?)?.toDouble() ?? 0.0,
        location: row['location']?.toString() ?? 'YARD',
        toLocation: row['to_location']?.toString(),
        reason: row['reason']?.toString(),
        note: row['note']?.toString(),
        invoiceNo: row['invoice_no']?.toString(),
        lorryNo: row['lorry_no']?.toString(),
        transportCo: row['transport_co']?.toString(),
        driverName: row['driver_name']?.toString(),
        driverPhone: row['driver_phone']?.toString(),
        partyName: row['party_name']?.toString(),
        contactNo: row['contact_no']?.toString(),
        batchId: row['batch_id']?.toString(),
        user: row['user']?.toString(),
        isReversed: row['is_reversed'] == true,
        category: canonicalizeCategory(itemName),
      );
    }).toList();

    return txns;
  }

  /// Calculates stock ledger opening balance, inward, outward, and closing MT per size.
  /// Opening Stock = SUM(qty_mt where txn_type IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN') AND created_at < startDate)
  ///                 - SUM(qty_mt where txn_type IN ('OUT','OUTWARD','SALE','TRANSFER') AND created_at < startDate)
  /// Period Inward = SUM(qty_mt where txn_type IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN') AND created_at BETWEEN startDate AND endDate)
  /// Period Outward = SUM(qty_mt where txn_type IN ('OUT','TRANSFER') AND created_at BETWEEN startDate AND endDate)
  /// Net Remaining Stock = Opening Stock + Period Inward - Period Outward
  static Map<String, Map<String, dynamic>> calculateStockLedgerData({
    required List<StockTransaction> transactions,
    required DateTime startDate,
    required DateTime endDate,
    String selectedLocation = 'ALL',
  }) {
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfDay =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final selectedLoc = selectedLocation.trim().toUpperCase();

    final Map<String, Map<String, dynamic>> ledgerMap = {};

    for (var tx in transactions) {
      if (tx.isReversed) continue;
      if (tx.txnId.startsWith('IN_V_')) continue;

      final String txLoc = tx.location.trim().toUpperCase();
      final String? toLoc = tx.toLocation?.trim().toUpperCase();
      final String type = tx.type.trim().toUpperCase();

      // Explicitly ignore PURCHASE transactions for warehouse stock
      if (type == 'PURCHASE') continue;

      bool isRelevant = false;
      bool isTransferIn = false;
      bool isTransferOut = false;

      if (selectedLoc == 'ALL') {
        isRelevant = true;
      } else {
        if (txLoc == selectedLoc) {
          isRelevant = true;
          if (type == 'TRANSFER') {
            isTransferOut = true;
          }
        }
        if (toLoc == selectedLoc && type == 'TRANSFER') {
          isRelevant = true;
          isTransferIn = true;
        }
      }

      if (!isRelevant) continue;

      final key = "${tx.itemName}_${tx.size}";
      final String cat = canonicalizeCategory(
          tx.category.isNotEmpty && tx.category != 'General'
              ? tx.category
              : tx.itemName);
      ledgerMap.putIfAbsent(
          key,
          () => {
                'itemName': tx.itemName,
                'category': cat,
                'category_name': cat,
                'size': tx.size,
                'opening': 0.0,
                'opening_mt': 0.0,
                'opening_balance': 0.0,
                'inward': 0.0,
                'outward': 0.0,
                'closing': 0.0,
                'closing_mt': 0.0,
              });

      final entry = ledgerMap[key]!;
      final double qty = tx.qtyMT.abs();

      double txIn = 0.0;
      double txOut = 0.0;

      if (selectedLoc != 'ALL' && type == 'TRANSFER') {
        if (isTransferIn) txIn = qty;
        if (isTransferOut) txOut = qty;
      } else if (type == 'TRANSFER') {
        txIn = 0.0;
        txOut = 0.0;
      } else if (['IN', 'INWARD', 'OPENING_STOCK', 'OPENING', 'RETURN'].contains(type)) {
        txIn = qty;
      } else if (['OUT', 'OUTWARD', 'SALE', 'RESERVE'].contains(type)) {
        txOut = qty;
      } else if (type == 'ADJUSTMENT') {
        if (tx.qtyMT >= 0) {
          txIn = qty;
        } else {
          txOut = qty;
        }
      }

      if (tx.dateTime.isBefore(startOfDay)) {
        final double currentOp = (entry['opening'] as double) + (txIn - txOut);
        entry['opening'] = currentOp;
        entry['opening_mt'] = currentOp;
        entry['opening_balance'] = currentOp;
      } else if ((tx.dateTime.isAtSameMomentAs(startOfDay) ||
              tx.dateTime.isAfter(startOfDay)) &&
          (tx.dateTime.isAtSameMomentAs(endOfDay) ||
              tx.dateTime.isBefore(endOfDay))) {
        entry['inward'] = (entry['inward'] as double) + txIn;
        entry['outward'] = (entry['outward'] as double) + txOut;
      }
    }

    for (var entry in ledgerMap.values) {
      final double op = entry['opening'] as double;
      final double inQty = entry['inward'] as double;
      final double outQty = entry['outward'] as double;
      final double cl = op + inQty - outQty;
      entry['closing'] = cl;
      entry['closing_mt'] = cl;
    }

    return ledgerMap;
  }
}
