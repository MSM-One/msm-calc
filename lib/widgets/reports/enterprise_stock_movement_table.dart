import 'package:flutter/material.dart';
import '../../models/report_models.dart';
import '../../utils/item_order_util.dart';
import '../../utils/formatters.dart';

/// Enterprise Data Table for Stock Movement & Inventory Analytics.
/// Modernized into a compact, high-density ERP layout:
/// 1. Desktop Split-View (Width >= 1024px): 320px Left Category Sidebar + Right High-Density Pane.
/// 2. Mobile/Tablet Single Table (Width < 1024px): High-density vertical table.
/// 3. Streamlined Table Data Density: 38px row heights, 6px padding, zebra striping,
///    Columns: [ # | SIZE & SECTION | OPENING | INWARD | OUTWARD | NET / CLOSING ]
class EnterpriseStockMovementTable extends StatefulWidget {
  final Map<String, Map<String, List<StockMovementEntry>>> groupedReport;
  final bool isDetailed;
  final Set<String> expandedCategories;
  final ValueChanged<String> onCategoryToggle;
  final Function(String category, Map<String, List<StockMovementEntry>> items)?
      onExportCategoryPdf;
  final Map<String, bool> categoryDownloading;
  final String locationFilter;
  final Widget? emptyState;
  final bool activeOnly;

  const EnterpriseStockMovementTable({
    super.key,
    required this.groupedReport,
    this.isDetailed = true,
    required this.expandedCategories,
    required this.onCategoryToggle,
    this.onExportCategoryPdf,
    this.categoryDownloading = const {},
    this.locationFilter = 'ALL',
    this.emptyState,
    this.activeOnly = true,
  });

