import 'package:flutter/material.dart';
import '../../models/report_models.dart';
import '../../services/data_repository.dart';
import '../../utils/item_order_util.dart';
import '../../utils/sorting_utils.dart';
import '../../widgets/m_loader.dart';
import '../../widgets/reports/enterprise_stock_movement_table.dart';

/// Enterprise Data Models for Today's Summary Split View
class _TodaySizeRowData {
  final int index;
  final String itemName;
  final String sizeLabel;
  final double opening;
  final double inward;
  final double outward;
  final double closing;
  final double net;

  _TodaySizeRowData({
    required this.index,
    required this.itemName,
    required this.sizeLabel,
    required this.opening,
    required this.inward,
    required this.outward,
    required this.closing,
    required this.net,
  });

  bool get hasMovement => inward.abs() > 0.0001 || outward.abs() > 0.0001;

  _TodaySizeRowData copyWith({int? index}) {
    return _TodaySizeRowData(
      index: index ?? this.index,
      itemName: itemName,
      sizeLabel: sizeLabel,
      opening: opening,
      inward: inward,
      outward: outward,
      closing: closing,
      net: net,
    );
  }
}

class _CategorySummaryData {
  final String name;
  final double totalOpening;
  final double totalInward;
  final double totalOutward;
  final double totalClosing;
  final double totalNet;
  final List<_TodaySizeRowData> sizes;

  _CategorySummaryData({
    required this.name,
    required this.totalOpening,
    required this.totalInward,
    required this.totalOutward,
    required this.totalClosing,
    required this.totalNet,
    required this.sizes,
  });

  int get activeSizesCount => sizes.where((s) => s.hasMovement).length;
  bool get hasMovement => totalInward.abs() > 0.0001 || totalOutward.abs() > 0.0001;
}

/// Today's Summary Sub-Report Tab.
/// Modernized into an Enterprise 2-Pane Master-Detail Split View matching "Stock Movement":
/// 1. Desktop Split-View (Width >= 1024px): 300px Left Category Sidebar + Right High-Density Detail Pane.
/// 2. Mobile/Tablet Responsive View (Width < 1024px): High-density collapsible accordion table.
/// 3. Standardized High-Density Grid (38px row height):
///    Columns: [ # | SIZE & SECTION | OPENING | INWARD | OUTWARD | NET / CLOSING ]
class TodaySummaryTab extends StatefulWidget {
  final bool isLoading;
  final List<DailyMovementEntry> filteredDailyMovement;
  final Widget emptyState;
  final ValueChanged<String>? onTabChanged;
  final ValueChanged<String>? onFlowChanged;
  final String dateRangeLabel;
  final String selectedTab;
  final String selectedFlow;
  final Function(String category)? onExportCategoryPdf;
  final Map<String, bool> categoryDownloading;
  final bool activeOnly;
  final ValueChanged<bool>? onActiveOnlyChanged;

  const TodaySummaryTab({
    super.key,
    required this.isLoading,
    required this.filteredDailyMovement,
    required this.emptyState,
    this.onTabChanged,
    this.onFlowChanged,
    this.dateRangeLabel = 'today',
    this.selectedTab = 'Detailed',
    this.selectedFlow = 'Inward',
    this.onExportCategoryPdf,
    this.categoryDownloading = const {},
    this.activeOnly = true,
    this.onActiveOnlyChanged,
  });

  @override
  State<TodaySummaryTab> createState() => _TodaySummaryTabState();
}

