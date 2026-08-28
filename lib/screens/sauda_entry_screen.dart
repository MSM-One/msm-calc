import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/m_loader.dart';
import '../widgets/motion_toast.dart';
import '../services/sheet_service.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/sorting_utils.dart';
import '../widgets/responsive_size_picker.dart';
import '../utils/steel_helper.dart';
import '../constants/app_colors.dart';
import '../services/supabase_service.dart';
import 'sauda_report_screen.dart';
import '../utils/resilient_supabase_stream.dart';
import '../widgets/shimmer_widget.dart';
import '../utils/formatters.dart';

import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../services/data_repository.dart';
import '../widgets/vendor_search_autocomplete.dart';

class SaudaEntryScreen extends StatefulWidget {
  const SaudaEntryScreen({super.key});

  @override
  State<SaudaEntryScreen> createState() => _SaudaEntryScreenState();
}

class _SaudaEntryScreenState extends State<SaudaEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _dateCtrl;
  late TextEditingController _vendorCtrl;
  late TextEditingController _specificSizeCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _rateCtrl;
  late TextEditingController _remarkCtrl;
  late TextEditingController _regionCtrl;

  DateTime _selectedDate = DateTime.now();
  String? _selectedItem;
  String? _selectedSize;
  String _selectedLocation = "YARD";

  List<String> _vendors = [];
  bool _isLoading = false;
  ResilientSupabaseStream<List<Map<String, dynamic>>>? _purchaseLedgerStream;

  // COLORS
  final Color msmRed = const Color(0xFFE52823);
  final Color cardBg = Colors.white;
  final Color screenBg = const Color(0xFFF5F5F5);

  @override
  void initState() {
    _purchaseLedgerStream = ResilientSupabaseStream<List<Map<String, dynamic>>>(
      streamFactory: () => SupabaseService.client
          .from('transactions')
          .stream(primaryKey: ['id'])
          .eq('txn_type', 'PURCHASE')
          .order('created_at'),
    );
    _dateCtrl = TextEditingController();
    _vendorCtrl = TextEditingController();
    _specificSizeCtrl = TextEditingController();
    _qtyCtrl = TextEditingController();
    _rateCtrl = TextEditingController();
    _remarkCtrl = TextEditingController();
    _regionCtrl = TextEditingController();
    _dateCtrl.text = DateFormat('dd/MM/yyyy').format(_selectedDate);
    super.initState();

    // --- Navigation Guard: Admin or Log Vendor Purchase Permission ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = DataRepository.currentUserNotifier.value;
      if (!hasVendorPurchaseAccess(user)) {
        MotionToast.show(context, "Access Denied: Missing Permission",
            isError: true);
        Navigator.pop(context);
      }
    });

    context.read<InventoryProvider>().loadSaudaData();
    _loadVendors();
  }

  @override
  void dispose() {
    _purchaseLedgerStream?.dispose();
    _dateCtrl.dispose();
    _vendorCtrl.dispose();
    _specificSizeCtrl.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _remarkCtrl.dispose();
    _regionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVendors() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final txns = await SheetService.fetchTransactions(limit: 50);
      final vendorsList = txns
          .map((t) => t['partyName']?.toString() ?? "")
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          _vendors = vendorsList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("[VendorPurchase] Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onItemChanged(String? newItem) {
    setState(() {
      _selectedItem = newItem;
      _selectedSize = null;
      _specificSizeCtrl.text = "";
    });
    if (newItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerSizePicker(context, newItem);
      });
    }
  }

  Future<void> _triggerSizePicker(BuildContext context, String itemType) async {
    final result = await ResponsiveSizePicker.show(
      context,
      itemType: itemType,
    );
    if (result != null) {
      setState(() {
        _selectedSize = result['label']?.toString();
      });
    }
  }

  Future<void> _saveSauda() async {
    if (!_formKey.currentState!.validate()) return;

    if (_vendorCtrl.text.trim().isEmpty || _selectedItem == null) {
      MotionToast.show(context, "Please fill Vendor and Item fields",
          isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final String customSizeText = _specificSizeCtrl.text.trim();
    final String resolvedSize =
        (_selectedSize != null && _selectedSize!.isNotEmpty)
            ? _selectedSize!
            : customSizeText;

    final data = {
      "date": _dateCtrl.text,
      "vendor": _vendorCtrl.text.trim(),
      "item": _selectedItem,
      "size": resolvedSize,
      "specificSize": customSizeText,
      "orderQty": double.tryParse(_qtyCtrl.text) ?? 0,
      "basicRate": double.tryParse(_rateCtrl.text) ?? 0,
      "remark": _remarkCtrl.text.trim(),
      "region": _regionCtrl.text.trim(),
      "location": _selectedLocation,
    };

    try {
      final result = await SheetService.submitSauda(data);
      if (mounted) {
        setState(() => _isLoading = false);
        if (result.success) {
          MotionToast.show(context, "Vendor Purchase Saved Successfully");
          Navigator.pop(context, true);
        } else {
          MotionToast.show(context, "Error: ${result.errorMessage}",
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        MotionToast.show(context, "Connection Error: $e", isError: true);
      }
    }
  }

  Future<void> _confirmDeleteEntry(Map<String, dynamic> item) async {
    final String entryId =
        item['txn_id']?.toString() ?? item['id']?.toString() ?? "";
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
            style: ElevatedButton.styleFrom(backgroundColor: msmRed),
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
        } else {
          MotionToast.show(context, "Error: ${result.errorMessage}",
              isError: true);
        }
      } catch (e) {
        debugPrint("Delete error: $e");
        MotionToast.show(context, "Delete failed: $e", isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _fieldDeco(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 14),
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: msmRed, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: screenBg,
      appBar: AppBar(
        title: const Text(
          "Add New Booking",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
            overflow: TextOverflow.ellipsis,
          ),
          maxLines: 1,
        ),
        backgroundColor: msmRed,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Group 1: Basic Details
              _buildCard(
                children: [
                  const Text("Basic Details",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dateCtrl,
                    readOnly: true,
                    decoration: _fieldDeco("Booking Date",
                        suffix: Icon(Icons.calendar_month_outlined,
                            color: msmRed, size: 22)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: ColorScheme.light(
                                primary: msmRed, onPrimary: Colors.white),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                          _dateCtrl.text =
                              DateFormat('dd/MM/yyyy').format(picked);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _regionCtrl,
                    decoration: _fieldDeco("Purchase Region",
                        hint: "e.g. Jalna, Raipur"),
                    validator: (v) =>
                        v!.trim().isEmpty ? "Region is required" : null,
                  ),
                  const SizedBox(height: 16),
                  VendorSearchAutocomplete(
                    controller: _vendorCtrl,
                    existingVendors: _vendors,
                    onVendorSelected: (val) => _vendorCtrl.text = val,
                    labelText: "Vendor Name",
                    validator: (v) => v == null || v.trim().isEmpty
                        ? "Vendor is required"
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedLocation,
                    decoration: _fieldDeco("Location"),
                    items: ["YARD", "FACTORY"]
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLocation = v!),
                  ),
                ],
              ),

              // Group 2: Product Details
              _buildCard(
                children: [
                  const Text("Product Details",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  Consumer<InventoryProvider>(
                    builder: (context, provider, child) {
                      final itemNames = provider.saudaItemTypes;
                      return InkWell(
                        onTap: () {
                          _showSaudaItemPicker(context, itemNames);
                        },
                        child: InputDecorator(
                          decoration: _fieldDeco("Select Item").copyWith(
                            suffixIcon: Icon(Icons.keyboard_arrow_down_rounded,
                                color: msmRed),
                          ),
                          child: Text(
                            _selectedItem ?? "Tap to select product",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color:
                                  _selectedItem == null ? textGrey : textDark,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _selectedItem == null
                              ? null
                              : () =>
                                  _triggerSizePicker(context, _selectedItem!),
                          child: IgnorePointer(
                            child: TextFormField(
                              key: ValueKey('${_selectedItem}_$_selectedSize'),
                              initialValue: _selectedSize == null
                                  ? null
                                  : getFormattedSizeDisplay(
                                      _selectedSize!, null),
                              readOnly: true,
                              decoration: _fieldDeco(
                                "Select Size (Optional)",
                                hint: _selectedItem == null
                                    ? "Select an Item first"
                                    : "Click to select size (Optional)",
                                suffix: const Icon(Icons.arrow_drop_down,
                                    color: Colors.grey),
                              ),
                              validator: (v) => null,
                            ),
                          ),
                        ),
                      ),
                      if (_selectedSize != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          tooltip: "Clear Size",
                          onPressed: () => setState(() => _selectedSize = null),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _specificSizeCtrl,
                    decoration: _fieldDeco("Custom Specification",
                        hint: "e.g. 12ft, Special..."),
                  ),
                ],
              ),

              // Group 3: Numbers
              _buildCard(
                children: [
                  const Text("Calculations",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, constraints) {
                    bool stack = constraints.maxWidth < 400;
                    List<Widget> children = [
                      Flexible(
                        flex: stack ? 0 : 1,
                        fit: stack ? FlexFit.loose : FlexFit.tight,
                        child: TextFormField(
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _fieldDeco("Qty (MT)"),
                          validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                              ? "Invalid Qty"
                              : null,
                        ),
                      ),
                      if (!stack) const SizedBox(width: 16),
                      if (stack) const SizedBox(height: 16),
                      Flexible(
                        flex: stack ? 0 : 1,
                        fit: stack ? FlexFit.loose : FlexFit.tight,
                        child: TextFormField(
                          controller: _rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _fieldDeco("Basic Rate"),
                          validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                              ? "Invalid Rate"
                              : null,
                        ),
                      ),
                    ];
                    return stack
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children)
                        : Row(children: children);
                  }),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _remarkCtrl,
                    maxLines: 2,
                    decoration: _fieldDeco("Remark (Optional)"),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Submit Button
              ValueListenableBuilder(
                valueListenable: DataRepository.currentUserNotifier,
                builder: (context, user, _) {
                  final canSubmit = hasVendorPurchaseAccess(user);

                  return ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 55),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_isLoading || !canSubmit) ? null : _saveSauda,
                        icon: _isLoading
                            ? const SizedBox.shrink()
                            : Icon(
                                canSubmit
                                    ? Icons.save_rounded
                                    : Icons.lock_outline,
                                color: Colors.white,
                                size: 22),
                        label: _isLoading
                            ? const MLoader(size: 20, color: Colors.white)
                            : Text(
                                canSubmit
                                    ? "SAVE ENTRY"
                                    : "🔒 ACCESS RESTRICTED",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 1),
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canSubmit ? msmRed : Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade400,
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: canSubmit ? 4 : 0,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              // ── Purchase Ledger Header ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Recent Purchase Ledger",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "LIVE",
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Purchase Ledger Stream List ────────────────────────────────
              ValueListenableBuilder<bool>(
                valueListenable: _purchaseLedgerStream!.isErrorNotifier,
                builder: (context, hasError, _) {
                  if (hasError) {
                    return _buildShimmerLedgerPlaceholder();
                  }

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _purchaseLedgerStream!.stream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildShimmerLedgerPlaceholder();
                      }
                      if (snapshot.hasError) {
                        return _buildShimmerLedgerPlaceholder();
                      }
                      final data = snapshot.data ?? [];
                      if (data.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Center(
                            child: Text(
                              "No purchase records found.",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                        );
                      }

                      // Sort by created_at descending in memory
                      final sorted = List<Map<String, dynamic>>.from(data);
                      sorted.sort((a, b) {
                        final tA = DateTime.tryParse(
                                a['created_at']?.toString() ?? '') ??
                            DateTime.now();
                        final tB = DateTime.tryParse(
                                b['created_at']?.toString() ?? '') ??
                            DateTime.now();
                        return tB.compareTo(tA);
                      });

                      final recentList = sorted.take(5).toList();

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: recentList.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = recentList[i];
                          final rawDate =
                              item['date_time'] ?? item['created_at'] ?? '';
                          String formattedDate = 'N/A';
                          if (rawDate.isNotEmpty) {
                            try {
                              final parsed = DateTime.parse(rawDate);
                              formattedDate =
                                  DateFormat('dd MMM yyyy').format(parsed);
                            } catch (_) {}
                          }

                          final vendor =
                              item['party_name']?.toString() ?? 'N/A';
                          final material =
                              item['item_name']?.toString() ?? 'N/A';
                          final size = item['size']?.toString() ?? '';
                          final qty =
                              (item['qty_mt'] as num?)?.toDouble() ?? 0.0;
                          final isRev = item['is_reversed'] == true;

                          return Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.shade200, width: 1),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.shopping_bag_outlined,
                                      color: Colors.red, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vendor,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.grey.shade800,
                                          decoration: isRev
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "$material ${size.isNotEmpty ? '($size)' : ''}",
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${qty.toStringAsFixed(3)} MT",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isRev
                                            ? Colors.grey
                                            : Colors.green.shade700,
                                        decoration: isRev
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formattedDate,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade400),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 20),
                                  tooltip: "Delete Entry",
                                  onPressed: AccessGuard.can(
                                              AppPermissions.vendorPurchase) ||
                                          AccessGuard.can(
                                              AppPermissions.usersDelete)
                                      ? () => _confirmDeleteEntry(item)
                                      : null,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),

              // ── View All Purchases Button ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const VendorPurchaseReportScreen()),
                    );
                  },
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text(
                    "View All Purchase History",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: msmRed,
                    side: BorderSide(color: msmRed.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showSaudaItemPicker(BuildContext context, List<String> itemNames) {
    final sortedNames = List<String>.from(itemNames)
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
            final filtered =
                applyPrioritizedSearch(query, sortedNames, (n) => n);

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
                        Icon(Icons.sort, color: msmRed),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: _fieldDeco("Search item...",
                              hint: "Type to search...")
                          .copyWith(
                        prefixIcon: const Icon(Icons.search, color: textGrey),
                      ),
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
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.category,
                                            color: msmRed,
                                            size: 20)),
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: textDark)),
                                  trailing: const Icon(Icons.chevron_right,
                                      size: 16, color: textGrey),
                                  onTap: () {
                                    Navigator.pop(context, name);
                                  },
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
    ).then((selectedName) {
      if (selectedName != null && selectedName is String) {
        _onItemChanged(selectedName);
      }
    });
  }

  String _getItemIconPath(String catName) {
    final norm = catName.toLowerCase().replaceAll(' ', '_');
    return 'assets/images/icons/$norm.png';
  }

  Widget _buildShimmerLedgerPlaceholder() {
    return Shimmer(
      child: Column(
        children: List.generate(
            3,
            (index) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                )),
      ),
    );
  }
}
