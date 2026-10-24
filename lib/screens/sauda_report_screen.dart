import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import '../widgets/add_supplier_dialog.dart';

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
  bool _isFilterExpanded = false;
  bool _isFullLedgerMode = false;
  int _selectedSegmentIndex = 0;

  int get _activeFilterCount {
    int count = 0;
    if (_selectedVendor != null && _selectedVendor!.trim().isNotEmpty) count++;
    if (_selectedItem != null && _selectedItem!.trim().isNotEmpty) count++;
    if (_selectedRegion != null && _selectedRegion!.trim().isNotEmpty) count++;
    if (_selectedLocation != null && _selectedLocation!.trim().isNotEmpty) count++;
    if (_showHidden) count++;
    return count;
  }

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
      List<Map<String, dynamic>> extraVendors = [];
      try {
        final response = await Supabase.instance.client
            .from('vendors')
            .select('id, vendor_name, phone, gstin, city, region, business_type, is_active')
            .eq('is_active', true)
            .order('vendor_name', ascending: true);

        extraVendors = List<Map<String, dynamic>>.from(response);
      } catch (e) {
        debugPrint("[VendorReport] Supabase vendors fetch error: $e");
      }

      if (mounted) {
        DataRepository.vendorSaudaListNotifier.value = reports;
        _updateFilterLists(reports, extraVendors: extraVendors);
        await _applyFilters();
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("[VendorReport] Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateFilterLists(List<dynamic> reports,
      {List<dynamic> extraVendors = const []}) {
    final Set<String> seenVendors = {};
    final List<String> uniqueVendors = [];
    for (final v in extraVendors) {
      final raw = (v is Map ? (v['vendor_name'] ?? v['name'] ?? '') : v).toString();
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty && seenVendors.add(trimmed.toUpperCase())) {
        uniqueVendors.add(trimmed.toUpperCase());
      }
    }
    for (final e in reports) {
      final raw = e['party']?.toString() ??
          e['vendor']?.toString() ??
          e['party_name']?.toString() ??
          "";
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty && seenVendors.add(trimmed.toUpperCase())) {
        uniqueVendors.add(trimmed.toUpperCase());
      }
    }
    uniqueVendors.sort();
    _vendors = uniqueVendors;

    _items = reports
        .map((e) => e['item']?.toString() ?? "")
        .where((i) => i.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    final Set<String> seenRegions = {};
    final List<String> uniqueRegions = [];
    for (final v in extraVendors) {
      if (v is Map) {
        final raw = v['region']?.toString() ?? "";
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty && seenRegions.add(trimmed.toUpperCase())) {
          uniqueRegions.add(trimmed.toUpperCase());
        }
      }
    }
    for (final e in reports) {
      final raw = e['reg']?.toString() ?? e['region']?.toString() ?? "";
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty && seenRegions.add(trimmed.toUpperCase())) {
        uniqueRegions.add(trimmed.toUpperCase());
      }
    }
    uniqueRegions.sort();
    _regions = uniqueRegions;

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

    final String? selectedVendorUpper = _selectedVendor?.trim().toUpperCase();
    final String? selectedRegionUpper = _selectedRegion?.trim().toUpperCase();

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
      final String recVendor = (r['party']?.toString() ??
              r['vendor']?.toString() ??
              r['party_name']?.toString() ??
              '')
          .trim()
          .toUpperCase();
      final String recRegion = (r['reg']?.toString() ??
              r['region']?.toString() ??
              "YARD")
          .trim()
          .toUpperCase();

      bool matchesVendor = selectedVendorUpper == null ||
          selectedVendorUpper.isEmpty ||
          recVendor == selectedVendorUpper;
      bool matchesItem = _selectedItem == null || r['item'] == _selectedItem;
      bool matchesRegion = selectedRegionUpper == null ||
          selectedRegionUpper.isEmpty ||
          recRegion == selectedRegionUpper;
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

    final String initialRegion =
        region.trim().isNotEmpty ? region.trim().toUpperCase() : "YARD";
    String selectedRegion = initialRegion;
    String selectedLocation = location.isNotEmpty ? location : "YARD";

    final Set<String> seenAvailable = {};
    final List<String> availableRegions = [];
    final defaultRegions =
        _regions.isNotEmpty ? _regions : ["RAIPUR", "JALNA", "YARD"];
    for (final r in defaultRegions) {
      final trimmed = r.trim();
      if (trimmed.isNotEmpty && seenAvailable.add(trimmed.toUpperCase())) {
        availableRegions.add(trimmed.toUpperCase());
      }
    }
    if (seenAvailable.add(selectedRegion.toUpperCase())) {
      availableRegions.add(selectedRegion.toUpperCase());
    }
    availableRegions.sort();

    final List<String> availableLocations =
        _locations.isNotEmpty ? List.from(_locations) : ["YARD", "FACTORY"];

    if (!availableLocations.contains(selectedLocation)) {
      availableLocations.add(selectedLocation);
    }

    try {
      final response = await Supabase.instance.client
          .from('vendors')
          .select('id, vendor_name, phone, gstin, city, region, business_type, is_active')
          .eq('is_active', true)
          .order('vendor_name', ascending: true);

      final List<Map<String, dynamic>> vendorsList =
          List<Map<String, dynamic>>.from(response);
      for (final v in vendorsList) {
        final name = (v['vendor_name'] ?? v['name'] ?? '').toString().trim().toUpperCase();
        if (name.isNotEmpty && !_vendors.contains(name)) {
          _vendors.add(name);
        }
      }
      _vendors.sort();
    } catch (_) {}

    if (!mounted) return;
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

                    final now = DateTime.now();
                    final today = DateTime(
                        now.year, now.month, now.day, 23, 59, 59);
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: initial.isAfter(today) ? now : initial,
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
        final String newVendorUpper = vendorController.text.trim().toUpperCase();
        final String origVendorUpper = party.trim().toUpperCase();
        final String newRegionUpper = selectedRegion.trim().toUpperCase();
        final String origRegionUpper = region.trim().toUpperCase();

        final result = await DataRepository.updatePurchaseEntry(
          saudaId: saudaId,
          qtyMt: newQty,
          rate: newRate,
          vendorName: newVendorUpper != origVendorUpper ? newVendorUpper : null,
          itemName: newItem != item ? newItem : null,
          size: newSize != size ? newSize : null,
          region: newRegionUpper != origRegionUpper ? newRegionUpper : null,
          location: selectedLocation != location ? selectedLocation : null,
          date: newDate != dateStr ? newDate : null,
        );

        if (mounted) {
          if (result.success) {
            if (newVendorUpper != origVendorUpper) {
              MotionToast.show(context,
                  "Vendor updated successfully from $party to $newVendorUpper");
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

  Future<void> _openAddSupplierDialog(BuildContext context) async {
    final user = DataRepository.currentUserNotifier.value;
    if (!hasVendorPurchaseAccess(user)) {
      MotionToast.show(context, "Access Denied: Missing Permission",
          isError: true);
      return;
    }

    final newSupplier = await AddSupplierDialog.show(
      context,
      existingRegions: _regions,
    );

    if (newSupplier != null && newSupplier.isNotEmpty) {
      final upper = newSupplier.trim().toUpperCase();
      if (!_vendors.contains(upper)) {
        _vendors.add(upper);
        _vendors.sort();
      }
      setState(() {
        _selectedVendor = upper;
      });
      await _loadReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    if (!isDesktop) {
      return _buildMobileLayout(context, isDark);
    }
    return _buildDesktopLayout(context, isDark);
  }

  Widget _buildDesktopLayout(BuildContext context, bool isDark) {
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: cardColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          toolbarHeight: 60,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          shape: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
            tooltip: 'Back to Dashboard',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            "Vendor Purchases",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          actions: [
            _buildSquareIconButton(
              Icons.history_rounded,
              iconColor: const Color(0xFFDC2626),
              bgColor: isDark
                  ? const Color(0xFFDC2626).withValues(alpha: 0.15)
                  : const Color(0xFFFEE2E2),
              borderColor: isDark
                  ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                  : const Color(0xFFFECACA),
              onTap: () => _showItemWiseSummary(),
              isDark: isDark,
              size: 36,
              tooltip: "Item Summary",
            ),
            const SizedBox(width: 6),
            _buildSquareIconButton(
              Icons.refresh_rounded,
              iconColor: isDark ? Colors.white : const Color(0xFF475569),
              onTap: _isLoading ? null : _loadReports,
              isDark: isDark,
              size: 36,
              tooltip: "Refresh Data",
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.person_add_alt_1_outlined,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
              tooltip: 'Add Supplier',
              onPressed: () => _openAddSupplierDialog(context),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_rounded,
                  size: 16, color: Colors.white),
              label: const Text(
                '+ Inward',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              onPressed: () => _openVendorPurchaseForm(context),
            ),
            const SizedBox(width: 6),
            _buildMoreOptionsMenu(isDark, cardColor),
            const SizedBox(width: 16),
          ],
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
            padding: const EdgeInsets.symmetric(
                horizontal: 16.0, vertical: 12.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 2. KEY METRICS KPI CARDS ────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<double>(
                            valueListenable:
                                DataRepository.vendorTotalQtyNotifier,
                            builder: (context, val, _) => _buildMetricCard(
                              label: "Total Ordered",
                              value: "${val.toStringAsFixed(3)} MT",
                              icon: Icons.shopping_bag_outlined,
                              iconColor: const Color(0xFF475569),
                              iconBgColor: const Color(0xFFF1F5F9),
                              isDark: isDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            label: "Total Received",
                            value: "${_totalReceivedQty.toStringAsFixed(3)} MT",
                            icon: Icons.download_rounded,
                            iconColor: const Color(0xFF059669),
                            iconBgColor: const Color(0xFFECFDF5),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            label: "Pending Balance",
                            value: "${_totalPendingBal.toStringAsFixed(3)} MT",
                            icon: Icons.pending_actions_rounded,
                            iconColor: const Color(0xFFDC2626),
                            iconBgColor: const Color(0xFFFEF2F2),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ValueListenableBuilder<double>(
                            valueListenable:
                                DataRepository.vendorAvgRateNotifier,
                            builder: (context, val, _) => _buildMetricCard(
                              label: "Avg Purchase Rate",
                              value: "₹ ${val.toStringAsFixed(0)}/MT",
                              icon: Icons.trending_up_rounded,
                              iconColor: const Color(0xFF0284C7),
                              iconBgColor: const Color(0xFFF0F9FF),
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── 3. FILTER RECORDS CARD ────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: isDark
                            ? []
                            : [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.tune_rounded,
                                      size: 18, color: Color(0xFFDC2626)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Filter Records',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_filteredReports.length} Records',
                                      style: const TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.scale(
                                    scale: 0.75,
                                    child: Switch(
                                      value: _showHidden,
                                      activeThumbColor: const Color(0xFFDC2626),
                                      activeTrackColor: const Color(0xFFDC2626).withValues(alpha: 0.35),
                                      onChanged: (val) {
                                        setState(() => _showHidden = val);
                                        _applyFilters();
                                      },
                                    ),
                                  ),
                                  Text(
                                    'Hidden',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          _buildStackedFilterField(
                            icon: Icons.person_outline_rounded,
                            hint: "All Vendors",
                            value: _selectedVendor,
                            items: _vendors,
                            isSearchableVendor: true,
                            isDark: isDark,
                            onChanged: (v) {
                              setState(() => _selectedVendor = v);
                              _applyFilters();
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildStackedFilterField(
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
                          const SizedBox(height: 8),
                          _buildStackedFilterField(
                            icon: Icons.map_outlined,
                            hint: "All Regions",
                            value: _selectedRegion,
                            items: _regions,
                            isDark: isDark,
                            onChanged: (v) {
                              setState(() => _selectedRegion = v);
                              _applyFilters();
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildStackedFilterField(
                            icon: Icons.location_on_outlined,
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
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A)
                                        .withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 880,
                                ),
                                child: DataTable(
                                headingRowHeight: 46,
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 58,
                                headingRowColor: WidgetStateProperty.all(
                                  isDark
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFF8FAFC),
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
                                      final dt = parseSupabaseDateTime(dateRaw);
                                      dateDisplay = formatTransactionDate(dt);
                                    }
                                  } catch (_) {}

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(
                                        dateDisplay,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF475569),
                                        ),
                                      )),
                                      DataCell(SizedBox(
                                        width: 130,
                                        child: Text(
                                          (r['party']?.toString() ?? "").toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
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
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
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
                                                fontSize: 11,
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
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
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
                                                      Icons.download_done_rounded,
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
                                            PopupMenuItem(
                                              value: 'hide',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    r['is_hidden'] == true
                                                        ? Icons.visibility_rounded
                                                        : Icons
                                                            .visibility_off_rounded,
                                                    color:
                                                        const Color(0xFF64748B),
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                      r['is_hidden'] == true
                                                          ? "Unhide"
                                                          : "Hide Record",
                                                      style: const TextStyle(
                                                          fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            if (AccessGuard.can(
                                                AppPermissions.vendorPurchase))
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.edit_outlined,
                                                      color: Color(0xFF0284C7),
                                                      size: 18,
                                                    ),
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

  dynamic _extractField(dynamic obj, List<String> keys) {
    if (obj == null) return null;
    if (obj is Map) {
      for (final k in keys) {
        if (obj[k] != null) return obj[k];
      }
    }
    return null;
  }

  Widget _buildMobileLayout(BuildContext context, bool isDark) {
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final List<dynamic> displayTxns = _isFullLedgerMode
        ? _filteredReports
        : (_filteredReports.length > 15
            ? _filteredReports.take(15).toList()
            : _filteredReports);

    return Scaffold(
      backgroundColor: bgColor,
      body: NestedScrollView(
        physics: const BouncingScrollPhysics(),
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            // 1. Pinned Top Bar with Untruncated Title & Shortcut Actions
            SliverAppBar(
              pinned: true,
              floating: false,
              elevation: 0.5,
              backgroundColor: cardColor,
              foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
                tooltip: 'Back to Dashboard',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              titleSpacing: 0,
              centerTitle: false,
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Vendor Purchases',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                  tooltip: 'Add Supplier',
                  onPressed: () => _openAddSupplierDialog(context),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text(
                      'Inward',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _openVendorPurchaseForm(context),
                  ),
                ),
                _buildMoreOptionsMenu(isDark, cardColor),
                const SizedBox(width: 4),
              ],
            ),

            // 2. Collapsible Top Sliver for 2x2 KPI Cards + Filter Bar (scrolls out naturally)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMobileKpiGrid(isDark, cardColor, borderColor),
                    const SizedBox(height: 14),
                    _buildMobileCollapsibleFilterBar(
                        isDark, cardColor, borderColor),
                  ],
                ),
              ),
            ),

            // 3. Pinned / Sticky Header for Category Tabs & Recent Transactions Row
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickySectionHeaderDelegate(
                height: 86.0,
                child: Container(
                  color: bgColor,
                  padding: const EdgeInsets.fromLTRB(16.0, 6.0, 16.0, 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMobileSegmentedTabs(isDark),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'RECENT TRANSACTIONS',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _isFullLedgerMode
                                        ? '${_filteredReports.length}'
                                        : (_filteredReports.length > 15
                                            ? '${displayTxns.length}/${_filteredReports.length}'
                                            : '${_filteredReports.length}'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() =>
                                  _isFullLedgerMode = !_isFullLedgerMode);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Text(
                                _isFullLedgerMode
                                    ? "Show Recent <"
                                    : "View All >",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: _isLoading
            ? _buildMobileShimmerList(isDark)
            : _filteredReports.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: _buildMobileEmptyState(
                        isDark, cardColor, borderColor),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16.0,
                      4.0,
                      16.0,
                      MediaQuery.of(context).padding.bottom + 24.0,
                    ),
                    itemCount: displayTxns.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      if (index < displayTxns.length) {
                        return _buildMobileTransactionCard(
                          context,
                          displayTxns[index],
                          isDark,
                          cardColor,
                          borderColor,
                        );
                      }
                      return _buildTotalPurchaseValueCard(
                        context,
                        displayTxns,
                        isDark,
                        cardColor,
                        borderColor,
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildMoreOptionsMenu(bool isDark, Color cardColor) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: isDark ? Colors.white70 : const Color(0xFF475569),
      ),
      tooltip: "More Options",
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cardColor,
      onSelected: (val) {
        if (val == 'refresh') {
          if (!_isLoading) _loadReports();
        } else if (val == 'item_summary') {
          _showItemWiseSummary();
        } else if (val == 'export_pdf') {
          _generateAndSharePDF();
        } else if (val == 'export_excel') {
          _generateAndShareExcel();
        } else if (val == 'toggle_hidden') {
          setState(() => _showHidden = !_showHidden);
          _applyFilters();
        } else if (val == 'reset_view') {
          _showResetConfirmation();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              const Icon(Icons.refresh_rounded,
                  color: Color(0xFF2563EB), size: 18),
              const SizedBox(width: 8),
              Text(
                "Refresh Data",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'item_summary',
          child: Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: Color(0xFF64748B), size: 18),
              const SizedBox(width: 8),
              Text(
                "Item Summary",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export_pdf',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded,
                  color: Color(0xFFDC2626), size: 18),
              const SizedBox(width: 8),
              Text(
                "Export PDF",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export_excel',
          child: Row(
            children: [
              const Icon(Icons.table_view_rounded,
                  color: Color(0xFF059669), size: 18),
              const SizedBox(width: 8),
              Text(
                "Export Excel",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle_hidden',
          child: Row(
            children: [
              Icon(
                _showHidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: const Color(0xFF64748B),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _showHidden ? "Hide Hidden Sauda" : "Show Hidden Sauda",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'reset_view',
          child: Row(
            children: [
              const Icon(
                Icons.restore_page_outlined,
                color: Color(0xFFDC2626),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "Reset View",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileKpiGrid(
      bool isDark, Color cardColor, Color borderColor) {
    return ValueListenableBuilder<double>(
      valueListenable: DataRepository.vendorTotalQtyNotifier,
      builder: (context, totalQty, _) {
        return ValueListenableBuilder<double>(
          valueListenable: DataRepository.vendorAvgRateNotifier,
          builder: (context, avgRate, _) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMobileKpiCard(
                        icon: Icons.inventory_2_outlined,
                        iconBg: const Color(0xFFEDE9FE),
                        iconColor: const Color(0xFF7C3AED),
                        trendText: "+8.2%",
                        isPositiveTrend: true,
                        value: "${totalQty.toStringAsFixed(1)} MT",
                        label: "Total Ordered",
                        isDark: isDark,
                        cardColor: cardColor,
                        borderColor: borderColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMobileKpiCard(
                        icon: Icons.call_received_rounded,
                        iconBg: const Color(0xFFECFDF5),
                        iconColor: const Color(0xFF059669),
                        trendText: "+5.1%",
                        isPositiveTrend: true,
                        value: "${_totalReceivedQty.toStringAsFixed(1)} MT",
                        label: "Total Received",
                        isDark: isDark,
                        cardColor: cardColor,
                        borderColor: borderColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMobileKpiCard(
                        icon: Icons.layers_outlined,
                        iconBg: const Color(0xFFFEF3C7),
                        iconColor: const Color(0xFFD97706),
                        trendText: "-3.4%",
                        isPositiveTrend: false,
                        value: "${_totalPendingBal.toStringAsFixed(1)} MT",
                        label: "Pending Balance",
                        isDark: isDark,
                        cardColor: cardColor,
                        borderColor: borderColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMobileKpiCard(
                        icon: Icons.currency_rupee_rounded,
                        iconBg: const Color(0xFFEFF6FF),
                        iconColor: const Color(0xFF2563EB),
                        trendText: "+2.7%",
                        isPositiveTrend: true,
                        value: "₹${formatIndianCurrency(avgRate.round())}/MT",
                        label: "Avg Purchase Rate",
                        isDark: isDark,
                        cardColor: cardColor,
                        borderColor: borderColor,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMobileKpiCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String trendText,
    required bool isPositiveTrend,
    required String value,
    required String label,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
  }) {
    final trendColor =
        isPositiveTrend ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? iconColor.withValues(alpha: 0.15) : iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPositiveTrend
                        ? Icons.arrow_outward_rounded
                        : Icons.south_east_rounded,
                    size: 11,
                    color: trendColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    trendText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: trendColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCollapsibleFilterBar(
      bool isDark, Color cardColor, Color borderColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          InkWell(
            onTap: () {
              setState(() => _isFilterExpanded = !_isFilterExpanded);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            "Filter Records",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _activeFilterCount > 0
                                ? const Color(0xFFDC2626)
                                : (isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _activeFilterCount > 0
                                ? '$_activeFilterCount'
                                : '${_filteredReports.length}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeFilterCount > 0
                                  ? Colors.white
                                  : (isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Visibility toggle button / pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isFilterExpanded
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 14,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isFilterExpanded ? "Visible" : "Hidden",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Filter Controls
          if (_isFilterExpanded) ...[
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: _buildHorizontalFilterChips(isDark),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileSegmentedTabs(bool isDark) {
    final tabs = ["Purchase", "Transfer", "Reports"];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final isSelected = _selectedSegmentIndex == idx;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _selectedSegmentIndex = idx);
                if (idx == 1) {
                  MotionToast.show(context, "Stock Transfer Mode active");
                } else if (idx == 2) {
                  _showItemWiseSummary();
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFDC2626)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFFDC2626).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[idx],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMobileTransactionCard(BuildContext context, dynamic txn,
      bool isDark, Color cardColor, Color borderColor) {
    // 1. Date (Absolute Null-Safety)
    DateTime? dt;
    final dynamic rawDt =
        _extractField(txn, ['dateTime', 'datetime', 'date_time']);
    final dynamic rawDate = _extractField(txn, ['date']);
    final dynamic rawCreated =
        _extractField(txn, ['createdAt', 'created_at']);

    if (rawDt != null) {
      if (rawDt is DateTime) {
        dt = rawDt;
      } else {
        dt = DateTime.tryParse(rawDt.toString());
      }
    }
    if (dt == null && rawDate != null) {
      if (rawDate is DateTime) {
        dt = rawDate;
      } else {
        final s = rawDate.toString().trim();
        dt = DateTime.tryParse(s);
        if (dt == null && s.isNotEmpty) {
          try {
            dt = DateFormat('dd-MMM-yyyy').parse(s);
          } catch (_) {}
          if (dt == null) {
            try {
              dt = DateFormat('dd/MM/yyyy').parse(s);
            } catch (_) {}
          }
          if (dt == null) {
            try {
              dt = parseSupabaseDateTime(s);
            } catch (_) {}
          }
        }
      }
    }
    if (dt == null && rawCreated != null) {
      if (rawCreated is DateTime) {
        dt = rawCreated;
      } else {
        dt = DateTime.tryParse(rawCreated.toString());
      }
    }

    final String monthStr =
        dt != null ? DateFormat('MMM').format(dt).toUpperCase() : 'SEP';
    final String dayStr = dt != null ? DateFormat('dd').format(dt) : '14';

    // 2. Vendor Name
    final String party = (_extractField(txn, [
              'party',
              'partyName',
              'party_name',
              'vendor',
              'vendorName',
              'vendor_name',
              'name'
            ]) ??
            'Unknown Vendor')
        .toString()
        .toUpperCase();

    // 3. Category & Size
    final String item = (_extractField(txn, [
              'item',
              'itemName',
              'item_name',
              'material',
              'materialName',
              'category'
            ]) ??
            'Material')
        .toString();
    final String rawSize =
        (_extractField(txn, ['size', 'sizeLabel', 'size_label']) ?? '').toString();
    final dynamic rawUnitWeight =
        _extractField(txn, ['unitWeightKg', 'unitWeight', 'unit_weight']);
    final String formattedSize = rawSize.isNotEmpty
        ? formatMaterialSize(rawSize, rawUnitWeight)
        : '';

    // 4. Numbers & Rates (Absolute Null-Safety: NEVER use `!`)
    final dynamic rawRate = _extractField(txn, ['rate', 'basicRate', 'price']);
    final double rate = rawRate is num
        ? rawRate.toDouble()
        : (double.tryParse(rawRate?.toString() ?? '') ?? 0.0);

    final dynamic rawOrd = _extractField(
        txn, ['ord', 'qtyMt', 'qty', 'weightMt', 'orderedQty', 'quantity']);
    final double ord = rawOrd is num
        ? rawOrd.toDouble()
        : (double.tryParse(rawOrd?.toString() ?? '') ?? 0.0);

    final dynamic rawRec =
        _extractField(txn, ['rec', 'recQty', 'receivedQty', 'received']);
    final double rec = rawRec is num
        ? rawRec.toDouble()
        : (double.tryParse(rawRec?.toString() ?? '') ?? 0.0);

    final dynamic rawBal = _extractField(txn, ['bal', 'balance', 'balanceQty']);
    final double bal =
        rawBal is num ? rawBal.toDouble() : (ord - rec);

    final String region =
        (_extractField(txn, ['reg', 'region']) ?? 'YARD').toString();
    final String location =
        (_extractField(txn, ['location', 'loc']) ?? 'YARD').toString();

    // 5. Status Determination
    String status = "Pending";
    Color statusColor = const Color(0xFFF59E0B);
    Color statusBg = const Color(0xFFFFFBEB);
    if (bal <= 0 && ord > 0) {
      status = "Received";
      statusColor = const Color(0xFF10B981);
      statusBg = const Color(0xFFECFDF5);
    } else if (location.toUpperCase() == 'FACTORY' ||
        region.toUpperCase() == 'FACTORY') {
      status = "In Transit";
      statusColor = const Color(0xFF3B82F6);
      statusBg = const Color(0xFFEFF6FF);
    } else if (rec > 0) {
      status = "Partial";
      statusColor = const Color(0xFF3B82F6);
      statusBg = const Color(0xFFEFF6FF);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showTransactionDetailsModal(context, txn, isDark),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent indicator bar
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        // Date Badge Container
                        Container(
                          width: 44,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                monthStr,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                dayStr,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Middle Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                party,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (item.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  if (formattedSize.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        formattedSize,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Right Column
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? statusColor.withValues(alpha: 0.15)
                                    : statusBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "₹${formatIndianCurrency(rate)}",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              "${ord.toStringAsFixed(1)} MT",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  void _showTransactionDetailsModal(
      BuildContext context, dynamic txn, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final dynamic rawOrd = _extractField(
        txn, ['ord', 'qtyMt', 'qty', 'weightMt', 'orderedQty', 'quantity']);
    final double ord = rawOrd is num
        ? rawOrd.toDouble()
        : (double.tryParse(rawOrd?.toString() ?? '') ?? 0.0);

    final dynamic rawRec =
        _extractField(txn, ['rec', 'recQty', 'receivedQty', 'received']);
    final double rec = rawRec is num
        ? rawRec.toDouble()
        : (double.tryParse(rawRec?.toString() ?? '') ?? 0.0);

    final dynamic rawBal = _extractField(txn, ['bal', 'balance', 'balanceQty']);
    final double bal =
        rawBal is num ? rawBal.toDouble() : (ord - rec);

    final String party = (_extractField(txn, [
              'party',
              'partyName',
              'party_name',
              'vendor',
              'vendorName',
              'vendor_name',
              'name'
            ]) ??
            'Unknown Vendor')
        .toString()
        .toUpperCase();

    final String item = (_extractField(txn, [
              'item',
              'itemName',
              'item_name',
              'material',
              'materialName',
              'category'
            ]) ??
            'Material')
        .toString();

    final String rawSize =
        (_extractField(txn, ['size', 'sizeLabel', 'size_label']) ?? '').toString();
    final dynamic rawUnitWeight =
        _extractField(txn, ['unitWeightKg', 'unitWeight', 'unit_weight']);
    final String formattedSize = rawSize.isNotEmpty
        ? formatMaterialSize(rawSize, rawUnitWeight)
        : '-';

    final dynamic rawRate = _extractField(txn, ['rate', 'basicRate', 'price']);
    final double rate = rawRate is num
        ? rawRate.toDouble()
        : (double.tryParse(rawRate?.toString() ?? '') ?? 0.0);

    DateTime? dt;
    final dynamic rawDt =
        _extractField(txn, ['dateTime', 'datetime', 'date_time']);
    final dynamic rawDate = _extractField(txn, ['date']);
    final dynamic rawCreated =
        _extractField(txn, ['createdAt', 'created_at']);

    if (rawDt != null) {
      if (rawDt is DateTime) {
        dt = rawDt;
      } else {
        dt = DateTime.tryParse(rawDt.toString());
      }
    }
    if (dt == null && rawDate != null) {
      if (rawDate is DateTime) {
        dt = rawDate;
      } else {
        final s = rawDate.toString().trim();
        dt = DateTime.tryParse(s);
        if (dt == null && s.isNotEmpty) {
          try {
            dt = DateFormat('dd-MMM-yyyy').parse(s);
          } catch (_) {}
          if (dt == null) {
            try {
              dt = DateFormat('dd/MM/yyyy').parse(s);
            } catch (_) {}
          }
          if (dt == null) {
            try {
              dt = parseSupabaseDateTime(s);
            } catch (_) {}
          }
        }
      }
    }
    if (dt == null && rawCreated != null) {
      if (rawCreated is DateTime) {
        dt = rawCreated;
      } else {
        dt = DateTime.tryParse(rawCreated.toString());
      }
    }

    final String dateDisplay =
        dt != null ? formatTransactionDate(dt) : (rawDate?.toString() ?? '-');

    final String region =
        (_extractField(txn, ['reg', 'region']) ?? 'YARD').toString();
    final String location =
        (_extractField(txn, ['location', 'loc']) ?? 'YARD').toString();

    // Determine status
    String status = "Pending";
    Color statusColor = const Color(0xFFF59E0B);
    Color statusBg = const Color(0xFFFFFBEB);
    if (bal <= 0 && ord > 0) {
      status = "Received";
      statusColor = const Color(0xFF10B981);
      statusBg = const Color(0xFFECFDF5);
    } else if (location.toUpperCase() == 'FACTORY' ||
        region.toUpperCase() == 'FACTORY') {
      status = "In Transit";
      statusColor = const Color(0xFF3B82F6);
      statusBg = const Color(0xFFEFF6FF);
    } else if (rec > 0) {
      status = "Partial";
      statusColor = const Color(0xFF3B82F6);
      statusBg = const Color(0xFFEFF6FF);
    }

    final Map<String, dynamic> rMap = txn is Map<String, dynamic>
        ? txn
        : (txn is Map ? Map<String, dynamic>.from(txn) : <String, dynamic>{});

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        party,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? statusColor.withValues(alpha: 0.15)
                            : statusBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow("Date", dateDisplay, isDark),
                      const Divider(height: 14),
                      _buildDetailRow("Material", item, isDark, isBold: true),
                      const Divider(height: 14),
                      _buildDetailRow("Size", formattedSize, isDark),
                      const Divider(height: 14),
                      _buildDetailRow(
                        "Rate",
                        "₹ ${formatIndianCurrency(rate)} / MT",
                        isDark,
                        isBold: true,
                        valueColor: const Color(0xFFDC2626),
                      ),
                      const Divider(height: 14),
                      _buildDetailRow(
                        "Ordered Qty",
                        "${ord.toStringAsFixed(3)} MT",
                        isDark,
                      ),
                      const Divider(height: 14),
                      _buildDetailRow(
                        "Received Qty",
                        "${rec.toStringAsFixed(3)} MT",
                        isDark,
                        valueColor: const Color(0xFF10B981),
                      ),
                      const Divider(height: 14),
                      _buildDetailRow(
                        "Pending Balance",
                        "${bal.toStringAsFixed(3)} MT",
                        isDark,
                        valueColor: bal > 0 ? const Color(0xFFDC2626) : null,
                        isBold: bal > 0,
                      ),
                      const Divider(height: 14),
                      _buildDetailRow(
                        "Region / Loc",
                        "$region • $location",
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Action Buttons
                Row(
                  children: [
                    if (AccessGuard.can(AppPermissions.vendorPurchase)) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showManualReceiveDialog(rMap);
                          },
                          icon: const Icon(Icons.download_done_rounded,
                              size: 18),
                          label: const Text(
                            "Receive",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditSaudaDialog(rMap);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text(
                            "Edit",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _toggleHideSauda(rMap);
                      },
                      icon: Icon(
                        (rMap['is_hidden'] == true || rMap['hidden'] == true)
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                        color: const Color(0xFF64748B),
                      ),
                      tooltip: "Hide / Unhide",
                    ),
                    if (AccessGuard.can(AppPermissions.vendorPurchase)) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFEF2F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showDeleteConfirmation(rMap);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                        tooltip: "Delete",
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ??
                (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileEmptyState(
      bool isDark, Color cardColor, Color borderColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 32,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "No Transactions Found",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _activeFilterCount > 0
                ? "Try clearing filters to view all purchases."
                : "No inward or purchase records available.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              onPressed: _resetAllFilters,
              child: const Text("Clear Filters"),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileShimmerList(bool isDark) {
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: List.generate(
            5,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 76,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resetAllFilters() {
    setState(() {
      _selectedVendor = null;
      _selectedItem = null;
      _selectedRegion = null;
      _selectedLocation = null;
      _showHidden = false;
    });
    _applyFilters();
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

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
          width: 1.5,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? iconBgColor.withValues(alpha: 0.15) : iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
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
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 16,
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
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

  Widget _buildSquareIconButton(
    IconData icon, {
    required VoidCallback? onTap,
    Color? iconColor,
    Color? bgColor,
    Color? borderColor,
    bool isDark = false,
    double size = 38,
    String? tooltip,
  }) {
    final bg = bgColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF1F5F9));
    final border = borderColor ??
        (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    final icColor =
        iconColor ?? (isDark ? Colors.white : const Color(0xFF1E293B));

    Widget btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: icColor, size: size <= 36 ? 16 : 18),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  Widget _buildHorizontalFilterChips(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // 1. Vendor Chip
          _buildFilterChip(
            label: _selectedVendor != null ? _selectedVendor! : "Vendor: All",
            icon: Icons.person_outline_rounded,
            isActive: _selectedVendor != null,
            isDark: isDark,
            onTap: () async {
              final picked = await SearchableVendorModal.show(
                context,
                allVendors: _vendors,
                selectedVendor: _selectedVendor,
                title: "Select Vendor",
                allOptionLabel: "All Vendors",
              );
              if (picked != null) {
                setState(() => _selectedVendor = picked.isEmpty ? null : picked);
                _applyFilters();
              }
            },
          ),
          const SizedBox(width: 8),

          // 2. Item Chip
          _buildFilterChip(
            label: _selectedItem != null ? _selectedItem! : "Item: All",
            icon: Icons.grid_view_rounded,
            isActive: _selectedItem != null,
            isDark: isDark,
            onTap: () => _showQuickPickerBottomSheet(
              context: context,
              title: "Item",
              items: _items,
              currentValue: _selectedItem,
              isDark: isDark,
              onSelected: (val) {
                setState(() => _selectedItem = val);
                _applyFilters();
              },
            ),
          ),
          const SizedBox(width: 8),

          // 3. Region Chip
          _buildFilterChip(
            label: _selectedRegion != null ? _selectedRegion! : "Region: All",
            icon: Icons.map_outlined,
            isActive: _selectedRegion != null,
            isDark: isDark,
            onTap: () => _showQuickPickerBottomSheet(
              context: context,
              title: "Region",
              items: _regions,
              currentValue: _selectedRegion,
              isDark: isDark,
              onSelected: (val) {
                setState(() => _selectedRegion = val);
                _applyFilters();
              },
            ),
          ),
          const SizedBox(width: 8),

          // 4. Location Chip
          _buildFilterChip(
            label: _selectedLocation != null ? _selectedLocation! : "Loc: All",
            icon: Icons.location_on_outlined,
            isActive: _selectedLocation != null,
            isDark: isDark,
            onTap: () => _showQuickPickerBottomSheet(
              context: context,
              title: "Location",
              items: _locations,
              currentValue: _selectedLocation,
              isDark: isDark,
              onSelected: (val) {
                setState(() => _selectedLocation = val);
                _applyFilters();
              },
            ),
          ),

          // 5. Clear All button if any active filter
          if (_activeFilterCount > 0) ...[
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _selectedVendor = null;
                  _selectedItem = null;
                  _selectedRegion = null;
                  _selectedLocation = null;
                  _showHidden = false;
                });
                _applyFilters();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF87171)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                    SizedBox(width: 4),
                    Text(
                      "Clear",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final bg = isActive
        ? (isDark ? const Color(0xFFDC2626).withValues(alpha: 0.2) : const Color(0xFFFEF2F2))
        : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC));
    final border = isActive
        ? const Color(0xFFFCA5A5)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    final textColor = isActive
        ? const Color(0xFFDC2626)
        : (isDark ? Colors.white : const Color(0xFF1E293B));
    final iconColor = isActive
        ? const Color(0xFFDC2626)
        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B));

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: iconColor),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickPickerBottomSheet({
    required BuildContext context,
    required String title,
    required List<String> items,
    required String? currentValue,
    required ValueChanged<String?> onSelected,
    required bool isDark,
  }) async {
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    await showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Filter by $title",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      if (currentValue != null)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            onSelected(null);
                          },
                          child: const Text('Reset', style: TextStyle(color: Color(0xFFDC2626))),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(
                          'All ${title}s',
                          style: TextStyle(
                            fontWeight: currentValue == null ? FontWeight.bold : FontWeight.normal,
                            color: currentValue == null ? const Color(0xFFDC2626) : textColor,
                          ),
                        ),
                        trailing: currentValue == null ? const Icon(Icons.check, color: Color(0xFFDC2626), size: 18) : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          onSelected(null);
                        },
                      ),
                      ...items.map((item) {
                        final isSelected = item.trim().toUpperCase() == currentValue?.trim().toUpperCase();
                        return ListTile(
                          title: Text(
                            item,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? const Color(0xFFDC2626) : textColor,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFDC2626), size: 18) : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            onSelected(item);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStackedFilterField({
    required IconData icon,
    required String hint,
    required String? value,
    required List<String> items,
    required bool isDark,
    required ValueChanged<String?> onChanged,
    bool isSearchableVendor = false,
  }) {
    final String? safeValue = (value != null &&
            items.any((i) => i.trim().toUpperCase() == value.trim().toUpperCase()))
        ? items.firstWhere(
            (i) => i.trim().toUpperCase() == value.trim().toUpperCase())
        : null;
    final bool hasSelection = safeValue != null && safeValue.isNotEmpty;

    if (isSearchableVendor) {
      return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await SearchableVendorModal.show(
              context,
              allVendors: items,
              selectedVendor: safeValue,
              title: "Select Vendor",
              allOptionLabel: "All Vendors",
            );
            if (picked != null) {
              onChanged(picked.isEmpty ? null : picked);
            }
          },
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFDC2626), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasSelection ? safeValue : hint,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        hasSelection ? FontWeight.w700 : FontWeight.w500,
                    color: hasSelection
                        ? (isDark ? Colors.white : const Color(0xFF0F172A))
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
                  onTap: () => onChanged(null),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF94A3B8)),
                  ),
                )
              else
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF94A3B8), size: 20),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: safeValue,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF94A3B8), size: 20),
                hint: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                selectedItemBuilder: (context) {
                  return [
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    ...items.map((i) => Text(
                          i,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        )),
                  ];
                },
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  ...items.map((i) => DropdownMenuItem<String?>(
                        value: i,
                        child: Text(
                          i,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: value == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      )),
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

  Widget _buildTotalPurchaseValueCard(
    BuildContext context,
    List<dynamic> visibleList,
    bool isDark,
    Color cardColor,
    Color borderColor,
  ) {
    double totalValuation = 0.0;
    double totalTonnage = 0.0;

    for (final txn in visibleList) {
      final dynamic rawOrd = _extractField(
          txn, ['ord', 'qtyMt', 'qty', 'weightMt', 'orderedQty', 'quantity']);
      final double ord = rawOrd is num
          ? rawOrd.toDouble()
          : (double.tryParse(rawOrd?.toString() ?? '') ?? 0.0);
      totalTonnage += ord;

      final dynamic rawVal = _extractField(txn, [
        'valuation',
        'totalAmount',
        'total_amount',
        'netValuation',
        'net_valuation',
        'amount',
        'netAmount'
      ]);
      if (rawVal is num) {
        totalValuation += rawVal.toDouble();
      } else if (rawVal != null && double.tryParse(rawVal.toString()) != null) {
        totalValuation += double.tryParse(rawVal.toString())!;
      } else {
        final dynamic rawRate =
            _extractField(txn, ['rate', 'basicRate', 'price']);
        final double rate = rawRate is num
            ? rawRate.toDouble()
            : (double.tryParse(rawRate?.toString() ?? '') ?? 0.0);
        totalValuation += (rate * ord);
      }
    }

    String formattedValuation;
    if (totalValuation >= 10000000) {
      final cr = totalValuation / 10000000;
      formattedValuation = "₹ ${cr.toStringAsFixed(2)} Cr";
    } else if (totalValuation >= 100000) {
      final l = totalValuation / 100000;
      formattedValuation = "₹ ${l.toStringAsFixed(2)} Lakh";
    } else {
      formattedValuation = "₹ ${formatIndianCurrency(totalValuation.round())}";
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [
                  Color(0xFF1E293B),
                  Color(0xFF0F172A),
                ]
              : const [
                  Color(0xFF991B1B),
                  Color(0xFFDC2626),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xFFDC2626).withValues(alpha: 0.4)
              : const Color(0xFFEF4444).withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFFDC2626))
                .withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 80,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.payments_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "TOTAL PURCHASE VALUE",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          "${totalTonnage.toStringAsFixed(1)} MT Total",
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    formattedValuation,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Exact: ₹${formatIndianCurrency(totalValuation.round())} • ${visibleList.length} visible ${visibleList.length == 1 ? 'purchase' : 'purchases'}",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickySectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StickySectionHeaderDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickySectionHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

