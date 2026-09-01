import 'package:flutter/material.dart';
import '../../models/report_models.dart';
import '../../utils/item_order_util.dart';
import '../../utils/formatters.dart';

/// Enterprise Data Table for Stock Movement & Inventory Analytics.
/// Features:
/// 1. Strict canonical 14-category sequencing via ItemOrderUtil
/// 2. Sticky category group headers with total tonnage badges
/// 3. Column layout: [ Item / Size | Unit Wt | Opening | Inward | Outward | Closing (MT) ]
/// 4. High-contrast visual cues (Emerald Inward, Slate Outward, Crimson Negative Alerts)
/// 5. Right-aligned numeric weights (.toStringAsFixed(3) MT)
/// 6. Horizontal scroll protection for narrow viewports
class EnterpriseStockMovementTable extends StatelessWidget {
  final Map<String, Map<String, List<StockMovementEntry>>> groupedReport;
  final bool isDetailed;
  final Set<String> expandedCategories;
  final ValueChanged<String> onCategoryToggle;
  final Function(String category, Map<String, List<StockMovementEntry>> items)?
      onExportCategoryPdf;
  final Map<String, bool> categoryDownloading;
  final String locationFilter;
  final Widget? emptyState;

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
  Widget build(BuildContext context) {
    if (groupedReport.isEmpty) {
      return emptyState ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Text(
                'No stock movement data found',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          );
    }

    // Sort categories using ItemOrderUtil canonical sequence
    final List<String> sortedCategories = groupedReport.keys.toList()
      ..sort(ItemOrderUtil.compare);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minTableWidth = isDetailed ? 860.0 : 640.0;
        final bool needsHorizontalScroll = constraints.maxWidth < minTableWidth;

        final Widget content = ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: sortedCategories.length,
          itemBuilder: (context, index) {
            final category = sortedCategories[index];
            final categoryItems = groupedReport[category] ?? {};
            return _CategoryGroupCard(
              category: category,
              items: categoryItems,
              isDetailed: isDetailed,
              isExpanded: expandedCategories.contains(category),
              onToggle: () => onCategoryToggle(category),
              onExportPdf: onExportCategoryPdf != null
                  ? () => onExportCategoryPdf!(category, categoryItems)
                  : null,
              isDownloading: categoryDownloading[category] == true,
              locationFilter: locationFilter,
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
      },
    );
  }
}

class _CategoryGroupCard extends StatelessWidget {
  final String category;
  final Map<String, List<StockMovementEntry>> items;
  final bool isDetailed;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onExportPdf;
  final bool isDownloading;
  final String locationFilter;

  const _CategoryGroupCard({
    required this.category,
    required this.items,
    required this.isDetailed,
    required this.isExpanded,
    required this.onToggle,
    this.onExportPdf,
    this.isDownloading = false,
    this.locationFilter = 'ALL',
  });

