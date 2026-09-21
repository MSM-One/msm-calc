import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_models.dart';
import '../utils/sorting_utils.dart';
import 'data_repository.dart';
import 'supabase_service.dart';

class SampleRateService {
  static const List<String> orderedCategories = [
    "MS Pipe",
    "MS Angle",
    "MS Channel",
    "Sqr Bar",
    "Round Bar",
    "Flats",
  ];

  static const Map<String, List<String>> categoryAliases = {
    "MS Pipe": ["MS PIPE", "PIPE", "MS PIPES", "MS PIPES (STRUCTURAL)"],
    "MS Angle": ["MS ANGLE", "ANGLE", "MS ANGLES", "MS ANGLE (STRUCTURAL)"],
    "MS Channel": [
      "MS CHANNEL",
      "CHANNEL",
      "MS CHANNELS",
      "MS CHANNEL (STRUCTURAL)"
    ],
    "Sqr Bar": ["SQR BAR", "SQUARE BAR", "SQ BAR", "MS SQR BAR", "SQR. BAR"],
    "Flats": ["FLATS", "FLAT", "MS FLAT", "MS FLATS"],
    "Round Bar": ["ROUND BAR", "ROUND", "MS ROUND BAR", "MS ROUND"],
  };

  static const Map<String, int> categoryToMaterialId = {
    "MS Pipe": 1,
    "MS Angle": 2,
    "MS Channel": 3,
    "Sqr Bar": 6,
    "Round Bar": 7,
    "Flats": 8,
  };

