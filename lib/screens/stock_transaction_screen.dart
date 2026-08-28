import 'dart:convert';
import 'dart:ui';
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

  void _refreshMasterItemData() {
    final data = DataRepository.sheetDataNotifier.value;
    final List<dynamic> itemsList = data['items'] ?? [];
    final Map<String, List<Map<String, dynamic>>> tempMap = {};
    for (var item in itemsList) {
      final name = item['name']?.toString().trim() ?? '';
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
          'weight': weight,
          'sd': sheetSD,
        };
      }).toList();
      tempMap[name] = parsedSizes;
    }
    setState(() {
      _masterItemData = tempMap;
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
      _formSubmitted = false;
    });
    MotionToast.show(context, "Form cleared");
  }

  final List<_StockItemBlock> _items = [];
  Map<String, List<Map<String, dynamic>>> _masterItemData = {};
  List<StockTransaction> _allTransactions = [];
  final Map<String, double> _currentStockMap = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _formSubmitted = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType ?? 'IN';
    _loadMasterData();
    _generateNextBillNo();
    DataRepository.sheetDataNotifier.addListener(_onSheetDataUpdated);
    DataRepository.itemSizesNotifier.addListener(_onSheetDataUpdated);

    if (widget.initialItem != null) {
      final block = _StockItemBlock(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        selectedItemName: widget.initialItem,
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
    } catch (e) {
      debugPrint("Error loading true ERP stock for picker: $e");
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

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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
    setState(() => _formSubmitted = true);
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
            : (googleUser?.email?.isNotEmpty == true
                ? googleUser!.email
                : (currentUser?.email.isNotEmpty == true
                    ? currentUser!.email
                    : (storedEmail.isNotEmpty
                        ? storedEmail
                        : (UserSession.userEmail?.isNotEmpty == true
                            ? UserSession.userEmail!
                            : (googleUser?.id?.isNotEmpty == true
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
        final sMatName = (s['material_name'] ?? s['materialName'])?.toString();
        final matchId = (selectedMaterialId != null &&
            sMatId != null &&
            sMatId.toString() == selectedMaterialId.toString());
        final matchName = (sMatName != null &&
            sMatName.trim().toLowerCase() == itemName.trim().toLowerCase());
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
          MotionToast.show(context,
              "Please select a valid size for ${item.selectedItemName} ${sz.selectedSizeLabel}",
              isError: true);
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
            MotionToast.show(
              context,
              "Warning: Insufficient Stock! Shortfall of -${deficitMt.toStringAsFixed(3)} MT (-${(deficitMt * 1000).toStringAsFixed(0)} kg)",
              isError: true,
            );
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

    final nav = Navigator.of(context);
    final overlay = Overlay.of(context);

    if (mounted) {
      await DataRepository.getERPStockAsync(null, forceRefresh: true);
      notifyStockDataChanged();

      MotionToast.show(context, "MSM One: Stock Entry Verified ✔");

      nav.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: MLoader()));

    // Clamp text scaling to 1.3 to prevent UI breakage while maintaining accessibility
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
            MediaQuery.of(context).textScaler.scale(1.0).clamp(1.0, 1.3)),
      ),
      child: Scaffold(
        backgroundColor: bgLight,
        extendBodyBehindAppBar: false,
        appBar: _buildModernAppBar(),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  bool isDesktop = constraints.maxWidth > 700;
                  return isDesktop
                      ? _buildDesktopLayout()
                      : _buildMobileLayout();
                },
              ),
            ),
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border:
                Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: StockTransactionTotalWeightCard(
                      totalWeight: _grandTotalMT,
                      isSubmitting: _isSubmitting,
                      onProceed: _confirmTransaction,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldStack(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double textScale = MediaQuery.of(context).textScaler.scale(1.0);
    return width < 450 || textScale > 1.15;
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: msmRed,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("MSM ONE",
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                  letterSpacing: 2)),
          Text(
            _selectedType == 'IN'
                ? 'Stock In Transaction'
                : _selectedType == 'OUT'
                    ? 'Stock Out Transaction'
                    : 'Stock Operation',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      actions: [
        Tooltip(
          message: "Clear Form",
          child: IconButton(
            icon: const Icon(Icons.clear_all_rounded, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.restore_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Text("Clear Form?"),
                    ],
                  ),
                  content: const Text(
                    "This will reset all fields and line items.\nNo data will be deleted from the sheet.",
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel",
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _clearForm();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: msmRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Clear"),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          _buildTypeSelector(context),
          const SizedBox(height: 16),
          _buildFormSection(
              title: "Logistics & Timing", child: _buildBasicInfo(context)),
          const SizedBox(height: 16),
          _buildFormSection(
              title: "Transport Details",
              child: _buildAdvancedTransport(context)),
          const SizedBox(height: 16),
          _buildFormSection(
            title: "Stock Items",
            child: Column(
              children: [
                ..._items
                    .asMap()
                    .entries
                    .map((e) => _buildItemCard(context, e.key, e.value)),
                const SizedBox(height: 12),
                _buildAddItemButton(context),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildFormSection(
            title: "Split Loading",
            child: _buildSplitLoading(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          _buildTypeSelector(context),
          const SizedBox(height: 16),
          _buildBasicInfo(context),
          const SizedBox(height: 12),
          _buildAdvancedTransport(context),
          const SizedBox(height: 16),
          ..._items
              .asMap()
              .entries
              .map((e) => _buildItemCard(context, e.key, e.value)),
          const SizedBox(height: 12),
          _buildAddItemButton(context),
          const SizedBox(height: 16),
          _buildSplitLoading(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFormSection(
      {required String title, Widget? trailing, required Widget child}) {
    IconData? titleIcon;
    if (title.contains("Logistics"))
      titleIcon = Icons.location_on_rounded;
    else if (title.contains("Transport"))
      titleIcon = Icons.local_shipping_rounded;
    else if (title.contains("Split"))
      titleIcon = Icons.call_split_rounded;
    else if (title.contains("Stock")) titleIcon = Icons.inventory_2_rounded;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (titleIcon != null) ...[
                      Icon(titleIcon, color: msmRed, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textDark)),
                  ],
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          const Divider(height: 1, color: borderLight),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  InputDecoration _filledDeco(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          color: textGrey, fontSize: 13, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: const Color(0xFFF6F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffix,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: msmRed, width: 1.5)),
    );
  }

  Widget _buildTypeSelector(BuildContext context) {
    final types = ['IN', 'OUT', 'TRANSFER', 'ADJUSTMENT', 'RETURN'].where((t) {
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
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: types.map((t) {
              bool isSelected = _selectedType == t;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]
                        : [],
                  ),
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? msmRed : textGrey,
                          letterSpacing: 0.5)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildLocationDropdown(context),
          const SizedBox(height: 12),
          _buildDateInput(context),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            bool stack = _shouldStack(context);
            List<Widget> children = [
              Flexible(
                flex: stack ? 0 : 1,
                fit: stack ? FlexFit.loose : FlexFit.tight,
                child: TextFormField(
                  controller: _invoiceCtrl,
                  keyboardType: TextInputType.text,
                  decoration: _filledDeco(
                    "Bill/Invoice Number",
                    suffix: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: msmRed),
                      onPressed: () {
                        MotionToast.show(context,
                            "Scanner library not linked. Please enter manually.",
                            isError: true);
                      },
                    ),
                  ),
                ),
              ),
              if (!stack) const SizedBox(width: 12),
              if (stack) const SizedBox(height: 12),
              Flexible(
                flex: stack ? 0 : 1,
                fit: stack ? FlexFit.loose : FlexFit.tight,
                child: TextFormField(
                  controller: _lorryCtrl,
                  decoration: _filledDeco("Lorry Number"),
                ),
              ),
            ];

            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children)
                : Row(children: children);
          }),
          if (_selectedType == 'TRANSFER') ...[
            const SizedBox(height: 12),
            _buildToLocationDropdown(context),
          ]
        ],
      ),
    );
  }

  Widget _buildLocationDropdown(BuildContext context) {
    return InkWell(
      onTap: () => _showLocationPicker(
          context, (loc) => setState(() => _selectedLocation = loc)),
      child: InputDecorator(
        decoration: _filledDeco(
            _selectedType == 'TRANSFER' ? "From Location" : "Location"),
        child: Text(_selectedLocation ?? "Select Location",
            style: TextStyle(
                color: _selectedLocation == null ? textGrey : textDark)),
      ),
    );
  }

  Widget _buildToLocationDropdown(BuildContext context) {
    return InkWell(
      onTap: () => _showLocationPicker(
          context, (loc) => setState(() => _toLocation = loc),
          exclude: _selectedLocation),
      child: InputDecorator(
        decoration: _filledDeco("To Location"),
        child: Text(_toLocation ?? "Select Destination",
            style: TextStyle(color: _toLocation == null ? textGrey : textDark)),
      ),
    );
  }

  void _showLocationPicker(BuildContext context, Function(String) onSelect,
      {String? exclude}) {
    final locs = ['YARD', 'FACTORY'].where((l) => l != exclude).toList();
    showModalBottomSheet(
        context: context,
        builder: (ctx) => ListView(
              shrinkWrap: true,
              children: locs
                  .map((l) => ListTile(
                      title: Text(l),
                      onTap: () {
                        onSelect(l);
                        Navigator.pop(ctx);
                      }))
                  .toList(),
            ));
  }

  Widget _buildDateInput(BuildContext context) {
    return TextFormField(
      readOnly: true,
      decoration: _filledDeco("Date",
          suffix: const Icon(Icons.calendar_today, size: 16)),
      controller: TextEditingController(
          text:
              "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}"),
      onTap: () async {
        final d = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime.now());
        if (d != null) setState(() => _selectedDate = d);
      },
    );
  }

  Widget _buildAdvancedTransport(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text("Advanced Transport Details",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.indigo)),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        tilePadding: EdgeInsets.zero,
        children: [
          TextFormField(
              controller: _transportCompanyCtrl,
              decoration: _filledDeco("Transport Company")),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            bool stack = _shouldStack(context);
            List<Widget> children = [
              Flexible(
                flex: stack ? 0 : 1,
                fit: stack ? FlexFit.loose : FlexFit.tight,
                child: TextFormField(
                  controller: _driverNameCtrl,
                  decoration: _filledDeco("Driver Name"),
                ),
              ),
              if (!stack) const SizedBox(width: 12),
              if (stack) const SizedBox(height: 12),
              Flexible(
                flex: stack ? 0 : 1,
                fit: stack ? FlexFit.loose : FlexFit.tight,
                child: TextFormField(
                  controller: _driverPhoneCtrl,
                  decoration: _filledDeco("Driver Phone"),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ];

            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children)
                : Row(children: children);
          }),
          const SizedBox(height: 12),
          TextFormField(
              controller: _remarksCtrl,
              decoration: _filledDeco("General Remarks")),
        ],
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, int idx, _StockItemBlock item) {
    double totalMT = item.sizes
        .fold(0.0, (sum, sz) => sum + (double.tryParse(sz.mtCtrl.text) ?? 0.0));
    double rate = double.tryParse(item.basicRateCtrl.text) ?? 0.0;
    double totalAmt = totalMT * rate;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => item.isExpanded = !item.isExpanded),
            borderRadius: BorderRadius.vertical(
                top: const Radius.circular(20),
                bottom: Radius.circular(item.isExpanded ? 0 : 20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: msmRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.category_rounded, color: msmRed),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.selectedItemName ?? "Select Product",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: item.selectedItemName == null
                                ? textGrey
                                : textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: msmRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${totalMT.toStringAsFixed(3)} MT",
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: msmRed),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "₹ ${totalAmt.toStringAsFixed(0)}",
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: textDark),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    item.isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: msmRed,
                  ),
                ],
              ),
            ),
          ),
          if (item.isExpanded) ...[
            Divider(color: Colors.grey.shade100, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Type row
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text("Product Type",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: textGrey)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showItemPicker(context, item),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item.selectedItemName ?? "Select Item Type",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: item.selectedItemName == null
                                        ? textGrey
                                        : textDark,
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    color: msmRed, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => setState(() => _items.removeAt(idx)),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: msmRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: msmRed, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  ...item.sizes.map((sz) => _buildSizeRow(context, item, sz)),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () => setState(() => item.sizes.add(_StockSizeRow(
                          id: DateTime.now()
                              .millisecondsSinceEpoch
                              .toString()))),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: msmRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_outline_rounded,
                                color: msmRed, size: 16),
                            SizedBox(width: 6),
                            Text("Add Size",
                                style: TextStyle(
                                    color: msmRed,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ],
                        ),
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

  Widget _buildSizeRow(
      BuildContext context, _StockItemBlock item, _StockSizeRow sz) {
    double avail =
        _getAvailableStock(item.selectedItemName, sz.selectedSizeLabel);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        bool isNarrow = constraints.maxWidth < 400;

        Widget sizeInfo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                "SIZE / VARIANT",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: textGrey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Builder(builder: (context) {
              return InkWell(
                onTap: () => _showSizePicker(context, item, sz),
                child: InputDecorator(
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: msmRed, width: 1.5),
                    ),
                    suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: msmRed),
                  ),
                  child: Text(
                    sz.selectedSizeLabel == null
                        ? "Select Size"
                        : getFormattedSizeDisplay(sz.selectedSizeLabel!, null),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: sz.selectedSizeLabel == null
                          ? textGrey
                          : Colors.black87,
                    ),
                  ),
                ),
              );
            }),
            if (item.selectedItemName != null &&
                sz.selectedSizeLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                "Stock: ${avail.toStringAsFixed(3)} MT",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: avail > 0.1 ? Colors.teal : Colors.orange,
                ),
              ),
            ],
          ],
        );

        Widget weightInput = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                "WEIGHT (MT)",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: textGrey,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            TextFormField(
              controller: sz.mtCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              cursorColor: msmRed,
              onChanged: (v) => setState(() {}),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: textDark),
              decoration: InputDecoration(
                hintText: "0.000",
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade50,
                suffixText: "MT",
                suffixStyle: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 11, color: textGrey),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: msmRed, width: 1.5),
                ),
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (isNarrow) ...[
                sizeInfo,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: weightInput),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          color: textGrey, size: 22),
                      onPressed: () => setState(() => item.sizes.remove(sz)),
                    ),
                  ],
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 3, child: sizeInfo),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: weightInput),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          color: textGrey, size: 22),
                      onPressed: () => setState(() => item.sizes.remove(sz)),
                    ),
                  ],
                ),
            ],
          ),
        );
      }),
    );
  }

  String _getItemIconPath(String itemName) {
    String name = itemName.toLowerCase().trim();
    if (name.contains("pipe") && name.contains("hr"))
      return "assets/hr_pipe.png";
    if (name.contains("pipe")) return "assets/ms_pipe.png";
    if (name.contains("round")) return "assets/round_bar.png";
    if (name.contains("angle")) return "assets/angle.png";
    if (name.contains("channel")) return "assets/channel.png";
    if (name.contains("flat")) return "assets/flat.png";
    return "assets/msm_icon.jpg";
  }

  void _showItemPicker(BuildContext context, _StockItemBlock? block) {
    List<String> allNames = _masterItemData.keys.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        String query = "";
        return StatefulBuilder(
          builder: (context, setSheetState) {
            var filtered = applyPrioritizedSearch(query, allNames, (n) => n);
            if (_selectedType == 'OUT') {
              filtered = filtered.where((name) {
                double totalQty = 0;
                final sizes = _masterItemData[name] ?? [];
                for (var s in sizes)
                  totalQty += _getAvailableStock(name, s['label'].toString());
                return totalQty > 0.0001;
              }).toList();
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    top: 24,
                    left: 16,
                    right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Select Item",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textDark)),
                        const Icon(Icons.sort, color: msmRed),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: msmInputDeco("Search Item...",
                          prefix: const Icon(Icons.search, color: textGrey)),
                      onChanged: (val) => setSheetState(() => query = val),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(child: Text("No item found"))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                double totalQty = 0;
                                final sizes = _masterItemData[name] ?? [];
                                for (var s in sizes)
                                  totalQty += _getAvailableStock(
                                      name, s['label'].toString());

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                        color: msmRed.withValues(alpha: 0.05),
                                        shape: BoxShape.circle),
                                    child: Image.asset(_getItemIconPath(name),
                                        width: 24,
                                        height: 24,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.category,
                                                color: msmRed, size: 20)),
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: textDark)),
                                  trailing: (_selectedType == 'OUT' ||
                                          _selectedType == 'TRANSFER')
                                      ? Text(
                                          "${totalQty.toStringAsFixed(3)} MT",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                              fontSize: 14))
                                      : const Icon(Icons.chevron_right,
                                          size: 16, color: textGrey),
                                  onTap: () => Navigator.pop(context, name),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((selectedItemName) {
      if (selectedItemName != null && selectedItemName is String) {
        if (block != null) {
          setState(() {
            block.selectedItemName = selectedItemName;
            for (var s in block.sizes) {
              s.selectedSizeLabel = null;
            }
          });
        } else {
          setState(() {
            _items.add(_StockItemBlock(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              sizes: [
                _StockSizeRow(
                    id: DateTime.now().millisecondsSinceEpoch.toString())
              ],
              selectedItemName: selectedItemName,
            ));
          });
        }
      }
    });
  }

  void _showSizePicker(
      BuildContext context, _StockItemBlock block, _StockSizeRow szRow) async {
    if (block.selectedItemName == null) return;
    final selectedMaterialName = block.selectedItemName;
    final selectedMaterialId =
        DataRepository.getMaterialIdByName(selectedMaterialName);
    final allSizes = DataRepository.instance.itemSizes;

    final matchingSizes = allSizes.where((s) {
      final sMatId = s['material_id'] ?? s['materialId'];
      final sMatName = (s['material_name'] ?? s['materialName'])?.toString();
      final matchId = (selectedMaterialId != null &&
          sMatId != null &&
          sMatId.toString() == selectedMaterialId.toString());
      final matchName = (selectedMaterialName != null &&
          selectedMaterialName.trim().isNotEmpty &&
          sMatName != null &&
          sMatName.trim().toLowerCase() ==
              selectedMaterialName.trim().toLowerCase());
      return matchId || matchName;
    }).toList();

    final availableSizes = matchingSizes
        .where((row) {
          final label = (row['label'] ?? row['size_label'] ?? '').toString();
          if (label.isEmpty) return false;
          if (_selectedType == 'OUT') {
            return _getAvailableStock(block.selectedItemName, label) > 0.0001;
          }
          return true;
        })
        .map((row) => {
              'id': row['id'],
              'material_id': row['material_id'] ?? row['materialId'],
              'material_name': row['material_name'] ?? row['materialName'],
              'label': (row['label'] ?? row['size_label'] ?? '').toString(),
              'weight': double.tryParse(
                      (row['unit_weight_kg'] ?? row['weight'] ?? '0')
                          .toString()) ??
                  0.0,
              'sd': double.tryParse(
                      (row['size_difference'] ?? row['sd'] ?? '0')
                          .toString()) ??
                  0.0,
            })
        .toList();

    final result = await ResponsiveSizePicker.show(
      context,
      itemType: block.selectedItemName!,
      materialId: selectedMaterialId,
      customSizes: availableSizes,
      trailingBuilder: (sizeData) {
        if (_selectedType == 'OUT' || _selectedType == 'TRANSFER') {
          final sizeLabel = (sizeData['label'] ?? '').toString();
          double qty = _getAvailableStock(block.selectedItemName, sizeLabel);
          return Text(
            "${qty.toStringAsFixed(3)} MT",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 14,
            ),
          );
        }
        return null;
      },
    );

    if (result != null) {
      setState(() {
        szRow.selectedSizeLabel = result['label'].toString();
      });
    }
  }

  Widget _buildAddItemButton(BuildContext context) {
    return TextButton.icon(
      onPressed: _addItem,
      icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
      label: const Text("ADD ITEM",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.blue.withValues(alpha: 0.08),
        foregroundColor: Colors.blue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildSplitLoading(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Split Loading (Hand vs Crane)",
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            bool stack = _shouldStack(context);
            List<Widget> children = [
              Flexible(
                flex: stack ? 0 : 1,
                fit: stack ? FlexFit.loose : FlexFit.tight,
                child: TextFormField(
                  controller: _handMTCtrl,
                  decoration: _filledDeco("Hand MT"),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              if (!stack) const SizedBox(width: 12),
              if (stack) const SizedBox(height: 12),
              Flexible(
                flex: stack ? 0 : 1,
                fit: stack ? FlexFit.loose : FlexFit.tight,
                child: TextFormField(
                  controller: _craneMTCtrl,
                  decoration: _filledDeco("Crane MT"),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ];

            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children)
                : Row(children: children);
          }),
        ],
      ),
    );
  }
}

