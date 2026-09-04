import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../widgets/m_loader.dart';
import '../widgets/motion_toast.dart';
import '../services/sheet_service.dart';
import '../providers/inventory_provider.dart';
import '../utils/sorting_utils.dart';
import '../widgets/responsive_size_picker.dart';
import '../utils/steel_helper.dart';
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

  // BRAND COLORS
  static const Color brandRed = Color(0xFFD32F2F);

  @override
  void initState() {
    super.initState();
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

  double get _currentValuation {
    final double q = double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
    final double r = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    return q * r;
  }

  double get _currentQty {
    return double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
  }

  void _resetForm() {
    setState(() {
      _selectedDate = DateTime.now();
      _dateCtrl.text = DateFormat('dd/MM/yyyy').format(_selectedDate);
      _vendorCtrl.clear();
      _selectedItem = null;
      _selectedSize = null;
      _specificSizeCtrl.clear();
      _qtyCtrl.clear();
      _rateCtrl.clear();
      _remarkCtrl.clear();
      _regionCtrl.clear();
      _selectedLocation = "YARD";
    });
  }

  Future<void> _saveSauda() async {
    if (!_formKey.currentState!.validate()) return;

    if (_vendorCtrl.text.trim().isEmpty || _selectedItem == null) {
      MotionToast.show(context, "Please select Vendor and Product Item",
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
          _resetForm();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Confirm Delete",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          "Are you sure you want to delete this purchase entry?",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: brandRed,
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
          } else {
            MotionToast.show(context, "Error: ${result.errorMessage}",
                isError: true);
          }
        }
      } catch (e) {
        debugPrint("Delete error: $e");
        if (mounted) {
          MotionToast.show(context, "Delete failed: $e", isError: true);
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
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
          title: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          Navigator.of(context).pushReplacementNamed('/home');
                        }
                      },
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
                          Icons.arrow_back_rounded,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: brandRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shopping_cart_outlined,
                        color: brandRed,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Vendor Purchase Inward",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: isNarrow ? 15 : 18,
                              color:
                                  isDark ? Colors.white : const Color(0xFF1E293B),
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!isNarrow)
                            Text(
                              "Procurement Booking & Inward Stock Entry",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (!isNarrow) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_outlined,
                                size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('dd MMM yyyy').format(DateTime.now()),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
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
                          Icons.restart_alt_rounded,
                          color:
                              isDark ? Colors.white : const Color(0xFF1E293B),
                          size: 18,
                        ),
                      ),
                      tooltip: "Reset Form",
                      onPressed: _resetForm,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── SECTION 1: VENDOR & INVOICE DETAILS ───────────────────────
                  _buildSectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    title: "Vendor & Procurement Details",
                    icon: Icons.business_rounded,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isNarrow = constraints.maxWidth < 500;
                          final vendorInput = VendorSearchAutocomplete(
                            controller: _vendorCtrl,
                            existingVendors: _vendors,
                            onVendorSelected: (val) => _vendorCtrl.text = val,
                            labelText: "Vendor / Party Name",
                            validator: (v) => v == null || v.trim().isEmpty
                                ? "Vendor is required"
                                : null,
                          );

                          final dateInput = TextFormField(
                            controller: _dateCtrl,
                            readOnly: true,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                            decoration: _fieldDeco(
                              label: "Purchase Date",
                              isDark: isDark,
                              suffix: const Icon(
                                Icons.calendar_month_outlined,
                                color: brandRed,
                                size: 20,
                              ),
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2024),
                                lastDate: DateTime.now(),
                                builder: (ctx, child) => Theme(
                                  data: Theme.of(ctx).copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: brandRed,
                                      onPrimary: Colors.white,
                                    ),
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
                          );

                          if (isNarrow) {
                            return Column(
                              children: [
                                vendorInput,
                                const SizedBox(height: 12),
                                dateInput,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(flex: 3, child: vendorInput),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: dateInput),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isNarrow = constraints.maxWidth < 500;
                          final regionInput = TextFormField(
                            controller: _regionCtrl,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                            decoration: _fieldDeco(
                              label: "Purchase Region",
                              hint: "e.g. Jalna, Raipur, Local",
                              isDark: isDark,
                              prefixIcon: Icons.map_outlined,
                            ),
                            validator: (v) => v!.trim().isEmpty
                                ? "Region is required"
                                : null,
                          );

                          final locationSelector = _buildLocationPillSelector(
                              isDark, cardColor);

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                regionInput,
                                const SizedBox(height: 12),
                                locationSelector,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(flex: 3, child: regionInput),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: locationSelector),
                            ],
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── SECTION 2: MATERIAL & WEIGHT SPECIFICATIONS ─────────────
                  _buildSectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    title: "Material & Size Specifications",
                    icon: Icons.category_outlined,
                    children: [
                      Consumer<InventoryProvider>(
                        builder: (context, provider, child) {
                          final itemNames = provider.saudaItemTypes;
                          return InkWell(
                            onTap: () =>
                                _showSaudaItemPicker(context, itemNames),
                            borderRadius: BorderRadius.circular(10),
                            child: InputDecorator(
                              decoration: _fieldDeco(
                                label: "Product Category",
                                isDark: isDark,
                                suffix: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: brandRed,
                                  size: 22,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (_selectedItem != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: brandRed.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Image.asset(
                                        _getItemIconPath(_selectedItem!),
                                        width: 18,
                                        height: 18,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.category,
                                                color: brandRed, size: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      _selectedItem ??
                                          "Tap to select material category",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _selectedItem == null
                                            ? (isDark
                                                ? Colors.white38
                                                : const Color(0xFF94A3B8))
                                            : (isDark
                                                ? Colors.white
                                                : const Color(0xFF1E293B)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isNarrow = constraints.maxWidth < 500;
                          final sizePickerField = InkWell(
                            onTap: _selectedItem == null
                                ? null
                                : () => _triggerSizePicker(
                                    context, _selectedItem!),
                            borderRadius: BorderRadius.circular(10),
                            child: InputDecorator(
                              decoration: _fieldDeco(
                                label: "Standard Size Dimension",
                                hint: _selectedItem == null
                                    ? "Select material first"
                                    : "Tap to select size",
                                isDark: isDark,
                                suffix: _selectedSize != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded,
                                            size: 16, color: Colors.redAccent),
                                        onPressed: () => setState(
                                            () => _selectedSize = null),
                                      )
                                    : const Icon(Icons.arrow_drop_down,
                                        color: Color(0xFF94A3B8)),
                              ),
                              child: Text(
                                _selectedSize != null
                                    ? getFormattedSizeDisplay(
                                        _selectedSize!, null)
                                    : (_selectedItem == null
                                        ? "Select material first"
                                        : "Tap to select dimension"),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedSize == null
                                      ? (isDark
                                          ? Colors.white38
                                          : const Color(0xFF94A3B8))
                                      : brandRed,
                                ),
                              ),
                            ),
                          );

                          final customSizeField = TextFormField(
                            controller: _specificSizeCtrl,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                            decoration: _fieldDeco(
                              label: "Custom Spec / Notes",
                              hint: "e.g. 12ft, Heavy Gauge",
                              isDark: isDark,
                              prefixIcon: Icons.edit_note_outlined,
                            ),
                          );

                          if (isNarrow) {
                            return Column(
                              children: [
                                sizePickerField,
                                const SizedBox(height: 12),
                                customSizeField,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(flex: 3, child: sizePickerField),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: customSizeField),
                            ],
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── SECTION 3: PURCHASE VALUATION & CALCULATIONS ────────────
                  _buildSectionCard(
                    isDark: isDark,
                    cardColor: cardColor,
                    title: "Purchase Valuation & Numbers",
                    icon: Icons.calculate_outlined,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isNarrow = constraints.maxWidth < 450;
                          final qtyField = TextFormField(
                            controller: _qtyCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                            decoration: _fieldDeco(
                              label: "Order Qty (MT)",
                              isDark: isDark,
                              suffixText: "MT",
                              prefixIcon: Icons.scale_outlined,
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (v) =>
                                (double.tryParse(v ?? '') ?? 0) <= 0
                                    ? "Invalid Qty"
                                    : null,
                          );

                          final rateField = TextFormField(
                            controller: _rateCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                            decoration: _fieldDeco(
                              label: "Basic Purchase Rate",
                              isDark: isDark,
                              prefixText: "₹ ",
                              suffixText: "/MT",
                              prefixIcon: Icons.currency_rupee_rounded,
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (v) =>
                                (double.tryParse(v ?? '') ?? 0) <= 0
                                    ? "Invalid Rate"
                                    : null,
                          );

                          if (isNarrow) {
                            return Column(
                              children: [
                                qtyField,
                                const SizedBox(height: 12),
                                rateField,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: qtyField),
                              const SizedBox(width: 12),
                              Expanded(child: rateField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      // ── LIVE PURCHASE VALUATION BANNER ───────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, valConstraints) {
                            final isVeryNarrow = valConstraints.maxWidth < 360;

                            final weightWidget = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "TOTAL ORDER WEIGHT",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${_currentQty.toStringAsFixed(3)} MT",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            );

                            final valuationWidget = Column(
                              crossAxisAlignment: isVeryNarrow
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "NET PURCHASE VALUATION",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "₹ ${formatIndianCurrency(_currentValuation)}",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: brandRed,
                                  ),
                                ),
                              ],
                            );

                            if (isVeryNarrow) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  weightWidget,
                                  const SizedBox(height: 8),
                                  Divider(
                                    height: 1,
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                  const SizedBox(height: 8),
                                  valuationWidget,
                                ],
                              );
                            }

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                weightWidget,
                                Container(
                                  height: 30,
                                  width: 1,
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1),
                                ),
                                valuationWidget,
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _remarkCtrl,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                        decoration: _fieldDeco(
                          label: "Remarks / Inward Notes (Optional)",
                          hint: "e.g. Mill test certificate attached, Truck #",
                          isDark: isDark,
                          prefixIcon: Icons.notes_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ── ACTION BUTTON DOCK ───────────────────────────────────────
                  ValueListenableBuilder(
                    valueListenable: DataRepository.currentUserNotifier,
                    builder: (context, user, _) {
                      final canSubmit = hasVendorPurchaseAccess(user);

                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: _resetForm,
                              icon: const Icon(Icons.restart_alt_rounded,
                                  size: 18),
                              label: const Text(
                                "Clear Form",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? Colors.white70
                                    : const Color(0xFF64748B),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1),
                                ),
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: (_isLoading || !canSubmit)
                                  ? null
                                  : _saveSauda,
                              icon: _isLoading
                                  ? const SizedBox.shrink()
                                  : Icon(
                                      canSubmit
                                          ? Icons.save_rounded
                                          : Icons.lock_outline,
                                      color: Colors.white,
                                      size: 18),
                              label: _isLoading
                                  ? const MLoader(size: 20, color: Colors.white)
                                  : Text(
                                      canSubmit
                                          ? "SAVE INWARD ENTRY"
                                          : "🔒 ACCESS RESTRICTED",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    canSubmit ? brandRed : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // ── RECENT PURCHASE LEDGER STRIP ───────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 3.5,
                              height: 16,
                              decoration: BoxDecoration(
                                color: brandRed,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Recent Purchase Ledger",
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle,
                                size: 6, color: Color(0xFF10B981)),
                            SizedBox(width: 4),
                            Text(
                              "LIVE STREAM",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF10B981),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── RECENT PURCHASE LEDGER STREAM ──────────────────────────
                  ValueListenableBuilder<bool>(
                    valueListenable: _purchaseLedgerStream!.isErrorNotifier,
                    builder: (context, hasError, _) {
                      if (hasError) {
                        return _buildShimmerLedgerPlaceholder();
                      }

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _purchaseLedgerStream!.stream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
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
                              decoration: _cardDecoration(isDark, cardColor),
                              child: const Center(
                                child: Text(
                                  "No purchase records logged yet.",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF94A3B8),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }

                          // Sort by created_at descending
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
                            separatorBuilder: (c, i) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final item = recentList[i];
                              final rawDate = item['date_time'] ??
                                  item['created_at'] ??
                                  '';
                              String formattedDate = 'N/A';
                              if (rawDate.isNotEmpty) {
                                try {
                                  final parsed = parseSupabaseDateTime(rawDate);
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
                              final rate =
                                  (item['rate'] as num?)?.toDouble() ?? 0.0;
                              final isRev = item['is_reversed'] == true;

                              return Container(
                                decoration: _cardDecoration(isDark, cardColor),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: brandRed.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.shopping_bag_outlined,
                                        color: brandRed,
                                        size: 18,
                                      ),
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
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1E293B),
                                              decoration: isRev
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "$material ${size.isNotEmpty ? '• $size' : ''} ${rate > 0 ? '• ₹${formatIndianCurrency(rate)}' : ''}",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          "${qty.toStringAsFixed(3)} MT",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: isRev
                                                ? Colors.grey
                                                : const Color(0xFF059669),
                                            decoration: isRev
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formattedDate,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? const Color(0xFF64748B)
                                                : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFD32F2F),
                                        size: 18,
                                      ),
                                      tooltip: "Delete Entry",
                                      onPressed: AccessGuard.can(AppPermissions
                                                  .vendorPurchase) ||
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

                  // ── VIEW ALL PURCHASE HISTORY BUTTON ────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const VendorPurchaseReportScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: const Text(
                        "View Full Vendor Purchase Ledger",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: brandRed,
                        side: BorderSide(
                          color: brandRed.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationPillSelector(bool isDark, Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Location",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: ["YARD", "FACTORY"].map((loc) {
              final isSelected = _selectedLocation == loc;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () => setState(() => _selectedLocation = loc),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? brandRed
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      loc,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? Colors.white70
                                : const Color(0xFF334155)),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required Color cardColor,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: _cardDecoration(isDark, cardColor),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: brandRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: brandRed, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
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

  InputDecoration _fieldDeco({
    required String label,
    required bool isDark,
    String? hint,
    Widget? suffix,
    String? prefixText,
    String? suffixText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      suffixText: suffixText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon,
              size: 18,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
          : null,
      prefixStyle: TextStyle(
        color: isDark ? Colors.white70 : const Color(0xFF64748B),
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      suffixStyle: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      labelStyle: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
        fontSize: 12,
      ),
      filled: true,
      isDense: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: brandRed, width: 1.5),
      ),
    );
  }

  void _showSaudaItemPicker(BuildContext context, List<String> itemNames) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    final sortedNames = List<String>.from(itemNames)
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String query = "";
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered =
                applyPrioritizedSearch(query, sortedNames, (n) => n);

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 20,
                  left: 20,
                  right: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Select Material Category",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color:
                                isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "Search material categories...",
                        hintStyle: TextStyle(
                          color:
                              isDark ? Colors.white24 : const Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color:
                              isDark ? Colors.white60 : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: brandRed, width: 1.5),
                        ),
                      ),
                      onChanged: (val) => setSheetState(() => query = val),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  "No material category found",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white38
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) => Divider(
                                height: 1,
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: brandRed.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Image.asset(
                                      _getItemIconPath(name),
                                      width: 22,
                                      height: 22,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.category_rounded,
                                        color: brandRed,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
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
    ).then((selectedName) {
      if (selectedName != null && selectedName is String) {
        _onItemChanged(selectedName);
      }
    });
  }

  String _getItemIconPath(String catName) {
    String name = catName.toLowerCase().trim();
    if (name.contains("pipe") && name.contains("hr")) {
      return "assets/hr_pipe.png";
    }
    if (name.contains("pipe")) return "assets/ms_pipe.png";
    if (name.contains("round")) return "assets/round_bar.png";
    if (name.contains("angle")) return "assets/angle.png";
    if (name.contains("channel")) return "assets/channel.png";
    if (name.contains("flat")) return "assets/flat.png";
    return "assets/msm_icon.jpg";
  }

  Widget _buildShimmerLedgerPlaceholder() {
    return Shimmer(
      child: Column(
        children: List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            height: 60,
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
