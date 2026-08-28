// Master Size Management Screen
// Accessible only to Admin roles.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:msm_calc/services/data_repository.dart';
import 'package:msm_calc/widgets/motion_toast.dart';
import 'package:msm_calc/services/sheet_service.dart';
import 'package:msm_calc/services/supabase_service.dart';
import 'package:msm_calc/models/stock_role.dart';
import 'package:msm_calc/services/access_guard.dart';
import 'package:msm_calc/models/permission_model.dart';
import 'package:msm_calc/constants/app_colors.dart';

/// Tracks whether the form is in edit or create mode.
enum FormMode { edit, create }

class MasterSizeManagementScreen extends StatefulWidget {
  const MasterSizeManagementScreen({Key? key}) : super(key: key);

  @override
  State<MasterSizeManagementScreen> createState() =>
      _MasterSizeManagementScreenState();
}

class _MasterSizeManagementScreenState
    extends State<MasterSizeManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sizeLabelCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _differenceCtrl = TextEditingController();
  FormMode _formMode = FormMode.edit;

  String? _selectedItem;
  List<String> _itemOptions = [];

  // Mapping of category name to list of size detail maps: [{'label': '...', 'sd': ..., 'weight': '...'}]
  Map<String, List<Map<String, dynamic>>> _categorySizes = {};
  List<Map<String, dynamic>> _filteredSizes = [];
  Map<String, dynamic>? _selectedSizeDetail;
  // _formMode now replaces the old _isNewSize boolean.

  bool _isLoading = false;
  String? _statusMessage;
  bool _statusIsSuccess = false;

  @override
  void initState() {
    super.initState();
    // Load item categories and their sizes for dropdown.
    _loadItemCategories();
    DataRepository.sheetDataNotifier.addListener(_loadItemCategories);
  }

  @override
  void dispose() {
    DataRepository.sheetDataNotifier.removeListener(_loadItemCategories);
    super.dispose();
  }

  Future<void> _loadItemCategories() async {
    try {
      final result = DataRepository.sheetDataNotifier.value;
      final itemsList = result['items'] as List<dynamic>? ?? [];

      final Map<String, List<Map<String, dynamic>>> tempCategorySizes = {};
      final List<String> items = [];

      for (var e in itemsList) {
        if (e is Map) {
          final String catName = (e['name'] ?? '').toString();
          if (catName.isNotEmpty) {
            items.add(catName);
            final List<dynamic> sizesRaw = e['sizes'] as List<dynamic>? ?? [];
            tempCategorySizes[catName] = sizesRaw.map((s) {
              if (s is Map) {
                return Map<String, dynamic>.from(s);
              }
              return <String, dynamic>{};
            }).toList();
          }
        }
      }

      // Desired order matching Netrate Calc screen
      const List<String> preferredOrder = [
        'MS Pipe',
        'MS Angle',
        'MS Channel',
        'SQR BAR',
        'Flats',
        'Round Bar',
      ];

      items.sort((a, b) {
        int ai = preferredOrder.indexOf(a);
        int bi = preferredOrder.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

      setState(() {
        _itemOptions = items;
        _categorySizes = tempCategorySizes;
        _updateFilteredSizes();
      });
    } catch (e) {
      // ignore errors; fallback empty list.
    }
  }

  void _updateFilteredSizes() {
    if (_selectedItem != null && _categorySizes.containsKey(_selectedItem)) {
      _filteredSizes = _categorySizes[_selectedItem]!;
    } else {
      _filteredSizes = [];
    }
  }

  void _onCategoryChanged(String? val) {
    setState(() {
      _selectedItem = val;
      _updateFilteredSizes();
      _resetSizeFields();
    });
  }

  void _resetSizeFields() {
    _sizeLabelCtrl.clear();
    _weightCtrl.clear();
    _differenceCtrl.clear();
    _selectedSizeDetail = null;
    _formMode = FormMode.edit;
  }

  void _onSizeSelected(Map<String, dynamic> sizeDetail) {
    setState(() {
      _selectedSizeDetail = sizeDetail;
      _sizeLabelCtrl.text = (sizeDetail['label'] ?? '').toString();
      _weightCtrl.text = (sizeDetail['weight'] ?? '').toString();
      _differenceCtrl.text = (sizeDetail['sd'] ?? '').toString();
      _formMode = FormMode.edit;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String sizeLabel = _sizeLabelCtrl.text.trim();
    final String weightText = _weightCtrl.text.trim();
    final String diffText = _differenceCtrl.text.trim();
    if (sizeLabel.isEmpty || weightText.isEmpty || diffText.isEmpty) {
      setState(() {
        _statusIsSuccess = false;
        _statusMessage =
            'Size Label, Standard Weight and Size Difference fields cannot be empty.';
      });
      return;
    }

    if (_selectedItem == null || _selectedItem!.isEmpty) {
      setState(() {
        _statusIsSuccess = false;
        _statusMessage = 'Please select a product category first.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final String item = _selectedItem!;

    try {
      final double weightVal = double.tryParse(weightText) ?? 0.0;
      final double diffVal = double.tryParse(diffText) ?? 0.0;

      // Step A: Resolve the material ID for the active item category
      final matRow = await SupabaseService.client
          .from('materials')
          .select('id')
          .eq('item_name', item)
          .maybeSingle();
      final int? materialId = matRow?['id'] as int?;

      if (materialId == null) {
        throw Exception('Failed to resolve material category: $item');
      }

      if (_formMode == FormMode.edit) {
        if (_selectedSizeDetail == null) {
          throw Exception('No selected size details found to update.');
        }
        final dynamic sizeId = _selectedSizeDetail!['id'];
        if (sizeId == null) {
          throw Exception('Size primary key ID is missing.');
        }

        // 1. EDIT/UPDATE MODE: ONLY update the 'item_sizes' table.
        await SupabaseService.client.from('item_sizes').update({
          'size_label': sizeLabel,
          'unit_weight_kg': weightVal,
          'size_difference': diffVal,
        }).eq('id', sizeId);
      } else {
        // 2. CREATE MODE: Insert the fresh size under the resolved material id
        await SupabaseService.client.from('item_sizes').insert({
          'material_id': materialId,
          'size_label': sizeLabel,
          'unit_weight_kg': weightVal,
          'size_difference': diffVal,
        });
      }

      // Refresh data models and dropdown list cache
      if (mounted) {
        await DataRepository.syncSheetData(context, force: true);
      }
      await _loadItemCategories();

      setState(() {
        _isLoading = false;
        _statusIsSuccess = true;
        _statusMessage = 'Saved successfully';

        // safely switch back selection in state if it exists in options
        if (_itemOptions.contains(item)) {
          _selectedItem = item;
          _updateFilteredSizes();

          // Match and select the updated size if it exists in the filtered sizes
          final updatedSize = _filteredSizes.firstWhere(
            (s) => (s['label'] ?? '').toString().trim() == sizeLabel,
            orElse: () => <String, dynamic>{},
          );
          if (updatedSize.isNotEmpty) {
            _selectedSizeDetail = updatedSize;
            _formMode = FormMode.edit;
          } else {
            _resetSizeFields();
          }
        } else {
          _selectedItem = _itemOptions.isNotEmpty ? _itemOptions.first : null;
          _updateFilteredSizes();
          _resetSizeFields();
        }
      });

      // Show a clean success snackbar.
      if (mounted) {
        MotionToast.show(context, 'Size saved successfully');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusIsSuccess = false;
        _statusMessage = 'Unexpected error: $e';
      });
    }
  }

  Future<void> _delete() async {
    final String item = _selectedItem ?? '';
    final String sizeLabel = _sizeLabelCtrl.text.trim();
    if (item.isEmpty || sizeLabel.isEmpty) return;

    // Show warning confirmation dialog before delete
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text(
            'Warning: Deleting "$sizeLabel" might affect historical transaction records. Are you sure you want to proceed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final matRow = await SupabaseService.client
          .from('materials')
          .select('id')
          .eq('item_name', item)
          .maybeSingle();
      final int? materialId = matRow?['id'] as int?;

      if (materialId == null) {
        throw Exception('Failed to resolve material category for deletion.');
      }

      await SupabaseService.client
          .from('item_sizes')
          .delete()
          .eq('material_id', materialId)
          .eq('size_label', sizeLabel);

      setState(() {
        _isLoading = false;
        _statusIsSuccess = true;
        _statusMessage = "Deleted successfully";
      });

      _selectedItem = null;
      _resetSizeFields();
      if (mounted) {
        await DataRepository.syncSheetData(context, force: true);
      }
      await _loadItemCategories();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusIsSuccess = false;
        _statusMessage = 'Delete failed: $e';
      });
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('foreign key') ||
            errorStr.contains('violates foreign key constraint') ||
            errorStr.contains('foreignkey')) {
          MotionToast.show(context,
              'Cannot delete this size as it contains active transaction history.',
              isError: true);
        } else {
          MotionToast.show(context, 'Error: $e', isError: true);
        }
      }
    }
  }

  Future<void> _confirmDeleteMaterial(BuildContext context) async {
    final String? item = _selectedItem;
    if (item == null || item.isEmpty) return;

    // Show warning confirmation dialog before delete
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete Category'),
        content: Text(
            'Warning: Deleting the category "$item" will remove all associated sizes. Are you sure you want to proceed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final matRow = await SupabaseService.client
          .from('materials')
          .select('id')
          .eq('item_name', item)
          .maybeSingle();
      final int? materialId = matRow?['id'] as int?;

      if (materialId == null) {
        throw Exception('Failed to resolve material category for deletion.');
      }

      // Delete the material row (foreign keys on cascade will delete item_sizes automatically if defined,
      // otherwise this will handle materials deletion)
      await SupabaseService.client
          .from('materials')
          .delete()
          .eq('id', materialId);

      setState(() {
        _isLoading = false;
        _statusIsSuccess = true;
        _statusMessage = "Category deleted successfully";
        _selectedItem = null;
        _resetSizeFields();
      });

      if (context.mounted) {
        await DataRepository.syncSheetData(context, force: true);
      }
      await _loadItemCategories();

      if (context.mounted) {
        MotionToast.show(context, 'Category "$item" deleted successfully');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusIsSuccess = false;
        _statusMessage = 'Delete category failed: $e';
      });
      if (context.mounted) {
        MotionToast.show(context, 'Error: $e', isError: true);
      }
    }
  }

  void _showAddMaterialDialog(BuildContext context) {
    final newMaterialCtrl = TextEditingController();
    final dialogFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.category_outlined, color: msmRed),
            const SizedBox(width: 10),
            const Text(
              'Add New Material',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: dialogFormKey,
          child: TextFormField(
            controller: newMaterialCtrl,
            decoration: InputDecoration(
              labelText: 'Material / Category Name',
              hintText: 'e.g., MS Flat, Channel',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a material name' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final String materialName = newMaterialCtrl.text.trim();

              if (materialName.isEmpty) {
                debugPrint("Discarding save: Material name field is empty.");
                return;
              }

              try {
                // Explicit standalone insert into materials table
                await SupabaseService.client.from('materials').insert({
                  'item_name': materialName,
                });

                // Clean pop and view reload sequence
                if (context.mounted) {
                  Navigator.of(context).pop();
                }

                // Force reload active drop-down state instantly
                if (context.mounted) {
                  await DataRepository.syncSheetData(context, force: true);
                }

                if (mounted) {
                  setState(() {
                    _selectedItem = materialName;
                    _loadItemCategories();
                    _resetSizeFields();
                    _formMode = FormMode.create;
                  });

                  if (context.mounted) {
                    MotionToast.show(context,
                        'Category "$materialName" created successfully');
                  }
                }
              } catch (error) {
                debugPrint("Supabase direct insert exception: $error");
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: msmRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guard: Check Master Size permission.
    if (AccessGuard.cannot(Permissions.screensMasterSize)) {
      return const Scaffold(
        body: Center(
            child: Text('Access Denied: Master Size Permission Required')),
      );
    }

    return Scaffold(
      backgroundColor: msmBg,
      appBar: AppBar(
        title: const Text(
          'Master Size Management',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: msmRed,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Colors.white),
            tooltip: 'Add New Material',
            onPressed: () => _showAddMaterialDialog(context),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              color: cardBg,
              elevation: 4,
              shadowColor: kPremiumShadow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: borderLight, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header info
                      Row(
                        children: [
                          Icon(Icons.settings_suggest, color: msmRed, size: 28),
                          const SizedBox(width: 12),
                          const Text(
                            'Size Details',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Configure item category sizes and standard weight parameters.',
                        style: TextStyle(fontSize: 13, color: textGrey),
                      ),
                      const Divider(
                          height: 32, thickness: 1, color: borderLight),

                      // Status Alert Banner
                      if (_statusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _statusIsSuccess
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _statusIsSuccess
                                  ? const Color(0xFFC8E6C9)
                                  : const Color(0xFFFFCDD2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusIsSuccess
                                    ? Icons.check_circle
                                    : Icons.error_outline,
                                color: _statusIsSuccess
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: TextStyle(
                                    color: _statusIsSuccess
                                        ? Colors.green[900]
                                        : Colors.red[900],
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Category Section
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Item Category',
                                prefixIcon: const Icon(Icons.category_outlined,
                                    color: textGrey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              value: (_selectedItem != null &&
                                      _itemOptions.contains(_selectedItem))
                                  ? _selectedItem
                                  : null,
                              items: _itemOptions
                                  .map((e) => DropdownMenuItem(
                                      value: e, child: Text(e)))
                                  .toList(),
                              onChanged: _onCategoryChanged,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Select an item'
                                  : null,
                            ),
                          ),
                          if (_selectedItem != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              tooltip: 'Delete This Material Category',
                              onPressed: () => _confirmDeleteMaterial(context),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Size Label Selector / Search / Text Field
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  Autocomplete<Map<String, dynamic>>(
                                displayStringForOption: (option) =>
                                    (option['label'] ?? '').toString(),
                                optionsBuilder:
                                    (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return _filteredSizes;
                                  }
                                  return _filteredSizes
                                      .where((Map<String, dynamic> option) {
                                    final label = (option['label'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                    return label.contains(
                                        textEditingValue.text.toLowerCase());
                                  });
                                },
                                onSelected: _onSizeSelected,
                                fieldViewBuilder: (context, controller,
                                    focusNode, onFieldSubmitted) {
                                  // Keep form text controller in sync if needed, or set initial value
                                  if (controller.text != _sizeLabelCtrl.text) {
                                    controller.text = _sizeLabelCtrl.text;
                                  }
                                  controller.addListener(() {
                                    if (_sizeLabelCtrl.text !=
                                        controller.text) {
                                      _sizeLabelCtrl.text = controller.text;
                                      // If the user manually edits away from the selected value, treat as new
                                      final matched = _filteredSizes.any((s) =>
                                          (s['label'] ?? '')
                                              .toString()
                                              .trim() ==
                                          controller.text.trim());
                                      if (!matched &&
                                          _formMode != FormMode.create) {
                                        setState(() {
                                          _formMode = FormMode.create;
                                          _selectedSizeDetail = null;
                                        });
                                      }
                                    }
                                  });
                                  return TextFormField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      labelText: 'Size Label',
                                      hintText:
                                          'Search or type size label (e.g. 25x3)',
                                      prefixIcon: const Icon(Icons.search,
                                          color: textGrey),
                                      suffixIcon: controller.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear,
                                                  size: 18, color: textGrey),
                                              onPressed: () {
                                                controller.clear();
                                                _resetSizeFields();
                                              },
                                            )
                                          : null,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Enter or select a size label'
                                        : null,
                                  );
                                },
                                optionsViewBuilder:
                                    (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4.0,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(10)),
                                      ),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: 200,
                                          // Subtract the button size padding to align with the selector field width
                                          maxWidth: constraints.maxWidth,
                                        ),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (BuildContext context,
                                              int index) {
                                            final Map<String, dynamic> option =
                                                options.elementAt(index);
                                            return ListTile(
                                              dense: true,
                                              title: Text(
                                                (option['label'] ?? '')
                                                    .toString(),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w500),
                                              ),
                                              subtitle: Text(
                                                  'SD: ${option['sd'] ?? 0.0}'),
                                              onTap: () => onSelected(option),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _sizeLabelCtrl.clear();
                                  _weightCtrl.clear();
                                  _differenceCtrl.clear();
                                  _selectedSizeDetail = null;
                                  _formMode = FormMode.create;
                                });
                              },
                              icon:
                                  const Icon(Icons.add_box_outlined, size: 18),
                              label: const Text('+ New Size'),
                              style: TextButton.styleFrom(
                                foregroundColor: msmRed,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Standard Weight (kg)
                      TextFormField(
                        controller: _weightCtrl,
                        decoration: InputDecoration(
                          labelText: 'Standard Weight (kg)',
                          hintText: 'Unit weight in kg (e.g., 1.5)',
                          prefixIcon:
                              const Icon(Icons.fitness_center, color: textGrey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^[0-9]*\.?[0-9]*')),
                        ],
                        validator: (v) => v == null ||
                                v.trim().isEmpty ||
                                double.tryParse(v) == null
                            ? 'Enter a numeric value'
                            : null,
                      ),
                      const SizedBox(height: 18),

                      // Size Difference (₹)
                      TextFormField(
                        controller: _differenceCtrl,
                        decoration: InputDecoration(
                          labelText: 'Size Difference (₹)',
                          hintText: 'Size difference in ₹ (e.g., 0.0)',
                          prefixIcon:
                              const Icon(Icons.currency_rupee, color: textGrey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^[0-9]*\.?[0-9]*')),
                        ],
                        validator: (v) => v == null ||
                                v.trim().isEmpty ||
                                double.tryParse(v) == null
                            ? 'Enter a numeric value'
                            : null,
                      ),

                      const SizedBox(height: 24),

                      // Action Buttons
                      if (_isLoading)
                        const Center(
                          child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(msmRed)),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _submit,
                                icon: Icon(
                                  _formMode == FormMode.create
                                      ? Icons.add_circle_outline
                                      : Icons.save_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                label: Text(
                                  _formMode == FormMode.create
                                      ? 'Save New Size'
                                      : 'Update Size Details',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: msmRed,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: OutlinedButton.icon(
                                onPressed: _delete,
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 18),
                                label: const Text(
                                  'Delete',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
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
          ),
        ),
      ),
    );
  }
}
