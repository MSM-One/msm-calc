import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/data_repository.dart';
import '../models/stock_models.dart';
import '../models/user_model.dart';
import '../services/report_calculators.dart';
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

  static const List<String> _orderedSampleRateCategories = [
    "MS Pipe",
    "MS Angle",
    "MS Channel",
    "Sqr Bar",
    "Round Bar",
    "Flats",
  ];

  static const Map<String, List<String>> _sampleRateAliases = {
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

  static const Map<String, List<SampleRateSpec>> _sampleSpecifications = {
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
    "MS Pipe": [
      SampleRateSpec(
        label: "0.75\" 19x19(1.6)",
        defaultWeight: 5.0,
        defaultSd: 6500,
        matchKeys: ["0.75\" 19X19(1.6)", "0.75\" 19X19 (1.6)", "3/4\" 19X19", "19X19(1.6)", "19X19 (1.6)", "19X19", "0.75\" 19X19"],
      ),
      SampleRateSpec(
        label: "1\" 25x25(1.6)",
        defaultWeight: 7.0,
        defaultSd: 4500,
        matchKeys: ["1\" 25X25(1.6)", "1\" 25X25 (1.6)", "25X25(1.6)", "25X25 (1.6)", "25X25", "1\" 25X25"],
      ),
      SampleRateSpec(
        label: "1.25\" 32x32(1.6)",
        defaultWeight: 9.0,
        defaultSd: 4000,
        matchKeys: ["1.25\" 32X32(1.6)", "1.25\" 32X32 (1.6)", "1-1/4\" 32X32", "32X32(1.6)", "32X32 (1.6)", "32X32", "1.25\" 32X32"],
      ),
      SampleRateSpec(
        label: "1.5\" 38x38(2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: ["1.5\" 38X38(2.0)", "1.5\" 38X38 (2.0)", "1-1/2\" 38X38", "38X38(2.0)", "38X38 (2.0)", "38X38", "1.5\" 38X38"],
      ),
      SampleRateSpec(
        label: "2\" 50x50(1.6)",
        defaultWeight: 15.0,
        defaultSd: 3500,
        matchKeys: ["2\" 50X50(1.6)", "2\" 50X50 (1.6)", "50X50(1.6)", "50X50 (1.6)", "2\" 50X50"],
      ),
      SampleRateSpec(
        label: "2\" 50x50(2.0)",
        defaultWeight: 18.0,
        defaultSd: 3500,
        matchKeys: ["2\" 50X50(2.0)", "2\" 50X50 (2.0)", "50X50(2.0)", "50X50 (2.0)"],
      ),
      SampleRateSpec(
        label: "2.5\" 60x60(2.0)",
        defaultWeight: 22.0,
        defaultSd: 4000,
        matchKeys: ["2.5\" 60X60(2.0)", "2.5\" 60X60 (2.0)", "2-1/2\" 60X60", "60X60(2.0)", "60X60 (2.0)", "60X60", "2.5\" 60X60"],
      ),
      SampleRateSpec(
        label: "3\" 72x72(2.0)",
        defaultWeight: 27.0,
        defaultSd: 4500,
        matchKeys: ["3\" 72X72(2.0)", "3\" 72X72 (2.0)", "72X72(2.0)", "72X72 (2.0)", "72X72", "3\" 72X72", "75X75", "80X80"],
      ),
      SampleRateSpec(
        label: "1.5\"x 0.75\" 40x20 (1.6)",
        defaultWeight: 9.0,
        defaultSd: 5000,
        matchKeys: ["1.5\"X 0.75\" 40X20 (1.6)", "1.5\"X0.75\" 40X20 (1.6)", "1.5\"X0.75\" 40X20(1.6)", "40X20 (1.6)", "40X20(1.6)", "40X20", "1.5\"X0.75\""],
      ),
      SampleRateSpec(
        label: "2\"x1\" 50x25 (2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: ["2\"X1\" 50X25 (2.0)", "2\"X1\" 50X25(2.0)", "50X25 (2.0)", "50X25(2.0)", "2\"X1\" 50X25", "50X25", "2\"X1\""],
      ),
      SampleRateSpec(
        label: "3\"x1\" 75x25 (2.0)",
        defaultWeight: 17.0,
        defaultSd: 4500,
        matchKeys: ["3\"X1\" 75X25 (2.0)", "3\"X1\" 75X25(2.0)", "75X25 (2.0)", "75X25(2.0)", "3\"X1\" 75X25", "75X25", "3\"X1\""],
      ),
      SampleRateSpec(
        label: "3\"x1.5\" 80x40 (2.0)",
        defaultWeight: 22.0,
        defaultSd: 4000,
        matchKeys: ["3\"X1.5\" 80X40 (2.0)", "3\"X1.5\" 80X40(2.0)", "80X40 (2.0)", "80X40(2.0)", "3\"X1.5\" 80X40", "80X40", "3\"X1.5\""],
      ),
      SampleRateSpec(
        label: "4\"x2\" 96x48 (2.0)",
        defaultWeight: 27.0,
        defaultSd: 4500,
        matchKeys: ["4\"X2\" 96X48 (2.0)", "4\"X2\" 96X48(2.0)", "96X48 (2.0)", "96X48(2.0)", "4\"X2\" 96X48", "96X48", "4\"X2\"", "100X50"],
      ),
      SampleRateSpec(
        label: "0.75\" 25OD (1.6)",
        defaultWeight: 5.0,
        defaultSd: 6500,
        matchKeys: ["0.75\" 25OD (1.6)", "0.75\" 25OD(1.6)", "25OD (1.6)", "25OD(1.6)", "25OD", "0.75\" 25OD", "3/4\" 25OD", "25.4OD"],
      ),
      SampleRateSpec(
        label: "1\" 33.4OD (1.6)",
        defaultWeight: 7.0,
        defaultSd: 4500,
        matchKeys: ["1\" 33.4OD (1.6)", "1\" 33.4OD(1.6)", "1\" 32OD (1.6)", "33.4OD (1.6)", "33.4OD(1.6)", "33.4OD", "1\" 33.4OD", "32OD"],
      ),
      SampleRateSpec(
        label: "1.25\" 41OD (1.6)",
        defaultWeight: 9.0,
        defaultSd: 4500,
        matchKeys: ["1.25\" 41OD (1.6)", "1.25\" 41OD(1.6)", "41OD (1.6)", "41OD(1.6)", "1.25\" 41OD", "41OD", "41.3OD"],
      ),
      SampleRateSpec(
        label: "1.5\" 48.3OD (2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: ["1.5\" 48.3OD (2.0)", "1.5\" 48.3OD(2.0)", "48.3OD (2.0)", "48.3OD(2.0)", "1.5\" 48.3OD", "48.3OD", "48OD"],
      ),
      SampleRateSpec(
        label: "2\" 60.3OD (1.6)",
        defaultWeight: 14.0,
        defaultSd: 3500,
        matchKeys: ["2\" 60.3OD (1.6)", "2\" 60.3OD(1.6)", "60.3OD (1.6)", "60.3OD(1.6)", "2\" 60.3OD", "60.3OD", "60OD"],
      ),
    ],
  };

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

  String _normalizeSize(String s) {
    return _cleanSizeForMatch(s);
  }

  Future<void> fetchSampleRateData({bool force = false}) async {
    if (_isLoadingSampleRates) return;

    _isLoadingSampleRates = true;

    try {
      debugPrint("DEBUG: [SampleRate-Dynamic] Starting dynamic data fetch (force: $force)");
      final data =
          await DataRepository.getSheetDataAsync(null, forceRefresh: force);
      final List items = data['items'] as List? ?? [];

      final Map<String, List<SampleRateSize>> grouped = {};

      for (var catName in _orderedSampleRateCategories) {
        final List<String> aliases = _sampleRateAliases[catName] ?? [];
        final String normCatName = _normalizeCategory(catName);

        // Filter items that match this category
        final List categoryItemsFromSheet = items.where((catItem) {
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

        // Extract all raw sizes for this category from sheet / Supabase
        final List rawSizes = [];
        for (var catItem in categoryItemsFromSheet) {
          final List sizesRaw = catItem['sizes'] ?? [];
          rawSizes.addAll(sizesRaw);
        }

        // Also check DataRepository.itemSizesNotifier (Supabase master table item_sizes)
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

        final List<SampleRateSize> categorySizes = [];
        final List<SampleRateSpec> specs = _sampleSpecifications[catName] ?? [];

        for (var spec in specs) {
          num matchedSd = spec.defaultSd;
          num matchedWeight = spec.defaultWeight;

          for (var s in rawSizes) {
            final String rawLabel =
                (s['size_label'] ?? s['label'] ?? s['size'] ?? '').toString().trim();
            if (rawLabel.isEmpty) continue;
            final String normRaw = _cleanSizeForMatch(rawLabel);
            final String noSpaceRaw = normRaw.replaceAll(' ', '');

            bool isMatch = spec.matchKeys.any((k) {
              final String normK = _cleanSizeForMatch(k);
              final String noSpaceK = normK.replaceAll(' ', '');
              return normRaw == normK ||
                  noSpaceRaw == noSpaceK ||
                  normRaw.startsWith(normK) ||
                  noSpaceRaw.startsWith(noSpaceK) ||
                  normRaw.contains(normK) ||
                  noSpaceRaw.contains(noSpaceK);
            });

            if (isMatch) {
              final rawSd = s['size_difference'] ?? s['sd'] ?? s['diffRate'] ?? s['diff_rate'];
              final rawWeight = s['unit_weight_kg'] ?? s['weight'] ?? s['std_weight'] ?? s['std_wt'];
              if (rawSd != null) {
                matchedSd = (rawSd is num)
                    ? rawSd
                    : (num.tryParse(rawSd.toString()) ?? spec.defaultSd);
              }
              if (rawWeight != null) {
                num parsedW = (rawWeight is num)
                    ? rawWeight
                    : (num.tryParse(rawWeight.toString()) ?? 0);
                if (parsedW > 0) {
                  matchedWeight = parsedW;
                }
              }
              break;
            }
          }

          if (matchedWeight == 0 && spec.defaultWeight > 0) {
            matchedWeight = spec.defaultWeight;
          }

          categorySizes.add(SampleRateSize(spec.label, matchedSd, matchedWeight));
        }

        grouped[catName] = categorySizes;
      }

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
    print('Attempting update: ${user.email}');
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
      print('Server Response: ${response.body}');
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
      print('Error updating user role: $e');
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