  static const Map<String, List<SampleRateSpec>> benchmarkSpecifications = {
    "MS Pipe": [
      SampleRateSpec(
        id: 2,
        label: "0.75\" 19x19(1.6)",
        defaultWeight: 5.0,
        defaultSd: 6500,
        matchKeys: [
          "0.75\" 19X19(1.6)",
          "0.75\" 19X19 (1.6)",
          "3/4\" 19X19(1.6)",
          "19X19(1.6)",
          "19X19 (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 5,
        label: "1\" 25x25(1.6)",
        defaultWeight: 7.0,
        defaultSd: 4500,
        matchKeys: [
          "1\" 25X25(1.6)",
          "1\" 25X25 (1.6)",
          "25X25(1.6)",
          "25X25 (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 9,
        label: "1.25\" 32x32(1.6)",
        defaultWeight: 9.0,
        defaultSd: 4000,
        matchKeys: [
          "1.25\" 32X32(1.6)",
          "1.25\" 32X32 (1.6)",
          "1-1/4\" 32X32(1.6)",
          "32X32(1.6)",
          "32X32 (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 15,
        label: "1.5\" 38x38(2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: [
          "1.5\" 38X38(2.0)",
          "1.5\" 38X38 (2.0)",
          "1-1/2\" 38X38(2.0)",
          "38X38(2.0)",
          "38X38 (2.0)",
        ],
      ),
      SampleRateSpec(
        id: 20,
        label: "2\" 50x50(1.6)",
        defaultWeight: 15.0,
        defaultSd: 3500,
        matchKeys: [
          "2\" 50X50(1.6)",
          "2\" 50X50 (1.6)",
          "50X50(1.6)",
          "50X50 (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 21,
        label: "2\" 50x50(2.0)",
        defaultWeight: 18.0,
        defaultSd: 3500,
        matchKeys: [
          "2\" 50X50(2.0)",
          "2\" 50X50 (2.0)",
          "50X50(2.0)",
          "50X50 (2.0)",
        ],
      ),
      SampleRateSpec(
        id: 25,
        label: "2.5\" 60x60(2.0)",
        defaultWeight: 22.0,
        defaultSd: 4000,
        matchKeys: [
          "2.5\" 60X60(2.0)",
          "2.5\" 60X60 (2.0)",
          "2-1/2\" 60X60(2.0)",
          "60X60(2.0)",
          "60X60 (2.0)",
        ],
      ),
      SampleRateSpec(
        id: 28,
        label: "3\" 72x72(2.0)",
        defaultWeight: 27.0,
        defaultSd: 4500,
        matchKeys: [
          "3\" 72X72(2.0)",
          "3\" 72X72 (2.0)",
          "72X72(2.0)",
          "72X72 (2.0)",
        ],
      ),
      SampleRateSpec(
        id: 32,
        label: "1.5\"x 0.75\" 40x20 (1.6)",
        defaultWeight: 9.0,
        defaultSd: 5000,
        matchKeys: [
          "1.5\"X 0.75\" 40X20 (1.6)",
          "1.5\"X0.75\" 40X20 (1.6)",
          "1.5\"X0.75\" 40X20(1.6)",
          "40X20 (1.6)",
          "40X20(1.6)",
        ],
      ),
      SampleRateSpec(
        id: 37,
        label: "2\"x1\" 50x25 (2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: [
          "2\"X1\" 50X25 (2.0)",
          "2\"X1\" 50X25(2.0)",
          "50X25 (2.0)",
          "50X25(2.0)",
        ],
      ),
      SampleRateSpec(
        id: 48,
        label: "3\"x1\" 75x25 (2.0)",
        defaultWeight: 17.0,
        defaultSd: 4500,
        matchKeys: [
          "3\"X1\" 75X25 (2.0)",
          "3\"X1\" 75X25(2.0)",
          "75X25 (2.0)",
          "75X25(2.0)",
        ],
      ),
      SampleRateSpec(
        id: 52,
        label: "3\"x1.5\" 80x40 (2.0)",
        defaultWeight: 22.0,
        defaultSd: 4000,
        matchKeys: [
          "3\"X1.5\" 80X40 (2.0)",
          "3\"X1.5\" 80X40(2.0)",
          "80X40 (2.0)",
          "80X40(2.0)",
        ],
      ),
      SampleRateSpec(
        id: 56,
        label: "4\"x2\" 96x48 (2.0)",
        defaultWeight: 27.0,
        defaultSd: 4500,
        matchKeys: [
          "4\"X2\" 96X48 (2.0)",
          "4\"X2\" 96X48(2.0)",
          "96X48 (2.0)",
          "96X48(2.0)",
        ],
      ),
      SampleRateSpec(
        id: 60,
        label: "0.75\" 25OD (1.6)",
        defaultWeight: 5.0,
        defaultSd: 6500,
        matchKeys: [
          "0.75\" 25OD (1.6)",
          "0.75\" 25OD(1.6)",
          "25OD (1.6)",
          "25OD(1.6)",
          "3/4\" 25OD (1.6)",
          "25.4OD (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 63,
        label: "1\" 33.4OD (1.6)",
        defaultWeight: 7.0,
        defaultSd: 4500,
        matchKeys: [
          "1\" 33.4OD (1.6)",
          "1\" 33.4OD(1.6)",
          "33.4OD (1.6)",
          "33.4OD(1.6)",
          "1\" 32OD (1.6)",
          "32OD (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 67,
        label: "1.25\" 41OD (1.6)",
        defaultWeight: 9.0,
        defaultSd: 4500,
        matchKeys: [
          "1.25\" 41OD (1.6)",
          "1.25\" 41OD(1.6)",
          "41OD (1.6)",
          "41OD(1.6)",
          "41.3OD (1.6)",
        ],
      ),
      SampleRateSpec(
        id: 73,
        label: "1.5\" 48.3OD (2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: [
          "1.5\" 48.3OD (2.0)",
          "1.5\" 48.3OD(2.0)",
          "48.3OD (2.0)",
          "48.3OD(2.0)",
          "48OD (2.0)",
        ],
      ),
      SampleRateSpec(
        id: 77,
        label: "2\" 60.3OD (1.6)",
        defaultWeight: 14.0,
        defaultSd: 3500,
        matchKeys: [
          "2\" 60.3OD (1.6)",
          "2\" 60.3OD(1.6)",
          "60.3OD (1.6)",
          "60.3OD(1.6)",
          "60OD (1.6)",
        ],
      ),
    ],
    "MS Angle": [
      SampleRateSpec(
        label: "25x3",
        defaultWeight: 6.2,
        defaultSd: 3000,
        matchKeys: ["25X3", "1\" 25X3", "25 X 3", "25*3", "ISA 25X3", "25X25X3"],
      ),
      SampleRateSpec(
        label: "25x5",
        defaultWeight: 10.0,
        defaultSd: 3000,
        matchKeys: ["25X5", "1\" 25X5", "25 X 5", "25*5", "ISA 25X5", "25X25X5"],
      ),
      SampleRateSpec(
        label: "32x3",
        defaultWeight: 8.5,
        defaultSd: 2500,
        matchKeys: ["32X3", "1.25\" 32X3", "32 X 3", "32*3", "ISA 32X3", "32X32X3"],
      ),
      SampleRateSpec(
        label: "35x5",
        defaultWeight: 14.5,
        defaultSd: 2000,
        matchKeys: ["35X5", "1.25\" 35X5", "35 X 5", "35*5", "ISA 35X5", "35X35X5"],
      ),
      SampleRateSpec(
        label: "40x4",
        defaultWeight: 14.5,
        defaultSd: 1500,
        matchKeys: ["40X4", "1.5\" 40X4", "40 X 4", "40*4", "ISA 40X4", "40X40X4"],
      ),
      SampleRateSpec(
        label: "40x5",
        defaultWeight: 18.0,
        defaultSd: 1000,
        matchKeys: ["40X5", "1.5\" 40X5", "40 X 5", "40*5", "ISA 40X5", "40X40X5"],
      ),
      SampleRateSpec(
        label: "50x5",
        defaultWeight: 21.5,
        defaultSd: 0,
        matchKeys: ["50X5", "2\" 50X5", "50 X 5", "50*5", "ISA 50X5", "50X50X5"],
      ),
      SampleRateSpec(
        label: "65x5",
        defaultWeight: 30.0,
        defaultSd: 0,
        matchKeys: ["65X5", "2.5\" 65X5", "65 X 5", "65*5", "ISA 65X5", "65X65X5"],
      ),
    ],
    "MS Channel": [
      SampleRateSpec(
        label: "70x35 (3\"X1.5\")",
        defaultWeight: 22.0,
        defaultSd: 2500,
        matchKeys: ["70X35", "C 70X35", "70X35 (3\"X1.5\")", "70 X 35", "MC 70X35", "ISMC 70X35"],
      ),
      SampleRateSpec(
        label: "75x40 (3\"X1.5\")",
        defaultWeight: 36.0,
        defaultSd: 1500,
        matchKeys: ["75X40", "C 75X40", "75X40 (3\"X1.5\")", "75 X 40", "MC 75X40", "ISMC 75X40"],
      ),
      SampleRateSpec(
        label: "100x50 (4\"x 2\")",
        defaultWeight: 56.0,
        defaultSd: 0,
        matchKeys: ["100X50", "C 100X50", "100X50 (4\"X2\")", "100 X 50", "MC 100X50", "ISMC 100X50"],
      ),
    ],
    "Sqr Bar": [
      SampleRateSpec(
        label: "8MM",
        defaultWeight: 0.0,
        defaultSd: 2000,
        matchKeys: ["8MM", "08MM", "8 MM", "08 MM", "SQ 8", "SQ 08", "8"],
      ),
      SampleRateSpec(
        label: "10MM",
        defaultWeight: 0.0,
        defaultSd: 1500,
        matchKeys: ["10MM", "10 MM", "SQ 10", "10"],
      ),
    ],
    "Round Bar": [
      SampleRateSpec(
        label: "10MM",
        defaultWeight: 0.0,
        defaultSd: 1500,
        matchKeys: ["10MM", "10 MM", "RD 10", "10"],
      ),
      SampleRateSpec(
        label: "12MM",
        defaultWeight: 0.0,
        defaultSd: 0,
        matchKeys: ["12MM", "12 MM", "RD 12", "12"],
      ),
      SampleRateSpec(
        label: "16MM",
        defaultWeight: 0.0,
        defaultSd: 0,
        matchKeys: ["16MM", "16 MM", "RD 16", "16"],
      ),
    ],
    "Flats": [
      SampleRateSpec(
        label: "F 25x3",
        defaultWeight: 0.0,
        defaultSd: 2500,
        matchKeys: ["25X3", "F 25X3", "F25X3", "25 X 3", "F 25 X 3", "25*3"],
      ),
      SampleRateSpec(
        label: "F 40x3",
        defaultWeight: 0.0,
        defaultSd: 2000,
        matchKeys: ["40X3", "F 40X3", "F40X3", "40 X 3", "F 40 X 3", "40*3"],
      ),
      SampleRateSpec(
        label: "F 40x5",
        defaultWeight: 0.0,
        defaultSd: 1000,
        matchKeys: ["40X5", "F 40X5", "F40X5", "40 X 5", "F 40 X 5", "40*5"],
      ),
      SampleRateSpec(
        label: "F 50x5",
        defaultWeight: 0.0,
        defaultSd: 0,
        matchKeys: ["50X5", "F 50X5", "F50X5", "50 X 5", "F 50 X 5", "50*5"],
      ),
    ],
  };

  static String normalizeCategory(String cat) {
    return cat
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .toUpperCase()
        .trim();
  }

  static String cleanSizeForMatch(String s) {
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

  /// Storage key pattern: sample_rate_active_sizes_${category.toLowerCase()}
  /// Kept for legacy fallback compatibility
  static String getStorageKey(String category) {
    final clean = category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'sample_rate_active_sizes_$clean';
  }

  /// Direct Supabase update to set a size's is_sample_rate_active flag
  static Future<bool> setSizeSampleRateActive({
    required int sizeId,
    required bool isActive,
  }) async {
    try {
      await SupabaseService.client
          .from('item_sizes')
          .update({'is_sample_rate_active': isActive})
          .eq('id', sizeId);

      // Sync local in-memory cache in DataRepository
      final List<Map<String, dynamic>> updatedCache =
          List.from(DataRepository.itemSizesNotifier.value);
      final idx = updatedCache.indexWhere((s) => s['id'] == sizeId);
      if (idx >= 0) {
        updatedCache[idx] = {
          ...updatedCache[idx],
          'is_sample_rate_active': isActive,
        };
        DataRepository.itemSizesNotifier.value = updatedCache;
      }
      return true;
    } catch (e) {
      debugPrint("[SampleRateService] Error setting is_sample_rate_active for $sizeId: $e");
      return false;
    }
  }

  /// Direct Supabase query to load active benchmark sizes for any category
  static Future<List<SampleRateSize>> fetchBenchmarkSizesForCategory(
      String category) async {
    final materialId = await resolveOrCreateMaterialId(category);
    try {
      final response = await SupabaseService.client
          .from('item_sizes')
          .select(
              'id, material_id, size_label, unit_weight_kg, size_difference, is_sample_rate_active')
          .eq('material_id', materialId)
          .eq('is_sample_rate_active', true)
          .order('id');
      final list = List<Map<String, dynamic>>.from(response);
      return list.map((m) => SampleRateSize.fromSupabaseMap(m)).toList();
    } catch (e) {
      debugPrint(
          "[SampleRateService] Error fetching benchmark sizes for $category: $e");
      return [];
    }
  }

  /// Persists the active sizes for a given category in SharedPreferences (legacy compatibility).
  static Future<void> saveActiveSizes(
      String category, List<SampleRateSize> sizes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = getStorageKey(category);
      final directKey =
          'sample_rate_active_sizes_${category.trim().toLowerCase()}';
      final List<String> encoded =
          sizes.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(key, encoded);
      if (directKey != key) {
        await prefs.setStringList(directKey, encoded);
      }
    } catch (e) {
      debugPrint(
          "[SampleRateService] Error saving active sizes for $category: $e");
    }
  }

  /// Loads the persisted active sizes for a given category from SharedPreferences.
  static Future<List<SampleRateSize>?> loadActiveSizes(String category) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = getStorageKey(category);
      final directKey =
          'sample_rate_active_sizes_${category.trim().toLowerCase()}';

      var rawList = prefs.getStringList(key);
      rawList ??= prefs.getStringList(directKey);

      if (rawList == null) {
        for (final catName in orderedCategories) {
          if (normalizeCategory(catName) == normalizeCategory(category)) {
            rawList = prefs.getStringList(getStorageKey(catName)) ??
                prefs.getStringList(
                    'sample_rate_active_sizes_${catName.trim().toLowerCase()}');
            if (rawList != null) break;
          }
        }
      }

      if (rawList == null) return null;

      final List<SampleRateSize> sizes = [];
      for (final item in rawList) {
        final trimmed = item.trim();
        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
          try {
            final map = jsonDecode(trimmed) as Map<String, dynamic>;
            sizes.add(SampleRateSize.fromJson(map));
            continue;
          } catch (_) {}
        }
        // Fallback for plain string labels or IDs
        sizes.add(SampleRateSize(trimmed, 0, 0, isCustom: false));
      }
      return sizes;
    } catch (e) {
      debugPrint(
          "[SampleRateService] Error loading active sizes for $category: $e");
      return null;
    }
  }

