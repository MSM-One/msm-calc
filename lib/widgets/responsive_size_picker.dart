import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../services/data_repository.dart';
import '../utils/steel_helper.dart';
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';

class ResponsiveSizePicker extends StatefulWidget {
  final String itemType;
  final dynamic materialId;
  final List<Map<String, dynamic>>? customSizes;
  final Function(Map<String, dynamic> size) onSizeSelected;
  final Widget? Function(Map<String, dynamic> size)? trailingBuilder;

  const ResponsiveSizePicker({
    super.key,
    required this.itemType,
    required this.onSizeSelected,
    this.materialId,
    this.customSizes,
    this.trailingBuilder,
  });

  @override
  State<ResponsiveSizePicker> createState() => _ResponsiveSizePickerState();

  /// Static helper to show the picker responsively.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String itemType,
    dynamic materialId,
    List<Map<String, dynamic>>? customSizes,
    Widget? Function(Map<String, dynamic> size)? trailingBuilder,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ResponsiveSizePicker(
          itemType: itemType,
          materialId: materialId,
          customSizes: customSizes,
          onSizeSelected: (size) => Navigator.pop(context, size),
          trailingBuilder: trailingBuilder,
        ),
      );
    } else {
      return showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: ResponsiveSizePicker(
              itemType: itemType,
              materialId: materialId,
              customSizes: customSizes,
              onSizeSelected: (size) => Navigator.pop(context, size),
              trailingBuilder: trailingBuilder,
            ),
          ),
        ),
      );
    }
  }
}

class _ResponsiveSizePickerState extends State<ResponsiveSizePicker> {
  String _query = "";
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allSizes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Map<String, dynamic>> rawSizes = [];
      if (widget.customSizes != null) {
        rawSizes = widget.customSizes!;
      } else {
        final allSizes = DataRepository.instance.itemSizes;
        final selectedMaterialName = widget.itemType;
        final selectedMaterialId = widget.materialId ??
            DataRepository.getMaterialIdByName(selectedMaterialName);

        final matchingSizes = allSizes.where((s) {
          final sMatId = s['material_id'] ?? s['materialId'];
          final sMatName =
              (s['material_name'] ?? s['materialName'])?.toString();
          final matchId = (selectedMaterialId != null &&
              sMatId != null &&
              sMatId.toString() == selectedMaterialId.toString());
          final matchName = (selectedMaterialName.trim().isNotEmpty &&
              sMatName != null &&
              sMatName.trim().toLowerCase() ==
                  selectedMaterialName.trim().toLowerCase());
          return matchId || matchName;
        }).toList();

        if (matchingSizes.isNotEmpty) {
          rawSizes = matchingSizes;
        } else {
          final provider = context.read<InventoryProvider>();

          // Ensure data is loaded
          if (provider.saudaSizesMap.isEmpty) {
            await provider.loadSaudaData(force: false);
          }

          // Case-insensitive lookup using the uppercase key
          final key = widget.itemType.toUpperCase();
          rawSizes = provider.saudaSizesMap[key] ?? [];
        }
      }

      if (kDebugMode) {
        debugPrint("--------------------------------------------------");
        debugPrint("DEBUG: [ResponsiveSizePicker] Item: ${widget.itemType}");
        debugPrint(
            "DEBUG: [ResponsiveSizePicker] Final Display Count: ${rawSizes.length}");
        debugPrint("--------------------------------------------------");
      }

      if (mounted) {
        final sortedSizes = List<Map<String, dynamic>>.from(rawSizes);
        sortedSizes.sort((a, b) => SortingUtils.compareSizes(
            a['label']?.toString() ?? '', b['label']?.toString() ?? ''));
        setState(() {
          _allSizes = sortedSizes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load sizes. Please check your connection.";
        });
      }
      debugPrint("ERROR: [ResponsiveSizePicker] $e");
    }
  }

  List<Map<String, dynamic>> get _filteredSizes {
    if (_query.isEmpty) return _allSizes;
    final q = _query.toLowerCase().trim();
    return _allSizes.where((s) {
      final label = s['label']?.toString().toLowerCase() ?? '';
      return label.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: _buildContent(scrollController),
          );
        },
      );
    } else {
      return Material(color: Colors.white, child: _buildContent(null));
    }
  }

  Widget _buildContent(ScrollController? scrollController) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.red))
              : _error != null
                  ? _buildErrorState()
                  : _filteredSizes.isEmpty
                      ? _buildEmptyState()
                      : _buildList(scrollController),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.itemType,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Consumer<InventoryProvider>(
                      builder: (context, provider, _) => Text(
                        provider.isBackgroundSyncing
                            ? "Syncing with Google Sheet..."
                            : "${_allSizes.length} sizes available",
                        style: TextStyle(
                          fontSize: 12,
                          color: provider.isBackgroundSyncing
                              ? Colors.red
                              : Colors.grey[600],
                          fontWeight: provider.isBackgroundSyncing
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.refresh, color: Colors.red, size: 20),
                    onPressed: () => context
                        .read<InventoryProvider>()
                        .loadSaudaData(force: true),
                    tooltip: "Refresh from Sheet",
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: msmInputDeco(
              "Search size...",
              prefix: const Icon(Icons.search, color: Colors.grey, size: 20),
              suffix: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = "");
                      })
                  : null,
            ).copyWith(
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ScrollController? scrollController) {
    final filtered = _filteredSizes;
    return ListView.separated(
      controller: scrollController,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: filtered.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: Colors.grey.shade100),
      itemBuilder: (context, index) {
        final s = filtered[index];
        final label = s['label']?.toString() ?? '';
        final double weight =
            double.tryParse(s['weight']?.toString() ?? '0') ?? 0.0;
        final sd = s['sd'] ?? 0;

        return Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(
              formatSizeWithWeight(
                  formatSizeDisplay(widget.itemType, label), weight),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Text(
                    "SD: +$sd",
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  const Text("•",
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200, width: 0.7),
                    ),
                    child: Text(
                      "Weight: ${weight.toStringAsFixed(1)} kg",
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            trailing: widget.trailingBuilder != null
                ? widget.trailingBuilder!(s)
                : const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: () => widget.onSizeSelected(s),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _query.isEmpty ? "No sizes available" : "No results for '$_query'",
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
          if (_query.isNotEmpty)
            TextButton(
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = "");
              },
              child: const Text("Clear Search",
                  style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 64, color: Colors.redAccent),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry Connection"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      ),
    );
  }
}
