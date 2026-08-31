import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/stock_notifier.dart';
import '../services/supabase_realtime_service.dart';
import '../constants/app_colors.dart';
import '../widgets/erp_segmented_filter.dart';
import '../widgets/m_loader.dart';
import '../widgets/shimmer_widget.dart';
import '../utils/steel_helper.dart';
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import '../models/stock_models.dart';
import 'stock_transaction_screen.dart';
import 'dealer_stock_share_screen.dart';

class CurrentStockScreen extends StatefulWidget {
  final String? initialLocation;
  final String? initialFilter;
  const CurrentStockScreen(
      {super.key, this.initialLocation, this.initialFilter});

  @override
  State<CurrentStockScreen> createState() => _CurrentStockScreenState();
}

class _CurrentStockScreenState extends State<CurrentStockScreen> {
  bool _isLoading = true;
  bool _isAutoRefreshing = false;
  Map<String, dynamic> _erpData = {};
  String _activeLocation = 'YARD';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  final List<String> _selectedCategories = [];
  String _sortBy = "Category";

  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    stockRefreshNotifier.addListener(_onStockDataChanged);
    _activeLocation = widget.initialLocation ?? 'YARD';
    if (widget.initialFilter == 'LOW') {
      _sortBy = "Low Stock First";
    }
    _loadData();
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) {
        _loadData(forceRefresh: true, isAutoRefresh: true);
      }
    });
  }

  @override
  void dispose() {
    stockRefreshNotifier.removeListener(_onStockDataChanged);
    _syncSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onStockDataChanged() {
    if (!mounted) return;
    setState(() {
      _erpData = DataRepository.erpStockNotifier.value;
    });
  }

  Future<void> _loadData(
      {bool forceRefresh = false, bool isAutoRefresh = false}) async {
    if (isAutoRefresh) {
      if (mounted) setState(() => _isAutoRefreshing = true);
    } else {
      if (mounted) setState(() => _isLoading = true);
    }

    if (forceRefresh) {
      await DataRepository.clearLocalStockCache();
    }

    final data =
        await DataRepository.getERPStockAsync(null, forceRefresh: forceRefresh);

    if (mounted) {
      setState(() {
        _erpData = data;
        _isLoading = false;
        _isAutoRefreshing = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredItems() {
    if (_erpData.isEmpty || !_erpData.containsKey('locations')) return [];

    List locs = _erpData['locations'] as List? ?? [];
    Map<String, dynamic>? locationData;
    for (var l in locs) {
      if (l is Map &&
          l['location']?.toString().toUpperCase() == _activeLocation) {
        locationData = Map<String, dynamic>.from(l);
        break;
      }
    }

    if (locationData == null || locationData['items'] == null) return [];

    List<Map<String, dynamic>> displayItems = [];
    final List<dynamic> itemsList = locationData['items'] as List? ?? [];

    for (var item in itemsList) {
      if (item is Map) {
        final itemMap = Map<String, dynamic>.from(item);
        final List<Map<String, dynamic>> variants =
            (itemMap['variants'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [];
        variants.sort((a, b) => SortingUtils.compareSizes(
            a['size']?.toString() ?? '', b['size']?.toString() ?? ''));

        displayItems.add({
          'itemName': itemMap['itemName'] ?? 'Unknown',
          'category': itemMap['category'] ?? '',
          'totalQty': (itemMap['totalQty'] as num?)?.toDouble() ?? 0.0,
          'variants': variants
        });
      }
    }

    if (_searchQuery.isNotEmpty) {
      displayItems = applyPrioritizedSearch(_searchQuery, displayItems, (v) {
        String base = "${v['itemName']} ${v['category']}";
        List variants = v['variants'] ?? [];
        for (var s in variants) {
          if (s is Map) base += " ${s['size']}";
        }
        return base;
      });
    }

    if (_selectedCategories.isNotEmpty) {
      displayItems = displayItems
          .where((v) => _selectedCategories.contains(v['category']))
          .toList();
    }

    if (_sortBy == "Qty High → Low") {
      displayItems.sort(
          (a, b) => (b['totalQty'] as num).compareTo(a['totalQty'] as num));
    } else if (_sortBy == "Qty Low → High") {
      displayItems.sort(
          (a, b) => (a['totalQty'] as num).compareTo(b['totalQty'] as num));
    } else if (_sortBy == "Name A-Z") {
      displayItems.sort((a, b) {
        int catComp =
            SortingUtils.compareCategories(a['category'], b['category']);
        if (catComp != 0) return catComp;
        return a['itemName']
            .toString()
            .toLowerCase()
            .compareTo(b['itemName'].toString().toLowerCase());
      });
    } else if (_sortBy == "Name Z-A") {
      displayItems.sort((a, b) {
        int catComp =
            SortingUtils.compareCategories(b['category'], a['category']);
        if (catComp != 0) return catComp;
        return b['itemName']
            .toString()
            .toLowerCase()
            .compareTo(a['itemName'].toString().toLowerCase());
      });
    } else if (_sortBy == "Category") {
      displayItems.sort((a, b) {
        int catComp =
            SortingUtils.compareCategories(a['category'], b['category']);
        if (catComp != 0) return catComp;
        return a['itemName']
            .toString()
            .toLowerCase()
            .compareTo(b['itemName'].toString().toLowerCase());
      });
    } else if (_sortBy == "Low Stock First") {
      displayItems.sort((a, b) {
        bool aLow = _hasLowStock(a['variants']);
        bool bLow = _hasLowStock(b['variants']);
        if (aLow == bLow) {
          return (b['totalQty'] as num).compareTo(a['totalQty'] as num);
        }
        return aLow ? -1 : 1;
      });
    }

    return displayItems;
  }

  bool _hasLowStock(List variants) {
    for (var s in variants) {
      if (s is Map &&
          (s['stockStatus'] == 'Low Stock' ||
              s['stockStatus'] == 'Out of Stock')) {
        return true;
      }
    }
    return false;
  }

  void _showFilterSheet(List<ItemVariant> list) {
    final Set<String> categories = list
        .where((e) => e.location.toUpperCase() == _activeLocation.toUpperCase())
        .map((e) => e.category)
        .where((c) => c.isNotEmpty)
        .toSet();

    final catList = categories.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Filter by Category",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: textDark)),
                  TextButton(
                      onPressed: () =>
                          setModalState(() => _selectedCategories.clear()),
                      child:
                          const Text("Reset", style: TextStyle(color: msmRed)))
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: catList.map((cat) {
                  final isSelected = _selectedCategories.contains(cat);
                  return GestureDetector(
                    onTap: () {
                      setModalState(() {
                        if (isSelected) {
                          _selectedCategories.remove(cat);
                        } else {
                          _selectedCategories.add(cat);
                        }
                      });
                      setState(() {});
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected ? msmRed : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : textDark,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: msmRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text("Apply Filters",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortSheet() {
    final options = [
      "Category",
      "Qty High → Low",
      "Qty Low → High",
      "Name A-Z",
      "Name Z-A",
      "Low Stock First"
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Sort Options",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: textDark)),
            const SizedBox(height: 16),
            ...options.map((opt) => ListTile(
                  title: Text(opt,
                      style: TextStyle(
                          fontWeight: _sortBy == opt
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _sortBy == opt ? msmRed : textDark)),
                  trailing: _sortBy == opt
                      ? const Icon(Icons.check_circle, color: msmRed)
                      : null,
                  onTap: () {
                    setState(() => _sortBy = opt);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      extendBodyBehindAppBar: true,
      appBar: _buildModernAppBar(),
      body: StreamBuilder<List<ItemVariant>>(
        stream: DataRepository.getSupabaseStockStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text("Error loading stock: ${snapshot.error}",
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            );
          }

          final list = snapshot.data ?? [];

          double grandTotal = list.fold(0.0, (s, v) => s + v.currentStockMT);
          double yardTotal = list
              .where((v) => v.location == 'YARD')
              .fold(0.0, (s, v) => s + v.currentStockMT);
          double factoryTotal = list
              .where((v) => v.location == 'FACTORY')
              .fold(0.0, (s, v) => s + v.currentStockMT);
          int activeItemsCount = list
              .where((v) => v.currentStockMT > 0)
              .map((e) => e.itemName)
              .toSet()
              .length;

          return Column(
            children: [
              _buildPremiumHeader(
                  yardTotal, factoryTotal, grandTotal, activeItemsCount),
              _buildFilterBar(list),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? ListView.builder(
                        itemCount: 8,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (ctx, i) => _buildSkeletonRow())
                    : _buildListContent(list),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildListContent(List<ItemVariant> list) {
    List<ItemVariant> displayItems = list.where((item) {
      if (item.location.toUpperCase() != _activeLocation.toUpperCase()) {
        return false;
      }
      if (_selectedCategories.isNotEmpty &&
          !_selectedCategories.contains(item.category)) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchName = item.itemName.toLowerCase().contains(query);
        final matchSize = item.sizeLabel.toLowerCase().contains(query);
        final matchCat = item.category.toLowerCase().contains(query);
        if (!matchName && !matchSize && !matchCat) return false;
      }
      return true;
    }).toList();

    if (_sortBy == "Qty High → Low") {
      displayItems.sort((a, b) => b.netStockMt.compareTo(a.netStockMt));
    } else if (_sortBy == "Qty Low → High") {
      displayItems.sort((a, b) => a.netStockMt.compareTo(b.netStockMt));
    } else if (_sortBy == "Name A-Z") {
      displayItems.sort((a, b) {
        int catComp = SortingUtils.compareCategories(a.category, b.category);
        if (catComp != 0) return catComp;
        return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      });
    } else if (_sortBy == "Name Z-A") {
      displayItems.sort((a, b) {
        int catComp = SortingUtils.compareCategories(b.category, a.category);
        if (catComp != 0) return catComp;
        return b.itemName.toLowerCase().compareTo(a.itemName.toLowerCase());
      });
    } else if (_sortBy == "Category") {
      displayItems.sort((a, b) {
        int catComp = SortingUtils.compareCategories(a.category, b.category);
        if (catComp != 0) return catComp;
        return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      });
    } else if (_sortBy == "Low Stock First") {
      displayItems.sort((a, b) {
        bool aLow = a.netStockMt <= a.minStock;
        bool bLow = b.netStockMt <= b.minStock;
        if (aLow == bLow) {
          return b.netStockMt.compareTo(a.netStockMt);
        }
        return aLow ? -1 : 1;
      });
    }

    if (displayItems.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final itemVariant = displayItems[index];
        final isOutOfStock = itemVariant.netStockMt <= 0;
        final isLowStock = itemVariant.netStockMt <= itemVariant.minStock;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              itemVariant.itemName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "Size: ${getFormattedSizeDisplay(itemVariant.sizeLabel, null)}",
              style: const TextStyle(color: Colors.grey),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${itemVariant.netStockMt.toStringAsFixed(3)} MT",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isOutOfStock
                        ? Colors.red
                        : (isLowStock ? Colors.orange : Colors.teal),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isOutOfStock
                      ? "Out of Stock"
                      : (isLowStock ? "Low Stock" : "In Stock"),
                  style: TextStyle(
                    fontSize: 10,
                    color: isOutOfStock
                        ? Colors.red
                        : (isLowStock ? Colors.orange : Colors.teal),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            backgroundColor: msmRed.withValues(alpha: 0.85),
            elevation: 0,
            centerTitle: false,
            title: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("MSM ONE",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                            letterSpacing: 2)),
                    Text("Stock Inventory",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
                if (_isAutoRefreshing) ...[
                  const SizedBox(width: 12),
                  const MLoader(size: 14, color: Colors.white),
                ]
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                tooltip: "Export Stock Sheet",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DealerStockShareScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: () => _loadData(forceRefresh: true),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumHeader(
      double yard, double factory, double total, int active) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 110, 16, 24),
      decoration: const BoxDecoration(
        color: msmRed,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _buildSummaryCard(
                      "Yard",
                      "${yard.toStringAsFixed(3)} MT",
                      Icons.warehouse_rounded,
                      Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildSummaryCard(
                      "Factory",
                      "${factory.toStringAsFixed(3)} MT",
                      Icons.factory_rounded,
                      Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildSummaryCard(
                      "Grand Total",
                      "${total.toStringAsFixed(3)} MT",
                      Icons.functions_rounded,
                      Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildSummaryCard("Items", "$active",
                      Icons.category_rounded, Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          _buildModernSearchPanel(),
        ],
      ),
    );
  }

  Widget _buildModernSearchPanel() {
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "Search item name or size...",
                hintStyle: const TextStyle(color: textGrey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: msmRed, size: 22),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: textGrey),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = "");
                        })
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ERPSegmentedFilter(
          options: const ['YARD', 'FACTORY'],
          selectedOption: _activeLocation,
          onOptionSelected: (loc) => setState(() => _activeLocation = loc),
        ),
      ],
    );
  }

  Widget _buildFilterBar(List<ItemVariant> list) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          _buildModernChip(
            label: _sortBy,
            icon: Icons.sort_rounded,
            onTap: _showSortSheet,
          ),
          const SizedBox(width: 8),
          _buildModernChip(
            label: _selectedCategories.isEmpty
                ? "Categories"
                : "${_selectedCategories.length} Selected",
            icon: Icons.filter_list_rounded,
            onTap: () => _showFilterSheet(list),
            isActive: _selectedCategories.isNotEmpty,
          ),
          const Spacer(),
          if (_selectedCategories.isNotEmpty || _searchQuery.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _selectedCategories.clear();
                _searchCtrl.clear();
                _searchQuery = "";
              }),
              child: const Text("Clear All",
                  style: TextStyle(
                      fontSize: 12,
                      color: msmRed,
                      fontWeight: FontWeight.bold)),
            )
        ],
      ),
    );
  }

  Widget _buildModernChip(
      {required String label,
      required IconData icon,
      required VoidCallback onTap,
      bool isActive = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? msmRed.withValues(alpha: 0.1) : bgLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isActive ? msmRed.withValues(alpha: 0.3) : borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? msmRed : textGrey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: isActive ? msmRed : textDark,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis),
                Text(title,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableItem(Map<String, dynamic> item) {
    final double totalMT = (item['totalQty'] as num?)?.toDouble() ?? 0;
    final List variants = item['variants'] ?? [];

    final bool isLowStock = _hasLowStock(variants);
    final bool isOutOfStock = totalMT <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isOutOfStock
              ? Colors.red.withValues(alpha: 0.3)
              : (isLowStock
                  ? Colors.orange.withValues(alpha: 0.3)
                  : borderLight),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(item['itemName'],
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    fontSize: 16)),
            subtitle: Row(
              children: [
                Text(item['category'],
                    style: const TextStyle(
                        fontSize: 11,
                        color: textGrey,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: bgLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text("${variants.length} SKU",
                      style: const TextStyle(
                          fontSize: 9,
                          color: textGrey,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${totalMT.toStringAsFixed(2)} MT",
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: isOutOfStock
                                ? Colors.red
                                : (isLowStock
                                    ? Colors.orange.shade800
                                    : Colors.teal))),
                    _buildStatusBadge(isOutOfStock
                        ? "Out of Stock"
                        : (isLowStock ? "Low Stock" : "In Stock")),
                  ],
                ),
                const SizedBox(width: 12),
                const Icon(Icons.keyboard_arrow_down_rounded, color: textGrey),
              ],
            ),
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            childrenPadding: EdgeInsets.zero,
            expandedAlignment: Alignment.topLeft,
            children: [
              Container(height: 1, color: bgLight),
              ...variants.map((s) => _buildVariantRow(item['itemName'], s)),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariantRow(String itemName, Map<String, dynamic> v) {
    double qty = (v['qtyMT'] ?? (v['qty'] ?? 0.0) as num).toDouble();
    String status = v['stockStatus'] ?? "In Stock";
    String label = v['size'] ?? "";

    bool isLow = status == 'Low Stock';
    bool isOut = status == 'Out of Stock' || qty <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOut
            ? Colors.red.shade50.withValues(alpha: 0.5)
            : (isLow
                ? Colors.orange.shade50.withValues(alpha: 0.5)
                : Colors.transparent),
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatSizeDisplay(itemName, label),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: _activeLocation == 'YARD'
                              ? Colors.indigo.shade50
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _activeLocation == 'YARD'
                                  ? Colors.indigo.shade100
                                  : Colors.teal.shade100)),
                      child: Text(_activeLocation,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeLocation == 'YARD'
                                  ? Colors.indigo
                                  : Colors.teal)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        "Stock: ${qty.toStringAsFixed(2)} ${v['unit'] ?? 'MT'}",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOut
                                ? Colors.red
                                : (isLow ? Colors.orange.shade800 : textDark))),
                  ],
                ),
                if (v['last_updated_at'] != null &&
                    v['last_updated_at'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text("Updated: ${v['last_updated_at']}",
                        style: const TextStyle(fontSize: 10, color: textGrey)),
                  )
              ],
            ),
          ),
          Row(
            children: [
              _buildCompactActionButton(Icons.add_circle_outline, Colors.teal,
                  () => _openTransaction(itemName, v, true)),
              const SizedBox(width: 8),
              _buildCompactActionButton(Icons.remove_circle_outline, msmRed,
                  () => _openTransaction(itemName, v, false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButton(
      IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.teal;
    if (status == "Out of Stock") {
      color = Colors.red;
    } else if (status == "Low Stock") color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4)),
      child: Text(status,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _openTransaction(
      String itemName, Map<String, dynamic> v, bool isStockIn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StockTransactionScreen(
          initialType: isStockIn ? 'IN' : 'OUT',
          initialItem: itemName,
          initialSize: v['size'] ?? ''),
    ).then((_) => _loadData());
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text("No items found.",
              style: TextStyle(color: textGrey, fontSize: 16)),
          const SizedBox(height: 24),
          if (_selectedCategories.isNotEmpty || _searchQuery.isNotEmpty)
            ElevatedButton(
              onPressed: () => setState(() {
                _selectedCategories.clear();
                _searchCtrl.clear();
                _searchQuery = "";
              }),
              style: ElevatedButton.styleFrom(
                  backgroundColor: msmRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30))),
              child: const Text("Clear Filters"),
            )
        ],
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Shimmer(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const CircleAvatar(radius: 20, backgroundColor: Colors.white),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 140, height: 16, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(width: 80, height: 12, color: Colors.white)
                ])
              ]))),
    );
  }
}
