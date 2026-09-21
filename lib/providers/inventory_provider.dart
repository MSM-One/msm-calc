import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/data_repository.dart';
import '../models/stock_models.dart';
import '../models/user_model.dart';
import '../services/report_calculators.dart';
import '../services/sample_rate_service.dart';
import '../utils/sorting_utils.dart';

class InventoryProvider extends ChangeNotifier {
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  bool _isBackgroundSyncing = false;

  DateTime? get lastUpdated => _lastUpdated;
  bool get isBackgroundSyncing => _isBackgroundSyncing;

  Map<String, List<SampleRateSize>> _sampleRateCategories = {};
  Map<String, List<SampleRateSize>> get sampleRateCategories =>
      _sampleRateCategories;

  // Reactive base rate state mapping per category
  final Map<String, double> _sampleRateBaseRates = {};
  Map<String, double> get sampleRateBaseRates => _sampleRateBaseRates;

  double getBaseRateForCategory(String category) {
    return _sampleRateBaseRates[category] ??
        _sampleRateBaseRates[_normalizeCategory(category)] ??
        0.0;
  }

  void updateBaseRate(String category, double rate) {
    _sampleRateBaseRates[category] = rate;
    _sampleRateBaseRates[_normalizeCategory(category)] = rate;
    notifyListeners();
  }

  @visibleForTesting
  void setSampleRateCategoriesForTesting(
      Map<String, List<SampleRateSize>> categories) {
    _sampleRateCategories = categories;
    notifyListeners();
  }

  List<ItemVariant> get lowStockItems {
    final inventory = DataRepository.inventoryListNotifier.value;
    return ReportCalculators.calculateLowStock(inventory: inventory);
  }

  bool get isDesktopOrWeb =>
      kIsWeb ||
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static List<String> get orderedSampleRateCategories =>
      SampleRateService.orderedCategories;

  static Map<String, List<String>> get sampleRateAliases =>
      SampleRateService.categoryAliases;

  static Map<String, List<SampleRateSpec>> get sampleSpecifications =>
      SampleRateService.benchmarkSpecifications;

  static List<String> get _orderedSampleRateCategories =>
      SampleRateService.orderedCategories;

  static Map<String, List<String>> get _sampleRateAliases =>
      SampleRateService.categoryAliases;

  bool _isLoadingSampleRates = false;
  bool get isLoadingSampleRates => _isLoadingSampleRates;

  Map<String, List<Map<String, dynamic>>> _saudaSizesMap = {};
  Map<String, List<Map<String, dynamic>>> get saudaSizesMap => _saudaSizesMap;

  List<String> _saudaItemTypes = [];
  List<String> get saudaItemTypes => _saudaItemTypes;

  final double _sheetLoading = 255;
  double get sheetLoading => _sheetLoading;

  final double _sheetGst = 0.18;
  double get sheetGst => _sheetGst;

