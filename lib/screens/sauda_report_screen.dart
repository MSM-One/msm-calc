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
  static const Color primaryRed = Color(0xFFD32F2F);

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
            continue;
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
        analyticsReports.add(r);

        final rawHidden = r['is_hidden'] ?? r['isHidden'];
        final bool isHidden = rawHidden == true ||
            rawHidden == 1 ||
            rawHidden?.toString().toLowerCase() == 'true' ||
            rawHidden?.toString() == '1';

        if (!_showHidden && isHidden) {
          // Skip
        } else {
          uiFilteredReports.add(r);
        }
      }
    }

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
    DataRepository.vendorAvgRateNotifier.value =
        sumQty > 0 ? totalValue / sumQty : 0.0;
  }

  double get _totalReceivedQty {
    double total = 0;
    for (var r in _filteredReports) {
      total += (r['rec'] as num?)?.toDouble() ?? 0.0;
    }
    return total;
  }

  double get _totalPendingBal {
    double total = 0;
    for (var r in _filteredReports) {
      final double ord = (r['ord'] as num?)?.toDouble() ?? 0.0;
      final double rec = (r['rec'] as num?)?.toDouble() ?? 0.0;
      total += (ord - rec);
    }
    return total;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.move_to_inbox_rounded,
                  color: Color(0xFF10B981), size: 18),
            ),
            const SizedBox(width: 10),
            const Text("Manual Stock Receive",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Vendor: $party",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Item: $item ${getFormattedSizeDisplay(size, null)}",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 14),
            const Text(
              "Enter quantity to receive. This will update the Sauda Balance and ADD this quantity to your Current Stock.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
              ],
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: "Quantity (MT)",
                suffixText: "MT",
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("CONFIRM & UPDATE"),
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

        if (mounted) {
          if (result.success) {
            MotionToast.show(context,
                "Successfully received ${qty.toStringAsFixed(3)} MT for $party");
            await _loadReports();
          } else {
            MotionToast.show(context, "Error: ${result.errorMessage}",
                isError: true);
          }
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: primaryRed),
              SizedBox(width: 8),
              Text("Edit Sauda Entry",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                    isDense: true,
                    prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
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
                    isDense: true,
                    prefixIcon: Icon(Icons.category_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Size / Specification Field
                TextField(
                  controller: sizeController,
                  decoration: const InputDecoration(
                    labelText: "Size / Specification",
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.straighten_rounded, size: 18),
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
                    isDense: true,
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
                    isDense: true,
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
                    isDense: true,
                    prefixIcon: Icon(Icons.map_rounded, size: 18),
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
                    isDense: true,
                    prefixIcon: Icon(Icons.location_on_rounded, size: 18),
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
                elevation: 0,
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

      if (newVendor != party && receivedQty > 0) {
        if (!mounted) return;
        final bool? transferConfirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

        if (mounted) {
          if (result.success) {
            if (newVendor != party) {
              MotionToast.show(context,
                  "Vendor updated successfully from $party to $newVendor");
            } else {
              MotionToast.show(context, "Sauda entry updated successfully.");
            }
            await _loadReports();
          } else {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Confirm Delete",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
              backgroundColor: primaryRed,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final result = await DataRepository.deletePurchaseEntry(entryId);
        if (mounted) {
          if (result.success) {
            MotionToast.show(context, "Purchase entry deleted successfully");
            await _loadReports();
          } else {
            MotionToast.show(
                context, "Error deleting entry: ${result.errorMessage}",
                isError: true);
          }
        }
      } catch (e) {
        debugPrint("[VendorReport] Delete Error: $e");
        if (mounted) {
          MotionToast.show(context, "Delete failed: $e", isError: true);
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showResetConfirmation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Reset Report View?",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
              backgroundColor: primaryRed,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text("RESET"),
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
          if (mounted) {
            MotionToast.show(
                context, "Report view reset permanently on this device.");
          }
        }
      });
    }
  }

  void _showItemWiseSummary() {
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text("Item-wise Purchase Summary",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                )),
            const SizedBox(height: 2),
            Text("Aggregated across current filtered records",
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                )),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: summaryList.length,
                separatorBuilder: (context, index) => Divider(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                ),
                itemBuilder: (context, index) {
                  final s = summaryList[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(s['item'],
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              )),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "${(s['totalQty'] as double).toStringAsFixed(3)} MT",
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "₹ ${(s['avgRate'] as double).toStringAsFixed(0)}",
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: primaryRed,
                            ),
                          ),
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
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text("CLOSE",
                  style: TextStyle(fontWeight: FontWeight.w700)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: AppBar(
          backgroundColor: cardColor,
          elevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          toolbarHeight: 68,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: primaryRed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Vendor Purchase Ledger",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        "Procurement History, Balances & Dispatches",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      size: 18,
                    ),
                  ),
                  tooltip: "Refresh Data",
                  onPressed: _isLoading ? null : _loadReports,
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: () => _openVendorPurchaseForm(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text(
                    "New Inward",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryRed,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.more_vert_rounded,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      size: 18,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: cardColor,
                  onSelected: (val) {
                    if (val == 'pdf') _generateAndSharePDF();
                    if (val == 'excel' &&
                        UserSession.currentRole == StockRole.ADMIN) {
                      _generateAndShareExcel();
                    }
                    if (val == 'reset') _showResetConfirmation();
                    if (val == 'summary') _showItemWiseSummary();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'pdf',
                      child: _PopupRow(
                        icon: Icons.picture_as_pdf_rounded,
                        color: primaryRed,
                        label: "Export PDF",
                      ),
                    ),
                    if (UserSession.currentRole == StockRole.ADMIN)
                      const PopupMenuItem(
                        value: 'excel',
                        child: _PopupRow(
                          icon: Icons.table_view_rounded,
                          color: Color(0xFF10B981),
                          label: "Export Excel",
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'reset',
                      child: _PopupRow(
                        icon: Icons.restart_alt_rounded,
                        color: Color(0xFF64748B),
                        label: "Reset Local View",
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'summary',
                      child: _PopupRow(
                        icon: Icons.analytics_outlined,
                        color: Color(0xFF0284C7),
                        label: "Item Summary",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: _isExporting
                ? const LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryRed),
                    minHeight: 2,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        color: primaryRed,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 4-CARD KPI STRIP ─────────────────────────────────────
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isNarrow = constraints.maxWidth < 600;

                        final card1 = ValueListenableBuilder<double>(
                          valueListenable:
                              DataRepository.vendorTotalQtyNotifier,
                          builder: (context, val, _) => _buildMetricCard(
                            "Total Ordered",
                            "${val.toStringAsFixed(3)} MT",
                            Icons.shopping_bag_outlined,
                            const Color(0xFF1E293B),
                            isDark,
                            cardColor,
                          ),
                        );

                        final card2 = _buildMetricCard(
                          "Total Received",
                          "${_totalReceivedQty.toStringAsFixed(3)} MT",
                          Icons.move_to_inbox_rounded,
                          const Color(0xFF10B981),
                          isDark,
                          cardColor,
                        );

                        final card3 = _buildMetricCard(
                          "Pending Balance",
                          "${_totalPendingBal.toStringAsFixed(3)} MT",
                          Icons.pending_actions_rounded,
                          primaryRed,
                          isDark,
                          cardColor,
                        );

                        final card4 = ValueListenableBuilder<double>(
                          valueListenable:
                              DataRepository.vendorAvgRateNotifier,
                          builder: (context, val, _) => _buildMetricCard(
                            "Avg Purchase Rate",
                            "₹ ${val.toStringAsFixed(0)}/MT",
                            Icons.trending_up_rounded,
                            const Color(0xFF0284C7),
                            isDark,
                            cardColor,
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: card1),
                                  const SizedBox(width: 8),
                                  Expanded(child: card2),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: card3),
                                  const SizedBox(width: 8),
                                  Expanded(child: card4),
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: card1),
                            const SizedBox(width: 10),
                            Expanded(child: card2),
                            const SizedBox(width: 10),
                            Expanded(child: card3),
                            const SizedBox(width: 10),
                            Expanded(child: card4),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // ── FILTERS PANEL ────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: _cardDecoration(isDark, cardColor),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.tune_rounded,
                                      size: 16, color: primaryRed),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Filter Records",
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: primaryRed.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${_filteredReports.length} ${(_filteredReports.length == 1) ? 'Record' : 'Records'}",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: primaryRed,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              InkWell(
                                onTap: () {
                                  setState(() => _showHidden = !_showHidden);
                                  _applyFilters();
                                },
                                borderRadius: BorderRadius.circular(6),
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
                                        activeTrackColor:
                                            primaryRed.withValues(alpha: 0.4),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Show Hidden",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white70
                                              : const Color(0xFF374151),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Divider(
                            height: 1,
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 600;
                              if (isCompact) {
                                return Column(
                                  children: [
                                    _buildSearchableVendorSelectorRow(
                                      icon: Icons.person_search_outlined,
                                      hint: "All Vendors",
                                      value: _selectedVendor,
                                      items: _vendors,
                                      isDark: isDark,
                                      onChanged: (v) {
                                        setState(() => _selectedVendor = v);
                                        _applyFilters();
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    _buildFilterDropdownRow(
                                      icon: Icons.grid_view_rounded,
                                      hint: "All Items",
                                      value: _selectedItem,
                                      items: _items,
                                      isDark: isDark,
                                      onChanged: (v) {
                                        setState(() => _selectedItem = v);
                                        _applyFilters();
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    _buildFilterDropdownRow(
                                      icon: Icons.map_rounded,
                                      hint: "All Regions",
                                      value: _selectedRegion,
                                      items: _regions,
                                      isDark: isDark,
                                      onChanged: (v) {
                                        setState(() => _selectedRegion = v);
                                        _applyFilters();
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    _buildFilterDropdownRow(
                                      icon: Icons.location_on_rounded,
                                      hint: "All Locations",
                                      value: _selectedLocation,
                                      items: _locations,
                                      isDark: isDark,
                                      onChanged: (v) {
                                        setState(() => _selectedLocation = v);
                                        _applyFilters();
                                      },
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSearchableVendorSelectorRow(
                                          icon: Icons.person_search_outlined,
                                          hint: "All Vendors",
                                          value: _selectedVendor,
                                          items: _vendors,
                                          isDark: isDark,
                                          onChanged: (v) {
                                            setState(() => _selectedVendor = v);
                                            _applyFilters();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildFilterDropdownRow(
                                          icon: Icons.grid_view_rounded,
                                          hint: "All Items",
                                          value: _selectedItem,
                                          items: _items,
                                          isDark: isDark,
                                          onChanged: (v) {
                                            setState(() => _selectedItem = v);
                                            _applyFilters();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildFilterDropdownRow(
                                          icon: Icons.map_rounded,
                                          hint: "All Regions",
                                          value: _selectedRegion,
                                          items: _regions,
                                          isDark: isDark,
                                          onChanged: (v) {
                                            setState(() => _selectedRegion = v);
                                            _applyFilters();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildFilterDropdownRow(
                                          icon: Icons.location_on_rounded,
                                          hint: "All Locations",
                                          value: _selectedLocation,
                                          items: _locations,
                                          isDark: isDark,
                                          onChanged: (v) {
                                            setState(
                                                () => _selectedLocation = v);
                                            _applyFilters();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── MAIN REPORTS TABLE / CARDS ────────────────────────────
                    if (_isLoading)
                      _buildShimmerTable()
                    else if (_filteredReports.isEmpty)
                      _buildEmptyState(isDark)
                    else
                      Container(
                        decoration: _cardDecoration(isDark, cardColor),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth:
                                    MediaQuery.of(context).size.width > 800
                                        ? 800
                                        : MediaQuery.of(context).size.width -
                                            32,
                              ),
                              child: DataTable(
                                headingRowHeight: 44,
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 56,
                                headingRowColor: WidgetStateProperty.all(
                                  isDark
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFF1F5F9),
                                ),
                                horizontalMargin: 16,
                                columnSpacing: 18,
                                columns: [
                                  _dataCol("Date", isDark),
                                  _dataCol("Vendor", isDark),
                                  _dataCol("Material (Size)", isDark),
                                  _dataCol("Rate", isDark),
                                  _dataCol("Order (MT)", isDark),
                                  _dataCol("Received", isDark),
                                  _dataCol("Balance", isDark, isHighlight: true),
                                  _dataCol("Region", isDark),
                                  _dataCol("Loc", isDark),
                                  _dataCol("Action", isDark),
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
                                      DataCell(Text(
                                        dateDisplay,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white70
                                              : const Color(0xFF1E293B),
                                        ),
                                      )),
                                      DataCell(SizedBox(
                                        width: 120,
                                        child: Text(
                                          r['party']?.toString() ?? "",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF1E293B),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                                      DataCell(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            item,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1E293B),
                                            ),
                                          ),
                                          if (size.isNotEmpty)
                                            Text(
                                              formatMaterialSize(
                                                size,
                                                r['unitWeightKg'] ??
                                                    r['unitWeight'],
                                              ),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? const Color(0xFF94A3B8)
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                        ],
                                      )),
                                      DataCell(Text(
                                        "₹ ${formatIndianCurrency(r['rate'] ?? 0)}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1E293B),
                                        ),
                                      )),
                                      DataCell(Text(
                                        ord.toStringAsFixed(3),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1E293B),
                                        ),
                                      )),
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
                                                      color: const Color(
                                                              0xFF10B981)
                                                          .withValues(
                                                              alpha: 0.3),
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    color: const Color(
                                                            0xFF10B981)
                                                        .withValues(alpha: 0.08),
                                                  )
                                                : null,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  rec.toStringAsFixed(3),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF10B981),
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                if (AccessGuard.can(
                                                    AppPermissions
                                                        .vendorPurchase)) ...[
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.edit_note_rounded,
                                                    size: 14,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(
                                        bal.toStringAsFixed(3),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: bal > 0
                                              ? primaryRed
                                              : (isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B)),
                                        ),
                                      )),
                                      DataCell(Text(
                                        r['region']?.toString() ?? "YARD",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                      )),
                                      DataCell(Text(
                                        r['location']?.toString() ?? "YARD",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                      )),
                                      DataCell(
                                        PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert_rounded,
                                            size: 18,
                                            color: isDark
                                                ? Colors.white70
                                                : const Color(0xFF64748B),
                                          ),
                                          tooltip: "Sauda Actions",
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          color: cardColor,
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
                                                      color: Color(0xFF10B981),
                                                      size: 18,
                                                    ),
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
                                                      color:
                                                          const Color(0xFF0284C7),
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
                                                      size: 18,
                                                    ),
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
    );
  }

  DataColumn _dataCol(String label, bool isDark, {bool isHighlight = false}) {
    return DataColumn(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: isHighlight
              ? primaryRed
              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
    Color cardColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(isDark, cardColor),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(bool isDark, Color cardColor) {
    return BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      ),
      boxShadow: isDark
          ? []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  Widget _buildSearchableVendorSelectorRow({
    required IconData icon,
    required String hint,
    required String? value,
    required List<String> items,
    required bool isDark,
    required ValueChanged<String?> onChanged,
  }) {
    final bool hasSelection = value != null && value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
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
        child: Row(
          children: [
            Icon(icon, color: primaryRed, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasSelection ? value : hint,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      hasSelection ? FontWeight.w700 : FontWeight.w500,
                  color: hasSelection
                      ? (isDark ? Colors.white : const Color(0xFF1E293B))
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (hasSelection)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(null),
                child: const Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.cancel_rounded,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              )
            else
              const Icon(
                Icons.arrow_drop_down_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdownRow({
    required IconData icon,
    required String hint,
    required String? value,
    required List<String> items,
    required bool isDark,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                isDense: true,
                dropdownColor:
                    isDark ? const Color(0xFF1E293B) : Colors.white,
                hint: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down_rounded,
                    color: Color(0xFF94A3B8), size: 20),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  ...items.map((i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                          i,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1E293B),
                          ),
                        ),
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

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "No purchase records found",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Try changing filter options or log a new purchase entry.",
            style: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontSize: 12,
            ),
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
            margin: const EdgeInsets.symmetric(vertical: 6),
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
          ),
        ),
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
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
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