class StockTransactionTotalWeightCard extends StatelessWidget {
  final double totalWeight;
  final bool isSubmitting;
  final VoidCallback onProceed;

  const StockTransactionTotalWeightCard({
    super.key,
    required this.totalWeight,
    required this.isSubmitting,
    required this.onProceed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 500;

    Widget weightWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "TOTAL WEIGHT",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: textGrey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "${totalWeight.toStringAsFixed(3)} MT",
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: msmRed,
          ),
        ),
      ],
    );

    Widget buttonWidget = SizedBox(
      height: 46,
      width: isMobile ? double.infinity : 200,
      child: FilledButton.icon(
        onPressed: isSubmitting ? null : onProceed,
        style: FilledButton.styleFrom(
          backgroundColor: msmRed,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 1,
        ),
        icon: isSubmitting
            ? const MLoader(size: 16, color: Colors.white)
            : const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text(
          "Proceed",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    weightWidget,
                  ],
                ),
                const SizedBox(height: 12),
                buttonWidget,
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                weightWidget,
                buttonWidget,
              ],
            ),
    );
  }
}

class _StockItemBlock {
  final String id;
  String? selectedItemName;
  List<_StockSizeRow> sizes;
  bool isExpanded;
  final TextEditingController basicRateCtrl = TextEditingController();

  _StockItemBlock({
    required this.id,
    required this.sizes,
    this.selectedItemName,
    this.isExpanded = true,
  });
}

class _StockSizeRow {
  final String id;
  String? selectedSizeLabel;
  final TextEditingController mtCtrl = TextEditingController();
  final TextEditingController noteCtrl = TextEditingController();
  _StockSizeRow({required this.id});
}