  // --- Normalization for Sample Rate Calc ---
  void initTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      refreshData();
    });
    // Trigger initial load
    refreshData();
  }

  Future<void> refreshData() async {
    if (_isBackgroundSyncing) return;
    _isBackgroundSyncing = true;
    notifyListeners();

    try {
      await Future.wait([
        fetchSampleRateData(force: true),
        loadSaudaData(force: true),
        DataRepository.refreshAllStockData(forceRefresh: true),
      ]);
      _lastUpdated = DateTime.now();
    } catch (e) {
      debugPrint("Refresh failed: $e");
    } finally {
      _isBackgroundSyncing = false;
      notifyListeners();
    }
  }

  Future<void> loadSaudaData({bool force = false}) async {
    try {
      final data =
          await DataRepository.getSheetDataAsync(null, forceRefresh: force);
      final List items = data['items'] ?? [];

      final Map<String, List<Map<String, dynamic>>> tempMap = {};
      final List<String> tempTypes = [];

      for (var cat in items) {
        final name = (cat['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        tempTypes.add(name);

        final sizes = cat['sizes'] as List? ?? [];
        final sizesList =
            sizes.map((s) => Map<String, dynamic>.from(s)).toList();
        sizesList.sort((a, b) => SortingUtils.compareSizes(
            a['label']?.toString() ?? '', b['label']?.toString() ?? ''));
        tempMap[name.toUpperCase()] = sizesList;
      }

      tempTypes.sort(SortingUtils.compareCategories);
      _saudaItemTypes = tempTypes;
      _saudaSizesMap = tempMap;
      _lastUpdated = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading sauda data: $e");
    }
  }

  String _normalizeCategory(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _cleanSizeForMatch(String s) {
    return s
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('”', '')
        .replaceAll('“', '')
        .replaceAll('’', '')
        .replaceAll('‘', '')
        .replaceAll('×', 'X')
        .replaceAll('x', 'X')
        .replaceAll('*', 'X')
        .replaceAll(' (', '(')
        .replaceAll('( ', '(')
        .replaceAll(' )', ')')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  Future<void> fetchSampleRateData({bool force = false}) async {
    if (_isLoadingSampleRates) return;

    _isLoadingSampleRates = true;

    try {
      debugPrint("DEBUG: [SampleRate-Dynamic] Starting dynamic data fetch (force: $force)");
      final grouped = await SampleRateService.fetchSampleRateCategories(force: force);

      int totalMatched = 0;
      grouped.forEach((cat, sizes) {
        totalMatched += sizes.length;
      });
      debugPrint(
          "DEBUG: [SampleRate-Dynamic] Load complete. Benchmark categories: ${grouped.length}, sizes: $totalMatched");

      _sampleRateCategories = grouped;
      notifyListeners();
    } catch (e, stack) {
      debugPrint("ERROR: [SampleRate-Dynamic] $e");
      debugPrint(stack.toString());
    } finally {
      _isLoadingSampleRates = false;
      notifyListeners();
    }
  }

  String _resolveCategoryKey(String category) {
    if (_sampleRateCategories.containsKey(category)) return category;
    final norm = _normalizeCategory(category);
    for (final k in _sampleRateCategories.keys) {
      if (_normalizeCategory(k) == norm) return k;
    }
    return category;
  }

  /// Adds a custom size to a category, persists to SharedPreferences, and notifies listeners.
  Future<void> addCustomSizeToCategory(
      String category, SampleRateSize size) async {
    final targetCat = _resolveCategoryKey(category);
    final list =
        List<SampleRateSize>.from(_sampleRateCategories[targetCat] ?? []);
    final cleanLabel = _cleanSizeForMatch(size.label);
    if (!list.any((s) => _cleanSizeForMatch(s.label) == cleanLabel)) {
      list.add(size.copyWith(isCustom: true));
      _sampleRateCategories[targetCat] = list;
      await SampleRateService.saveActiveSizes(targetCat, list);
      notifyListeners();
    }
  }

  /// Creates a new item size, inserts into Supabase, appends to active category, persists to SharedPreferences, and notifies listeners.
  Future<SampleRateSize> addNewItemSize({
    required String category,
    required String sizeLabel,
    required double weight,
    required double sd,
    bool isNewCategory = false,
  }) async {
    final newSize = await SampleRateService.insertNewItemSize(
      category: category,
      sizeLabel: sizeLabel,
      weight: weight,
      sd: sd,
    );

    // If new category, persist category name
    if (isNewCategory) {
      final customCats = await SampleRateService.loadCustomCategories();
      if (!customCats
          .any((c) => _normalizeCategory(c) == _normalizeCategory(category))) {
        customCats.add(category);
        await SampleRateService.saveCustomCategories(customCats);
      }
    }

    final targetCat = _resolveCategoryKey(category);
    final list =
        List<SampleRateSize>.from(_sampleRateCategories[targetCat] ?? []);
    final cleanLabel = _cleanSizeForMatch(newSize.label);
    if (!list.any((s) => _cleanSizeForMatch(s.label) == cleanLabel)) {
      list.add(newSize);
    }
    _sampleRateCategories[targetCat] = list;
    await SampleRateService.saveActiveSizes(targetCat, list);
    notifyListeners();
    return newSize;
  }

  /// Adds multiple sizes to a category, persists to SharedPreferences, and notifies listeners.
  Future<void> addMultipleSizesToCategory(
    String category,
    List<SampleRateSize> sizes, {
    bool isNewCategory = false,
  }) async {
    if (isNewCategory) {
      final customCats = await SampleRateService.loadCustomCategories();
      if (!customCats
          .any((c) => _normalizeCategory(c) == _normalizeCategory(category))) {
        customCats.add(category);
        await SampleRateService.saveCustomCategories(customCats);
      }
    }

    final targetCat = _resolveCategoryKey(category);
    final list =
        List<SampleRateSize>.from(_sampleRateCategories[targetCat] ?? []);
    for (final s in sizes) {
      final cleanLabel = _cleanSizeForMatch(s.label);
      if (!list.any((existing) =>
          _cleanSizeForMatch(existing.label) == cleanLabel)) {
        list.add(s.copyWith(isCustom: true));
      }
    }
    _sampleRateCategories[targetCat] = list;
    await SampleRateService.saveActiveSizes(targetCat, list);
    notifyListeners();
  }

  /// Removes a size from a category, persists to SharedPreferences, and notifies listeners.
  Future<void> removeSizeFromCategory(
      String category, SampleRateSize size) async {
    final targetCat = _resolveCategoryKey(category);
    final list =
        List<SampleRateSize>.from(_sampleRateCategories[targetCat] ?? []);
    final cleanLabel = _cleanSizeForMatch(size.label);
    list.removeWhere((s) => _cleanSizeForMatch(s.label) == cleanLabel);
    _sampleRateCategories[targetCat] = list;
    await SampleRateService.saveActiveSizes(targetCat, list);
    notifyListeners();
  }

  /// Removes a custom category from state and persistence. Core benchmark categories cannot be removed.
  Future<bool> removeCustomCategory(String category) async {
    if (SampleRateService.isCoreCategory(category)) {
      return false; // Protected core category
    }

    _sampleRateCategories.remove(category);
    _sampleRateCategories.removeWhere(
      (key, _) => _normalizeCategory(key) == _normalizeCategory(category),
    );

    await SampleRateService.removeCustomCategory(category);
    notifyListeners();
    return true;
  }

  /// Resets all categories and sizes back to default benchmark specifications.
  Future<void> resetAllCategoriesToDefaults() async {
    await SampleRateService.clearAllCustomCategories();
    for (final cat in _sampleRateCategories.keys) {
      await SampleRateService.clearActiveSizes(cat);
    }
    _sampleRateCategories.clear();
    final baselineGrouped =
        await SampleRateService.fetchBaselineBenchmarkCategories(force: true);
    _sampleRateCategories.addAll(baselineGrouped);
    notifyListeners();
  }

  /// Resets a category back to default benchmark sizes, clears SharedPreferences, and notifies listeners.
  Future<void> resetCategoryToDefaults(String category) async {
    await SampleRateService.clearActiveSizes(category);
    final baselineGrouped =
        await SampleRateService.fetchBaselineBenchmarkCategories();
    if (baselineGrouped.containsKey(category)) {
      _sampleRateCategories[category] = baselineGrouped[category]!;
    } else {
      for (final entry in baselineGrouped.entries) {
        if (_normalizeCategory(entry.key) == _normalizeCategory(category)) {
          _sampleRateCategories[category] = entry.value;
          break;
        }
      }
    }
    notifyListeners();
  }

  /// Checks if a category's current active sizes differ from the default benchmark specs.
  bool isCategoryModified(String category) {
    final current = _sampleRateCategories[category] ?? [];
    return SampleRateService.isCategoryModified(category, current);
  }

  /// Retrieves all master catalog sizes for a given category from Supabase / Google Sheets.
  List<SampleRateSize> getMasterSizesForCategory(String category) {
    String targetCatName = category;
    for (final catName in _orderedSampleRateCategories) {
      if (_normalizeCategory(catName) == _normalizeCategory(category)) {
        targetCatName = catName;
        break;
      }
    }

    final List<String> aliases = _sampleRateAliases[targetCatName] ?? [targetCatName];
    final String normCatName = _normalizeCategory(targetCatName);

    final List rawSizes = [];

    // 1. From Google Sheets (sheetDataNotifier)
    final items = DataRepository.sheetDataNotifier.value['items'] as List? ?? [];
    final categoryItemsFromSheet = items.where((catItem) {
      final String sheetCatName = (catItem['name'] ?? '').toString();
      final String normSheetCat = _normalizeCategory(sheetCatName);
      final String upperSheetCat = sheetCatName.toUpperCase().trim();

      if (upperSheetCat.contains('HR PIPE') ||
          upperSheetCat.contains('CR PIPE') ||
          upperSheetCat.contains('ISMB') ||
          upperSheetCat.contains('ISMC') ||
          upperSheetCat.contains('STRUCTURE') ||
          upperSheetCat.contains('BEAM') ||
          upperSheetCat.contains('BARBED') ||
          upperSheetCat.contains('GATE') ||
          upperSheetCat.contains('BINDING') ||
          upperSheetCat.contains('NAIL') ||
          upperSheetCat.contains('ERW')) {
        return false;
      }

      bool matchesAlias = aliases
          .any((alias) => alias.toUpperCase().trim() == upperSheetCat);
      bool matchesNorm = normSheetCat == normCatName;
      return matchesAlias || matchesNorm;
    }).toList();

    for (var catItem in categoryItemsFromSheet) {
      final List sizesRaw = catItem['sizes'] ?? [];
      rawSizes.addAll(sizesRaw);
    }

    // 2. From Supabase master table item_sizes (itemSizesNotifier)
    if (DataRepository.itemSizesNotifier.value.isNotEmpty) {
      for (final s in DataRepository.itemSizesNotifier.value) {
        final String matName = (s['material_name'] ?? s['category'] ?? s['item_name'] ?? '').toString();
        final String upperMat = matName.toUpperCase().trim();
        final String normMat = _normalizeCategory(matName);

        bool matchesAlias = aliases.any((alias) => alias.toUpperCase().trim() == upperMat);
        bool matchesNorm = normMat == normCatName;
        if (matchesAlias || matchesNorm) {
          rawSizes.add(s);
        }
      }
    }

    // Parse and deduplicate
    final Map<String, SampleRateSize> uniqueMap = {};
    for (var s in rawSizes) {
      final String rawLabel =
          (s['size_label'] ?? s['label'] ?? s['size'] ?? '').toString().trim();
      if (rawLabel.isEmpty) continue;

      final rawSd = s['size_difference'] ?? s['sd'] ?? s['diffRate'] ?? s['diff_rate'];
      final rawWeight = s['unit_weight_kg'] ?? s['weight'] ?? s['std_weight'] ?? s['std_wt'];

      num parsedSd = 0;
      if (rawSd != null) {
        parsedSd = (rawSd is num) ? rawSd : (num.tryParse(rawSd.toString()) ?? 0);
      }

      num parsedWeight = 0;
      if (rawWeight != null) {
        parsedWeight = (rawWeight is num) ? rawWeight : (num.tryParse(rawWeight.toString()) ?? 0);
      }

      final key = _cleanSizeForMatch(rawLabel);
      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = SampleRateSize(
          rawLabel,
          parsedSd,
          parsedWeight,
          isCustom: true,
        );
      }
    }

    final result = uniqueMap.values.toList();
    result.sort((a, b) => SortingUtils.compareSizes(a.label, b.label));
    return result;
  }

  /// Updates a user's role and permissions on the server.
  /// Used for Web compatibility with POST requests.
  Future<bool> updateUserRole(UserModel user) async {
    const String url =
        "https://script.google.com/macros/s/AKfycbzcSBboPXwuH-whwxXe8IdaaTqnTgIPBVo_z1aMJNZuzX2KQq12AL-RjH1znoq3MCex/exec";

    // Requested Logs
    debugPrint('Attempting update: ${user.email}');
    debugPrint(
        'DEBUG: [InventoryProvider] Initiating updateUserRole for ${user.email}');

    try {
      final body = jsonEncode({
        "action": "updateRole",
        "userData": user.toJson(),
      });

      debugPrint('DEBUG: [InventoryProvider] Target URL: $url');
      debugPrint('DEBUG: [InventoryProvider] Request Body: $body');

      // Send purely as body string to force default 'text/plain; charset=utf-8' inside standard web fetch
      final response = await http
          .post(
            Uri.parse(url),
            body: body,
          )
          .timeout(const Duration(seconds: 45));

      // Requested Logs
      debugPrint('Server Response: ${response.body}');
      debugPrint(
          'DEBUG: [InventoryProvider] Status Code: ${response.statusCode}');

      // Handle status code 302 (Redirect) or check for "success" in response body
      final bool isSuccessBody =
          response.body.toLowerCase().contains('success');
      final bool isSuccessStatus =
          response.statusCode >= 200 && response.statusCode < 400;

      if (isSuccessStatus || isSuccessBody) {
        debugPrint(
            'DEBUG: [InventoryProvider] Role update SUCCESS (Status: ${response.statusCode}, Body Match: $isSuccessBody)');
        return true;
      } else {
        debugPrint(
            'DEBUG: [InventoryProvider] Role update FAILED (Status: ${response.statusCode}, Body: ${response.body})');
        return false;
      }
    } catch (e, stack) {
      debugPrint('Error updating user role: $e');
      debugPrint('DEBUG: [InventoryProvider] Role update EXCEPTION: $e');
      debugPrint('DEBUG: [InventoryProvider] Stacktrace: $stack');
      return false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
