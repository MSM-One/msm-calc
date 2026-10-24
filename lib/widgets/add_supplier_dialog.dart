import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import 'motion_toast.dart';

/// Professional Enterprise "+ Add Supplier" Modal Dialog.
/// Allows registering vendor credentials, tax details, and linking
/// dynamic material categories and sizes into `vendors` and `vendor_supplied_sizes`.
class AddSupplierDialog extends StatefulWidget {
  final List<String> existingRegions;
  final bool isBottomSheet;

  const AddSupplierDialog({
    super.key,
    this.existingRegions = const [],
    this.isBottomSheet = false,
  });

  static Future<String?> show(
    BuildContext context, {
    List<String> existingRegions = const [],
  }) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (isMobile) {
      return showModalBottomSheet<String?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => FractionallySizedBox(
          heightFactor: 0.92,
          child: AddSupplierDialog(
            existingRegions: existingRegions,
            isBottomSheet: true,
          ),
        ),
      );
    } else {
      return showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AddSupplierDialog(
          existingRegions: existingRegions,
          isBottomSheet: false,
        ),
      );
    }
  }

  @override
  State<AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends State<AddSupplierDialog> {
  static const Color brandRed = Color(0xFFD32F2F);

  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _firmNameCtrl = TextEditingController();
  final TextEditingController _regionCtrl = TextEditingController();
  final TextEditingController _gstinCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _sizeSearchCtrl = TextEditingController();

  String _businessType = 'MANUFACTURER'; // 'MANUFACTURER' or 'TRADER'
  String _sizeSearchQuery = '';
  bool _isSaving = false;
  bool _isLoadingMaterials = true;

  // Materials & Sizes
  List<Map<String, dynamic>> _materials = [];
  int? _selectedMaterialId;
  final Map<int, List<Map<String, dynamic>>> _sizesCacheByMaterial = {};
  bool _isLoadingSizes = false;

  // Selected size IDs mapped per material: material_id -> Set<item_size_id>
  final Map<int, Set<int>> _selectedSizesByMaterial = {};

  @override
  void initState() {
    super.initState();
    _loadMaterials();
    if (widget.existingRegions.isNotEmpty) {
      _regionCtrl.text = widget.existingRegions.first.toUpperCase();
    }
  }

  @override
  void dispose() {
    _firmNameCtrl.dispose();
    _regionCtrl.dispose();
    _gstinCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _sizeSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    try {
      final res = await SupabaseService.client
          .from('materials')
          .select('id, item_name')
          .order('item_name');
      final list = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _materials = list;
          _isLoadingMaterials = false;
          if (_materials.isNotEmpty) {
            _selectedMaterialId = _materials.first['id'] as int?;
          }
        });
        if (_selectedMaterialId != null) {
          _loadSizesForMaterial(_selectedMaterialId!);
        }
      }
    } catch (e) {
      debugPrint("[AddSupplierDialog] Error loading materials: $e");
      if (mounted) setState(() => _isLoadingMaterials = false);
    }
  }

  Future<void> _loadSizesForMaterial(int materialId) async {
    if (_sizesCacheByMaterial.containsKey(materialId)) {
      return;
    }
    setState(() => _isLoadingSizes = true);
    try {
      final res = await SupabaseService.client
          .from('item_sizes')
          .select('id, material_id, size_label, unit_weight_kg, size_difference')
          .eq('material_id', materialId)
          .order('id');
      final list = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _sizesCacheByMaterial[materialId] = list;
          _isLoadingSizes = false;
        });
      }
    } catch (e) {
      debugPrint("[AddSupplierDialog] Error loading sizes: $e");
      if (mounted) setState(() => _isLoadingSizes = false);
    }
  }

  void _onMaterialChanged(int? newMatId) {
    if (newMatId == null) return;
    setState(() {
      _selectedMaterialId = newMatId;
      _sizeSearchCtrl.clear();
      _sizeSearchQuery = '';
    });
    _loadSizesForMaterial(newMatId);
  }

  void _toggleSize(int materialId, int sizeId) {
    setState(() {
      final set = _selectedSizesByMaterial.putIfAbsent(materialId, () => {});
      if (set.contains(sizeId)) {
        set.remove(sizeId);
      } else {
        set.add(sizeId);
      }
    });
  }

  void _selectAllCurrentCategory(List<Map<String, dynamic>> sizes) {
    if (_selectedMaterialId == null) return;
    final matId = _selectedMaterialId!;
    final set = _selectedSizesByMaterial.putIfAbsent(matId, () => {});
    final ids = sizes.map((s) => s['id'] as int).whereType<int>().toSet();
    setState(() {
      set.addAll(ids);
    });
  }

  void _clearAllCurrentCategory() {
    if (_selectedMaterialId == null) return;
    final matId = _selectedMaterialId!;
    setState(() {
      _selectedSizesByMaterial[matId]?.clear();
    });
  }

  int get _totalSelectedSizesCount {
    int count = 0;
    for (var s in _selectedSizesByMaterial.values) {
      count += s.length;
    }
    return count;
  }

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) return;

    final String firmName = _firmNameCtrl.text.trim().toUpperCase();
    final String region = _regionCtrl.text.trim().toUpperCase();
    final String gstin = _gstinCtrl.text.trim().toUpperCase();
    final String phone = _phoneCtrl.text.trim();
    final String email = _emailCtrl.text.trim().toLowerCase();

    setState(() => _isSaving = true);
    try {
      // 1. Insert into public.vendors
      final vendorPayload = {
        'vendor_name': firmName,
        'region': region.isNotEmpty ? region : null,
        'business_type': _businessType,
        'gstin': gstin.isNotEmpty ? gstin : null,
        'phone': phone.isNotEmpty ? phone : null,
        'email': email.isNotEmpty ? email : null,
        'is_active': true,
      };

      final vendorRes = await SupabaseService.client
          .from('vendors')
          .insert(vendorPayload)
          .select('id')
          .single();

      final dynamic vendorId = vendorRes['id'];

      // 2. Insert into public.vendor_supplied_sizes
      final List<Map<String, dynamic>> sizeInserts = [];
      _selectedSizesByMaterial.forEach((matId, sizeIds) {
        for (final sizeId in sizeIds) {
          sizeInserts.add({
            'vendor_id': vendorId,
            'material_id': matId,
            'item_size_id': sizeId,
          });
        }
      });

      if (sizeInserts.isNotEmpty) {
        await SupabaseService.client
            .from('vendor_supplied_sizes')
            .insert(sizeInserts);
      }

      if (mounted) {
        MotionToast.show(context, "Supplier added successfully");
        Navigator.of(context).pop(firmName);
      }
    } catch (e) {
      debugPrint("[AddSupplierDialog] Save Error: $e");
      if (mounted) {
        MotionToast.show(context, "Error saving supplier: $e", isError: true);
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final currentSizes = _selectedMaterialId != null
        ? (_sizesCacheByMaterial[_selectedMaterialId!] ?? [])
        : <Map<String, dynamic>>[];
    final currentSelectedSet = _selectedMaterialId != null
        ? (_selectedSizesByMaterial[_selectedMaterialId!] ?? <int>{})
        : <int>{};
    final visibleSizes = _sizeSearchQuery.isEmpty
        ? currentSizes
        : currentSizes.where((s) {
            final label = s['size_label']?.toString().toLowerCase() ?? '';
            return label.contains(_sizeSearchQuery.toLowerCase());
          }).toList();

    final dialogContent = ClipRRect(
      borderRadius: widget.isBottomSheet
          ? const BorderRadius.vertical(top: Radius.circular(20))
          : BorderRadius.circular(20),
      child: Scaffold(
            backgroundColor: cardColor,
            appBar: AppBar(
              backgroundColor: cardColor,
              elevation: 0,
              centerTitle: false,
              automaticallyImplyLeading: false,
              titleSpacing: 20,
              shape: Border(bottom: BorderSide(color: borderColor)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: brandRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_outlined,
                      color: brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Add Supplier",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          "Register vendor credentials & material supply portfolio",
                          style: TextStyle(fontSize: 11.5, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textMuted),
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  splashRadius: 20,
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── SECTION 1: BASIC COMPANY DETAILS ─────────────────────
                    _buildSectionHeader(
                      title: "1. Basic Company Details",
                      icon: Icons.business_rounded,
                      color: brandRed,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Vendor Firm Name
                    TextFormField(
                      controller: _firmNameCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                      decoration: _fieldDeco(
                        label: "Supplier / Vendor Firm Name *",
                        hint: "e.g. SHRUTI STEEL TRADERS",
                        prefixIcon: Icons.storefront_rounded,
                        isDark: isDark,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return "Vendor firm name is required";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Region & Business Type Row
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 480;

                        // Region Autocomplete
                        final regionField = RawAutocomplete<String>(
                          textEditingController: _regionCtrl,
                          focusNode: FocusNode(),
                          optionsBuilder: (TextEditingValue val) {
                            final q = val.text.trim().toUpperCase();
                            if (q.isEmpty) return widget.existingRegions;
                            return widget.existingRegions.where(
                                (r) => r.toUpperCase().contains(q));
                          },
                          onSelected: (String s) {
                            _regionCtrl.text = s.trim().toUpperCase();
                          },
                          fieldViewBuilder: (ctx, ctrl, fn, onSubmitted) {
                            return TextFormField(
                              controller: ctrl,
                              focusNode: fn,
                              textCapitalization: TextCapitalization.characters,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                              decoration: _fieldDeco(
                                label: "Region / Operating Hub *",
                                hint: "e.g. NAGPUR, RAIPUR",
                                prefixIcon: Icons.map_outlined,
                                isDark: isDark,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? "Region is required"
                                  : null,
                            );
                          },
                          optionsViewBuilder: (ctx, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(10),
                                color: cardColor,
                                child: Container(
                                  constraints:
                                      const BoxConstraints(maxHeight: 180),
                                  width: 260,
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (c, idx) {
                                      final opt = options.elementAt(idx);
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          opt,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: textPrimary,
                                          ),
                                        ),
                                        onTap: () => onSelected(opt),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        );

                        // Business Type Segmented Toggle
                        final businessTypeToggle = Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              _buildTypeSegment(
                                label: "Manufacturer",
                                isSelected: _businessType == 'MANUFACTURER',
                                isDark: isDark,
                                onTap: () => setState(
                                    () => _businessType = 'MANUFACTURER'),
                              ),
                              _buildTypeSegment(
                                label: "Trader",
                                isSelected: _businessType == 'TRADER',
                                isDark: isDark,
                                onTap: () =>
                                    setState(() => _businessType = 'TRADER'),
                              ),
                            ],
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              regionField,
                              const SizedBox(height: 12),
                              businessTypeToggle,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: regionField),
                            const SizedBox(width: 12),
                            Expanded(child: businessTypeToggle),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Contact & Tax Details
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 540;

                        final gstinInput = TextFormField(
                          controller: _gstinCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(15),
                          ],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          decoration: _fieldDeco(
                            label: "GSTIN No.",
                            hint: "15-digit e.g. 27AAAAA0000A1Z5",
                            prefixIcon: Icons.receipt_long_outlined,
                            isDark: isDark,
                          ),
                        );

                        final phoneInput = TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          decoration: _fieldDeco(
                            label: "Mobile No. *",
                            hint: "10-digit phone number",
                            prefixIcon: Icons.phone_outlined,
                            isDark: isDark,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return "Mobile No. is required";
                            }
                            if (val.trim().length != 10) {
                              return "Enter a valid 10-digit number";
                            }
                            return null;
                          },
                        );

                        final emailInput = TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          decoration: _fieldDeco(
                            label: "Email ID (Optional)",
                            hint: "e.g. sales@vendor.com",
                            prefixIcon: Icons.alternate_email_rounded,
                            isDark: isDark,
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              phoneInput,
                              const SizedBox(height: 12),
                              gstinInput,
                              const SizedBox(height: 12),
                              emailInput,
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: phoneInput),
                                const SizedBox(width: 12),
                                Expanded(child: gstinInput),
                              ],
                            ),
                            const SizedBox(height: 12),
                            emailInput,
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── SECTION 2: MATERIAL & SIZE PORTFOLIO ──────────────────
                    _buildSectionHeader(
                      title: "2. Material & Size Portfolio",
                      icon: Icons.category_outlined,
                      color: const Color(0xFF0284C7),
                      isDark: isDark,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "$_totalSelectedSizesCount sizes selected",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Material Category Selection
                    if (_isLoadingMaterials)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_materials.isEmpty)
                      Text(
                        "No material categories found.",
                        style: TextStyle(fontSize: 12, color: textMuted),
                      )
                    else ...[
                      // A. Header Toolbar: Category Dropdown
                      DropdownButtonFormField<int>(
                        initialValue: _selectedMaterialId,
                        decoration: _fieldDeco(
                          label: "Material Category",
                          hint: "Select material category",
                          prefixIcon: Icons.layers_outlined,
                          isDark: isDark,
                        ),
                        items: _materials.map((m) {
                          final int matId = m['id'] as int;
                          final String name = m['item_name']?.toString() ?? "";
                          final int count =
                              _selectedSizesByMaterial[matId]?.length ?? 0;
                          return DropdownMenuItem<int>(
                            value: matId,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                if (count > 0)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "$count sizes",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: _onMaterialChanged,
                      ),
                      const SizedBox(height: 10),

                      // Quick Search Field, Selection Controls & Counter Badge Toolbar
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 500;
                          final searchField = SizedBox(
                            height: 36,
                            child: TextField(
                              controller: _sizeSearchCtrl,
                              onChanged: (v) =>
                                  setState(() => _sizeSearchQuery = v.trim()),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: "Search size...",
                                hintStyle:
                                    TextStyle(fontSize: 12, color: textMuted),
                                prefixIcon: const Icon(Icons.search_rounded,
                                    size: 18, color: Color(0xFF64748B)),
                                suffixIcon: _sizeSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded,
                                            size: 16, color: Color(0xFF94A3B8)),
                                        splashRadius: 14,
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          _sizeSearchCtrl.clear();
                                          setState(() => _sizeSearchQuery = '');
                                        },
                                      )
                                    : null,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: brandRed, width: 1.5),
                                ),
                              ),
                            ),
                          );

                          final controls = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: brandRed,
                                ),
                                onPressed: visibleSizes.isEmpty
                                    ? null
                                    : () => _selectAllCurrentCategory(
                                        visibleSizes),
                                child: const Text(
                                  "Select All",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const Text("·",
                                  style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.bold)),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: const Color(0xFF64748B),
                                ),
                                onPressed: currentSelectedSet.isEmpty
                                    ? null
                                    : _clearAllCurrentCategory,
                                child: const Text(
                                  "Clear All",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: currentSelectedSet.isNotEmpty
                                      ? brandRed.withValues(alpha: 0.1)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: currentSelectedSet.isNotEmpty
                                        ? brandRed.withValues(alpha: 0.3)
                                        : borderColor,
                                  ),
                                ),
                                child: Text(
                                  "${currentSelectedSet.length} of ${currentSizes.length} selected",
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: currentSelectedSet.isNotEmpty
                                        ? brandRed
                                        : textMuted,
                                  ),
                                ),
                              ),
                            ],
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchField,
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [controls],
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: searchField),
                              const SizedBox(width: 8),
                              controls,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),

                      // B. Structured Size Selection Container (height: 280px, ListView.separated)
                      Container(
                        height: 280,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: _isLoadingSizes
                            ? const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : currentSizes.isEmpty
                                ? Center(
                                    child: Text(
                                      "No registered sizes for this material.",
                                      style: TextStyle(
                                          fontSize: 12, color: textMuted),
                                    ),
                                  )
                                : visibleSizes.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.search_off_rounded,
                                                size: 28, color: textMuted),
                                            const SizedBox(height: 6),
                                            Text(
                                              'No sizes matching "$_sizeSearchQuery"',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: textMuted),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Scrollbar(
                                        thumbVisibility: true,
                                        child: ListView.separated(
                                          padding: EdgeInsets.zero,
                                          itemCount: visibleSizes.length,
                                          separatorBuilder: (context, idx) =>
                                              Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: isDark
                                                ? const Color(0xFF1E293B)
                                                : const Color(0xFFF1F5F9),
                                          ),
                                          itemBuilder: (context, idx) {
                                            final s = visibleSizes[idx];
                                            final int sizeId = s['id'] as int;
                                            final String label = (s['size_label'] ??
                                                    s['label'] ??
                                                    s['size'] ??
                                                    '')
                                                .toString();
                                            final double weight = (s['unit_weight_kg']
                                                        as num?)
                                                    ?.toDouble() ??
                                                double.tryParse(s['unit_weight_kg']
                                                        ?.toString() ??
                                                    '') ??
                                                (s['weight'] as num?)
                                                    ?.toDouble() ??
                                                double.tryParse(s['weight']
                                                        ?.toString() ??
                                                    '') ??
                                                0.0;
                                            final num sd = (s['size_difference']
                                                    as num?) ??
                                                num.tryParse(s['size_difference']
                                                        ?.toString() ??
                                                    '') ??
                                                (s['sd'] as num?) ??
                                                0;
                                            final bool isSelected =
                                                currentSelectedSet
                                                    .contains(sizeId);

                                            return Material(
                                              color: isSelected
                                                  ? (isDark
                                                      ? brandRed.withValues(
                                                          alpha: 0.12)
                                                      : const Color(0xFFFEF2F2))
                                                  : Colors.transparent,
                                              child: InkWell(
                                                onTap: () {
                                                  if (_selectedMaterialId !=
                                                      null) {
                                                    _toggleSize(
                                                        _selectedMaterialId!,
                                                        sizeId);
                                                  }
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 9),
                                                  child: Row(
                                                    children: [
                                                      // Leading: Checkbox
                                                      SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: Checkbox(
                                                          value: isSelected,
                                                          activeColor: brandRed,
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(4),
                                                          ),
                                                          onChanged: (_) {
                                                            if (_selectedMaterialId !=
                                                                null) {
                                                              _toggleSize(
                                                                  _selectedMaterialId!,
                                                                  sizeId);
                                                            }
                                                          },
                                                          materialTapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      // Title & Badges
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              label,
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                                color: isSelected
                                                                    ? brandRed
                                                                    : textPrimary,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                            const SizedBox(
                                                                height: 3),
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  sd != 0
                                                                      ? (sd > 0
                                                                          ? "SD: +$sd"
                                                                          : "SD: $sd")
                                                                      : "SD: 0",
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: isDark
                                                                        ? const Color(
                                                                            0xFF94A3B8)
                                                                        : const Color(
                                                                            0xFF64748B),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Text("•",
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: isDark
                                                                          ? const Color(
                                                                              0xFF475569)
                                                                          : const Color(
                                                                              0xFFCBD5E1),
                                                                    )),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Container(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                          horizontal:
                                                                              6,
                                                                          vertical:
                                                                              1.5),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: isDark
                                                                        ? brandRed
                                                                            .withValues(alpha: 0.18)
                                                                        : const Color(
                                                                            0xFFFEF2F2),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                                4),
                                                                    border:
                                                                        Border
                                                                            .all(
                                                                      color: isDark
                                                                          ? brandRed
                                                                              .withValues(alpha: 0.35)
                                                                          : const Color(
                                                                              0xFFFECACA),
                                                                      width:
                                                                          0.6,
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    weight > 0
                                                                        ? "Weight: ${weight.toStringAsFixed(1)} kg"
                                                                        : "Weight: —",
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: isDark
                                                                          ? const Color(
                                                                              0xFFFCA5A5)
                                                                          : const Color(
                                                                              0xFFDC2626),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      // Trailing: Selection indicator or arrow
                                                      Icon(
                                                        isSelected
                                                            ? Icons
                                                                .check_circle_rounded
                                                            : Icons
                                                                .chevron_right_rounded,
                                                        size: 18,
                                                        color: isSelected
                                                            ? brandRed
                                                            : const Color(
                                                                0xFF94A3B8),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                      ),

                      // C. Selected Summary Bar (Below the grid)
                      if (currentSelectedSet.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Selected (${currentSelectedSet.length}):",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 28,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: currentSizes
                                      .where((s) => currentSelectedSet
                                          .contains(s['id'] as int))
                                      .map((s) {
                                    final int id = s['id'] as int;
                                    final String label =
                                        s['size_label']?.toString() ?? '';
                                    return Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.only(
                                          left: 8,
                                          right: 4,
                                          top: 2,
                                          bottom: 2),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? brandRed.withValues(alpha: 0.15)
                                            : const Color(0xFFFEF2F2),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isDark
                                              ? brandRed.withValues(alpha: 0.4)
                                              : const Color(0xFFFECACA),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? const Color(0xFFFCA5A5)
                                                  : brandRed,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () => _toggleSize(
                                                _selectedMaterialId!, id),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Padding(
                                              padding: const EdgeInsets.all(2),
                                              child: Icon(
                                                Icons.close_rounded,
                                                size: 13,
                                                color: isDark
                                                    ? const Color(0xFFFCA5A5)
                                                    : brandRed,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),

                    // ── ACTION BUTTONS ─────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              _isSaving ? null : () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: textMuted,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveSupplier,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline_rounded,
                                  size: 18),
                          label: Text(
                            _isSaving ? "Saving..." : "Save Supplier",
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    if (widget.isBottomSheet) {
      return Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: dialogContent,
      );
    }

    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: dialogContent,
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildTypeSegment({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? brandRed : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: brandRed.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF475569)),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco({
    required String label,
    String? hint,
    IconData? prefixIcon,
    required bool isDark,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
      isDense: true,
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : const Color(0xFFF8FAFC),
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      ),
      hintStyle: TextStyle(
        fontSize: 12,
        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
      ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}