  static double extractUnitWeight(String sizeLabel) {
    if (sizeLabel.isEmpty) return 0.0;
    try {
      final RegExp regex = RegExp(r'\(([^)]+)\)');
      final match = regex.firstMatch(sizeLabel);
      if (match != null) {
        final String val = match.group(1)!.replaceAll(RegExp(r'[^0-9.]'), '');
        if (sizeLabel.contains("1.2")) return 4.0;
        if (sizeLabel.contains("1.6")) return 4.0;
        if (sizeLabel.contains("2.0")) return 5.0;
        return double.tryParse(val) ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  static String appendKgSuffix(String category, String sizeLabel) {
    const excludedCategories = [
      'sqr bar',
      'round bar',
      'flats',
      'barbed wire',
      'gate channel',
    ];
    final lower = category.toLowerCase();
    final isExcluded = excludedCategories.any((ex) => lower.contains(ex));
    if (isExcluded) return sizeLabel;
    return formatSizeWithWeight(sizeLabel, null);
  }

  @override
  State<EnterpriseStockMovementTable> createState() =>
      _EnterpriseStockMovementTableState();
}

class _EnterpriseStockMovementTableState
    extends State<EnterpriseStockMovementTable> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    if (widget.groupedReport.isEmpty) {
      return widget.emptyState ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Text(
                'No stock movement data found',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          );
    }

    // Sort categories canonically using ItemOrderUtil
    final List<String> sortedCategories = widget.groupedReport.keys.toList()
      ..sort(ItemOrderUtil.compare);

    if (_selectedCategory == null ||
        !sortedCategories.contains(_selectedCategory)) {
      _selectedCategory = sortedCategories.first;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        // Desktop Split View (>= 1024px)
        if (width >= 1024) {
          return _buildDesktopSplitView(sortedCategories);
        }

        // Mobile / Tablet Single Streamlined Table (< 1024px)
        return _buildMobileTabletView(sortedCategories, width);
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DESKTOP MASTER-DETAIL SPLIT VIEW (>= 1024px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopSplitView(List<String> sortedCategories) {
    final activeCat = _selectedCategory ?? sortedCategories.first;
    final categoryItems = widget.groupedReport[activeCat] ?? {};
    final rawRowDataList = _flattenCategoryItems(categoryItems);
    final rowDataList = widget.activeOnly
        ? rawRowDataList.where((r) => r.hasMovement).toList()
        : rawRowDataList;

    final allEntries = categoryItems.values.expand((list) => list).toList();
    final double totalOpening =
        allEntries.fold(0.0, (sum, e) => sum + e.opening);
    final double totalInward = allEntries.fold(0.0, (sum, e) => sum + e.inQty);
    final double totalOutward =
        allEntries.fold(0.0, (sum, e) => sum + e.outQty);
    final double totalClosing =
        allEntries.fold(0.0, (sum, e) => sum + e.closing);

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
          // ── Left Sidebar (320px fixed) ──
          SizedBox(
            width: 320,
            child: Container(
              color: const Color(0xFFFAFAFA),
              child: Column(
                children: [
                  // Sidebar Header
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom:
                            BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
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
                            '${sortedCategories.length}',
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

                  // Category List
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: sortedCategories.length,
                      itemBuilder: (context, index) {
                        final cat = sortedCategories[index];
                        final isSelected = cat == activeCat;
                        final items = widget.groupedReport[cat] ?? {};
                        final entries =
                            items.values.expand((list) => list).toList();
                        final double catClosing =
                            entries.fold(0.0, (sum, e) => sum + e.closing);
                        final rawItems = _flattenCategoryItems(items);
                        final int activeCount =
                            rawItems.where((r) => r.hasMovement).length;

                        return _buildCategorySidebarRow(
                          category: cat,
                          sizeCount: rawItems.length,
                          activeCount: activeCount,
                          netTonnage: catClosing,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() => _selectedCategory = cat);
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
                    sizeCount: rawRowDataList.length,
                    activeCount: rowDataList.length,
                    totalOpening: totalOpening,
                    totalInward: totalInward,
                    totalOutward: totalOutward,
                    totalClosing: totalClosing,
                    onExportPdf: widget.onExportCategoryPdf != null
                        ? () => widget.onExportCategoryPdf!(
                            activeCat, categoryItems)
                        : null,
                    isDownloading:
                        widget.categoryDownloading[activeCat] == true,
                  ),

                  // Table Header
                  _buildDenseTableHeader(),

                  // Table Body
                  Expanded(
                    child: rowDataList.isEmpty
                        ? Center(
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
                                    'No stock movements recorded for $activeCat on this date.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: rowDataList.length,
                            itemBuilder: (context, index) {
                              final row = rowDataList[index];
                              final reindexedRow = widget.activeOnly
                                  ? row.copyWith(index: index + 1)
                                  : row;
                              return _buildDenseTableRow(
                                row: reindexedRow,
                                isEven: index % 2 == 0,
                              );
                            },
                          ),
                  ),

                  // Table Footer (Totals)
                  _buildDenseTableFooter(
                    totalOpening: totalOpening,
                    totalInward: totalInward,
                    totalOutward: totalOutward,
                    totalClosing: totalClosing,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Sidebar Row Widget
  Widget _buildCategorySidebarRow({
    required String category,
    required int sizeCount,
    int? activeCount,
    required double netTonnage,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final bool isNegative = netTonnage < 0;

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
                    category.toUpperCase(),
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
                      (widget.activeOnly && activeCount != null)
                          ? '$activeCount active / $sizeCount sizes'
                          : '$sizeCount sizes',
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
            const SizedBox(width: 8),
            Text(
              '${netTonnage.toStringAsFixed(3)} MT',
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
    required String category,
    required int sizeCount,
    int? activeCount,
    required double totalOpening,
    required double totalInward,
    required double totalOutward,
    required double totalClosing,
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
                const Icon(Icons.category_outlined,
                    size: 14, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  category.toUpperCase(),
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
              (widget.activeOnly && activeCount != null)
                  ? '$activeCount active / $sizeCount sizes'
                  : '$sizeCount sizes',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),

          const Spacer(),

          // Summary Metrics
          _buildPillSummaryItem(
              'Opening', '${totalOpening.toStringAsFixed(3)} MT', const Color(0xFF475569)),
          const SizedBox(width: 10),
          _buildPillSummaryItem(
              'In', '+${totalInward.toStringAsFixed(3)} MT', const Color(0xFF059669)),
          const SizedBox(width: 10),
          _buildPillSummaryItem(
              'Out', '-${totalOutward.toStringAsFixed(3)} MT', const Color(0xFFDC2626)),
          const SizedBox(width: 10),
          _buildPillSummaryItem(
              'Closing',
              '${totalClosing.toStringAsFixed(3)} MT',
              totalClosing < 0
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF0F172A),
              isBold: true),

          // PDF Export
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
                message: 'Export $category PDF',
                child: InkWell(
                  onTap: onExportPdf,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFECACA)),
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
  // STREAMLINED TABLE DATA DENSITY (38px Row Heights, Strict 6 Columns)
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
            width: 44,
            child: Text(
              '#',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'SIZE & SECTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
            width: 105,
            child: Text(
              'OPENING',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 105,
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
            width: 105,
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
              'NET / CLOSING',
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
    required _MovementRowData row,
    required bool isEven,
  }) {
    final bool isNegative = row.closing < 0;
    final displayLabel =
        EnterpriseStockMovementTable.appendKgSuffix(row.itemName, row.sizeLabel);

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
          // 1. Index #
          SizedBox(
            width: 44,
            child: Text(
              '${row.index}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),

          // 2. Size & Section
          Expanded(
            flex: 3,
            child: Text(
              displayLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isNegative
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 3. Opening
          SizedBox(
            width: 105,
            child: Text(
              row.opening == 0 ? '-' : row.opening.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: row.opening == 0
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF475569),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 4. Inward
          SizedBox(
            width: 105,
            child: Text(
              row.inward == 0 ? '-' : '+${row.inward.toStringAsFixed(3)}',
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

          // 5. Outward
          SizedBox(
            width: 105,
            child: Text(
              row.outward == 0 ? '-' : '-${row.outward.toStringAsFixed(3)}',
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

          // 6. Net / Closing
          SizedBox(
            width: 120,
            child: Text(
              '${row.closing.toStringAsFixed(3)} MT',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: row.closing == 0
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
    );
  }

  Widget _buildDenseTableFooter({
    required double totalOpening,
    required double totalInward,
    required double totalOutward,
    required double totalClosing,
  }) {
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
          const SizedBox(width: 44),
          const Expanded(
            flex: 3,
            child: Text(
              'TOTAL',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            width: 105,
            child: Text(
              totalOpening.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 105,
            child: Text(
              '+${totalInward.toStringAsFixed(3)}',
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
            width: 105,
            child: Text(
              '-${totalOutward.toStringAsFixed(3)}',
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
              '${totalClosing.toStringAsFixed(3)} MT',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: totalClosing < 0
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
  // MOBILE / TABLET SINGLE STREAMLINED TABLE (< 1024px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMobileTabletView(
      List<String> sortedCategories, double availableWidth) {
    const double minTableWidth = 720.0;
    final bool needsHorizontalScroll = availableWidth < minTableWidth;

    final Widget content = ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final categoryItems = widget.groupedReport[category] ?? {};
        final rawRowDataList = _flattenCategoryItems(categoryItems);
        final rowDataList = widget.activeOnly
            ? rawRowDataList.where((r) => r.hasMovement).toList()
            : rawRowDataList;
        final allEntries =
            categoryItems.values.expand((list) => list).toList();
        final double totalOpening =
            allEntries.fold(0.0, (sum, e) => sum + e.opening);
        final double totalInward =
            allEntries.fold(0.0, (sum, e) => sum + e.inQty);
        final double totalOutward =
            allEntries.fold(0.0, (sum, e) => sum + e.outQty);
        final double totalClosing =
            allEntries.fold(0.0, (sum, e) => sum + e.closing);
        final bool isExpanded = widget.expandedCategories.contains(category);

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
              // Sticky Category Header
              InkWell(
                onTap: () => widget.onCategoryToggle(category),
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
                          category.toUpperCase(),
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
                            ? '${rowDataList.length} active / ${rawRowDataList.length} sizes'
                            : '${rawRowDataList.length} sizes',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${totalClosing.toStringAsFixed(3)} MT',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: totalClosing < 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0F172A),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
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
                if (rowDataList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No stock movements recorded for $category on this date.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                else ...[
                  _buildDenseTableHeader(),
                  ...rowDataList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;
                    final reindexedRow = widget.activeOnly
                        ? row.copyWith(index: idx + 1)
                        : row;
                    return _buildDenseTableRow(
                      row: reindexedRow,
                      isEven: idx % 2 == 0,
                    );
                  }),
                  _buildDenseTableFooter(
                    totalOpening: totalOpening,
                    totalInward: totalInward,
                    totalOutward: totalOutward,
                    totalClosing: totalClosing,
                  ),
                ],
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

  List<_MovementRowData> _flattenCategoryItems(
      Map<String, List<StockMovementEntry>> items) {
    final List<_MovementRowData> list = [];
    int idx = 1;

    items.forEach((itemGroupKey, entryList) {
      for (final entry in entryList) {
        if (entry.sizes.isNotEmpty) {
          for (final size in entry.sizes) {
            list.add(_MovementRowData(
              index: idx++,
              itemName: entry.item,
              sizeLabel: size.label,
              opening: size.opening,
              inward: size.inQty,
              outward: size.outQty,
              closing: size.closing,
            ));
          }
        } else {
          list.add(_MovementRowData(
            index: idx++,
            itemName: entry.item,
            sizeLabel: entry.size,
            opening: entry.opening,
            inward: entry.inQty,
            outward: entry.outQty,
            closing: entry.closing,
          ));
        }
      }
    });

    return list;
  }
}

class _MovementRowData {
  final int index;
  final String itemName;
  final String sizeLabel;
  final double opening;
  final double inward;
  final double outward;
  final double closing;

  _MovementRowData({
    required this.index,
    required this.itemName,
    required this.sizeLabel,
    required this.opening,
    required this.inward,
    required this.outward,
    required this.closing,
  });

  bool get hasMovement => inward.abs() > 0.0001 || outward.abs() > 0.0001;

  _MovementRowData copyWith({int? index}) {
    return _MovementRowData(
      index: index ?? this.index,
      itemName: itemName,
      sizeLabel: sizeLabel,
      opening: opening,
      inward: inward,
      outward: outward,
      closing: closing,
    );
  }
}