class _TodaySummaryTabState extends State<TodaySummaryTab> {
  String? _selectedCategory;
  final Set<String> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    if (widget.selectedTab == 'Detailed') {
      _expandAllCategories();
    }
  }

  @override
  void didUpdateWidget(covariant TodaySummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      if (widget.selectedTab == 'Detailed') {
        _expandAllCategories();
      } else {
        _expandedCategories.clear();
      }
    }
  }

  void _expandAllCategories() {
    for (var e in widget.filteredDailyMovement) {
      final rawCat = e.itemName.isNotEmpty
          ? e.itemName
          : (e.category.isNotEmpty ? e.category : 'Other');
      final name = DataRepository.canonicalizeCategory(rawCat);
      _expandedCategories.add(name);
    }
  }

  static IconData _getCategoryIcon(String catName) {
    final lower = catName.toLowerCase();
    if (lower.contains('pipe')) return Icons.architecture_rounded;
    if (lower.contains('angle') || lower.contains('channel')) {
      return Icons.grid_view_rounded;
    }
    if (lower.contains('bar') || lower.contains('flat')) {
      return Icons.view_in_ar_rounded;
    }
    if (lower.contains('wire')) return Icons.cable_rounded;
    if (lower.contains('nail')) return Icons.build_rounded;
    if (lower.contains('structure') || lower.contains('ism')) {
      return Icons.domain_rounded;
    }
    return Icons.category_outlined;
  }

  List<_CategorySummaryData> _processCategories() {
    final Map<String, Map<String, _TodaySizeRowData>> categoryMap = {};

    for (final e in widget.filteredDailyMovement) {
      final rawCat = e.itemName.isNotEmpty
          ? e.itemName
          : (e.category.isNotEmpty ? e.category : 'Other');
      final String categoryName = DataRepository.canonicalizeCategory(rawCat);
      categoryMap.putIfAbsent(categoryName, () => {});

      final sizeKey = e.size;
      if (categoryMap[categoryName]!.containsKey(sizeKey)) {
        final prev = categoryMap[categoryName]![sizeKey]!;
        categoryMap[categoryName]![sizeKey] = _TodaySizeRowData(
          index: 0,
          itemName: e.itemName.isNotEmpty ? e.itemName : prev.itemName,
          sizeLabel: sizeKey,
          opening: prev.opening + e.openingQty,
          inward: prev.inward + e.inQty,
          outward: prev.outward + e.outQty,
          closing: prev.closing + e.closingQty,
          net: (prev.inward + e.inQty) - (prev.outward + e.outQty),
        );
      } else {
        categoryMap[categoryName]![sizeKey] = _TodaySizeRowData(
          index: 0,
          itemName: e.itemName.isNotEmpty ? e.itemName : e.category,
          sizeLabel: sizeKey,
          opening: e.openingQty,
          inward: e.inQty,
          outward: e.outQty,
          closing: e.closingQty,
          net: e.inQty - e.outQty,
        );
      }
    }

    final List<_CategorySummaryData> categories = [];
    categoryMap.forEach((catName, sizeMap) {
      final sortedSizes = sizeMap.values.toList()
        ..sort((a, b) => SortingUtils.compareSizes(a.sizeLabel, b.sizeLabel));

      final reindexedSizes = <_TodaySizeRowData>[];
      for (int i = 0; i < sortedSizes.length; i++) {
        final s = sortedSizes[i];
        reindexedSizes.add(_TodaySizeRowData(
          index: i + 1,
          itemName: s.itemName,
          sizeLabel: s.sizeLabel,
          opening: s.opening,
          inward: s.inward,
          outward: s.outward,
          closing: s.closing,
          net: s.net,
        ));
      }

      final double totalOpen =
          reindexedSizes.fold(0.0, (sum, s) => sum + s.opening);
      final double totalIn =
          reindexedSizes.fold(0.0, (sum, s) => sum + s.inward);
      final double totalOut =
          reindexedSizes.fold(0.0, (sum, s) => sum + s.outward);
      final double totalClosing =
          reindexedSizes.fold(0.0, (sum, s) => sum + s.closing);
      final double totalNet = totalIn - totalOut;

      categories.add(_CategorySummaryData(
        name: catName,
        totalOpening: totalOpen,
        totalInward: totalIn,
        totalOutward: totalOut,
        totalClosing: totalClosing,
        totalNet: totalNet,
        sizes: reindexedSizes,
      ));
    });

    // Strictly sort categories canonically
    categories.sort((a, b) => ItemOrderUtil.compare(a.name, b.name));
    return categories;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return const Center(child: MLoader());
    if (widget.filteredDailyMovement.isEmpty) return widget.emptyState;

    final categories = _processCategories();
    if (categories.isEmpty) return widget.emptyState;

    // Default selection to first category in canonical sequence
    if (_selectedCategory == null ||
        !categories.any((c) => c.name == _selectedCategory)) {
      _selectedCategory = categories.first.name;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        // When 'Summary' is active, render single high-density table of all 10 canonical categories
        if (widget.selectedTab == 'Summary') {
          return _buildSummaryTableView(categories, width);
        }

        // Detailed Mode:
        // Desktop Split View (>= 1024px)
        if (width >= 1024) {
          return _buildDesktopSplitView(categories);
        }

        // Mobile / Tablet View (< 1024px)
        return _buildMobileTabletView(categories, width);
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SINGLE HIGH-DENSITY SUMMARY TABLE VIEW (Summary Mode)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildSummaryTableView(
      List<_CategorySummaryData> categories, double availableWidth) {
    final double grandInward =
        categories.fold(0.0, (sum, c) => sum + c.totalInward);
    final double grandOutward =
        categories.fold(0.0, (sum, c) => sum + c.totalOutward);
    final double grandNet = grandInward - grandOutward;

    const double minTableWidth = 720.0;
    final bool needsHorizontalScroll = availableWidth < minTableWidth;

    final Widget tableContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Table Header Banner
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.table_chart_rounded,
                        size: 14, color: Color(0xFFD32F2F)),
                    SizedBox(width: 6),
                    Text(
                      'DAILY CATEGORY SUMMARY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  '${categories.length} categories',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const Spacer(),
              _buildPillSummaryItem(
                  'In',
                  '+${grandInward.toStringAsFixed(3)} MT',
                  const Color(0xFF059669)),
              const SizedBox(width: 10),
              _buildPillSummaryItem(
                  'Out',
                  '-${grandOutward.toStringAsFixed(3)} MT',
                  const Color(0xFFDC2626)),
              const SizedBox(width: 10),
              _buildPillSummaryItem(
                  'Net',
                  '${grandNet.abs() < 0.00001 ? "0.000" : grandNet.toStringAsFixed(3)} MT',
                  grandNet < 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0F172A),
                  isBold: true),
            ],
          ),
        ),

        // Dense Summary Table Header (5 columns)
        _buildDenseSummaryTableHeader(),

        // Dense Summary Table Rows
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              return _buildDenseSummaryTableRow(
                cat: cat,
                index: index + 1,
                isEven: index % 2 == 0,
                onTap: () {
                  setState(() => _selectedCategory = cat.name);
                  widget.onTabChanged?.call('Detailed');
                },
              );
            },
          ),
        ),

        // Dense Summary Table Footer
        _buildDenseSummaryTableFooter(
          grandInward: grandInward,
          grandOutward: grandOutward,
          grandNet: grandNet,
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: needsHorizontalScroll
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minTableWidth, child: tableContent),
            )
          : tableContent,
    );
  }

  Widget _buildDenseSummaryTableHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              'CATEGORY / MATERIAL',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              'INWARD (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF059669),
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              'OUTWARD (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              'NET QTY (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDenseSummaryTableRow({
    required _CategorySummaryData cat,
    required int index,
    required bool isEven,
    required VoidCallback onTap,
  }) {
    final double netQty = cat.totalNet;
    final bool isNegative = netQty < 0;

    final String inwardText =
        cat.totalInward == 0 ? '-' : '+${cat.totalInward.toStringAsFixed(3)}';
    final String outwardText =
        cat.totalOutward == 0 ? '-' : '-${cat.totalOutward.toStringAsFixed(3)}';
    final String netText =
        netQty.abs() < 0.00001 ? '0.000' : netQty.toStringAsFixed(3);

    return InkWell(
      onTap: onTap,
      hoverColor: const Color(0xFFF1F5F9),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isEven ? Colors.white : const Color(0xFFF8FAFC),
          border: const Border(
            bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.0),
          ),
        ),
        child: Row(
          children: [
            // 1. Index #
            SizedBox(
              width: 44,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 2. Category / Material with Icon + Name + Size count pill
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _getCategoryIcon(cat.name),
                      size: 14,
                      color: const Color(0xFFD32F2F),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    cat.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${cat.sizes.length} sizes',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // 3. Inward (width: 130, right-aligned)
            SizedBox(
              width: 130,
              child: Text(
                inwardText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      cat.totalInward == 0 ? FontWeight.w500 : FontWeight.w800,
                  color: cat.totalInward == 0
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF059669),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 4. Outward (width: 130, right-aligned)
            SizedBox(
              width: 130,
              child: Text(
                outwardText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      cat.totalOutward == 0 ? FontWeight.w500 : FontWeight.w800,
                  color: cat.totalOutward == 0
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFFDC2626),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 5. Net Qty (width: 140, right-aligned)
            SizedBox(
              width: 140,
              child: Text(
                netText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: netQty.abs() < 0.00001
                      ? const Color(0xFF94A3B8)
                      : (isNegative
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F172A)),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDenseSummaryTableFooter({
    required double grandInward,
    required double grandOutward,
    required double grandNet,
  }) {
    final bool isNegative = grandNet < 0;
    final String inwardText =
        grandInward == 0 ? '-' : '+${grandInward.toStringAsFixed(3)}';
    final String outwardText =
        grandOutward == 0 ? '-' : '-${grandOutward.toStringAsFixed(3)}';
    final String netText = grandNet.abs() < 0.00001
        ? '0.000 MT'
        : '${grandNet.toStringAsFixed(3)} MT';

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 44,
            child: SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          const Expanded(
            flex: 4,
            child: Text(
              'TOTAL',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              inwardText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF059669),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              outwardText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFFDC2626),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              netText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: isNegative
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0F172A),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DESKTOP MASTER-DETAIL SPLIT VIEW (>= 1024px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopSplitView(List<_CategorySummaryData> categories) {
    final activeCat = categories.firstWhere(
      (c) => c.name == _selectedCategory,
      orElse: () => categories.first,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left Sidebar (300px fixed) ──
          SizedBox(
            width: 300,
            child: Container(
              color: const Color(0xFFFAFAFA),
              child: Column(
                children: [
                  // Sidebar Header: "CATEGORIES" + Count Pill
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'CATEGORIES',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF475569),
                            letterSpacing: 0.6,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${categories.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Category Scrollable List
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final catData = categories[index];
                        final isSelected = catData.name == activeCat.name;

                        return _buildCategorySidebarRow(
                          categoryData: catData,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() => _selectedCategory = catData.name);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Divider ──
          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // ── Right Data Pane (Expanded) ──
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active Category Top Header Banner
                  _buildRightPaneCategoryHeader(
                    category: activeCat,
                    onExportPdf: widget.onExportCategoryPdf != null
                        ? () => widget.onExportCategoryPdf!(activeCat.name)
                        : null,
                    isDownloading:
                        widget.categoryDownloading[activeCat.name] == true,
                  ),

                  // Table Header
                  _buildDenseTableHeader(),

                  // Table Body
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final displaySizes = widget.activeOnly
                            ? activeCat.sizes.where((s) => s.hasMovement).toList()
                            : activeCat.sizes;

                        if (displaySizes.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: const Icon(
                                      Icons.inbox_outlined,
                                      size: 28,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No stock movements recorded for ${activeCat.name} on this date.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  if (widget.activeOnly && activeCat.sizes.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    TextButton.icon(
                                      onPressed: () => widget.onActiveOnlyChanged?.call(false),
                                      icon: const Icon(Icons.visibility_outlined, size: 14),
                                      label: Text(
                                        'View all ${activeCat.sizes.length} catalog sizes',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFFD32F2F),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: displaySizes.length,
                          itemBuilder: (context, index) {
                            final row = displaySizes[index];
                            final reindexedRow = widget.activeOnly
                                ? row.copyWith(index: index + 1)
                                : row;
                            return _buildDenseTableRow(
                              row: reindexedRow,
                              isEven: index % 2 == 0,
                              categoryName: activeCat.name,
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Table Footer (Totals)
                  _buildDenseTableFooter(
                    totalInward: activeCat.totalInward,
                    totalOutward: activeCat.totalOutward,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Left Pane Category Tile
  Widget _buildCategorySidebarRow({
    required _CategorySummaryData categoryData,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final double netMovement = categoryData.totalNet;
    final bool hasMovement =
        categoryData.totalInward != 0 || categoryData.totalOutward != 0;
    final bool isNegative = netMovement < 0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected
                  ? const Color(0xFFD32F2F)
                  : Colors.transparent,
              width: 3.5,
            ),
            bottom: const BorderSide(color: Color(0xFFF1F5F9), width: 1.0),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    categoryData.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w700,
                      color: isSelected
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.activeOnly
                          ? '${categoryData.activeSizesCount} active / ${categoryData.sizes.length} sizes'
                          : '${categoryData.sizes.length} sizes',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasMovement) ...[
              const SizedBox(width: 8),
              Text(
                '${netMovement.toStringAsFixed(3)} MT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isNegative
                      ? const Color(0xFFDC2626)
                      : (isSelected
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF475569)),
                  fontFamily: 'monospace',
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isSelected
                  ? const Color(0xFFD32F2F)
                  : const Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    );
  }

  // Right Pane Category Header
  Widget _buildRightPaneCategoryHeader({
    required _CategorySummaryData category,
    required VoidCallback? onExportPdf,
    required bool isDownloading,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Category Title & Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getCategoryIcon(category.name),
                    size: 14, color: const Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  category.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              widget.activeOnly
                  ? '${category.activeSizesCount} active / ${category.sizes.length} sizes'
                  : '${category.sizes.length} sizes',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),

          // Summary breakdown strip alongside inline PDF button
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPillSummaryItem(
                      'In',
                      '+${category.totalInward.toStringAsFixed(3)} MT',
                      const Color(0xFF059669)),
                  const SizedBox(width: 10),
                  _buildPillSummaryItem(
                      'Out',
                      '-${category.totalOutward.toStringAsFixed(3)} MT',
                      const Color(0xFFDC2626)),
                  const SizedBox(width: 10),
                  _buildPillSummaryItem(
                      'Net',
                      '${category.totalNet.abs() < 0.00001 ? "0.000" : category.totalNet.toStringAsFixed(3)} MT',
                      category.totalNet < 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F172A),
                      isBold: true),

                  // Inline red [PDF] Quick Action
                  if (onExportPdf != null) ...[
                    const SizedBox(width: 12),
                    if (isDownloading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFD32F2F),
                        ),
                      )
                    else
                      Tooltip(
                        message: 'Export ${category.name} PDF',
                        child: InkWell(
                          onTap: onExportPdf,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border:
                                  Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.picture_as_pdf_outlined,
                                    size: 14, color: Color(0xFFD32F2F)),
                                SizedBox(width: 4),
                                Text(
                                  'PDF',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD32F2F),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  Widget _buildPillSummaryItem(String label, String value, Color color,
      {bool isBold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HIGH-DENSITY TABLE GRID (36px–38px Row Heights)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildDenseTableHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              'SIZE & SECTION',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              'INWARD',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF059669),
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              'OUTWARD',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              'NET QTY',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDenseTableRow({
    required _TodaySizeRowData row,
    required bool isEven,
    required String categoryName,
  }) {
    final double netQty = row.inward - row.outward;
    final bool isNegative = netQty < 0;
    final displayLabel =
        EnterpriseStockMovementTable.appendKgSuffix(categoryName, row.sizeLabel);

    final String inwardText =
        row.inward == 0 ? '-' : '+${row.inward.toStringAsFixed(3)}';
    final String outwardText =
        row.outward == 0 ? '-' : '-${row.outward.toStringAsFixed(3)}';
    final String netQtyText =
        netQty.abs() < 0.00001 ? '0.000' : netQty.toStringAsFixed(3);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isNegative
            ? const Color(0xFFFEF2F2)
            : (isEven ? Colors.white : const Color(0xFFF8FAFC)),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // 1. Index # (width: 32, text-align: center)
          SizedBox(
            width: 32,
            child: Text(
              '${row.index}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Size & Section (Expanded flex: 4, text-align: left, bold dark slate #1E293B)
          Expanded(
            flex: 4,
            child: Text(
              displayLabel,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isNegative
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),

          // 3. Inward (width: 110, text-align: right, emerald green #059669)
          SizedBox(
            width: 110,
            child: Text(
              inwardText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: row.inward == 0
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF059669),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 4. Outward (width: 110, text-align: right, crimson red #DC2626)
          SizedBox(
            width: 110,
            child: Text(
              outwardText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: row.outward == 0
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFDC2626),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 5. Net Qty (width: 120, text-align: right, bold dark slate #0F172A)
          SizedBox(
            width: 120,
            child: Text(
              netQtyText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isNegative
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0F172A),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDenseTableFooter({
    required double totalInward,
    required double totalOutward,
  }) {
    final double totalNet = totalInward - totalOutward;
    final bool isNegative = totalNet < 0;

    final String inwardText =
        totalInward == 0 ? '-' : '+${totalInward.toStringAsFixed(3)}';
    final String outwardText =
        totalOutward == 0 ? '-' : '-${totalOutward.toStringAsFixed(3)}';
    final String netText =
        totalNet.abs() < 0.00001 ? '0.000 MT' : '${totalNet.toStringAsFixed(3)} MT';

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const SizedBox(width: 8),
          const Expanded(
            flex: 4,
            child: Text(
              'TOTAL',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              inwardText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF059669),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              outwardText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFFDC2626),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              netText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: isNegative
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0F172A),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MOBILE / TABLET COLLAPSIBLE VIEW (< 1024px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMobileTabletView(
      List<_CategorySummaryData> sortedCategories, double availableWidth) {
    const double minTableWidth = 720.0;
    final bool needsHorizontalScroll = availableWidth < minTableWidth;

    final Widget content = ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final categoryData = sortedCategories[index];
        final bool isExpanded = _expandedCategories.contains(categoryData.name);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sticky Category Header Card
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedCategories.remove(categoryData.name);
                    } else {
                      _expandedCategories.add(categoryData.name);
                    }
                  });
                },
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: const Color(0xFFF8FAFC),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          categoryData.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.activeOnly
                            ? '${categoryData.activeSizesCount} active / ${categoryData.sizes.length} sizes'
                            : '${categoryData.sizes.length} sizes',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const Spacer(),
                      if (categoryData.totalInward != 0 ||
                          categoryData.totalOutward != 0) ...[
                        Text(
                          '${categoryData.totalNet.toStringAsFixed(3)} MT',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: categoryData.totalNet < 0
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF0F172A),
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF64748B),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded Detailed Table
              if (isExpanded) ...[
                Builder(
                  builder: (context) {
                    final displaySizes = widget.activeOnly
                        ? categoryData.sizes.where((s) => s.hasMovement).toList()
                        : categoryData.sizes;

                    if (displaySizes.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            'No stock movements recorded for ${categoryData.name} on this date.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDenseTableHeader(),
                        ...displaySizes.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final row = entry.value;
                          final reindexedRow = widget.activeOnly
                              ? row.copyWith(index: idx + 1)
                              : row;
                          return _buildDenseTableRow(
                            row: reindexedRow,
                            isEven: idx % 2 == 0,
                            categoryName: categoryData.name,
                          );
                        }),
                        _buildDenseTableFooter(
                          totalInward: categoryData.totalInward,
                          totalOutward: categoryData.totalOutward,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );

    if (needsHorizontalScroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          width: minTableWidth,
          child: content,
        ),
      );
    }

    return content;
  }
}
