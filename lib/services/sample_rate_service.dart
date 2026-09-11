import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
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
        .replaceAll(' (', '(')
        .replaceAll('( ', '(')
        .replaceAll(' )', ')')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  /// Direct Supabase query to fetch verified item sizes from the `item_sizes` table.
  static Future<List<Map<String, dynamic>>> fetchItemSizesFromSupabase({
    int? materialId,
  }) async {
    try {
      var query = SupabaseService.client
          .from('item_sizes')
          .select('id, material_id, size_label, unit_weight_kg, size_difference');
      if (materialId != null) {
        query = query.eq('material_id', materialId);
      }
      final response = await query.order('id').limit(10000);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("[SampleRateService] Supabase fetch error: $e");
      return [];
    }
  }

  /// Fetches and computes benchmark categories populated dynamically from `item_sizes`.
  static Future<Map<String, List<SampleRateSize>>> fetchSampleRateCategories({
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
        bool foundExactMatch = false;

        // Step 1: Match by exact ID if available
        if (spec.id != null) {
          for (final s in rawSizes) {
            final sId = s['id'];
            if (sId != null && sId == spec.id) {
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

        categorySizes.add(SampleRateSize(spec.label, matchedSd, matchedWeight));
      }

      grouped[catName] = categorySizes;
    }

    return grouped;
  }
}