  /// Clears the persisted active sizes entry in SharedPreferences for a category.
  static Future<void> clearActiveSizes(String category) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = getStorageKey(category);
      final directKey =
          'sample_rate_active_sizes_${category.trim().toLowerCase()}';
      await prefs.remove(key);
      await prefs.remove(directKey);
      for (final catName in orderedCategories) {
        if (normalizeCategory(catName) == normalizeCategory(category)) {
          await prefs.remove(getStorageKey(catName));
          await prefs.remove(
              'sample_rate_active_sizes_${catName.trim().toLowerCase()}');
        }
      }
    } catch (e) {
      debugPrint(
          "[SampleRateService] Error clearing active sizes for $category: $e");
    }
  }

  /// Checks if a category's active sizes differ from the default benchmark specs.
  static bool isCategoryModified(
      String category, List<SampleRateSize> currentSizes) {
    String targetCatName = category;
    for (final catName in orderedCategories) {
      if (normalizeCategory(catName) == normalizeCategory(category)) {
        targetCatName = catName;
        break;
      }
    }
    final specs = benchmarkSpecifications[targetCatName];
    if (specs == null) return false;

    if (currentSizes.length != specs.length) return true;
    if (currentSizes.any((s) => s.isCustom)) return true;

    final specCleanLabels = specs.map((s) => cleanSizeForMatch(s.label)).toSet();
    for (final s in currentSizes) {
      if (!specCleanLabels.contains(cleanSizeForMatch(s.label))) {
        return true;
      }
    }
    return false;
  }

  /// Direct Supabase query to fetch verified item sizes from the `item_sizes` table.
  static Future<List<Map<String, dynamic>>> fetchItemSizesFromSupabase({
    int? materialId,
    bool? isSampleRateActive,
  }) async {
    try {
      var query = SupabaseService.client
          .from('item_sizes')
          .select(
              'id, material_id, size_label, unit_weight_kg, size_difference, is_sample_rate_active');
      if (materialId != null) {
        query = query.eq('material_id', materialId);
      }
      if (isSampleRateActive != null) {
        query = query.eq('is_sample_rate_active', isSampleRateActive);
      }
      final response = await query.order('id').limit(10000);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("[SampleRateService] Supabase fetch error: $e");
      return [];
    }
  }

  /// Computes baseline benchmark categories populated dynamically from `item_sizes`.
  static Future<Map<String, List<SampleRateSize>>> fetchBaselineBenchmarkCategories({
    bool force = false,
  }) async {
    final Map<String, List<SampleRateSize>> grouped = {};

    List<Map<String, dynamic>> supabaseItemSizes = [];
    try {
      supabaseItemSizes = await fetchItemSizesFromSupabase();
    } catch (_) {}

    // If direct Supabase fetch succeeded, update DataRepository cache
    if (supabaseItemSizes.isNotEmpty) {
      final List<Map<String, dynamic>> updatedCache = List.from(DataRepository.itemSizesNotifier.value);
      for (final row in supabaseItemSizes) {
        final id = row['id'];
        final idx = updatedCache.indexWhere((item) => item['id'] == id);
        if (idx >= 0) {
          updatedCache[idx] = {...updatedCache[idx], ...row};
        } else {
          updatedCache.add(row);
        }
      }
      DataRepository.itemSizesNotifier.value = updatedCache;
    }

    // Combine raw sizes from Supabase item_sizes, cached notifier, and sheet data
    final cachedSizes = DataRepository.itemSizesNotifier.value;
    final sheetData = await DataRepository.getSheetDataAsync(null, forceRefresh: force);
    final List sheetItems = sheetData['items'] as List? ?? [];

    for (final catName in orderedCategories) {
      final List<String> aliases = categoryAliases[catName] ?? [catName];
      final String normCatName = normalizeCategory(catName);
      final int? matId = categoryToMaterialId[catName];

      final List<Map<String, dynamic>> rawSizes = [];

      // 1. Prioritize direct Supabase item_sizes query results
      if (supabaseItemSizes.isNotEmpty) {
        for (final s in supabaseItemSizes) {
          if (matId != null && s['material_id'] == matId) {
            rawSizes.add(s);
          }
        }
      }

      // 2. Add cached item_sizes
      if (cachedSizes.isNotEmpty) {
        for (final s in cachedSizes) {
          final sMatId = s['material_id'] ?? s['materialId'];
          final String sMatName = (s['material_name'] ?? s['category'] ?? s['item_name'] ?? '').toString();
          final String upperMat = sMatName.toUpperCase().trim();
          final String normMat = normalizeCategory(sMatName);

          bool matchesMatId = matId != null && sMatId == matId;
          bool matchesAlias = aliases.any((a) => a.toUpperCase().trim() == upperMat);
          bool matchesNorm = normMat == normCatName;

          if (matchesMatId || matchesAlias || matchesNorm) {
            if (!rawSizes.any((existing) => existing['id'] != null && existing['id'] == s['id'])) {
              rawSizes.add(s);
            }
          }
        }
      }

      // 3. Add sheet items as fallback
      for (final catItem in sheetItems) {
        final String sheetCatName = (catItem['name'] ?? '').toString();
        final String normSheetCat = normalizeCategory(sheetCatName);
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
          continue;
        }

        bool matchesAlias = aliases.any((a) => a.toUpperCase().trim() == upperSheetCat);
        bool matchesNorm = normSheetCat == normCatName;
        if (matchesAlias || matchesNorm) {
          final List sizesRaw = catItem['sizes'] ?? [];
          for (final sr in sizesRaw) {
            if (sr is Map<String, dynamic>) {
              rawSizes.add(sr);
            } else if (sr is Map) {
              rawSizes.add(Map<String, dynamic>.from(sr));
            }
          }
        }
      }

      final List<SampleRateSize> categorySizes = [];
      final List<SampleRateSpec> specs = benchmarkSpecifications[catName] ?? [];

      for (final spec in specs) {
        num matchedSd = spec.defaultSd;
        num matchedWeight = spec.defaultWeight;
        int? matchedId = spec.id;
        bool foundExactMatch = false;

        // Step 1: Match by exact ID if available
        if (spec.id != null) {
          for (final s in rawSizes) {
            final sId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '');
            if (sId != null && sId == spec.id) {
              matchedId = sId;
              final rawSd = s['size_difference'] ?? s['sd'] ?? s['diffRate'] ?? s['diff_rate'];
              final rawWeight = s['unit_weight_kg'] ?? s['weight'] ?? s['std_weight'] ?? s['std_wt'];
              if (rawSd != null) {
                matchedSd = (rawSd is num) ? rawSd : (num.tryParse(rawSd.toString()) ?? spec.defaultSd);
              }
              if (rawWeight != null) {
                num parsedW = (rawWeight is num) ? rawWeight : (num.tryParse(rawWeight.toString()) ?? 0);
                if (parsedW > 0) matchedWeight = parsedW;
              }
              foundExactMatch = true;
              break;
            }
          }
        }

        // Step 2: Match by exact label or matchKeys if not matched by ID
        if (!foundExactMatch) {
          final String normSpecLabel = cleanSizeForMatch(spec.label);
          final String noSpaceSpecLabel = normSpecLabel.replaceAll(' ', '');

          for (final s in rawSizes) {
            final String rawLabel = (s['size_label'] ?? s['label'] ?? s['size'] ?? '').toString().trim();
            if (rawLabel.isEmpty) continue;
            final String normRaw = cleanSizeForMatch(rawLabel);
            final String noSpaceRaw = normRaw.replaceAll(' ', '');

            bool isExact = normRaw == normSpecLabel || noSpaceRaw == noSpaceSpecLabel;
            bool isKeyMatch = spec.matchKeys.any((k) {
              final String normK = cleanSizeForMatch(k);
              final String noSpaceK = normK.replaceAll(' ', '');
              return normRaw == normK || noSpaceRaw == noSpaceK;
            });

            if (isExact || isKeyMatch) {
              matchedId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '');
              final rawSd = s['size_difference'] ?? s['sd'] ?? s['diffRate'] ?? s['diff_rate'];
              final rawWeight = s['unit_weight_kg'] ?? s['weight'] ?? s['std_weight'] ?? s['std_wt'];
              if (rawSd != null) {
                matchedSd = (rawSd is num) ? rawSd : (num.tryParse(rawSd.toString()) ?? spec.defaultSd);
              }
              if (rawWeight != null) {
                num parsedW = (rawWeight is num) ? rawWeight : (num.tryParse(rawWeight.toString()) ?? 0);
                if (parsedW > 0) matchedWeight = parsedW;
              }
              foundExactMatch = true;
              break;
            }
          }
        }

        if (matchedWeight == 0 && spec.defaultWeight > 0) {
          matchedWeight = spec.defaultWeight;
        }

        categorySizes.add(SampleRateSize(
          spec.label,
          matchedSd,
          matchedWeight,
          id: matchedId,
          materialId: matId,
          isCustom: false,
          isSampleRateActive: true,
        ));
      }

      grouped[catName] = categorySizes;
    }

    return grouped;
  }

  /// Storage key for custom user-created categories list
  static const String customCategoriesStorageKey = 'sample_rate_custom_categories';

  /// Saves the list of custom created category names to SharedPreferences.
  static Future<void> saveCustomCategories(List<String> categories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(customCategoriesStorageKey, categories);
    } catch (e) {
      debugPrint("[SampleRateService] Error saving custom categories: $e");
    }
  }

  /// Loads custom created category names from SharedPreferences.
  static Future<List<String>> loadCustomCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(customCategoriesStorageKey) ?? [];
    } catch (e) {
      debugPrint("[SampleRateService] Error loading custom categories: $e");
      return [];
    }
  }

  /// Checks whether a category is one of the protected 6 core baseline categories.
  static bool isCoreCategory(String category) {
    final norm = normalizeCategory(category);
    return orderedCategories.any((c) => normalizeCategory(c) == norm);
  }

  /// Removes a custom category from SharedPreferences and clears its saved sizes.
  static Future<void> removeCustomCategory(String category) async {
    try {
      final customCats = await loadCustomCategories();
      final norm = normalizeCategory(category);
      customCats.removeWhere((c) => normalizeCategory(c) == norm);
      await saveCustomCategories(customCats);
      await clearActiveSizes(category);
    } catch (e) {
      debugPrint("[SampleRateService] Error removing custom category: $e");
    }
  }

  /// Clears all custom categories.
  static Future<void> clearAllCustomCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(customCategoriesStorageKey);
    } catch (e) {
      debugPrint("[SampleRateService] Error clearing custom categories: $e");
    }
  }

  /// Resolves an existing material ID for a category or creates a new entry in the `materials` table.
  static Future<int> resolveOrCreateMaterialId(String categoryName) async {
    final cleanCat = categoryName.trim();
    if (categoryToMaterialId.containsKey(cleanCat)) {
      return categoryToMaterialId[cleanCat]!;
    }
    for (final entry in categoryToMaterialId.entries) {
      if (normalizeCategory(entry.key) == normalizeCategory(cleanCat)) {
        return entry.value;
      }
    }

    try {
      // 1. Query materials table for matching item_name
      final response = await SupabaseService.client
          .from('materials')
          .select('id, item_name')
          .limit(100);

      final List materialsList = response as List? ?? [];
      for (final m in materialsList) {
        final name = (m['item_name'] ?? '').toString().trim();
        if (normalizeCategory(name) == normalizeCategory(cleanCat) ||
            name.toUpperCase() == cleanCat.toUpperCase()) {
          final id = m['id'];
          if (id is int) return id;
          if (id != null) return int.tryParse(id.toString()) ?? 1;
        }
      }

      // 2. If not found, insert new material
      final inserted = await SupabaseService.client
          .from('materials')
          .insert({'item_name': cleanCat})
          .select('id')
          .maybeSingle();

      if (inserted != null && inserted['id'] != null) {
        final id = inserted['id'];
        return (id is int) ? id : (int.tryParse(id.toString()) ?? 1);
      }
    } catch (e) {
      debugPrint("[SampleRateService] resolveOrCreateMaterialId error: $e");
    }

    return 1;
  }

  /// Inserts a new item size into Supabase `item_sizes` table with is_sample_rate_active = true and syncs the cache.
  static Future<SampleRateSize> insertNewItemSize({
    required String category,
    required String sizeLabel,
    required double weight,
    required double sd,
  }) async {
    final String cleanLabel = sizeLabel.trim();
    int materialId = 1;

    try {
      materialId = await resolveOrCreateMaterialId(category);
    } catch (e) {
      debugPrint("[SampleRateService] Material ID resolution failed: $e");
    }

    int? newId;
    try {
      final insertPayload = {
        'material_id': materialId,
        'size_label': cleanLabel,
        'unit_weight_kg': weight,
        'size_difference': sd,
        'current_stock_in': 0.0,
        'is_sample_rate_active': true,
      };

      final response = await SupabaseService.client
          .from('item_sizes')
          .insert(insertPayload)
          .select(
              'id, material_id, size_label, unit_weight_kg, size_difference, is_sample_rate_active')
          .maybeSingle();

      if (response != null) {
        newId = response['id'] is int
            ? response['id']
            : int.tryParse(response['id']?.toString() ?? '');
        final List<Map<String, dynamic>> updatedCache =
            List.from(DataRepository.itemSizesNotifier.value);
        updatedCache.add(Map<String, dynamic>.from(response));
        DataRepository.itemSizesNotifier.value = updatedCache;
      } else {
        final List<Map<String, dynamic>> updatedCache =
            List.from(DataRepository.itemSizesNotifier.value);
        updatedCache.add({
          'id': null,
          'material_id': materialId,
          'material_name': category,
          'size_label': cleanLabel,
          'unit_weight_kg': weight,
          'size_difference': sd,
          'is_sample_rate_active': true,
        });
        DataRepository.itemSizesNotifier.value = updatedCache;
      }
    } catch (e) {
      debugPrint("[SampleRateService] Supabase insert error on item_sizes: $e");
      final List<Map<String, dynamic>> updatedCache =
          List.from(DataRepository.itemSizesNotifier.value);
      updatedCache.add({
        'id': null,
        'material_id': materialId,
        'material_name': category,
        'size_label': cleanLabel,
        'unit_weight_kg': weight,
        'size_difference': sd,
        'is_sample_rate_active': true,
      });
      DataRepository.itemSizesNotifier.value = updatedCache;
    }

    return SampleRateSize(
      cleanLabel,
      sd,
      weight,
      id: newId,
      materialId: materialId,
      isCustom: true,
      isSampleRateActive: true,
    );
  }

  /// Resets a category back to default benchmark sizes directly in Supabase.
  static Future<void> resetCategoryToDefaults(String category) async {
    try {
      int materialId = 1;
      try {
        materialId = await resolveOrCreateMaterialId(category);
      } catch (_) {}

      // Find target core category specs if applicable
      String targetCatName = category;
      for (final catName in orderedCategories) {
        if (normalizeCategory(catName) == normalizeCategory(category)) {
          targetCatName = catName;
          break;
        }
      }
      final specs = benchmarkSpecifications[targetCatName] ?? [];
      final defaultIds = specs.map((s) => s.id).whereType<int>().toList();

      // 1. Reset all sizes for this material in Supabase to is_sample_rate_active = false
      await SupabaseService.client
          .from('item_sizes')
          .update({'is_sample_rate_active': false})
          .eq('material_id', materialId);

      // 2. Set default benchmark IDs to is_sample_rate_active = true
      if (defaultIds.isNotEmpty) {
        await SupabaseService.client
            .from('item_sizes')
            .update({'is_sample_rate_active': true})
            .filter('id', 'in', defaultIds);
      } else {
        // Fallback: match by label for categories without hardcoded IDs
        for (final spec in specs) {
          final normSpec = cleanSizeForMatch(spec.label);
          final allSizes = DataRepository.itemSizesNotifier.value;
          for (final s in allSizes) {
            final sMatId = s['material_id'] ?? s['materialId'];
            final sLabel = cleanSizeForMatch((s['size_label'] ?? s['label'] ?? '').toString());
            if (sMatId == materialId && sLabel == normSpec) {
              final sId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '');
              if (sId != null) {
                await setSizeSampleRateActive(sizeId: sId, isActive: true);
              }
            }
          }
        }
      }

      // Update in-memory cache
      final List<Map<String, dynamic>> updatedCache =
          List.from(DataRepository.itemSizesNotifier.value);
      for (int i = 0; i < updatedCache.length; i++) {
        final s = updatedCache[i];
        final sMatId = s['material_id'] ?? s['materialId'];
        if (sMatId == materialId) {
          final sId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '');
          final isDef = defaultIds.contains(sId);
          updatedCache[i] = {
            ...s,
            'is_sample_rate_active': isDef,
          };
        }
      }
      DataRepository.itemSizesNotifier.value = updatedCache;

      // Also clean legacy SharedPreferences
      await clearActiveSizes(category);
    } catch (e) {
      debugPrint(
          "[SampleRateService] Error resetting category $category to defaults: $e");
    }
  }

  /// Resets all categories back to default benchmark specifications.
  static Future<void> resetAllCategoriesToDefaults() async {
    for (final cat in orderedCategories) {
      await resetCategoryToDefaults(cat);
    }
    await clearAllCustomCategories();
  }

  /// Fetches all materials from Supabase `materials` and merges with cached catalogs.
  static Future<List<Map<String, dynamic>>> fetchAllDatabaseMaterials() async {
    final Map<String, Map<String, dynamic>> uniqueMaterials = {};

    // 1. Core baseline categories
    for (final cat in orderedCategories) {
      final int? id = categoryToMaterialId[cat];
      uniqueMaterials[normalizeCategory(cat)] = {
        'id': id,
        'name': cat,
        'item_name': cat,
      };
    }

    // 2. Fetch from Supabase materials table
    try {
      final response = await SupabaseService.client
          .from('materials')
          .select('id, item_name')
          .order('item_name')
          .limit(1000);

      final List materialsList = response as List? ?? [];
      for (final m in materialsList) {
        final name = (m['item_name'] ?? m['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final id = m['id'];
        final int? parsedId =
            (id is int) ? id : (int.tryParse(id?.toString() ?? ''));
        uniqueMaterials[normalizeCategory(name)] = {
          'id': parsedId,
          'name': name,
          'item_name': name,
        };
      }
    } catch (e) {
      debugPrint(
          "[SampleRateService] Error fetching materials from Supabase: $e");
    }

    // 3. Supplement from DataRepository itemSizesNotifier and sheetDataNotifier
    for (final s in DataRepository.itemSizesNotifier.value) {
      final name =
          (s['material_name'] ?? s['category'] ?? s['item_name'] ?? s['name'] ?? '')
              .toString()
              .trim();
      if (name.isNotEmpty &&
          !uniqueMaterials.containsKey(normalizeCategory(name))) {
        final id = s['material_id'] ?? s['materialId'];
        final int? parsedId =
            (id is int) ? id : (int.tryParse(id?.toString() ?? ''));
        uniqueMaterials[normalizeCategory(name)] = {
          'id': parsedId,
          'name': name,
          'item_name': name,
        };
      }
    }

    final sheetItems =
        DataRepository.sheetDataNotifier.value['items'] as List? ?? [];
    for (final catItem in sheetItems) {
      final name = (catItem['name'] ?? catItem['item_name'] ?? '').toString().trim();
      if (name.isNotEmpty &&
          !uniqueMaterials.containsKey(normalizeCategory(name))) {
        uniqueMaterials[normalizeCategory(name)] = {
          'id': null,
          'name': name,
          'item_name': name,
        };
      }
    }

    final result = uniqueMaterials.values.toList();
    result.sort((a, b) => (a['name'] ?? a['item_name'] ?? '')
        .toString()
        .compareTo((b['name'] ?? b['item_name'] ?? '').toString()));
    return result;
  }

  /// Fetches all sizes for a given material from Supabase and in-memory caches.
  static Future<List<SampleRateSize>> fetchSizesForMaterial({
    int? materialId,
    String? categoryName,
  }) async {
    final Map<String, SampleRateSize> uniqueSizes = {};
    final String normCat =
        categoryName != null ? normalizeCategory(categoryName) : '';

    // 1. Direct Supabase query on item_sizes if materialId is available
    if (materialId != null) {
      try {
        final response = await SupabaseService.client
            .from('item_sizes')
            .select(
                'id, material_id, size_label, unit_weight_kg, size_difference, is_sample_rate_active')
            .eq('material_id', materialId)
            .order('size_label')
            .limit(1000);

        final List sizesList = response as List? ?? [];
        for (final s in sizesList) {
          final label = (s['size_label'] ?? '').toString().trim();
          if (label.isEmpty) continue;
          final sId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '');
          final sd = (s['size_difference'] is num)
              ? s['size_difference']
              : (num.tryParse(s['size_difference']?.toString() ?? '0') ?? 0);
          final w = (s['unit_weight_kg'] is num)
              ? s['unit_weight_kg']
              : (num.tryParse(s['unit_weight_kg']?.toString() ?? '0') ?? 0);
          final isAct = s['is_sample_rate_active'] == true;

          final cleanKey = cleanSizeForMatch(label);
          uniqueSizes[cleanKey] = SampleRateSize(
            label,
            sd,
            w,
            id: sId,
            materialId: materialId,
            isCustom: true,
            isSampleRateActive: isAct,
          );
        }
      } catch (e) {
        debugPrint(
            "[SampleRateService] Error fetching sizes for material $materialId: $e");
      }
    }

    // 2. Search DataRepository itemSizesNotifier cache
    for (final s in DataRepository.itemSizesNotifier.value) {
      final sMatId = s['material_id'] ?? s['materialId'];
      final sMatName =
          (s['material_name'] ?? s['category'] ?? s['item_name'] ?? '')
              .toString()
              .trim();

      bool match = (materialId != null && sMatId == materialId) ||
          (normCat.isNotEmpty && normalizeCategory(sMatName) == normCat);

      if (match) {
        final label =
            (s['size_label'] ?? s['label'] ?? s['size'] ?? '').toString().trim();
        if (label.isNotEmpty) {
          final cleanKey = cleanSizeForMatch(label);
          if (!uniqueSizes.containsKey(cleanKey)) {
            final sId = s['id'] is int ? s['id'] as int : int.tryParse(s['id']?.toString() ?? '');
            final parsedMatId =
                sMatId is int ? sMatId as int : int.tryParse(sMatId?.toString() ?? '');
            final sd = (s['size_difference'] ?? s['sd'] ?? s['diffRate'] ?? 0);
            final num parsedSd =
                (sd is num) ? sd : (num.tryParse(sd.toString()) ?? 0);
            final w =
                (s['unit_weight_kg'] ?? s['weight'] ?? s['std_weight'] ?? 0);
            final num parsedW =
                (w is num) ? w : (num.tryParse(w.toString()) ?? 0);
            final bool isAct = s['is_sample_rate_active'] == true;
            uniqueSizes[cleanKey] = SampleRateSize(
              label,
              parsedSd,
              parsedW,
              id: sId,
              materialId: parsedMatId,
              isCustom: true,
              isSampleRateActive: isAct,
            );
          }
        }
      }
    }

    // 3. Search DataRepository sheetDataNotifier cache
    if (categoryName != null) {
      final sheetItems =
          DataRepository.sheetDataNotifier.value['items'] as List? ?? [];
      for (final catItem in sheetItems) {
        final sheetName = (catItem['name'] ?? '').toString().trim();
        if (normalizeCategory(sheetName) == normCat) {
          final List sizesRaw = catItem['sizes'] ?? [];
          for (final sr in sizesRaw) {
            final label =
                (sr['size_label'] ?? sr['label'] ?? sr['size'] ?? '')
                    .toString()
                    .trim();
            if (label.isNotEmpty) {
              final cleanKey = cleanSizeForMatch(label);
              if (!uniqueSizes.containsKey(cleanKey)) {
                final sId = sr['id'] is int ? sr['id'] as int : int.tryParse(sr['id']?.toString() ?? '');
                final sd =
                    sr['size_difference'] ?? sr['sd'] ?? sr['diffRate'] ?? 0;
                final num parsedSd =
                    (sd is num) ? sd : (num.tryParse(sd.toString()) ?? 0);
                final w = sr['unit_weight_kg'] ??
                    sr['weight'] ??
                    sr['std_weight'] ??
                    0;
                final num parsedW =
                    (w is num) ? w : (num.tryParse(w.toString()) ?? 0);
                uniqueSizes[cleanKey] = SampleRateSize(
                  label,
                  parsedSd,
                  parsedW,
                  id: sId,
                  materialId: materialId,
                  isCustom: true,
                  isSampleRateActive: sr['is_sample_rate_active'] == true,
                );
              }
            }
          }
        }
      }
    }

    final list = uniqueSizes.values.toList();
    list.sort((a, b) => SortingUtils.compareSizes(a.label, b.label));
    return list;
  }

  /// Fetches and computes active sample rate categories from Supabase database synchronization.
  static Future<Map<String, List<SampleRateSize>>> fetchSampleRateCategories({
    bool force = false,
  }) async {
    final Map<String, List<SampleRateSize>> grouped = {};

    // 1. Fetch all item_sizes marked as is_sample_rate_active = true from Supabase
    List<Map<String, dynamic>> activeRows = [];
    try {
      activeRows = await fetchItemSizesFromSupabase(isSampleRateActive: true);
    } catch (_) {}

    // Fallback to cache if fetch returned empty
    if (activeRows.isEmpty && DataRepository.itemSizesNotifier.value.isNotEmpty) {
      activeRows = DataRepository.itemSizesNotifier.value
          .where((s) => s['is_sample_rate_active'] == true)
          .toList();
    }

    // 2. Fetch baseline specifications for fallback matching
    final baselineGrouped = await fetchBaselineBenchmarkCategories(force: force);
    final customCats = await loadCustomCategories();

    final allCategories = [...orderedCategories];
    for (final c in customCats) {
      if (!allCategories.any((cat) => normalizeCategory(cat) == normalizeCategory(c))) {
        allCategories.add(c);
      }
    }

    // Include custom categories from active database materials
    for (final row in activeRows) {
      final matId = row['material_id'] as int?;
      final matName = matId != null ? (DataRepository.materialIdToNameMap[matId] ?? '') : '';
      if (matName.isNotEmpty &&
          !allCategories.any((c) => normalizeCategory(c) == normalizeCategory(matName))) {
        allCategories.add(matName);
      }
    }

    for (final catName in allCategories) {
      final normCat = normalizeCategory(catName);
      final int? matId = categoryToMaterialId[catName];
      final List<SampleRateSpec> specs = benchmarkSpecifications[catName] ?? [];
      final Set<String> benchmarkCleanLabels =
          specs.map((s) => cleanSizeForMatch(s.label)).toSet();

      // Find active rows matching this category
      final matchingRows = activeRows.where((row) {
        final rowMatId = row['material_id'];
        final rowMatName = (row['material_name'] ??
                row['category'] ??
                (rowMatId is int ? DataRepository.materialIdToNameMap[rowMatId] : '') ??
                '')
            .toString();
        bool matchId = matId != null && rowMatId == matId;
        bool matchName = rowMatName.isNotEmpty && normalizeCategory(rowMatName) == normCat;
        return matchId || matchName;
      }).toList();

      if (matchingRows.isNotEmpty) {
        final List<SampleRateSize> catActiveSizes = [];
        for (final row in matchingRows) {
          final label = (row['size_label'] ?? row['label'] ?? '').toString().trim();
          if (label.isEmpty) continue;
          final sId = row['id'] is int ? row['id'] as int : int.tryParse(row['id']?.toString() ?? '');
          final rowMatId = row['material_id'] is int
              ? row['material_id'] as int
              : int.tryParse(row['material_id']?.toString() ?? '');
          final sd = (row['size_difference'] is num)
              ? row['size_difference']
              : (num.tryParse(row['size_difference']?.toString() ?? '0') ?? 0);
          final w = (row['unit_weight_kg'] is num)
              ? row['unit_weight_kg']
              : (num.tryParse(row['unit_weight_kg']?.toString() ?? '0') ?? 0);

          final cleanLabel = cleanSizeForMatch(label);
          final bool isCustom = !benchmarkCleanLabels.contains(cleanLabel);

          catActiveSizes.add(SampleRateSize(
            label,
            sd,
            w,
            id: sId,
            materialId: rowMatId ?? matId,
            isCustom: isCustom,
            isSampleRateActive: true,
          ));
        }
        grouped[catName] = catActiveSizes;
      } else {
        // Check legacy SharedPreferences or fallback to baseline
        final persisted = await loadActiveSizes(catName);
        if (persisted != null) {
          final baselineList = baselineGrouped[catName] ?? [];
          final reconciledList = <SampleRateSize>[];

          for (final pSize in persisted) {
            final cleanP = cleanSizeForMatch(pSize.label);
            final matchingBaseline = baselineList.where(
                (b) => cleanSizeForMatch(b.label) == cleanP).firstOrNull;

            if (matchingBaseline != null) {
              reconciledList.add(SampleRateSize(
                matchingBaseline.label,
                pSize.sd != 0 && pSize.isCustom ? pSize.sd : matchingBaseline.sd,
                matchingBaseline.weight > 0 ? matchingBaseline.weight : pSize.weight,
                id: matchingBaseline.id ?? pSize.id,
                materialId: matchingBaseline.materialId ?? pSize.materialId,
                isCustom: false,
                isSampleRateActive: true,
              ));
            } else {
              reconciledList.add(pSize.copyWith(isCustom: true, isSampleRateActive: true));
            }
          }
          grouped[catName] = reconciledList;
        } else {
          grouped[catName] = baselineGrouped[catName] ?? [];
        }
      }
    }

    return grouped;
  }
}
