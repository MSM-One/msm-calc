import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/motion_toast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/sheet_service.dart';
import '../services/vendor_purchase_export_service.dart';
import '../services/data_repository.dart';
import '../services/supabase_realtime_service.dart';
import '../models/stock_role.dart';
// For Global Key
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../utils/sorting_utils.dart';
import 'package:flutter/foundation.dart';
import '../utils/formatters.dart';
import 'package:printing/printing.dart';
import 'sauda_entry_screen.dart';
import '../widgets/shimmer_widget.dart';
import '../widgets/vendor_search_autocomplete.dart';
import '../widgets/searchable_vendor_modal.dart';

class VendorPurchaseReportScreen extends StatefulWidget {
  const VendorPurchaseReportScreen({super.key});

  @override
  State<VendorPurchaseReportScreen> createState() =>
      _VendorPurchaseReportScreenState();
}

class _VendorPurchaseReportScreenState
    extends State<VendorPurchaseReportScreen> {
  static const Color primaryRed = Color(0xFFD71920);

  // We now use global notifiers for persistence and easy clearing
  List<dynamic> _filteredReports = [];
  bool _isLoading = true;
  bool _isExporting = false;
  bool _showHidden = false;

  String? _selectedVendor;
  String? _selectedItem;
  String? _selectedRegion;
  String? _selectedLocation;

  List<String> _vendors = [];
  List<String> _items = [];
  List<String> _regions = [];
  List<String> _locations = [];

  DateTime? _cutoffTimestamp;
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    DataRepository.vendorSaudaListNotifier.addListener(_onSaudaNotifierChanged);
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _loadReports();
    });

    // --- Hard Navigation Guard ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = DataRepository.currentUserNotifier.value;
      if (!hasVendorPurchaseAccess(user)) {
        MotionToast.show(context, "Access Denied: Missing Permission",
            isError: true);
        Navigator.pop(context);
      }
    });

    // Only load if the list is currently empty, or we can force refresh
    if (DataRepository.vendorSaudaListNotifier.value.isEmpty) {
      _loadReports();
    } else {
      _isLoading = false;
      _applyFilters();
    }
  }

  void _onSaudaNotifierChanged() {
    if (!mounted) return;
    _applyFilters();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    DataRepository.vendorSaudaListNotifier
        .removeListener(_onSaudaNotifierChanged);
    super.dispose();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _cutoffTimestamp = await DataRepository.getVendorResetTimestamp();
      final reports = await SheetService.fetchSaudaReports();
      if (mounted) {
        DataRepository.vendorSaudaListNotifier.value = reports;
        _updateFilterLists(reports);
        await _applyFilters();
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("[VendorReport] Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateFilterLists(List<dynamic> reports) {
    _vendors = reports
        .map((e) => e['party']?.toString() ?? "")
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _items = reports
        .map((e) => e['item']?.toString() ?? "")
        .where((i) => i.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));
    _regions = reports
        .map((e) => e['reg']?.toString() ?? e['region']?.toString() ?? "")
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _locations = reports
        .map((e) => e['location']?.toString() ?? "YARD")
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _applyFilters() async {
    _cutoffTimestamp ??= await DataRepository.getVendorResetTimestamp();

    List<dynamic> reports = DataRepository.vendorSaudaListNotifier.value;
    List<dynamic> analyticsReports = [];
    List<dynamic> uiFilteredReports = [];

    for (var r in reports) {
      // 1. Permanent Reset Filter (ID based timestamp)
      if (_cutoffTimestamp != null) {
        final String srNo = r['srNo']?.toString() ?? "";
        if (srNo.startsWith("S-")) {
          final int? tsMs = int.tryParse(srNo.substring(2));
          if (tsMs != null && tsMs < _cutoffTimestamp!.millisecondsSinceEpoch) {
            continue; // Skip older data
          }
        }
      }

      // 2. UI Dropdown Filters
      bool matchesVendor =
          _selectedVendor == null || r['party'] == _selectedVendor;
      bool matchesItem = _selectedItem == null || r['item'] == _selectedItem;
      bool matchesRegion =
          _selectedRegion == null || (r['region'] ?? "YARD") == _selectedRegion;
      bool matchesLocation = _selectedLocation == null ||
          (r['location'] ?? "YARD") == _selectedLocation;

      if (matchesVendor && matchesItem && matchesRegion && matchesLocation) {
        // Included in Analytics & Average Rate calculation (INCLUDES hidden items)
        analyticsReports.add(r);

        // Robust boolean evaluation for hidden state
        final rawHidden = r['is_hidden'] ?? r['isHidden'];
        final bool isHidden = rawHidden == true ||
            rawHidden == 1 ||
            rawHidden?.toString().toLowerCase() == 'true' ||
            rawHidden?.toString() == '1';

        // Included in UI list display (strictly exclude hidden items if _showHidden is false)
        if (!_showHidden && isHidden) {
          // Skip adding to UI display list
        } else {
          uiFilteredReports.add(r);
        }
      }
    }

    // Average Rate & Total Qty include hidden items
    _calculateAnalytics(analyticsReports);

    if (mounted) {
      setState(() {
        _filteredReports = uiFilteredReports;
      });
    }
  }

  void _calculateAnalytics(List<dynamic> data) {
    double sumQty = 0;
    double totalValue = 0;

    for (var r in data) {
      double q = (r['ord'] as num?)?.toDouble() ?? 0.0;
      double rt = (r['rate'] as num?)?.toDouble() ?? 0.0;
      sumQty += q;
      totalValue += (q * rt);
    }

    DataRepository.vendorTotalQtyNotifier.value = sumQty;
    // Weighted Average Calculation: Sum(Rate * Qty) / Sum(Qty)
    DataRepository.vendorAvgRateNotifier.value =
        sumQty > 0 ? totalValue / sumQty : 0.0;
  }

  Future<void> _showManualReceiveDialog(Map<String, dynamic> report) async {
    final TextEditingController qtyController = TextEditingController();
    final String saudaId = report['srNo']?.toString() ?? "";
    final String party = report['party']?.toString() ?? "Vendor";
    final String item = report['item']?.toString() ?? "Item";
    final String size = report['size']?.toString() ?? "";

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Manual Stock Receive"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Vendor: $party",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Item: $item ${getFormattedSizeDisplay(size, null)}"),
            const SizedBox(height: 16),
            const Text(
                "Enter quantity to receive. This will update Sauda Balance and ADD this quantity to your Current Stock."),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
              ],
              decoration: const InputDecoration(
                labelText: "Quantity (MT)",
                border: OutlineInputBorder(),
                suffixText: "MT",
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              if (double.tryParse(qtyController.text) != null) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("CONFIRM & UPDATE",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final double qty = double.parse(qtyController.text);
      if (qty <= 0) return;

      setState(() => _isLoading = true);
      try {
        final result = await SheetService.manualSaudaReceive(
          saudaId: saudaId,
          enteredQty: qty,
          userEmail: UserSession.userEmail ?? "Admin",
        );

        if (result.success) {
          MotionToast.show(context,
              "Successfully received ${qty.toStringAsFixed(3)} MT for $party");
          await _loadReports(); // Refresh data
        } else {
          MotionToast.show(context, "Error: ${result.errorMessage}",
              isError: true);
        }
      } catch (e) {
        debugPrint("Manual Receive Error: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleHideSauda(Map<String, dynamic> report) async {
    final String saudaId = report['srNo']?.toString() ??
        report['txn_id']?.toString() ??
        report['id']?.toString() ??
        "";
    if (saudaId.isEmpty) return;

    final rawHidden = report['is_hidden'] ?? report['isHidden'];
    final bool currentlyHidden = rawHidden == true ||
        rawHidden == 1 ||
        rawHidden?.toString().toLowerCase() == 'true' ||
        rawHidden?.toString() == '1';
    final bool newHiddenState = !currentlyHidden;

    setState(() => _isLoading = true);
    try {
      final result = await DataRepository.toggleSaudaHiddenStatus(
        saudaId: saudaId,
        isHidden: newHiddenState,
      );

      if (result.success) {
        if (mounted) {
          MotionToast.show(
            context,
            newHiddenState
                ? "Sauda marked as Hidden (still included in Avg Rate)"
                : "Sauda unhidden",
          );
        }
        await _loadReports();
      } else {
        if (mounted) {
          MotionToast.show(
              context, "Error toggling hidden: ${result.errorMessage}",
              isError: true);
        }
      }
    } catch (e) {
      debugPrint("[VendorReport] Toggle Hide Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditSaudaDialog(Map<String, dynamic> report) async {
    final String saudaId = report['srNo']?.toString() ??
        report['txn_id']?.toString() ??
        report['id']?.toString() ??
        "";
    if (saudaId.isEmpty) return;

    final String party = report['party']?.toString() ?? "Vendor";
    final String item = report['item']?.toString() ?? "Item";
    final String size = report['size']?.toString() ?? "";
    final String dateStr = report['date']?.toString() ?? "";
    final String region = report['region']?.toString() ?? "YARD";
    final String location = report['location']?.toString() ?? "YARD";
    final double currentQty = (report['ord'] as num?)?.toDouble() ?? 0.0;
    final double currentRate = (report['rate'] as num?)?.toDouble() ?? 0.0;

    final TextEditingController dateController = TextEditingController(
        text: dateStr.isNotEmpty
            ? dateStr
            : DateFormat('dd/MM/yyyy').format(DateTime.now()));
    final TextEditingController vendorController =
        TextEditingController(text: party);
    final TextEditingController itemController =
        TextEditingController(text: item);
    final TextEditingController sizeController =
        TextEditingController(text: size);
    final TextEditingController qtyController = TextEditingController(
        text: currentQty > 0 ? currentQty.toString() : '');
    final TextEditingController rateController = TextEditingController(
        text: currentRate > 0 ? currentRate.toString() : '');

    String selectedRegion = region.isNotEmpty ? region : "YARD";
    String selectedLocation = location.isNotEmpty ? location : "YARD";

    final List<String> availableRegions =
        _regions.isNotEmpty ? List.from(_regions) : ["RAIPUR", "JALNA", "YARD"];
    final List<String> availableLocations =
        _locations.isNotEmpty ? List.from(_locations) : ["YARD", "FACTORY"];

    if (!availableRegions.contains(selectedRegion)) {
      availableRegions.add(selectedRegion);
    }
    if (!availableLocations.contains(selectedLocation)) {
      availableLocations.add(selectedLocation);
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: primaryRed),
              SizedBox(width: 8),
              Text("Edit Sauda Entry",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Date Field
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: "Date (DD/MM/YYYY)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                  ),
                  onTap: () async {
                    DateTime initial = DateTime.now();
                    try {
                      initial =
                          DateFormat('dd/MM/yyyy').parse(dateController.text);
                    } catch (_) {}

                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        dateController.text =
                            DateFormat('dd/MM/yyyy').format(picked);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                // 2. Vendor Name Field (Autocomplete)
                VendorSearchAutocomplete(
                  controller: vendorController,
                  existingVendors: _vendors,
                  onVendorSelected: (val) => vendorController.text = val,
                  labelText: "Vendor Name",
                ),
                const SizedBox(height: 12),

                // 3. Item / Material Category Field
                TextField(
                  controller: itemController,
                  decoration: const InputDecoration(
                    labelText: "Item / Material Category",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Size / Specification Field
                TextField(
                  controller: sizeController,
                  decoration: const InputDecoration(
                    labelText: "Size / Specification",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.straighten_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Quantity (MT) Field
                TextField(
                  controller: qtyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
                  ],
                  decoration: const InputDecoration(
                    labelText: "Quantity (MT)",
                    border: OutlineInputBorder(),
                    suffixText: "MT",
                  ),
                ),
                const SizedBox(height: 12),

                // 6. Basic Rate (₹/MT) Field
                TextField(
                  controller: rateController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
                  ],
                  decoration: const InputDecoration(
                    labelText: "Basic Rate (₹/MT)",
                    border: OutlineInputBorder(),
                    prefixText: "₹ ",
                  ),
                ),
                const SizedBox(height: 12),

                // 7. Region Dropdown
                DropdownButtonFormField<String>(
                  initialValue: selectedRegion,
                  decoration: const InputDecoration(
                    labelText: "Region",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.map_rounded, size: 20),
                  ),
                  items: availableRegions
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedRegion = val);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // 8. Location Dropdown
                DropdownButtonFormField<String>(
                  initialValue: selectedLocation,
                  decoration: const InputDecoration(
                    labelText: "Location",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_rounded, size: 20),
                  ),
                  items: availableLocations
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedLocation = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () {
                final v = vendorController.text.trim();
                final i = itemController.text.trim();
                final q = double.tryParse(qtyController.text);
                final r = double.tryParse(rateController.text);
                if (v.isNotEmpty &&
                    i.isNotEmpty &&
                    q != null &&
                    q > 0 &&
                    r != null &&
                    r >= 0) {
                  Navigator.pop(dialogContext, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("SAVE CHANGES"),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final String newDate = dateController.text.trim();
      final String newVendor = vendorController.text.trim();
      final String newItem = itemController.text.trim();
      final String newSize = sizeController.text.trim();
      final double newQty = double.parse(qtyController.text);
      final double newRate = double.parse(rateController.text);
      final double receivedQty = (report['rec'] as num?)?.toDouble() ?? 0.0;

      // 1. Validation for vendor change when stock has already been received
      if (newVendor != party && receivedQty > 0) {
        final bool? transferConfirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: primaryRed),
                SizedBox(width: 8),
                Text("Confirm Vendor Transfer",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              "This Sauda has received stock entries ($receivedQty MT). Changing the vendor will transfer all associated records to $newVendor. Proceed?",
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("CANCEL"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("PROCEED"),
              ),
            ],
          ),
        );
        if (transferConfirm != true) return;
      }

      setState(() => _isLoading = true);
      try {
        final result = await DataRepository.updatePurchaseEntry(
          saudaId: saudaId,
          qtyMt: newQty,
          rate: newRate,
          vendorName: newVendor != party ? newVendor : null,
          itemName: newItem != item ? newItem : null,
          size: newSize != size ? newSize : null,
          region: selectedRegion != region ? selectedRegion : null,
          location: selectedLocation != location ? selectedLocation : null,
          date: newDate != dateStr ? newDate : null,
        );

        if (result.success) {
          if (mounted) {
            if (newVendor != party) {
              MotionToast.show(context,
                  "Vendor updated successfully from $party to $newVendor");
            } else {
              MotionToast.show(context, "Sauda entry updated successfully.");
            }
          }
          await _loadReports();
        } else {
          if (mounted) {
            MotionToast.show(
                context, "Error updating sauda: ${result.errorMessage}",
                isError: true);
          }
        }
      } catch (e) {
        debugPrint("[VendorReport] Edit Error: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showDeleteConfirmation(Map<String, dynamic> report) async {
    final String entryId = report['srNo']?.toString() ??
        report['txn_id']?.toString() ??
        report['id']?.toString() ??
        "";
    if (entryId.isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content:
            const Text("Are you sure you want to delete this purchase entry?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE52823)),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final result = await DataRepository.deletePurchaseEntry(entryId);
        if (result.success) {
          MotionToast.show(context, "Purchase entry deleted successfully");
          await _loadReports();
        } else {
          MotionToast.show(
              context, "Error deleting entry: ${result.errorMessage}",
              isError: true);
        }
      } catch (e) {
        debugPrint("[VendorReport] Delete Error: $e");
        MotionToast.show(context, "Delete failed: $e", isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showResetConfirmation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Report View?"),
        content: const Text(
            "This will clear the screen locally. Use Refresh to bring data back from the cloud."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE52823)),
            child: const Text("RESET", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        setState(() => _isLoading = true);
        await DataRepository.clearVendorPurchaseCache();
        _cutoffTimestamp = await DataRepository.getVendorResetTimestamp();

        if (mounted) {
          await _applyFilters();
          setState(() {
            _vendors = [];
            _items = [];
            _regions = [];
            _locations = [];
            _selectedVendor = null;
            _selectedItem = null;
            _selectedRegion = null;
            _selectedLocation = null;
            _isLoading = false;
          });
          MotionToast.show(
              context, "Report view reset permanently on this device.");
        }
      });
    }
  }

  void _showItemWiseSummary() {
    // Calculate item-wise weighted averages
    final Map<String, List<Map<String, dynamic>>> itemGroups = {};
    for (var r in _filteredReports) {
      final String item = r['item']?.toString() ?? "Unknown";
      itemGroups.putIfAbsent(item, () => []).add(r);
    }

    final List<Map<String, dynamic>> summaryList = [];
    itemGroups.forEach((item, reports) {
      double sumQty = 0;
      double totalValue = 0;
      for (var r in reports) {
        double q = (r['ord'] as num?)?.toDouble() ?? 0.0;
        double rt = (r['rate'] as num?)?.toDouble() ?? 0.0;
        sumQty += q;
        totalValue += (q * rt);
      }
      summaryList.add({
        'item': item,
        'totalQty': sumQty,
        'avgRate': sumQty > 0 ? totalValue / sumQty : 0.0,
      });
    });

    summaryList.sort((a, b) => SortingUtils.compareCategories(
        a['item'].toString(), b['item'].toString()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Item-wise Summary",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("Based on current filters",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: summaryList.length,
                separatorBuilder: (context, index) =>
                    Divider(color: Colors.grey.shade100),
                itemBuilder: (context, index) {
                  final s = summaryList[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(s['item'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text("${s['totalQty'].toStringAsFixed(2)} MT",
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text("₹ ${s['avgRate'].toStringAsFixed(0)}",
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFFE52823))),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE52823),
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("CLOSE",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAndSharePDF() async {
    if (_filteredReports.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final pdfBytes = await VendorPurchaseExportService.generatePdf(
        reports: _filteredReports,
        totalQty: DataRepository.vendorTotalQtyNotifier.value,
        avgRate: DataRepository.vendorAvgRateNotifier.value,
      );

      final dateStr = DateFormat('dd_MMM_yyyy').format(DateTime.now());
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: 'Vendor_Purchase_Report_$dateStr.pdf',
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final file =
            File('${tempDir.path}/Vendor_Purchase_Report_$dateStr.pdf');
        await file.writeAsBytes(pdfBytes);

        await Share.shareXFiles([XFile(file.path)],
            text: 'Vendor Purchase Report ($dateStr)');
      }
    } catch (e) {
      debugPrint("[ExportPDF] Error: $e");
      if (mounted) {
        MotionToast.show(context, "Error generating PDF: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _generateAndShareExcel() async {
    if (_filteredReports.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final excelBytes = await VendorPurchaseExportService.generateExcel(
        reports: _filteredReports,
      );

      final tempDir = await getTemporaryDirectory();
      final dateStr = DateFormat('dd_MMM_yyyy').format(DateTime.now());
      final file = File('${tempDir.path}/Vendor_Purchase_Report_$dateStr.xlsx');
      await file.writeAsBytes(excelBytes);

      await Share.shareXFiles([XFile(file.path)],
          text: 'Vendor Purchase Report ($dateStr)');
    } catch (e) {
      debugPrint("[ExportExcel] Error: $e");
      if (mounted) {
        MotionToast.show(context, "Error generating Excel: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _openVendorPurchaseForm(BuildContext context) async {
    final user = DataRepository.currentUserNotifier.value;
    if (!hasVendorPurchaseAccess(user)) {
      MotionToast.show(context, "Access Denied: Missing Permission",
          isError: true);
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SaudaEntryScreen()),
    );
    if (result == true) {
      _loadReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryRed = Color(0xFFD71920);
    const Color bgLight = Color(0xFFF8FAFC);
    const Color borderColor = Color(0xFFE5E7EB);
    const Color darkText = Color(0xFF111827);
    const Color greyText = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: primaryRed,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Vendor Purchase",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            Text(
              "Purchase reports ledger",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: _isLoading ? null : _loadReports,
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openVendorPurchaseForm(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 4),
                      Text("Add",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Colors.white,
            onSelected: (val) {
              if (val == 'pdf') _generateAndSharePDF();
              if (val == 'excel' && UserSession.currentRole == StockRole.ADMIN)
                _generateAndShareExcel();
              if (val == 'reset') _showResetConfirmation();
              if (val == 'summary') _showItemWiseSummary();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pdf',
                child: _PopupRow(
                    icon: Icons.picture_as_pdf_rounded,
                    color: primaryRed,
                    label: "Export PDF"),
              ),
              if (UserSession.currentRole == StockRole.ADMIN)
                const PopupMenuItem(
                  value: 'excel',
                  child: _PopupRow(
                      icon: Icons.table_view_rounded,
                      color: Colors.green,
                      label: "Export Excel"),
                ),
              const PopupMenuItem(
                value: 'reset',
                child: _PopupRow(
                    icon: Icons.restart_alt_rounded,
                    color: greyText,
                    label: "Reset View"),
              ),
              const PopupMenuItem(
                value: 'summary',
                child: _PopupRow(
                    icon: Icons.analytics_outlined,
                    color: Colors.blue,
                    label: "Item Summary"),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: _isExporting
              ? const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 2,
                )
              : Container(
                  color: Colors.white.withValues(alpha: 0.15), height: 1),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        color: primaryRed,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Summary Cards Grid ───────────────────────────────────
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalQtyCard = ValueListenableBuilder<double>(
                          valueListenable:
                              DataRepository.vendorTotalQtyNotifier,
                          builder: (context, val, _) => _buildSummaryCard(
                            "Total Quantity",
                            "${val.toStringAsFixed(3)} MT",
                            Icons.inventory_2_outlined,
                            primaryRed,
                          ),
                        );
                        final avgRateCard = ValueListenableBuilder<double>(
                          valueListenable: DataRepository.vendorAvgRateNotifier,
                          builder: (context, val, _) => _buildSummaryCard(
                            "Weighted Avg Rate",
                            "₹ ${val.toStringAsFixed(2)}",
                            Icons.trending_up_rounded,
                            Colors.indigo,
                          ),
                        );

                        if (constraints.maxWidth > 500) {
                          return Row(
                            children: [
                              Expanded(child: totalQtyCard),
                              const SizedBox(width: 12),
                              Expanded(child: avgRateCard),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              totalQtyCard,
                              const SizedBox(height: 10),
                              avgRateCard,
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // ── Quick Summary Action Button ──────────────────────────
                    OutlinedButton.icon(
                      onPressed: _showItemWiseSummary,
                      icon: const Icon(Icons.analytics_outlined,
                          color: primaryRed, size: 16),
                      label: const Text(
                        "Show Item-wise Summary",
                        style: TextStyle(
                            color: primaryRed,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: primaryRed.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Filters Panel (Glassmorphism/Frost Card) ──────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 600;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.tune_rounded,
                                          size: 16, color: primaryRed),
                                      const SizedBox(width: 6),
                                      const Text(
                                        "Filters",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: darkText,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              primaryRed.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          "${_filteredReports.length} ${(_filteredReports.length == 1) ? 'Sauda' : 'Saude'}",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: primaryRed,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(
                                          () => _showHidden = !_showHidden);
                                      _applyFilters();
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Switch.adaptive(
                                            value: _showHidden,
                                            onChanged: (val) {
                                              setState(() => _showHidden = val);
                                              _applyFilters();
                                            },
                                            activeThumbColor: primaryRed,
                                            activeTrackColor: primaryRed
                                                .withValues(alpha: 0.5),
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            "Show Hidden",
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: darkText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Divider(height: 1, color: borderColor),
                              const SizedBox(height: 8),
                              if (isCompact) ...[
                                _buildSearchableVendorSelectorRow(
                                  icon: Icons.person_search_outlined,
                                  hint: "All Vendors",
                                  value: _selectedVendor,
                                  items: _vendors,
                                  onChanged: (v) {
                                    setState(() => _selectedVendor = v);
                                    _applyFilters();
                                  },
                                ),
                                const Divider(height: 1, color: borderColor),
                                _buildFilterDropdownRow(
                                  icon: Icons.grid_view_rounded,
                                  hint: "All Items",
                                  value: _selectedItem,
                                  items: _items,
                                  onChanged: (v) {
                                    setState(() => _selectedItem = v);
                                    _applyFilters();
                                  },
                                ),
                                const Divider(height: 1, color: borderColor),
                                _buildFilterDropdownRow(
                                  icon: Icons.map_rounded,
                                  hint: "All Regions",
                                  value: _selectedRegion,
                                  items: _regions,
                                  onChanged: (v) {
                                    setState(() => _selectedRegion = v);
                                    _applyFilters();
                                  },
                                ),
                                const Divider(height: 1, color: borderColor),
                                _buildFilterDropdownRow(
                                  icon: Icons.location_on_rounded,
                                  hint: "All Locations",
                                  value: _selectedLocation,
                                  items: _locations,
                                  onChanged: (v) {
                                    setState(() => _selectedLocation = v);
                                    _applyFilters();
                                  },
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSearchableVendorSelectorRow(
                                        icon: Icons.person_search_outlined,
                                        hint: "All Vendors",
                                        value: _selectedVendor,
                                        items: _vendors,
                                        onChanged: (v) {
                                          setState(() => _selectedVendor = v);
                                          _applyFilters();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _buildFilterDropdownRow(
                                        icon: Icons.grid_view_rounded,
                                        hint: "All Items",
                                        value: _selectedItem,
                                        items: _items,
                                        onChanged: (v) {
                                          setState(() => _selectedItem = v);
                                          _applyFilters();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 12, color: borderColor),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildFilterDropdownRow(
                                        icon: Icons.map_rounded,
                                        hint: "All Regions",
                                        value: _selectedRegion,
                                        items: _regions,
                                        onChanged: (v) {
                                          setState(() => _selectedRegion = v);
                                          _applyFilters();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _buildFilterDropdownRow(
                                        icon: Icons.location_on_rounded,
                                        hint: "All Locations",
                                        value: _selectedLocation,
                                        items: _locations,
                                        onChanged: (v) {
                                          setState(() => _selectedLocation = v);
                                          _applyFilters();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ]
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Main Reports Section ─────────────────────────────────
                    if (_isLoading)
                      _buildShimmerTable()
                    else if (_filteredReports.isEmpty)
                      _buildEmptyState()
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: MediaQuery.of(context).size.width >
                                        800
                                    ? 800
                                    : MediaQuery.of(context).size.width - 32,
                              ),
                              child: DataTable(
                                headingRowHeight: 46,
                                dataRowHeight: 56,
                                headingRowColor: WidgetStateProperty.all(
                                    Colors.grey.shade50),
                                horizontalMargin: 16,
                                columnSpacing: 20,
                                columns: const [
                                  DataColumn(
                                      label: Text("Date",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Vendor",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Material (Size)",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Rate",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Order (MT)",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Received",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Balance",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: primaryRed))),
                                  DataColumn(
                                      label: Text("Region",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Loc",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                  DataColumn(
                                      label: Text("Action",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: darkText))),
                                ],
                                rows: _filteredReports.map((r) {
                                  final String item =
                                      r['item']?.toString() ?? "";
                                  final String size =
                                      r['size']?.toString() ?? "";
                                  final double ord =
                                      (r['ord'] as num?)?.toDouble() ?? 0.0;
                                  final double rec =
                                      (r['rec'] as num?)?.toDouble() ?? 0.0;
                                  final double bal = r['bal'] != null
                                      ? (r['bal'] as num).toDouble()
                                      : ord - rec;
                                  final String dateRaw =
                                      r['date']?.toString() ?? "";
                                  String dateDisplay = dateRaw;
                                  try {
                                    if (dateRaw.isNotEmpty) {
                                      final dt = DateTime.parse(dateRaw);
                                      dateDisplay =
                                          DateFormat('dd/MM/yyyy').format(dt);
                                    }
                                  } catch (_) {}

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(dateDisplay,
                                          style: const TextStyle(
                                              fontSize: 11, color: darkText))),
                                      DataCell(SizedBox(
                                        width: 130,
                                        child: Text(
                                          r['party']?.toString() ?? "",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: darkText),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                                      DataCell(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(item,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: darkText)),
                                          if (size.isNotEmpty)
                                            Text(
                                                formatMaterialSize(
                                                    size,
                                                    r['unitWeightKg'] ??
                                                        r['unitWeight']),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: greyText)),
                                        ],
                                      )),
                                      DataCell(Text("₹ ${r['rate']}",
                                          style: const TextStyle(
                                              fontSize: 12, color: darkText))),
                                      DataCell(Text(ord.toStringAsFixed(3),
                                          style: const TextStyle(
                                              fontSize: 12, color: darkText))),
                                      DataCell(
                                        InkWell(
                                          onTap: AccessGuard.can(
                                                  AppPermissions.vendorPurchase)
                                              ? () =>
                                                  _showManualReceiveDialog(r)
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 3),
                                            decoration: AccessGuard.can(
                                                    AppPermissions
                                                        .vendorPurchase)
                                                ? BoxDecoration(
                                                    border: Border.all(
                                                        color: Colors.green
                                                            .withValues(
                                                                alpha: 0.3)),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    color: Colors.green
                                                        .withValues(
                                                            alpha: 0.05),
                                                  )
                                                : null,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  rec.toStringAsFixed(3),
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                if (AccessGuard.can(
                                                    AppPermissions
                                                        .vendorPurchase)) ...[
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                      Icons.edit_note_rounded,
                                                      size: 14,
                                                      color: Colors.green),
                                                ]
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(
                                        bal.toStringAsFixed(3),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              bal > 0 ? primaryRed : greyText,
                                        ),
                                      )),
                                      DataCell(Text(
                                          r['region']?.toString() ?? "YARD",
                                          style: const TextStyle(
                                              fontSize: 11, color: darkText))),
                                      DataCell(Text(
                                          r['location']?.toString() ?? "YARD",
                                          style: const TextStyle(
                                              fontSize: 11, color: darkText))),
                                      DataCell(
                                        PopupMenuButton<String>(
                                          icon: const Icon(
                                              Icons.more_vert_rounded,
                                              size: 20,
                                              color: darkText),
                                          tooltip: "Sauda Actions",
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          onSelected: (val) {
                                            Future.microtask(() {
                                              if (!mounted) return;
                                              if (val == 'receive') {
                                                _showManualReceiveDialog(r);
                                              } else if (val == 'hide') {
                                                _toggleHideSauda(r);
                                              } else if (val == 'edit') {
                                                _showEditSaudaDialog(r);
                                              } else if (val == 'delete') {
                                                _showDeleteConfirmation(r);
                                              }
                                            });
                                          },
                                          itemBuilder: (context) => [
                                            if (AccessGuard.can(
                                                AppPermissions.vendorPurchase))
                                              const PopupMenuItem(
                                                value: 'receive',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .move_to_inbox_rounded,
                                                        color: Colors.green,
                                                        size: 18),
                                                    SizedBox(width: 8),
                                                    Text("Receive Stock",
                                                        style: TextStyle(
                                                            fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                            if (AccessGuard.can(
                                                AppPermissions.vendorPurchase))
                                              PopupMenuItem(
                                                value: 'hide',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      (r['is_hidden'] == true ||
                                                              r['isHidden'] ==
                                                                  true ||
                                                              r['is_hidden']
                                                                      ?.toString()
                                                                      .toLowerCase() ==
                                                                  'true' ||
                                                              r['isHidden']
                                                                      ?.toString()
                                                                      .toLowerCase() ==
                                                                  'true')
                                                          ? Icons
                                                              .visibility_outlined
                                                          : Icons
                                                              .visibility_off_outlined,
                                                      color: Colors.blue,
                                                      size: 18,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      (r['is_hidden'] == true ||
                                                              r['isHidden'] ==
                                                                  true ||
                                                              r['is_hidden']
                                                                      ?.toString()
                                                                      .toLowerCase() ==
                                                                  'true' ||
                                                              r['isHidden']
                                                                      ?.toString()
                                                                      .toLowerCase() ==
                                                                  'true')
                                                          ? "Unhide Sauda"
                                                          : "Hide Sauda",
                                                      style: const TextStyle(
                                                          fontSize: 13),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (AccessGuard.can(
                                                AppPermissions.vendorPurchase))
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined,
                                                        color: Colors.orange,
                                                        size: 18),
                                                    SizedBox(width: 8),
                                                    Text("Edit Sauda",
                                                        style: TextStyle(
                                                            fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                            if (AccessGuard.can(AppPermissions
                                                    .vendorPurchase) ||
                                                AccessGuard.can(
                                                    AppPermissions.usersDelete))
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        color: primaryRed,
                                                        size: 18),
                                                    SizedBox(width: 8),
                                                    Text("Delete Sauda",
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: primaryRed)),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isExporting ? null : _generateAndSharePDF,
        backgroundColor: primaryRed,
        icon: _isExporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
        label: Text(_isExporting ? "Exporting..." : "Export PDF",
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSummaryCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchableVendorSelectorRow({
    required IconData icon,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final bool hasSelection = value != null && value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final picked = await SearchableVendorModal.show(
              context,
              allVendors: items,
              selectedVendor: value,
              title: "Select Vendor",
              allOptionLabel: "All Vendors",
            );
            if (picked != null) {
              onChanged(picked.isEmpty ? null : picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFD71920), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSelection)
                        const Text(
                          "Vendor",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD71920),
                          ),
                        ),
                      Text(
                        hasSelection ? value : hint,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: hasSelection
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: hasSelection
                              ? const Color(0xFF111827)
                              : const Color(0xFF6B7280),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                if (hasSelection)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(null),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.cancel_rounded,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Color(0xFF6B7280),
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdownRow({
    required IconData icon,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD71920), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                hint: Text(hint,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF6B7280))),
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down_rounded,
                    color: Color(0xFF6B7280)),
                items: [
                  DropdownMenuItem(
                      value: null,
                      child: Text(hint, style: const TextStyle(fontSize: 13))),
                  ...items.map((i) => DropdownMenuItem(
                        value: i,
                        child: Text(i,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF111827))),
                      ))
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  )
                ]),
            child: Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 18),
          const Text(
            "No purchase records found",
            style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            "Try changing the filter options or add a new purchase entry.",
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerTable() {
    return Shimmer(
      child: Column(
        children: List.generate(
            5,
            (index) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                )),
      ),
    );
  }
}

// ── Private Popup Row Helper ─────────────────────────────────────────────────
class _PopupRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _PopupRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
