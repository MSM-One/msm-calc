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
        matchKeys: ["25X3", "25 X 3"],
      ),
      SampleRateSpec(
        label: "35x5",
        defaultWeight: 14.5,
        defaultSd: 2000,
        matchKeys: ["35X5", "35 X 5"],
      ),
      SampleRateSpec(
        label: "40x5",
        defaultWeight: 18.0,
        defaultSd: 1000,
        matchKeys: ["40X5", "40 X 5"],
      ),
      SampleRateSpec(
        label: "50x5",
        defaultWeight: 21.5,
        defaultSd: 0,
        matchKeys: ["50X5", "50 X 5"],
      ),
    ],
    "MS Channel": [
      SampleRateSpec(
        label: "70x35 (3\"X1.5\")",
        defaultWeight: 22.0,
        defaultSd: 2500,
        matchKeys: ["70X35", "C 70X35", "70X35 (3\"X1.5\")"],
      ),
      SampleRateSpec(
        label: "75x40 (3\"X1.5\")",
        defaultWeight: 36.0,
        defaultSd: 1500,
        matchKeys: ["75X40", "C 75X40", "75X40 (3\"X1.5\")"],
      ),
      SampleRateSpec(
        label: "100x50 (4\"x 2\")",
        defaultWeight: 56.0,
        defaultSd: 0,
        matchKeys: ["100X50", "C 100X50", "100X50 (4\"X2\")"],
      ),
    ],
    "Sqr Bar": [
      SampleRateSpec(
        label: "10MM",
        defaultWeight: 0.0,
        defaultSd: 1500,
        matchKeys: ["10MM", "10 MM"],
      ),
      SampleRateSpec(
        label: "12MM",
        defaultWeight: 0.0,
        defaultSd: 0,
        matchKeys: ["12MM", "12 MM"],
      ),
    ],
    "Round Bar": [
      SampleRateSpec(
        label: "10MM",
        defaultWeight: 0.0,
        defaultSd: 1500,
        matchKeys: ["10MM", "10 MM"],
      ),
      SampleRateSpec(
        label: "12MM",
        defaultWeight: 0.0,
        defaultSd: 0,
        matchKeys: ["12MM", "12 MM"],
      ),
    ],
    "Flats": [
      SampleRateSpec(
        label: "F 25x5",
        defaultWeight: 0.0,
        defaultSd: 2000,
        matchKeys: ["25X5", "F 25X5", "F25X5"],
      ),
      SampleRateSpec(
        label: "F 32x5",
        defaultWeight: 0.0,
        defaultSd: 1000,
        matchKeys: ["32X5", "F 32X5", "F32X5"],
      ),
    ],
    "MS Pipe": [
      SampleRateSpec(
        label: "1\" 25x25 (1.6)",
        defaultWeight: 7.0,
        defaultSd: 4500,
        matchKeys: ["1\" 25X25", "25X25 (1.6)", "25X25"],
      ),
      SampleRateSpec(
        label: "1.25\" 41OD (2.0)",
        defaultWeight: 11.0,
        defaultSd: 4500,
        matchKeys: ["1.25\" 41OD", "41OD (2.0)", "41OD", "41.3OD"],
      ),
      SampleRateSpec(
        label: "1.5\" 38x38 (1.6)",
        defaultWeight: 11.0,
        defaultSd: 3500,
        matchKeys: ["1.5\" 38X38", "38X38 (1.6)", "38X38"],
      ),
      SampleRateSpec(
        label: "1.5\" 48.3OD (2.0)",
        defaultWeight: 13.0,
        defaultSd: 3500,
        matchKeys: ["1.5\" 48.3OD", "48.3OD (2.0)", "48.3OD", "48OD"],
      ),
      SampleRateSpec(
        label: "2\"x1\" 50x25 (1.6)",
        defaultWeight: 11.0,
        defaultSd: 3500,
        matchKeys: ["2\"X1\" 50X25", "50X25 (1.6)", "50X25", "2\"X1\""],
      ),
      SampleRateSpec(
        label: "2\" 50x50 (1.6)",
        defaultWeight: 15.0,
        defaultSd: 3500,
        matchKeys: ["2\" 50X50", "50X50 (1.6)", "50X50"],
      ),
      SampleRateSpec(
        label: "2\" 60.3OD (2.0)",
        defaultWeight: 17.0,
        defaultSd: 3500,
        matchKeys: ["2\" 60.3OD", "60.3OD (2.0)", "60.3OD", "60OD"],
      ),
      SampleRateSpec(
        label: "2.5\"x1.5\" 60x40 (1.6)",
        defaultWeight: 14.0,
        defaultSd: 3500,
        matchKeys: ["2.5\"X1.5\" 60X40", "60X40 (1.6)", "60X40", "2.5\"X1.5\""],
      ),
      SampleRateSpec(
        label: "2.5\" 60x60 (2.0)",
        defaultWeight: 22.0,
        defaultSd: 4000,
        matchKeys: ["2.5\" 60X60", "60X60 (2.0)", "60X60"],
      ),
      SampleRateSpec(
        label: "3\"x1.5\" 80x40 (1.6)",
        defaultWeight: 17.0,
        defaultSd: 4500,
        matchKeys: ["3\"X1.5\" 80X40", "80X40 (1.6)", "80X40", "3\"X1.5\""],
      ),
      SampleRateSpec(
        label: "3\" 72x72 (2.0)",
        defaultWeight: 27.0,
        defaultSd: 4500,
        matchKeys: ["3\" 72X72", "72X72 (2.0)", "72X72"],
      ),
      SampleRateSpec(
        label: "4\"x2\" 96x48 (1.6)",
        defaultWeight: 21.0,
        defaultSd: 5500,
        matchKeys: ["4\"X2\" 96X48", "96X48 (1.6)", "96X48", "4\"X2\""],
      ),
    ],
  };

  bool _isLoadingSampleRates = false;
  bool get isLoadingSampleRates => _isLoadingSampleRates;

  Map<String, List<Map<String, dynamic>>> _saudaSizesMap = {};
  Map<String, List<Map<String, dynamic>>> get saudaSizesMap => _saudaSizesMap;

  List<String> _saudaItemTypes = [];
  List<String> get saudaItemTypes => _saudaItemTypes;

  double _sheetLoading = 255;
  double get sheetLoading => _sheetLoading;

  double _sheetGst = 0.18;
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

  String _normalizeSize(String s) {
    return s.replaceAll('×', 'X').replaceAll('x', 'X').replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
  }

  Future<void> fetchSampleRateData({bool force = false}) async {
    if (_isLoadingSampleRates) return;

    _isLoadingSampleRates = true;

    try {
      debugPrint("DEBUG: [SampleRate-Dynamic] Starting data fetch (force: $force)");
      final data =
          await DataRepository.getSheetDataAsync(null, forceRefresh: force);
      final List items = data['items'] ?? [];

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

        final List<SampleRateSize> categorySizes = [];
        final List<SampleRateSpec> specs = _sampleSpecifications[catName] ?? [];

        for (var spec in specs) {
          num matchedSd = spec.defaultSd;
          num matchedWeight = spec.defaultWeight;

          for (var s in rawSizes) {
            final String rawLabel =
                (s['label'] ?? s['size'] ?? '').toString().trim();
            if (rawLabel.isEmpty) continue;
            final String normRaw = _normalizeSize(rawLabel);

            bool isMatch = spec.matchKeys.any((k) {
              final String normK = _normalizeSize(k);
              return normRaw == normK ||
                  normRaw.startsWith(normK) ||
                  normRaw.contains(normK);
            });

            if (isMatch) {
              final rawSd = s['sd'] ?? s['size_difference'];
              final rawWeight = s['weight'] ?? s['unit_weight_kg'];
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
          "DEBUG: [SampleRate-Dynamic] Load complete. Strictly filtered sample rows: $totalMatched");

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
