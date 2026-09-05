import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/stock_models.dart';
import '../../services/data_repository.dart';
import '../../services/stock_notifier.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../utils/item_order_util.dart';
import '../../utils/category_matcher.dart';
import '../../widgets/motion_toast.dart';

/// Compact Transaction Entry Panel for Enterprise Inventory In / Out / Transfer.
/// Supports high-density two-column layout on desktop and streamlined scroll on mobile.
class CompactTransactionEntryPanel extends StatefulWidget {
  final String? initialType;
  final String? initialMaterial;
  final String? initialSize;
  final String? initialLocation;
  final VoidCallback? onTransactionSubmitted;

  const CompactTransactionEntryPanel({
    super.key,
    this.initialType,
    this.initialMaterial,
    this.initialSize,
    this.initialLocation,
    this.onTransactionSubmitted,
  });

  @override
  State<CompactTransactionEntryPanel> createState() =>
      _CompactTransactionEntryPanelState();
}

class _CompactTransactionEntryPanelState
    extends State<CompactTransactionEntryPanel> {
  final _formKey = GlobalKey<FormState>();

  String _selectedType = 'IN'; // 'IN', 'OUT', 'TRANSFER'
  String _selectedLocation = 'YARD'; // 'YARD', 'FACTORY'
  String _toLocation = 'FACTORY'; // For TRANSFER
  String? _selectedMaterial;
  String? _selectedSize;

  final TextEditingController _weightMTCtrl = TextEditingController();
  final TextEditingController _vehicleNoCtrl = TextEditingController();
  final TextEditingController _invoiceNoCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();

  bool _isSubmitting = false;
  List<String> _materialOptions = [];
  Map<String, List<Map<String, dynamic>>> _materialSizesMap = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _selectedType = widget.initialType!;
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation!.toUpperCase();
    }
    _selectedMaterial = widget.initialMaterial;
    _selectedSize = widget.initialSize;

    _loadMasterMaterialsAndSizes();
    DataRepository.sheetDataNotifier.addListener(_loadMasterMaterialsAndSizes);
    DataRepository.itemSizesNotifier.addListener(_loadMasterMaterialsAndSizes);
    _weightMTCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    DataRepository.sheetDataNotifier.removeListener(_loadMasterMaterialsAndSizes);
    DataRepository.itemSizesNotifier.removeListener(_loadMasterMaterialsAndSizes);
    _weightMTCtrl.dispose();
    _vehicleNoCtrl.dispose();
    _invoiceNoCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getSizesForCategory(String? selectedCategory) {
    if (selectedCategory == null || selectedCategory.trim().isEmpty) {
      return [];
    }
    final allMasterSizes = DataRepository.itemSizesNotifier.value;

    final availableSizes = allMasterSizes.where((size) {
      return isSizeInCategory(size, selectedCategory);
    }).map((s) {
      String label = (s['label'] ?? s['size_label'] ?? '').toString().trim();
      double w = double.tryParse((s['weight'] ?? s['unit_weight_kg'] ?? '0').toString()) ?? 0.0;
      double sd = double.tryParse((s['sd'] ?? s['size_difference'] ?? '0').toString()) ?? 0.0;
      return {
        'label': label,
        'unit_weight_kg': w,
        'sd': sd,
      };
    }).toList();

    return availableSizes;
  }

  void _loadMasterMaterialsAndSizes() {
    if (!mounted) return;
    final data = DataRepository.sheetDataNotifier.value;
    final List<dynamic> itemsList = data['items'] ?? [];
    final Map<String, List<Map<String, dynamic>>> tempMap = {};

    for (var item in itemsList) {
      final name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final rawSizes = item['sizes'] as List? ?? [];
      final parsedSizes = rawSizes.map((s) {
        String label = (s['label'] ?? s['size_label'] ?? '').toString().trim();
        double w = double.tryParse((s['weight'] ?? s['unit_weight_kg'] ?? '0').toString()) ?? 0.0;
        double sd = double.tryParse((s['sd'] ?? s['size_difference'] ?? '0').toString()) ?? 0.0;
        return {
          'label': label,
          'unit_weight_kg': w,
          'sd': sd,
        };
      }).toList();

      tempMap[name] = parsedSizes;
    }

    final dynamicCategories = DataRepository.getDynamicCategories();
    for (final cat in dynamicCategories) {
      if (!tempMap.containsKey(cat) || tempMap[cat]!.isEmpty) {
        final sizes = _getSizesForCategory(cat);
        if (sizes.isNotEmpty) {
          tempMap[cat] = sizes;
        } else if (!tempMap.containsKey(cat)) {
          tempMap[cat] = [];
        }
      }
    }

    final sortedMaterials = tempMap.keys.toList()
      ..sort((a, b) => ItemOrderUtil.compare(a, b));

    setState(() {
      _materialSizesMap = tempMap;
      _materialOptions = sortedMaterials;
      if (_selectedMaterial == null && sortedMaterials.isNotEmpty) {
        _selectedMaterial = sortedMaterials.first;
      }
      if (_selectedMaterial != null &&
          _materialSizesMap.containsKey(_selectedMaterial) &&
          _materialSizesMap[_selectedMaterial]!.isNotEmpty) {
        if (_selectedSize == null ||
            !_materialSizesMap[_selectedMaterial]!
                .any((s) => s['label'] == _selectedSize)) {
          _selectedSize = _materialSizesMap[_selectedMaterial]!.first['label'];
        }
      }
    });
  }

  /// Calculates available stock in MT from DataRepository for the selected material & size
  double _getAvailableStockMT() {
    if (_selectedMaterial == null || _selectedSize == null) return 0.0;

    final inventory = DataRepository.inventoryListNotifier.value;
    for (final item in inventory) {
      final locMatch = StockUtils.normalizeLocation(item.location) ==
          StockUtils.normalizeLocation(_selectedLocation);
      final itemMatch = item.itemName.trim().toLowerCase() ==
          _selectedMaterial!.trim().toLowerCase();
      final sizeMatch = item.size.trim().toLowerCase() ==
          _selectedSize!.trim().toLowerCase();

      if (locMatch && itemMatch && sizeMatch) {
        return item.currentStockMT;
      }
    }
    return 0.0;
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMaterial == null || _selectedSize == null) {
      MotionToast.show(context, 'Please select both material and size', isError: true);
      return;
    }

    final enteredQty = double.tryParse(_weightMTCtrl.text.trim()) ?? 0.0;
    if (enteredQty <= 0) {
      MotionToast.show(context, 'Please enter a valid weight in MT (> 0)', isError: true);
      return;
    }

    final availableStock = _getAvailableStockMT();
    final bool isDeficit = _selectedType == 'OUT' && enteredQty > availableStock;

    if (isDeficit) {
      final shortfall = enteredQty - availableStock;
      MotionToast.show(
        context,
        'Deficit Warning: Shortfall of -${shortfall.toStringAsFixed(3)} MT recorded for audit.',
        isError: false,
      );
    }

    setState(() => _isSubmitting = true);

    try {
      final txId = '${DateTime.now().millisecondsSinceEpoch}_0';
      final timestamp = DateTime.now().toIso8601String();

      final supabaseTxn = {
        'txn_id': txId,
        'date': timestamp,
        'date_time': timestamp,
        'item_name': _selectedMaterial!,
        'size': _selectedSize!,
        'type': _selectedType,
        'txn_type': _selectedType,
        'qty_mt': enteredQty,
        'location': _selectedLocation,
        'to_location': _selectedType == 'TRANSFER' ? _toLocation : null,
        'invoice_no': _invoiceNoCtrl.text.trim(),
        'bill_no': _invoiceNoCtrl.text.trim(),
        'lorry_no': _vehicleNoCtrl.text.trim().toUpperCase(),
        'note': _remarksCtrl.text.trim(),
        'is_reversed': false,
      };

      await SupabaseService().insertTransaction(supabaseTxn);
      await DataRepository.getERPStockAsync(null, forceRefresh: true);
      notifyStockDataChanged();

      if (mounted) {
        MotionToast.show(
          context,
          '${_selectedType == 'IN' ? 'Inward' : _selectedType == 'OUT' ? 'Dispatch' : 'Transfer'} recorded successfully ✔',
        );
        _clearInputs();
        widget.onTransactionSubmitted?.call();
      }
    } catch (e) {
      debugPrint('[CompactTransactionEntryPanel] Submit Error: $e');
      if (mounted) {
        MotionToast.show(context, 'Transaction failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _clearInputs() {
    _weightMTCtrl.clear();
    _vehicleNoCtrl.clear();
    _invoiceNoCtrl.clear();
    _remarksCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final availableStock = _getAvailableStockMT();
    final enteredQty = double.tryParse(_weightMTCtrl.text.trim()) ?? 0.0;
    final bool isDeficit = _selectedType == 'OUT' && enteredQty > availableStock;
    final double deficitAmount = enteredQty - availableStock;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── HEADER & TYPE TOGGLE ──
                _buildHeader(isDesktop),
                const SizedBox(height: 12),

                // ── REAL-TIME STOCK & DEFICIT TELEMETRY ──
                _buildStockTelemetryBadge(availableStock, isDeficit, deficitAmount),
                const SizedBox(height: 12),

                // ── FORM FIELDS GRID ──
                if (isDesktop)
                  _buildDesktopGrid()
                else
                  _buildMobileFields(),

                const SizedBox(height: 14),

                // ── SUBMIT BUTTON ──
                _buildSubmitButton(isDeficit),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── HEADER & TYPE SELECTOR ──
  Widget _buildHeader(bool isDesktop) {
    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _selectedType == 'IN'
                      ? const Color(0xFFECFDF5)
                      : _selectedType == 'OUT'
                          ? const Color(0xFFF1F5F9)
                          : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _selectedType == 'IN'
                      ? Icons.arrow_downward_rounded
                      : _selectedType == 'OUT'
                          ? Icons.arrow_upward_rounded
                          : Icons.swap_horiz_rounded,
                  size: 16,
                  color: _selectedType == 'IN'
                      ? const Color(0xFF059669)
                      : _selectedType == 'OUT'
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'New Transaction',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTypePills(),
        ],
      );
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _selectedType == 'IN'
                ? const Color(0xFFECFDF5)
                : _selectedType == 'OUT'
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _selectedType == 'IN'
                ? Icons.arrow_downward_rounded
                : _selectedType == 'OUT'
                    ? Icons.arrow_upward_rounded
                    : Icons.swap_horiz_rounded,
            size: 18,
            color: _selectedType == 'IN'
                ? const Color(0xFF059669)
                : _selectedType == 'OUT'
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'New Transaction',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
        ),
        // Type Selector Segmented Pills
        _buildTypePills(),
      ],
    );
  }

  Widget _buildTypePills() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPillItem('IN', 'Inward', const Color(0xFF059669)),
          _buildPillItem('OUT', 'Dispatch', const Color(0xFF0F172A)),
          _buildPillItem('TRANSFER', 'Transfer', const Color(0xFFD97706)),
        ],
      ),
    );
  }

  Widget _buildPillItem(String type, String label, Color activeColor) {
    final bool isSelected = _selectedType == type;
    return InkWell(
      onTap: () => setState(() => _selectedType = type),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  // ── STOCK TELEMETRY & DEFICIT INDICATOR ──
  Widget _buildStockTelemetryBadge(
      double availableStock, bool isDeficit, double deficitAmount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDeficit
            ? const Color(0xFFFEF2F2)
            : availableStock > 0
                ? const Color(0xFFF8FAFC)
                : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDeficit
              ? const Color(0xFFFECACA)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDeficit
                ? Icons.warning_amber_rounded
                : Icons.inventory_2_outlined,
            size: 16,
            color: isDeficit
                ? const Color(0xFFDC2626)
                : const Color(0xFF475569),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                children: [
                  TextSpan(
                    text: 'Live Stock ($_selectedLocation): ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '${availableStock.toStringAsFixed(3)} MT',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: availableStock >= 0
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                  if (isDeficit) ...[
                    const TextSpan(text: '  ·  '),
                    TextSpan(
                      text: 'Deficit Alert: -${deficitAmount.toStringAsFixed(3)} MT shortfall',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── DESKTOP TWO-COLUMN GRID ──
  Widget _buildDesktopGrid() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildMaterialDropdown()),
            const SizedBox(width: 12),
            Expanded(child: _buildSizeDropdown()),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildWeightInput()),
            const SizedBox(width: 12),
            Expanded(child: _buildLocationSelector()),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildVehicleInput()),
            const SizedBox(width: 12),
            Expanded(child: _buildInvoiceInput()),
          ],
        ),
        const SizedBox(height: 10),
        _buildRemarksInput(),
      ],
    );
  }

  // ── MOBILE COMPACT SINGLE COLUMN ──
  Widget _buildMobileFields() {
    return Column(
      children: [
        _buildMaterialDropdown(),
        const SizedBox(height: 8),
        _buildSizeDropdown(),
        const SizedBox(height: 8),
        _buildWeightInput(),
        const SizedBox(height: 8),
        _buildLocationSelector(),
        const SizedBox(height: 8),
        _buildVehicleInput(),
        const SizedBox(height: 8),
        _buildInvoiceInput(),
        const SizedBox(height: 8),
        _buildRemarksInput(),
      ],
    );
  }

  // ── FORM FIELD WIDGETS ──
  Widget _buildMaterialDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedMaterial,
      isExpanded: true,
      menuMaxHeight: 350,
      decoration: _inputDecoration(
        label: 'Material / Category',
        icon: Icons.category_outlined,
      ),
      items: _materialOptions.map((mat) {
        return DropdownMenuItem<String>(
          value: mat,
          child: Text(
            mat,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        );
      }).toList(),
      onChanged: (val) {
        setState(() {
          _selectedMaterial = val;
          _selectedSize = null; // reset previously selected size
          if (val != null) {
            final available = _materialSizesMap[val] ?? _getSizesForCategory(val);
            _materialSizesMap[val] = available;
            if (available.isNotEmpty) {
              _selectedSize = available.first['label'];
            }
          }
        });
      },
    );
  }

  Widget _buildSizeDropdown() {
    final sizes = _selectedMaterial != null
        ? (_materialSizesMap[_selectedMaterial] ?? _getSizesForCategory(_selectedMaterial))
        : <Map<String, dynamic>>[];

    return DropdownButtonFormField<String>(
      value: _selectedSize,
      isExpanded: true,
      menuMaxHeight: 350,
      decoration: _inputDecoration(
        label: _selectedMaterial == null
            ? 'Select category first'
            : sizes.isEmpty
                ? 'No sizes available'
                : 'Size / Section (${sizes.length})',
        icon: Icons.straighten_outlined,
      ),
      items: sizes.map((s) {
        final label = s['label']?.toString() ?? '';
        final display = formatSizeDisplay(_selectedMaterial ?? '', label);
        return DropdownMenuItem<String>(
          value: label,
          child: Text(
            display,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() => _selectedSize = val),
      validator: (val) => val == null || val.isEmpty ? 'Select size' : null,
    );
  }

  Widget _buildWeightInput() {
    final enteredMt = double.tryParse(_weightMTCtrl.text.trim()) ?? 0.0;
    final kgStr = enteredMt > 0 ? '(${(enteredMt * 1000).toStringAsFixed(0)} kg)' : '';

    return TextFormField(
      controller: _weightMTCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,4}')),
      ],
      decoration: _inputDecoration(
        label: 'Weight (MT) $kgStr',
        icon: Icons.scale_outlined,
        hint: 'e.g. 15.250',
      ),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return 'Enter weight';
        final numVal = double.tryParse(val);
        if (numVal == null || numVal <= 0) return 'Invalid MT';
        return null;
      },
    );
  }

  Widget _buildLocationSelector() {
    if (_selectedType == 'TRANSFER') {
      return Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedLocation,
              decoration: _inputDecoration(label: 'From', icon: Icons.outbox_outlined),
              items: const [
                DropdownMenuItem(value: 'YARD', child: Text('YARD', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'FACTORY', child: Text('FACTORY', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedLocation = v;
                    _toLocation = v == 'YARD' ? 'FACTORY' : 'YARD';
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _toLocation,
              decoration: _inputDecoration(label: 'To', icon: Icons.move_to_inbox_outlined),
              items: const [
                DropdownMenuItem(value: 'YARD', child: Text('YARD', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'FACTORY', child: Text('FACTORY', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _toLocation = v);
              },
            ),
          ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedLocation,
      decoration: _inputDecoration(
        label: 'Storage Location',
        icon: Icons.location_on_outlined,
      ),
      items: const [
        DropdownMenuItem(
          value: 'YARD',
          child: Text('YARD (Main Yard)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        DropdownMenuItem(
          value: 'FACTORY',
          child: Text('FACTORY (Mill Unit)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ],
      onChanged: (val) {
        if (val != null) setState(() => _selectedLocation = val);
      },
    );
  }

  Widget _buildVehicleInput() {
    return TextFormField(
      controller: _vehicleNoCtrl,
      textCapitalization: TextCapitalization.characters,
      decoration: _inputDecoration(
        label: 'Vehicle / Lorry No',
        icon: Icons.local_shipping_outlined,
        hint: 'e.g. MH-20-DE-1234',
      ),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildInvoiceInput() {
    return TextFormField(
      controller: _invoiceNoCtrl,
      decoration: _inputDecoration(
        label: 'Invoice / Gate Pass Ref',
        icon: Icons.receipt_long_outlined,
        hint: 'e.g. INV-8492',
      ),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildRemarksInput() {
    return TextFormField(
      controller: _remarksCtrl,
      decoration: _inputDecoration(
        label: 'Remarks / Driver Notes',
        icon: Icons.notes_outlined,
        hint: 'Optional dispatch or weighment notes',
      ),
      style: const TextStyle(
        fontSize: 12.5,
        color: Color(0xFF0F172A),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF64748B),
      ),
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      prefixIcon: Icon(icon, size: 16, color: const Color(0xFF64748B)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
      ),
    );
  }

  // ── SUBMIT BUTTON ──
  Widget _buildSubmitButton(bool isDeficit) {
    final Color btnBg = _selectedType == 'IN'
        ? const Color(0xFF059669)
        : _selectedType == 'OUT'
            ? const Color(0xFF0F172A)
            : const Color(0xFFD97706);

    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitTransaction,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnBg,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedType == 'IN'
                        ? Icons.check_circle_outline_rounded
                        : _selectedType == 'OUT'
                            ? Icons.send_rounded
                            : Icons.sync_alt_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedType == 'IN'
                        ? 'Confirm Inward Stock'
                        : _selectedType == 'OUT'
                            ? (isDeficit ? 'Record Outward (Deficit)' : 'Confirm Dispatch')
                            : 'Confirm Yard Transfer',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
