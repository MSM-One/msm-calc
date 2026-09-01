import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/data_repository.dart';
import '../models/stock_models.dart';
import '../models/user_model.dart';
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
    final Map<String, ItemVariant> uniqueSizesMap = {};

    for (var item in inventory) {
      final key = '${item.itemName}|${item.size}';
      if (!uniqueSizesMap.containsKey(key)) {
        uniqueSizesMap[key] = ItemVariant(
          itemName: item.itemName,
          category: item.category,
          size: item.size,
          currentStockMT: item.currentStockMT,
          minStock: item.minStock,
          location: item.location,
          yardTotal: item.yardTotal,
          factoryTotal: item.factoryTotal,
        );
      } else {
        final existing = uniqueSizesMap[key]!;
        uniqueSizesMap[key] = ItemVariant(
          itemName: existing.itemName,
          category: existing.category,
          size: existing.size,
          currentStockMT: existing.currentStockMT + item.currentStockMT,
          minStock: existing.minStock,
          location:
              existing.location == item.location ? existing.location : 'ALL',
          yardTotal: existing.yardTotal + item.yardTotal,
          factoryTotal: existing.factoryTotal + item.factoryTotal,
        );
      }
    }

    final List<ItemVariant> result = uniqueSizesMap.values
        .where((item) => item.currentStockMT <= item.minStock)
        .toList();

    result.sort((a, b) {
      int catComp = SortingUtils.compareCategories(a.category, b.category);
      if (catComp != 0) return catComp;
      int qtyComp = b.currentStockMT.compareTo(a.currentStockMT);
      if (qtyComp != 0) return qtyComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });

    return result;
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
    "Heavy Structure ISMB",
    "Barbed Wire",
    "GATE Channel",
    "ERW Pipe",
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

  static const Map<String, List<String>> _sampleRateRequiredSizes = {
    "MS Pipe": [
      '1" 25x25(1.6) 7',
      '1.5" 38x38(1.6) 11',
      '2" 50x50(1.6) 15',
      '2.5" 60x60(2.0) 22',
      '3" 72x72(2.0) 27',
      '60.3OD (2.0)',
      '2"x1" 50x25 (1.6) 11',
      '2.5"x1.5" 60x40 (1.6) 14',
      '3"x1.5" 80x40 (1.6) 17',
      '4"x2" 96x48 (1.6) 21',
      '1.25" 41OD (2.0) 11',
      '1.5" 48.3OD (2.0) 13',
    ],
    "MS Angle": [
      "25x3 6.2",
      "35x5 14.5",
      "40x5 18",
      "50x5 21.5",
    ],
    "MS Channel": [
      'C 70x35 (3"X1.5") 22',
      'C 100x50 (4"x 2") 56',
      'C 75x40 (3"X1.5") 36',
    ],
    "Sqr Bar": [
      "10mm",
      "12mm",
    ],
    "Flats": [
      "F 25x5",
      "F 32x5",
    ],
    "Round Bar": [
      "10mm",
      "12mm",
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

  String _stripWeightSuffix(String s) {
    return s.trim().replaceAll(RegExp(r'\s+\d+(?:\.\d+)?$'), '');
  }

  String _normalizeSize(String s) {
    // 1. Replace mathematical cross symbol × and lowercase x with uppercase X, then trim
    String res =
        s.replaceAll('×', 'X').replaceAll('x', 'X').trim().toUpperCase();
    res = res.replaceAll(RegExp(r'\s+'), ' ');
    res = res.replaceAll(RegExp(r'\s*[xX]\s*'), 'X');

    // 2. Strip leading 'C ' or 'F ' prefixes for Channel/Flats matching
    if (res.startsWith('C ') || res.startsWith('F ')) {
      res = res.substring(2).trim();
    } else if ((res.startsWith('C') || res.startsWith('F')) &&
        res.length > 1 &&
        RegExp(r'^\d').hasMatch(res.substring(1))) {
      res = res.substring(1).trim();
    }

    // 3. Robust MM normalization without regex interpolation
    if (res.contains('MM')) {
      final digits = res.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        return '${digits}MM';
      }
    }
    return res;
  }

  bool _isSimpleMmSize(String s) {
    final norm = _normalizeSize(s);
    return RegExp(r'^\d+MM$').hasMatch(norm);
  }

  Future<void> fetchSampleRateData({bool force = false}) async {
    if (_isLoadingSampleRates) return;

    _isLoadingSampleRates = true;

    try {
      debugPrint("DEBUG: [SampleRate-V3] Starting data fetch (force: $force)");
      final data =
          await DataRepository.getSheetDataAsync(null, forceRefresh: force);
      final List items = data['items'] ?? [];

      final Map<String, List<SampleRateSize>> grouped = {};
      final Map<String, Map<String, SampleRateSize>> bestMatches =
          {}; // canonical -> normalizedReq -> SampleRateSize

      for (var catName in _orderedSampleRateCategories) {
        bestMatches[catName] = {};

        final List<String> requiredSizes =
            _sampleRateRequiredSizes[catName] ?? [];
        final List<String> aliases = _sampleRateAliases[catName] ?? [];
        final String normCatName = _normalizeCategory(catName);

        // Filter items that match this category
        final List categoryItemsFromSheet = items.where((catItem) {
          final String sheetCatName = (catItem['name'] ?? '').toString();
          final String normSheetCat = _normalizeCategory(sheetCatName);
          final String upperSheetCat = sheetCatName.toUpperCase().trim();

          bool matchesAlias = aliases
              .any((alias) => alias.toUpperCase().trim() == upperSheetCat);
          bool matchesNorm = normSheetCat == normCatName;

          return matchesAlias || matchesNorm;
        }).toList();

        if (catName == "Sqr Bar" || catName == "Round Bar") {
          final List<String> sheetLabels = [];
          for (var item in categoryItemsFromSheet) {
            final sizes = item['sizes'] as List? ?? [];
            for (var s in sizes) {
              sheetLabels.add((s['label'] ?? '').toString());
            }
          }
          debugPrint(
              "DEBUG: [SampleRate-V3] Available sheet labels for $catName: $sheetLabels");
        }

        for (final reqSize in requiredSizes) {
          final String baseReq = _stripWeightSuffix(reqSize);
          final String normReq = _normalizeSize(baseReq);
          final bool isSimpleMm = _isSimpleMmSize(baseReq);
          final String reqDigits = normReq.replaceAll(RegExp(r'[^0-9]'), '');

          Map<String, dynamic>? bestMatch;
          String? matchedLabel;

          // 1. Try Exact Match
          for (var catItem in categoryItemsFromSheet) {
            final List sizesRaw = catItem['sizes'] ?? [];
            for (var s in sizesRaw) {
              final String label = (s['label'] ?? '').toString();
              final String normLabel = _normalizeSize(label);

              if (normLabel == normReq) {
                // DOUBLE CHECK: If it's an MM size, the digits must match exactly.
                // This prevents 8MM from ever matching 10MM even if normalization fails.
                if (isSimpleMm) {
                  final labelDigits =
                      normLabel.replaceAll(RegExp(r'[^0-9]'), '');
                  if (labelDigits != reqDigits) {
                    debugPrint(
                        "WARNING: [SampleRate-V3] Skipping numeric mismatch: '$label' for requirement '$reqSize'");
                    continue;
                  }
                }

                bestMatch = s;
                matchedLabel = label;
                break;
              }
            }
            if (bestMatch != null) break;
          }

          // 2. Try Contains Fallback (ONLY for complex sizes like Pipe/Angle/Channel)
          if (bestMatch == null && !isSimpleMm) {
            for (var catItem in categoryItemsFromSheet) {
              final List sizesRaw = catItem['sizes'] ?? [];
              for (var s in sizesRaw) {
                final String label = (s['label'] ?? '').toString();
                final String normLabel = _normalizeSize(label);

                if (normLabel.contains(normReq)) {
                  bestMatch = s;
                  matchedLabel = label;
                  break;
                }
              }
              if (bestMatch != null) break;
            }
          }

          if (bestMatch != null) {
            if (catName == "Sqr Bar" || catName == "Round Bar") {
              debugPrint(
                  "DEBUG: [SampleRate-V3] SUCCESS: Matched '$reqSize' -> '$matchedLabel'");
            }

            final rawSd = bestMatch['sd'] ?? bestMatch['size_difference'];
            final rawWeight =
                bestMatch['weight'] ?? bestMatch['unit_weight_kg'];
            final num sd = (rawSd is num)
                ? rawSd
                : (num.tryParse(rawSd?.toString() ?? '') ?? 0);
            final num weight = (rawWeight is num)
                ? rawWeight
                : (num.tryParse(rawWeight?.toString() ?? '') ?? 0);

            bestMatches[catName]![normReq] =
                SampleRateSize(matchedLabel!, sd, weight);
          } else {
            if (catName == "Sqr Bar" || catName == "Round Bar") {
              debugPrint(
                  "DEBUG: [SampleRate-V3] FAILED to match '$reqSize' for $catName");
            }
          }
        }
      }

      // Build the final ordered map
      for (var catName in _orderedSampleRateCategories) {
        final List<SampleRateSize> categorySizes = [];
        final List<String> required = _sampleRateRequiredSizes[catName] ?? [];

        for (final req in required) {
          final String baseReq = _stripWeightSuffix(req);
          final normReq = _normalizeSize(baseReq);
          if (bestMatches[catName]!.containsKey(normReq)) {
            categorySizes.add(bestMatches[catName]![normReq]!);
          } else {
            // If missing, we show the requirement label but marked as missing
            categorySizes.add(SampleRateSize(req, 0, 0, isMissing: true));
          }
        }
        grouped[catName] = categorySizes;
      }

      int totalMatched = 0;
      grouped.forEach((cat, sizes) {
        totalMatched += sizes.where((s) => !s.isMissing).length;
      });
      debugPrint(
          "DEBUG: [SampleRate-V3] Load complete. Total matched rows: $totalMatched");

      _sampleRateCategories = grouped;
      notifyListeners();
    } catch (e, stack) {
      debugPrint("ERROR: [SampleRate-V3] $e");
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
