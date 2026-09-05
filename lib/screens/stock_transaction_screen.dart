import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/m_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/data_repository.dart';
import '../services/access_guard.dart';
import '../models/stock_models.dart';
import '../models/permission_model.dart';
import '../constants/app_colors.dart';
import '../utils/steel_helper.dart';
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import '../utils/category_matcher.dart';
import '../services/stock_notifier.dart';
import '../widgets/responsive_size_picker.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_role.dart';
import '../widgets/motion_toast.dart';

class StockTransactionScreen extends StatefulWidget {
  final String? initialType; // 'IN', 'OUT'
  final String? initialItem;
  final String? initialSize;
  const StockTransactionScreen(
      {super.key, this.initialType, this.initialItem, this.initialSize});

  @override
  State<StockTransactionScreen> createState() => _StockTransactionScreenState();
}

class _StockTransactionScreenState extends State<StockTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  String _selectedType = 'IN';
  DateTime _selectedDate = DateTime.now();
  String? _selectedLocation;
  String? _toLocation;

  final TextEditingController _invoiceCtrl = TextEditingController();
  final TextEditingController _lorryCtrl = TextEditingController();
  final TextEditingController _transportCompanyCtrl = TextEditingController();
  final TextEditingController _driverNameCtrl = TextEditingController();
  final TextEditingController _driverPhoneCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  final TextEditingController _handMTCtrl = TextEditingController();
  final TextEditingController _craneMTCtrl = TextEditingController();

  @override
  void dispose() {
    DataRepository.sheetDataNotifier.removeListener(_onSheetDataUpdated);
    DataRepository.itemSizesNotifier.removeListener(_onSheetDataUpdated);
    _invoiceCtrl.dispose();
    _lorryCtrl.dispose();
    _transportCompanyCtrl.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    _remarksCtrl.dispose();
    _handMTCtrl.dispose();
    _craneMTCtrl.dispose();
    for (var item in _items) {
      item.basicRateCtrl.dispose();
      for (var sz in item.sizes) {
        sz.mtCtrl.dispose();
        sz.noteCtrl.dispose();
      }
    }
    super.dispose();
  }

  void _onSheetDataUpdated() {
    if (!mounted) return;
    _refreshMasterItemData();
  }

  List<Map<String, dynamic>> getSizesForCategory(String? selectedCategory) {
    if (selectedCategory == null || selectedCategory.trim().isEmpty) {
      return [];
    }
    final allMasterSizes = DataRepository.itemSizesNotifier.value;

    final availableSizes = allMasterSizes.where((size) {
      return isSizeInCategory(size, selectedCategory);
    }).map((s) {
      String label = (s['label'] ?? s['size_label'] ?? '').toString().trim();
      double extractedW = extractUnitWeight(label);
      label = formatSizeDisplay(selectedCategory, label);
      double sheetSD =
          double.tryParse((s['sd'] ?? s['size_difference'] ?? '0').toString()) ??
              0.0;
      double sheetW =
          double.tryParse((s['weight'] ?? s['unit_weight_kg'] ?? '0').toString()) ??
              0.0;

      double weight = 0.0;
      if (extractedW > 0) {
        weight = extractedW;
      } else if (sheetSD > 0 && sheetSD < 500) {
        weight = sheetSD;
      } else if (sheetW > 0) {
        weight = sheetW;
      }

      return {
        'id': s['id'],
        'material_id': s['material_id'] ?? s['materialId'],
        'label': label,
        'size_label': label,
        'weight': weight,
        'unit_weight_kg': weight,
        'sd': sheetSD,
        'size_difference': sheetSD,
      };
    }).toList();

    if (availableSizes.isEmpty) {
      final fromMaster = _masterItemData[selectedCategory] ?? [];
      if (fromMaster.isNotEmpty) return fromMaster;

      final targetCat = getCanonicalCategory(selectedCategory);
      for (final entry in _masterItemData.entries) {
        if (getCanonicalCategory(entry.key) == targetCat) {
          return entry.value;
        }
      }
    }

    availableSizes.sort((a, b) => SortingUtils.compareSizes(
        a['label']?.toString() ?? '', b['label']?.toString() ?? ''));
    return availableSizes;
  }

  void _refreshMasterItemData() {
    final data = DataRepository.sheetDataNotifier.value;
    final List<dynamic> itemsList = data['items'] ?? [];
    final Map<String, List<Map<String, dynamic>>> tempMap = {};
    for (var item in itemsList) {
      final name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final rawSizes = item['sizes'] as List? ?? [];
      final parsedSizes = rawSizes.map((s) {
        String label = (s['label'] ?? s['size_label'] ?? '').toString().trim();
        double extractedW = extractUnitWeight(label);
        label = formatSizeDisplay(name, label);
        double sheetSD =
            double.tryParse((s['sd'] ?? s['size_difference'] ?? '0').toString()) ??
                0.0;
        double sheetW =
            double.tryParse((s['weight'] ?? s['unit_weight_kg'] ?? '0').toString()) ??
                0.0;

        double weight = 0.0;
        if (extractedW > 0) {
          weight = extractedW;
        } else if (sheetSD > 0 && sheetSD < 500) {
          weight = sheetSD;
        } else if (sheetW > 0) {
          weight = sheetW;
        }

        return {
          'id': s['id'],
          'material_id': s['material_id'] ?? s['materialId'],
          'label': label,
          'size_label': label,
          'weight': weight,
          'unit_weight_kg': weight,
          'sd': sheetSD,
          'size_difference': sheetSD,
        };
      }).toList();
      tempMap[name] = parsedSizes;
    }

    final dynamicCategories = DataRepository.getDynamicCategories();
    for (final cat in dynamicCategories) {
      if (!tempMap.containsKey(cat) || tempMap[cat]!.isEmpty) {
        final sizes = getSizesForCategory(cat);
        if (sizes.isNotEmpty) {
          tempMap[cat] = sizes;
        } else if (!tempMap.containsKey(cat)) {
          tempMap[cat] = [];
        }
      }
    }

    setState(() {
      _masterItemData = tempMap;
      for (var item in _items) {
        if (item.selectedItemName != null) {
          item.availableSizes = getSizesForCategory(item.selectedItemName);
        }
      }
    });
  }

  /// Clears all local UI state — does NOT touch the Google Sheet.
  void _clearForm() {
    setState(() {
      _invoiceCtrl.clear();
      _lorryCtrl.clear();
      _transportCompanyCtrl.clear();
      _driverNameCtrl.clear();
      _driverPhoneCtrl.clear();
      _remarksCtrl.clear();
      _handMTCtrl.clear();
      _craneMTCtrl.clear();
      _selectedLocation = null;
      _toLocation = null;
      _selectedDate = DateTime.now();
      _items.clear();
    });
    MotionToast.show(context, "Form cleared");
  }

  final List<_StockItemBlock> _items = [];
  Map<String, List<Map<String, dynamic>>> _masterItemData = {};
  List<StockTransaction> _allTransactions = [];
  final Map<String, double> _currentStockMap = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType ?? 'IN';
    _refreshMasterItemData();
    _loadMasterData();
    _generateNextBillNo();
    DataRepository.sheetDataNotifier.addListener(_onSheetDataUpdated);
    DataRepository.itemSizesNotifier.addListener(_onSheetDataUpdated);

    if (widget.initialItem != null) {
      final block = _StockItemBlock(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        selectedItemName: widget.initialItem,
        availableSizes: getSizesForCategory(widget.initialItem),
        sizes: [],
      );
      final sizeRow = _StockSizeRow(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString());
      if (widget.initialSize != null) {
        sizeRow.selectedSizeLabel = widget.initialSize;
      }
      block.sizes.add(sizeRow);
      _items.add(block);
    }
  }

  void _generateNextBillNo() {
    final txns = DataRepository.allTransactionsNotifier.value;
    int maxBill = 0;
    for (var tx in txns) {
      if (tx.invoiceNo != null) {
        final strDigits = tx.invoiceNo!.replaceAll(RegExp(r'[^0-9]'), '');
        if (strDigits.isNotEmpty) {
          final parsed = int.tryParse(strDigits);
          if (parsed != null && parsed > maxBill) {
            maxBill = parsed;
          }
        }
      }
    }
    setState(() {
      _invoiceCtrl.text = (maxBill + 1).toString();
    });
  }

  Future<void> _loadMasterData() async {
    try {
      final erpData = await DataRepository.getERPStockAsync(null);
      final rawLocations = erpData['locations'];

      List<Map<String, dynamic>> locationsList = [];
      if (rawLocations is List) {
        for (var loc in rawLocations) {
          if (loc is Map) locationsList.add(Map<String, dynamic>.from(loc));
        }
      } else if (rawLocations is Map) {
        rawLocations.forEach((locName, locData) {
          if (locData is Map) {
            final locMap = Map<String, dynamic>.from(locData);
            locMap['location'] = locName.toString();
            locationsList.add(locMap);
          }
        });
      }

      _currentStockMap.clear();
      for (var loc in locationsList) {
        final locName = _normalizeLocation(loc['location']?.toString());
        final rawItems = loc['items'];

        List<Map<String, dynamic>> itemsList = [];
        if (rawItems is List) {
          for (var item in rawItems) {
            if (item is Map) itemsList.add(Map<String, dynamic>.from(item));
          }
        } else if (rawItems is Map) {
          rawItems.forEach((itemName, itemData) {
            if (itemData is Map) {
              final itemMap = Map<String, dynamic>.from(itemData);
              itemMap['itemName'] = itemName.toString();
              itemsList.add(itemMap);
            }
          });
        }

        for (var item in itemsList) {
          final iName = item['itemName']?.toString() ?? '';
          final rawVariants = item['variants'] ?? item['sizes'];

          List<Map<String, dynamic>> variantsList = [];
          if (rawVariants is List) {
            for (var v in rawVariants) {
              if (v is Map) variantsList.add(Map<String, dynamic>.from(v));
            }
          } else if (rawVariants is Map) {
            rawVariants.forEach((sizeName, sizeData) {
              if (sizeData is Map) {
                final sizeMap = Map<String, dynamic>.from(sizeData);
                sizeMap['size'] = sizeName.toString();
                variantsList.add(sizeMap);
              } else if (sizeData is num) {
                variantsList.add({
                  'size': sizeName.toString(),
                  'qtyMT': sizeData.toDouble()
                });
              }
            });
          }

          for (var v in variantsList) {
            final rawSize = v['size']?.toString() ?? '';
            final qty = (v['qtyMT'] as num?)?.toDouble() ??
                (v['qty'] as num?)?.toDouble() ??
                0.0;
            final normalizedSize = formatSizeDisplay(iName, rawSize);
            _currentStockMap["$iName|$normalizedSize|$locName"] = qty;
          }
        }
      }

      await DataRepository.getSheetDataAsync(null);
      _refreshMasterItemData();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('stock_transactions_v2');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        final all = list.map((e) => StockTransaction.fromJson(e)).toList();
        final lastReset = await DataRepository.getLastResetTimestamp();
        final DateTime resetCutoff = lastReset ?? DateTime(1900);
        _allTransactions =
            all.where((tx) => tx.dateTime.isAfter(resetCutoff)).toList();
        _allTransactions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      }
    } catch (e) {
      debugPrint("Error loading master data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _addItem() {
    _showItemPicker(context, null);
  }

  String _normalizeLocation(String? loc) {
    if (loc == null) return 'Yard Stock';
    final trimmed = loc.trim().toLowerCase();
    if (trimmed.contains('yard') ||
        trimmed.contains('wh') ||
        trimmed.contains('warehouse')) {
      return 'Yard Stock';
    }
    if (trimmed.contains('factory') || trimmed.contains('plant')) {
      return 'Factory Stock';
    }
    return loc;
  }

  double _getAvailableStock(String? item, String? size) {
    if (item == null || size == null) return 0.0;

    final loc = _normalizeLocation(_selectedLocation);
    final normalizedSize = formatSizeDisplay(item, size);
    final key = "$item|$normalizedSize|$loc";

    double available = 0.0;
    if (_currentStockMap.containsKey(key)) {
      available = _currentStockMap[key] ?? 0.0;
    }

    // Fallback/add to inventoryListNotifier
    final variants = DataRepository.inventoryListNotifier.value;
    for (var v in variants) {
      if (v.itemName == item &&
          formatSizeDisplay(item, v.size) == normalizedSize &&
          _normalizeLocation(v.location) == loc) {
        if (available == 0.0) {
          available += v.currentStockMT;
        }
      }
    }
    return available;
  }

  double get _grandTotalMT {
    double total = 0;
    for (var item in _items) {
      for (var size in item.sizes) {
        total += double.tryParse(size.mtCtrl.text) ?? 0;
      }
    }
    return total;
  }

  void _confirmTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      MotionToast.show(context, "Please select a location", isError: true);
      return;
    }
    if (_invoiceCtrl.text.trim().isEmpty) {
      MotionToast.show(context, "Bill/Invoice Number is mandatory",
          isError: true);
      return;
    }

    if (_items.isEmpty) {
      MotionToast.show(context, "Please add at least one item block",
          isError: true);
      return;
    }

    // Validate that all items have a name and all sizes have a label selected
    for (var item in _items) {
      if (item.selectedItemName == null || item.selectedItemName!.isEmpty) {
        MotionToast.show(context, "Please select a Product Type for all items",
            isError: true);
        return;
      }
      if (item.sizes.isEmpty) {
        MotionToast.show(context,
            "Please add at least one size for ${item.selectedItemName}",
            isError: true);
        return;
      }
      for (var sz in item.sizes) {
        if (sz.selectedSizeLabel == null || sz.selectedSizeLabel!.isEmpty) {
          MotionToast.show(
              context, "Please select a size for ${item.selectedItemName}",
              isError: true);
          return;
        }
        final mtVal = double.tryParse(sz.mtCtrl.text) ?? 0.0;
        if (mtVal <= 0) {
          MotionToast.show(context,
              "Please enter a valid weight for ${item.selectedItemName} ${sz.selectedSizeLabel}",
              isError: true);
          return;
        }
      }
    }

    final String targetInv = _invoiceCtrl.text.trim();
    // Validate uniqueness against loaded transactions AND local _allTransactions
    bool isDuplicate = DataRepository.allTransactionsNotifier.value
        .any((tx) => tx.invoiceNo == targetInv && !tx.isReversed);
    if (!isDuplicate) {
      isDuplicate = _allTransactions
          .any((tx) => tx.invoiceNo == targetInv && !tx.isReversed);
    }

    if (isDuplicate) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text("Duplicate Used"),
            ],
          ),
          content: Text(
              "Bill/Invoice Number '$targetInv' has already been recorded in recent transactions.\n\nUse a unique number to avoid errors."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK", style: TextStyle(color: msmRed)),
            )
          ],
        ),
      );
      return;
    }

    double total = _grandTotalMT;
    double hand = double.tryParse(_handMTCtrl.text) ?? 0;
    double crane = double.tryParse(_craneMTCtrl.text) ?? 0;
    if ((hand + crane - total).abs() > 0.001) {
      MotionToast.show(
          context, "Hand + Crane loading must match Grand Total MT",
          isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final String batchId = "BATCH_${DateTime.now().millisecondsSinceEpoch}";

    final googleUser = AuthService.googleSignIn.currentUser;
    final currentUser = DataRepository.currentUserNotifier.value;
    final prefs = await SharedPreferences.getInstance();
    final storedDisplayName = prefs.getString('user_display_name') ?? '';
    final storedEmail = prefs.getString('user_email') ?? '';

    String entryByValue = (googleUser?.displayName?.isNotEmpty == true)
        ? googleUser!.displayName!
        : (storedDisplayName.isNotEmpty
            ? storedDisplayName
            : (googleUser?.email.isNotEmpty == true
                ? googleUser!.email
                : (currentUser?.email.isNotEmpty == true
                    ? currentUser!.email
                    : (storedEmail.isNotEmpty
                        ? storedEmail
                        : (UserSession.userEmail?.isNotEmpty == true
                            ? UserSession.userEmail!
                            : (googleUser?.id.isNotEmpty == true
                                ? googleUser!.id
                                : 'Unknown User'))))));

    if (entryByValue.trim().isEmpty || entryByValue == 'null') {
      entryByValue = 'Unknown User';
    }

    int? findSupabaseSizeId(String itemName, String sizeLabel) {
      final selectedMaterialId = DataRepository.getMaterialIdByName(itemName);
      final allSizes = DataRepository.instance.itemSizes;

      final matchingSizes = allSizes.where((s) {
        final sMatId = s['material_id'] ?? s['materialId'];
        final matchId = (selectedMaterialId != null &&
            sMatId != null &&
            sMatId.toString() == selectedMaterialId.toString());
        final matchName = isSizeInCategory(s, itemName);
        return matchId || matchName;
      }).toList();

      String normalize(String s) {
        String cleaned = s.trim();
        // Split by space to parse out trailing weight suffix
        final parts = cleaned.split(' ');
        if (parts.length > 1) {
          final lastPart = parts.last;
          // If the last part is a number (e.g., "13", "8.0", "13kg"), remove it
          if (RegExp(r'^\d+(\.\d+)?(kg|mt)?$', caseSensitive: false)
              .hasMatch(lastPart)) {
            parts.removeLast();
            cleaned = parts.join(' ');
          }
        }
        // Remove all spaces and lowercase for format-insensitive comparison
        return cleaned.toLowerCase().replaceAll(' ', '');
      }

      String normalizeFallback(String s) {
        // Fallback: Strip any remaining trailing digits at the very end (handles over-stripped DB values like "32x")
        return normalize(s).replaceFirst(RegExp(r'\d+$'), '');
      }

      // 1. Direct exact label match
      for (var row in matchingSizes) {
        final dbSize = (row['size_label'] ?? row['label'])?.toString() ?? '';
        if (dbSize.trim().toLowerCase() == sizeLabel.trim().toLowerCase()) {
          final rawId = row['id'];
          if (rawId != null) return int.tryParse(rawId.toString());
        }
      }

      // 2. Normalized match (preserving thickness digits)
      final normLookup = normalize(sizeLabel);
      for (var row in matchingSizes) {
        final dbSize = (row['size_label'] ?? row['label'])?.toString() ?? '';
        if (normalize(dbSize) == normLookup) {
          final rawId = row['id'];
          if (rawId != null) return int.tryParse(rawId.toString());
        }
      }

      // 3. Fallback match (stripping trailing digits from both)
      final fallbackLookup = normalizeFallback(sizeLabel);
      for (var row in matchingSizes) {
        final dbSize = (row['size_label'] ?? row['label'])?.toString() ?? '';
        if (normalizeFallback(dbSize) == fallbackLookup) {
          final rawId = row['id'];
          if (rawId != null) return int.tryParse(rawId.toString());
        }
      }

      return null;
    }

    // Lookup size IDs
    for (var item in _items) {
      for (var sz in item.sizes) {
        final sizeId =
            findSupabaseSizeId(item.selectedItemName!, sz.selectedSizeLabel!);
        if (sizeId == null) {
          setState(() => _isSubmitting = false);
          if (mounted) {
            MotionToast.show(context,
                "Please select a valid size for ${item.selectedItemName} ${sz.selectedSizeLabel}",
                isError: true);
          }
          return;
        }
      }
    }

    // Negative Stock Validation for Stock Out
    if (_selectedType == 'OUT') {
      for (var item in _items) {
        for (var sz in item.sizes) {
          final enteredQty = double.tryParse(sz.mtCtrl.text) ?? 0.0;
          final available =
              _getAvailableStock(item.selectedItemName, sz.selectedSizeLabel);
          if (enteredQty > available) {
            final deficitMt = enteredQty - available;
            // Kept as warning toast, but bypass return block to allow negative values:
            if (mounted) {
              MotionToast.show(
                context,
                "Warning: Insufficient Stock! Shortfall of -${deficitMt.toStringAsFixed(3)} MT (-${(deficitMt * 1000).toStringAsFixed(0)} kg)",
                isError: true,
              );
            }
          }
        }
      }
    }

    List<Map<String, dynamic>> newTransactions = [];
    for (var item in _items) {
      for (var sz in item.sizes) {
        final sizeId =
            findSupabaseSizeId(item.selectedItemName!, sz.selectedSizeLabel!);
        final matId = DataRepository.getMaterialIdByName(item.selectedItemName!) ??
            (sizeId != null
                ? DataRepository.instance.itemSizes
                    .firstWhere(
                      (s) => s['id']?.toString() == sizeId.toString(),
                      orElse: () => <String, dynamic>{},
                    )['material_id'] as int?
                : null);

        final txId =
            "${DateTime.now().millisecondsSinceEpoch}_${newTransactions.length}";
        final tx = StockTransaction(
          txnId: txId,
          dateTime: _selectedDate,
          itemName: item.selectedItemName!,
          size: sz.selectedSizeLabel!,
          type: _selectedType,
          qtyMT: double.tryParse(sz.mtCtrl.text) ?? 0,
          basicRate: double.tryParse(item.basicRateCtrl.text),
          location: _selectedLocation!,
          toLocation: _selectedType == 'TRANSFER' ? _toLocation : null,
          invoiceNo: _invoiceCtrl.text.trim(),
          lorryNo: _lorryCtrl.text,
          transportCo: _transportCompanyCtrl.text,
          driverName: _driverNameCtrl.text,
          driverPhone: _driverPhoneCtrl.text,
          note: sz.noteCtrl.text,
          batchId: batchId,
          handMT: hand > 0 ? hand : null,
          craneMT: crane > 0 ? crane : null,
          user: entryByValue,
        );
        final txMap = tx.toJson();
        txMap['nos'] = 0;
        newTransactions.add(txMap);

        // Map payload for Supabase
        final supabaseTxn = {
          'txn_id': txId,
          'date': _selectedDate.toIso8601String(),
          'date_time': _selectedDate.toIso8601String(),
          'material_id': matId,
          'item_name': item.selectedItemName!,
          'size': sz.selectedSizeLabel!,
          'size_id': sizeId,
          'type': _selectedType,
          'txn_type': _selectedType,
          'qty_mt': double.tryParse(sz.mtCtrl.text) ?? 0,
          'location': _selectedLocation!,
          'to_location': _selectedType == 'TRANSFER' ? _toLocation : null,
          'invoice_no': _invoiceCtrl.text.trim(),
          'bill_no': _invoiceCtrl.text.trim(),
          'lorry_no': _lorryCtrl.text,
          'transport_co': _transportCompanyCtrl.text,
          'transport_name': _transportCompanyCtrl.text,
          'driver_name': _driverNameCtrl.text,
          'driver_phone': _driverPhoneCtrl.text,
          'note': sz.noteCtrl.text,
          'batch_id': batchId,
          'hand_mt': hand > 0 ? hand : null,
          'crane_mt': crane > 0 ? crane : null,
          'user_name': entryByValue,
          'user': entryByValue,
          'is_reversed': false,
        };

        try {
          await SupabaseService().insertTransaction(supabaseTxn);
        } on PostgrestException catch (e) {
          debugPrint("Supabase DB Error: ${e.message}");
          if (mounted) {
            setState(() => _isSubmitting = false);
            MotionToast.show(context, "Database Error: ${e.message}",
                isError: true);
          }
          return;
        } catch (e) {
          debugPrint("Unknown Error: $e");
          if (mounted) {
            setState(() => _isSubmitting = false);
            MotionToast.show(context, "Submission failed: $e", isError: true);
          }
          return;
        }
      }
    }

    if (!mounted) return;
    final nav = Navigator.of(context);

    await DataRepository.getERPStockAsync(null, forceRefresh: true);
    notifyStockDataChanged();

    if (mounted) {
      MotionToast.show(context, "MSM One: Stock Entry Verified ✔");
      nav.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _buildModernAppBar(),
        body: const Center(child: MLoader()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildModernAppBar(),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // SCROLLABLE FORM BODY
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTypeSwitcher(), // [ IN | OUT | TRANSFER | ADJUSTMENT ]
                        const SizedBox(height: 16),
                        _buildDetailsCard(),  // Location, Date, Bill/Invoice, Lorry
                        const SizedBox(height: 16),
                        _buildTransportAccordion(),
                        const SizedBox(height: 16),
                        _buildProductsSection(),
                        const SizedBox(height: 16),
                        _buildSplitLoadingCard(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // PINNED BOTTOM ACTION BAR
            _buildStickyBottomBar(context),
          ],
        ),
      ),
    );
  }

  String _getHeaderTitle() {
    if (_selectedType == 'IN') {
      return 'Stock In Transaction';
    } else if (_selectedType == 'OUT') {
      return 'Stock Out Transaction';
    } else if (_selectedType == 'TRANSFER') {
      return 'Stock Transfer';
    } else if (_selectedType == 'ADJUSTMENT') {
      return 'Stock Adjustment';
    } else {
      return 'Stock ${_selectedType[0]}${_selectedType.substring(1).toLowerCase()} Transaction';
    }
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFD32F2F),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'MSM ONE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            _getHeaderTitle(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          tooltip: 'Options',
          onPressed: _showOptionsMenu,
        ),
      ],
    );
  }

  Widget _buildTypeSwitcher() => _buildTypeSelector(context);
  Widget _buildDetailsCard() => _buildTransactionDetailsCard(context);
  Widget _buildTransportAccordion() => _buildAdvancedTransportAccordion(context);
  Widget _buildProductsSection() => _buildProductsAndItemsSection(context);
  Widget _buildSplitLoadingCard() => _buildSplitLoadingSection(context);

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: Color(0xFF0284C7)),
                title: const Text("Refresh Master Data",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _loadMasterData();
                  MotionToast.show(context, "Master data refreshed");
                },
              ),
              ListTile(
                leading: const Icon(Icons.clear_all_rounded, color: Color(0xFFDC2626)),
                title: const Text("Clear Form",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFFDC2626))),
                onTap: () {
                  Navigator.pop(ctx);
                  _showClearFormDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearFormDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.restore_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text("Clear Form?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          "This will reset all fields and line items.\nNo data will be deleted from the database.",
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearForm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Clear"),
          ),
        ],
      ),
    );
  }

  // ── 2. TRANSACTION TYPE PILL SWITCHER ──
  Widget _buildTypeSelector(BuildContext context) {
    final segments = ['IN', 'OUT', 'TRANSFER', 'ADJUSTMENT'].where((t) {
      if (t == 'IN' && !AccessGuard.can(Permissions.stockIn)) return false;
      if (t == 'OUT' && !AccessGuard.can(Permissions.stockOut)) return false;
      if (t == 'TRANSFER' && !AccessGuard.can(Permissions.stockTransfer)) {
        return false;
      }
      return true;
    }).toList();

    return Center(
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: segments.map((t) {
              bool isSelected = _selectedType == t;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF64748B),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── 3. TRANSACTION DETAILS CARD ──
  Widget _buildTransactionDetailsCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Location & Date
          LayoutBuilder(builder: (context, constraints) {
            bool stack = constraints.maxWidth < 460;
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLocationField(context),
                      const SizedBox(height: 12),
                      _buildDateField(context),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildLocationField(context)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateField(context)),
                    ],
                  );
          }),

          if (_selectedType == 'TRANSFER') ...[
            const SizedBox(height: 12),
            _buildToLocationField(context),
          ],

          const SizedBox(height: 12),

          // Row 2: Bill/Invoice Number & Lorry Number
          LayoutBuilder(builder: (context, constraints) {
            bool stack = constraints.maxWidth < 460;
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInvoiceField(context),
                      const SizedBox(height: 12),
                      _buildLorryField(context),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildInvoiceField(context)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildLorryField(context)),
                    ],
                  );
          }),
        ],
      ),
    );
  }

  Widget _buildLocationField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedType == 'TRANSFER' ? "From Location" : "Location",
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        InkWell(
          onTap: () => _showLocationPicker(
              context, (loc) => setState(() => _selectedLocation = loc)),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedLocation ?? "Select Location",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selectedLocation == null
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF64748B), size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToLocationField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "To Location",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        InkWell(
          onTap: () => _showLocationPicker(
              context, (loc) => setState(() => _toLocation = loc),
              exclude: _selectedLocation),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _toLocation ?? "Select Destination",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _toLocation == null
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF64748B), size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Date",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
            final d = await showDatePicker(
              context: context,
              initialDate:
                  _selectedDate.isAfter(today) ? now : _selectedDate,
              firstDate: DateTime(2020),
              lastDate: today,
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFFD32F2F),
                      onPrimary: Colors.white,
                      onSurface: Color(0xFF1E293B),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (d != null) setState(() => _selectedDate = d);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Icon(Icons.calendar_today_outlined,
                    size: 18, color: Color(0xFFDC2626)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Bill/Invoice Number",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: _invoiceCtrl,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: "Invoice No.",
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFDC2626), size: 20),
              tooltip: "Scan Code",
              onPressed: () {
                MotionToast.show(
                  context,
                  "Barcode/QR scanner ready. Enter manually or scan bill.",
                  isError: false,
                );
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLorryField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Lorry Number",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: _lorryCtrl,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: "Lorry Number",
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ── 4. COLLAPSIBLE ACCORDIONS & ITEM BUILDER ──
  Widget _buildAdvancedTransportAccordion(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            iconColor: const Color(0xFF1E293B),
            collapsedIconColor: const Color(0xFF64748B),
            title: const Text(
              "Advanced Transport Details",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1E293B), // Dark Navy/Indigo
                letterSpacing: -0.2,
              ),
            ),
            children: [
              TextFormField(
                controller: _transportCompanyCtrl,
                decoration: _styledInputDeco("Transport Company"),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                bool stack = constraints.maxWidth < 460;
                return stack
                    ? Column(
                        children: [
                          TextFormField(
                            controller: _driverNameCtrl,
                            decoration: _styledInputDeco("Driver Name"),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _driverPhoneCtrl,
                            decoration: _styledInputDeco("Driver Phone"),
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _driverNameCtrl,
                              decoration: _styledInputDeco("Driver Name"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _driverPhoneCtrl,
                              decoration: _styledInputDeco("Driver Phone"),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      );
              }),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarksCtrl,
                decoration: _styledInputDeco("General Remarks"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _styledInputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
    );
  }

  Widget _buildProductsAndItemsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Material Items & Sizes",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            Text(
              "${_items.length} Product${_items.length == 1 ? '' : 's'}",
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ..._items.asMap().entries.map((entry) {
          return _buildProductCard(context, entry.key, entry.value);
        }),

        // Add Item Button
        Center(
          child: ElevatedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0284C7), size: 18),
            label: const Text(
              "ADD ITEM",
              style: TextStyle(
                color: Color(0xFF0284C7),
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE0F2FE),
              foregroundColor: const Color(0xFF0284C7),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, int idx, _StockItemBlock item) {
    double totalMT = item.sizes
        .fold(0.0, (sum, sz) => sum + (double.tryParse(sz.mtCtrl.text) ?? 0.0));
    double rate = double.tryParse(item.basicRateCtrl.text) ?? 0.0;
    double totalAmt = totalMT * rate;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => item.isExpanded = !item.isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(20),
              bottom: Radius.circular(item.isExpanded ? 0 : 20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      getItemIconPath(item.selectedItemName ?? ''),
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.category_rounded,
                        color: Color(0xFFDC2626),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.selectedItemName ?? "Select Product",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: item.selectedItemName == null
                                ? const Color(0xFF64748B)
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${totalMT.toStringAsFixed(3)} MT",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                            if (totalAmt > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                "₹ ${totalAmt.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626), size: 20),
                    onPressed: () => setState(() => _items.removeAt(idx)),
                  ),
                ],
              ),
            ),
          ),
          if (item.isExpanded) ...[
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("PRODUCT TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _openCategoryPicker(idx),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item.selectedItemName ?? "Select Item Type",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: item.selectedItemName == null
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFDC2626), size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...item.sizes.asMap().entries.map((entry) =>
                      _buildSizeVariantRow(context, idx, item, entry.key, entry.value)),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () => setState(() => item.sizes.add(_StockSizeRow(
                          id: DateTime.now().millisecondsSinceEpoch.toString()))),
                      child: const Row(
                        children: [
                          Icon(Icons.add_circle_outline, color: Color(0xFFDC2626), size: 18),
                          SizedBox(width: 6),
                          Text("Add Size", style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSizeSelector(int itemIndex, [int sizeRowIndex = 0]) {
    final currentItem = _items[itemIndex];
    final hasCategory =
        currentItem.category != null && currentItem.category!.isNotEmpty;
    final sizes = currentItem.availableSizes;
    final _StockSizeRow? sizeRow =
        sizeRowIndex < currentItem.sizes.length ? currentItem.sizes[sizeRowIndex] : null;

    final String? selectedLabel = sizeRow?.label ??
        (sizeRowIndex == 0 ? currentItem.selectedSize?.label : null);

    return InkWell(
      onTap: !hasCategory ? null : () => _openSizePicker(itemIndex, sizeRowIndex),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color:
              hasCategory ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedLabel != null
                    ? getFormattedSizeDisplay(selectedLabel, null)
                    : (hasCategory
                        ? 'Select Size (${sizes.length} available)'
                        : 'Select Category first'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selectedLabel != null ? FontWeight.w600 : FontWeight.normal,
                  color: selectedLabel != null
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF94A3B8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeVariantRow(
      BuildContext context, int itemIndex, _StockItemBlock item, int szIndex, _StockSizeRow sz) {
    double avail =
        _getAvailableStock(item.selectedItemName, sz.selectedSizeLabel);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              "SIZE / VARIANT",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),
          _buildSizeSelector(itemIndex, szIndex),
          if (item.selectedItemName != null && sz.selectedSizeLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              "Stock: ${avail.toStringAsFixed(3)} MT",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: avail > 0.1
                    ? const Color(0xFF059669)
                    : const Color(0xFFD97706),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            controller: sz.mtCtrl,
            onChanged: (v) => setState(() {}),
            decoration: _styledInputDeco("WEIGHT (MT)", hint: "0.000"),
          ),
        ],
      ),
    );
  }

  // ── 5. SPLIT LOADING & PINNED BOTTOM BAR ──
  Widget _buildSplitLoadingSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Split Loading (Hand vs Crane)",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            bool stack = constraints.maxWidth < 440;
            return stack
                ? Column(
                    children: [
                      TextFormField(
                        controller: _handMTCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _styledInputDeco("Hand MT", hint: "0.000"),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _craneMTCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _styledInputDeco("Crane MT", hint: "0.000"),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _handMTCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _styledInputDeco("Hand MT", hint: "0.000"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _craneMTCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _styledInputDeco("Crane MT", hint: "0.000"),
                        ),
                      ),
                    ],
                  );
          }),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final totalWeight = _grandTotalMT;
    final items = _items;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32 : 16,
        vertical: isDesktop ? 14 : 12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: isDesktop
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // LEFT: WEIGHT SUMMARY INLINE
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'TOTAL WEIGHT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${totalWeight.toStringAsFixed(3)} MT',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        Container(
                          height: 36,
                          width: 1,
                          color: const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(width: 24),
                        Text(
                          '${items.length} Product Category / Variants Selected',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                    // RIGHT: CONSTRAINED PROCEED BUTTON
                    SizedBox(
                      width: 220,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSubmitting
                            ? null
                            : (totalWeight > 0 ? _confirmTransaction : null),
                        child: _isSubmitting
                            ? const MLoader(size: 20, color: Colors.white)
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Proceed',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 18, color: Colors.white),
                                ],
                              ),
                      ),
                    ),
                  ],
                )
              // MOBILE VIEW (Original Clean Mobile Layout)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL WEIGHT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${totalWeight.toStringAsFixed(3)} MT',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isSubmitting ? null : _confirmTransaction,
                        child: _isSubmitting
                            ? const MLoader(size: 20, color: Colors.white)
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 18, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Proceed',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  List<CategoryItem> _getAllCategoryItems() {
    List<String> allNames = _masterItemData.keys.toList();
    if (allNames.isEmpty) {
      allNames = DataRepository.getDynamicCategories();
    }
    allNames.sort((a, b) => SortingUtils.compareCategories(a, b));

    return allNames.map((name) {
      final sizes = getSizesForCategory(name);
      return CategoryItem(
        name: name,
        variantsCount: sizes.length,
      );
    }).toList();
  }

  Future<void> _openCategoryPicker(int itemIndex, {bool isNewItem = false}) async {
    final allCategories = _getAllCategoryItems();
    final String? currentCat = (!isNewItem && itemIndex < _items.length)
        ? _items[itemIndex].category
        : null;

    final selected = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ProductCategoryPickerSheet(
        categories: allCategories,
        selectedCategory: currentCat,
      ),
    );

    if (selected != null) {
      setState(() {
        final categoryName = selected is String
            ? selected
            : (selected is CategoryItem ? selected.name : selected.toString());

        if (isNewItem || itemIndex >= _items.length) {
          final newBlock = _StockItemBlock(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            selectedItemName: categoryName,
            availableSizes: getSizesForCategory(categoryName),
            sizes: [
              _StockSizeRow(
                  id: (DateTime.now().millisecondsSinceEpoch + 1).toString())
            ],
          );
          _items.add(newBlock);
        } else {
          _items[itemIndex].category = categoryName;
          _items[itemIndex].selectedSize = null; 
          
          final allMasterSizes = DataRepository.itemSizesNotifier.value;
          final queriedSizes = getSizesForCategory(categoryName);
          _items[itemIndex].availableSizes = queriedSizes.isNotEmpty
              ? queriedSizes
              : allMasterSizes.where((s) {
                  return isSizeInCategory(s, categoryName);
                }).map((s) {
                  String label =
                      (s['label'] ?? s['size_label'] ?? '').toString().trim();
                  return {
                    'label': label,
                    'size_label': label,
                    'weight': double.tryParse(
                            (s['weight'] ?? s['unit_weight_kg'] ?? '0')
                                .toString()) ??
                        0.0,
                  };
                }).toList();

          if (_items[itemIndex].sizes.isEmpty) {
            _items[itemIndex].sizes.add(_StockSizeRow(
                id: DateTime.now().millisecondsSinceEpoch.toString()));
          } else {
            for (var sz in _items[itemIndex].sizes) {
              sz.selectedSizeLabel = null;
            }
          }
        }
      });
      final effectiveIdx = (isNewItem || itemIndex >= _items.length)
          ? _items.length - 1
          : itemIndex;
      debugPrint(
          "Category selected: ${_items[effectiveIdx].category} with ${_items[effectiveIdx].availableSizes.length} sizes");
    }
  }

  void _showItemPicker(BuildContext context, _StockItemBlock? block) {
    if (block != null) {
      final idx = _items.indexOf(block);
      if (idx != -1) {
        _openCategoryPicker(idx);
        return;
      }
    }
    _openCategoryPicker(_items.length, isNewItem: true);
  }

  void _showLocationPicker(BuildContext context, Function(String) onSelect,
      {String? exclude}) {
    final locs = ['YARD', 'FACTORY'].where((l) => l != exclude).toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: locs
              .map((l) => ListTile(
                    title: Text(
                      l,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: Color(0xFF94A3B8)),
                    onTap: () {
                      onSelect(l);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _openSizePicker(int itemIndex, [int sizeRowIndex = 0]) async {
    if (itemIndex >= _items.length) return;
    final currentItem = _items[itemIndex];

    if (currentItem.category == null || currentItem.category!.trim().isEmpty) {
      MotionToast.show(context, "Please select product category first",
          isError: true);
      return;
    }

    final availableSizes = currentItem.availableSizes.isNotEmpty
        ? currentItem.availableSizes
        : getSizesForCategory(currentItem.category);

    if (availableSizes.isEmpty) {
      MotionToast.show(
          context, "No sizes available for ${currentItem.category}",
          isError: true);
      return;
    }

    while (currentItem.sizes.length <= sizeRowIndex) {
      currentItem.sizes.add(_StockSizeRow(
          id: (DateTime.now().millisecondsSinceEpoch + currentItem.sizes.length)
              .toString()));
    }
    final szRow = currentItem.sizes[sizeRowIndex];

    final selectedMaterialId =
        DataRepository.getMaterialIdByName(currentItem.category);

    final result = await ResponsiveSizePicker.show(
      context,
      itemType: currentItem.category!,
      materialId: selectedMaterialId,
      customSizes: availableSizes,
      trailingBuilder: (sizeData) {
        if (_selectedType == 'OUT' || _selectedType == 'TRANSFER') {
          final sizeLabel =
              (sizeData['label'] ?? sizeData['size_label'] ?? '').toString();
          double qty = _getAvailableStock(currentItem.category, sizeLabel);
          return Text(
            "${qty.toStringAsFixed(3)} MT",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          );
        }
        return null;
      },
    );

    if (result != null) {
      setState(() {
        final label =
            (result['label'] ?? result['size_label'] ?? '').toString();
        szRow.selectedSizeLabel = label;
      });
    }
  }
}

String getItemIconPath(String itemName) {
  String name = itemName.toLowerCase().trim();
  if (name.contains("pipe") && name.contains("hr")) {
    return "assets/hr_pipe.png";
  }
  if (name.contains("pipe")) {
    return "assets/ms_pipe.png";
  }
  if (name.contains("round")) {
    return "assets/round_bar.png";
  }
  if (name.contains("angle")) {
    return "assets/angle.png";
  }
  if (name.contains("channel")) {
    return "assets/channel.png";
  }
  if (name.contains("flat")) {
    return "assets/flat.png";
  }
  return "assets/msm_icon.jpg";
}

class CategoryItem {
  final String name;
  final int variantsCount;
  final String? iconPath;

  const CategoryItem({
    required this.name,
    this.variantsCount = 0,
    this.iconPath,
  });
}

class ProductCategoryPickerSheet extends StatefulWidget {
  final List<dynamic> categories;
  final String? selectedCategory;

  const ProductCategoryPickerSheet({
    super.key,
    required this.categories,
    this.selectedCategory,
  });

  @override
  State<ProductCategoryPickerSheet> createState() =>
      _ProductCategoryPickerSheetState();
}

class _ProductCategoryPickerSheetState
    extends State<ProductCategoryPickerSheet> {
  String _searchQuery = '';

  Widget _buildCategoryIcon(dynamic cat, bool isSelected) {
    final String name = cat is CategoryItem
        ? cat.name
        : (cat is String ? cat : cat.toString());
    final iconPath = getItemIconPath(name);

    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset(
        iconPath,
        errorBuilder: (_, __, ___) => Icon(
          Icons.category,
          color: isSelected ? Colors.white : const Color(0xFFDC2626),
          size: 18,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCategories = widget.categories.where((cat) {
      final String name = cat is CategoryItem
          ? cat.name
          : (cat is String ? cat : cat.toString());
      return name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Select Product Category",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search products...",
              prefixIcon: const Icon(Icons.search, color: Color(0xFFDC2626)),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filteredCategories.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (ctx, i) {
                final cat = filteredCategories[i];
                final String catName = cat is CategoryItem
                    ? cat.name
                    : (cat is String ? cat : cat.toString());
                final int variantsCount = cat is CategoryItem
                    ? cat.variantsCount
                    : (cat is Map
                        ? (cat['variantsCount'] ?? 0)
                        : 0);
                final isSelected = widget.selectedCategory != null &&
                    widget.selectedCategory!.trim().toUpperCase() ==
                        catName.trim().toUpperCase();

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: _buildCategoryIcon(cat, isSelected),
                  title: Text(
                    catName,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color:
                          isSelected ? const Color(0xFFDC2626) : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    '$variantsCount size variants',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFFDC2626))
                      : null,
                  onTap: () {
                    Navigator.of(context).pop(cat);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StockItemBlock {
  final String id;
  String? selectedItemName;
  List<Map<String, dynamic>> availableSizes;
  List<_StockSizeRow> sizes;
  bool isExpanded = true;
  final TextEditingController basicRateCtrl = TextEditingController();

  _StockItemBlock({
    required this.id,
    required this.sizes,
    this.selectedItemName,
    List<Map<String, dynamic>>? availableSizes,
  }) : availableSizes = availableSizes ?? [];

  String? get category => selectedItemName;
  set category(String? val) => selectedItemName = val;

  _StockSizeRow? get selectedSize => sizes.isNotEmpty ? sizes.first : null;
  set selectedSize(dynamic val) {
    if (sizes.isNotEmpty) {
      if (val == null) {
        sizes.first.selectedSizeLabel = null;
      } else if (val is String) {
        sizes.first.selectedSizeLabel = val;
      } else if (val is _StockSizeRow) {
        sizes.first.selectedSizeLabel = val.selectedSizeLabel;
      }
    }
  }
}

class _StockSizeRow {
  final String id;
  String? selectedSizeLabel;
  String? get selectedSize => selectedSizeLabel;
  set selectedSize(String? val) => selectedSizeLabel = val;
  String? get label => selectedSizeLabel;
  set label(String? val) => selectedSizeLabel = val;
  final TextEditingController mtCtrl = TextEditingController();
  final TextEditingController noteCtrl = TextEditingController();
  _StockSizeRow({required this.id});
}