  @override
  Widget build(BuildContext context) {
    final allEntries = items.values.expand((list) => list).toList();
    final double totalOpening =
        allEntries.fold(0.0, (sum, e) => sum + e.opening);
    final double totalInward = allEntries.fold(0.0, (sum, e) => sum + e.inQty);
    final double totalOutward =
        allEntries.fold(0.0, (sum, e) => sum + e.outQty);
    final double totalClosing =
        allEntries.fold(0.0, (sum, e) => sum + e.closing);

    final bool hasNegativeBalance =
        allEntries.any((e) => e.sizes.any((s) => s.closing < 0));

    final int totalSizesCount =
        allEntries.fold(0, (sum, e) => sum + (e.sizes.isEmpty ? 1 : e.sizes.length));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasNegativeBalance
              ? const Color(0xFFFCA5A5) // Subtle red border if negative
              : (isExpanded
                  ? const Color(0xFFCBD5E1)
                  : const Color(0xFFE2E8F0)),
          width: hasNegativeBalance ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sticky / Prominent Category Header
          _buildCategoryHeader(
            context: context,
            totalOpening: totalOpening,
            totalInward: totalInward,
            totalOutward: totalOutward,
            totalClosing: totalClosing,
            totalSizesCount: totalSizesCount,
            hasNegativeBalance: hasNegativeBalance,
          ),

          // Detailed Table Body
          if (isDetailed && isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildTableHeader(),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            _buildTableBody(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildCategoryFooterRow(
              totalOpening: totalOpening,
              totalInward: totalInward,
              totalOutward: totalOutward,
              totalClosing: totalClosing,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryHeader({
    required BuildContext context,
    required double totalOpening,
    required double totalInward,
    required double totalOutward,
    required double totalClosing,
    required int totalSizesCount,
    required bool hasNegativeBalance,
  }) {
    return InkWell(
      onTap: isDetailed ? onToggle : null,
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(12),
        bottom: isDetailed && isExpanded
            ? Radius.zero
            : const Radius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Category Icon / Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.category_rounded,
                      size: 15, color: Color(0xFF475569)),
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
            const SizedBox(width: 10),

            // Item Count Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$totalSizesCount items',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),

            if (hasNegativeBalance) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 12, color: Color(0xFFDC2626)),
                    SizedBox(width: 4),
                    Text(
                      'Negative Balance',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            // Summary Totals on Header
            if (!isDetailed || !isExpanded) ...[
              _buildHeaderMetric(
                label: 'Inward',
                value: '+${totalInward.toStringAsFixed(3)} MT',
                color: const Color(0xFF059669),
              ),
              const SizedBox(width: 14),
              _buildHeaderMetric(
                label: 'Outward',
                value: '-${totalOutward.toStringAsFixed(3)} MT',
                color: const Color(0xFF1E293B),
              ),
              const SizedBox(width: 14),
            ],

            // Total Closing Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: totalClosing < 0
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: totalClosing < 0
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Closing: ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: totalClosing < 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF166534),
                    ),
                  ),
                  Text(
                    '${totalClosing.toStringAsFixed(3)} MT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: totalClosing < 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF166534),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Export PDF Action
            if (onExportPdf != null) ...[
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
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 16,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
            ],

            // Expand/Collapse Icon
            if (isDetailed)
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
    );
  }

  Widget _buildHeaderMetric({
    required String label,
    required String value,
    required Color color,
  }) {
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
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFFF8FAFC),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Item / Size Description',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
            width: 85,
            child: Text(
              'Unit Wt',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              'Opening (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              'Inward (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF059669),
              ),
            ),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              'Outward (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          SizedBox(width: 14),
          SizedBox(
            width: 120,
            child: Text(
              'Closing (MT)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBody() {
    final List<Widget> rows = [];

    items.forEach((itemGroupKey, entryList) {
      for (final entry in entryList) {
        if (entry.sizes.isNotEmpty) {
          for (final size in entry.sizes) {
            rows.add(_buildTableRow(
              itemName: entry.item,
              sizeLabel: size.label,
              opening: size.opening,
              inward: size.inQty,
              outward: size.outQty,
              closing: size.closing,
            ));
          }
        } else {
          rows.add(_buildTableRow(
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

    return Column(children: rows);
  }

  Widget _buildTableRow({
    required String itemName,
    required String sizeLabel,
    required double opening,
    required double inward,
    required double outward,
    required double closing,
  }) {
    final double unitWeight =
        EnterpriseStockMovementTable.extractUnitWeight(sizeLabel);
    final String displayLabel =
        EnterpriseStockMovementTable.appendKgSuffix(itemName, sizeLabel);
    final bool isNegative = closing < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: isNegative ? const Color(0xFFFEF2F2) : Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9)),
        ),
      ),
      child: Row(
        children: [
          // Item / Size Description
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (isNegative) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.priority_high_rounded,
                        size: 11, color: Colors.white),
                  ),
                ],
                Expanded(
                  child: Text(
                    displayLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isNegative
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Unit Wt
          SizedBox(
            width: 85,
            child: Text(
              unitWeight > 0 ? '${unitWeight.toStringAsFixed(2)} kg' : '-',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Opening
          SizedBox(
            width: 105,
            child: Text(
              opening.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Inward (Emerald Green)
          SizedBox(
            width: 105,
            child: Text(
              inward > 0 ? '+${inward.toStringAsFixed(3)}' : inward.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: inward > 0 ? FontWeight.w800 : FontWeight.w500,
                color: inward > 0
                    ? const Color(0xFF059669) // Emerald 600
                    : const Color(0xFF94A3B8),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Outward (Dark Charcoal)
          SizedBox(
            width: 105,
            child: Text(
              outward > 0
                  ? '-${outward.toStringAsFixed(3)}'
                  : outward.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: outward > 0 ? FontWeight.w800 : FontWeight.w500,
                color: outward > 0
                    ? const Color(0xFF1E293B) // Dark Charcoal
                    : const Color(0xFF94A3B8),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Closing (MT) - Crimson for negative
          SizedBox(
            width: 120,
            child: Text(
              '${closing.toStringAsFixed(3)} MT',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isNegative
                    ? const Color(0xFFDC2626) // Crimson
                    : const Color(0xFF0F172A), // Slate 900
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFooterRow({
    required double totalOpening,
    required double totalInward,
    required double totalOutward,
    required double totalClosing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'TOTAL CATEGORY TONNAGE',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF334155),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(
            width: 85,
            child: Text(
              '-',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              totalOpening.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              '+${totalInward.toStringAsFixed(3)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF059669),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 105,
            child: Text(
              '-${totalOutward.toStringAsFixed(3)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E293B),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 120,
            child: Text(
              '${totalClosing.toStringAsFixed(3)} MT',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
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
}
