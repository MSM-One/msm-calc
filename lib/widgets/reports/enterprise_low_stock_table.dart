import 'package:flutter/material.dart';
import '../../models/stock_models.dart';
import '../../services/data_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/item_order_util.dart';
import '../../utils/sorting_utils.dart';

/// Enterprise Expandable Table for Low Stock Inventory Alerts.
/// Supports:
/// 1. "Summary" view with clean category cards & aggregated subtotal tonnage.
/// 2. Inline Accordion expansion revealing detailed nested sizes.
/// 3. "Detailed" view expanding all categories for a continuous scroll.
/// 4. Canonical category sorting & zero/deficit priority within each category.
class EnterpriseLowStockTable extends StatelessWidget {
  final List<ItemVariant> items;
  final bool isDetailed;
  final Set<String> expandedCategories;
  final ValueChanged<String> onCategoryToggle;
  final Function(String category, List<ItemVariant> items)? onExportCategoryPdf;
  final VoidCallback? onExportPdf;
  final bool isPdfLoading;
  final Map<String, bool> categoryDownloading;
  final String locationFilter;
  final Widget? emptyState;
  final bool activeOnly;

  const EnterpriseLowStockTable({
    super.key,
    required this.items,
    this.isDetailed = false,
    required this.expandedCategories,
    required this.onCategoryToggle,
    this.onExportCategoryPdf,
    this.onExportPdf,
    this.isPdfLoading = false,
    this.categoryDownloading = const {},
    this.locationFilter = 'ALL',
    this.emptyState,
    this.activeOnly = true,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return emptyState ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Text(
                'No low stock items found',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          );
    }

    // 1. Group items by Canonical Category
    final Map<String, List<ItemVariant>> grouped = {};
    for (final item in items) {
      final rawCat = item.category.isNotEmpty ? item.category : item.itemName;
      final category = DataRepository.canonicalizeCategory(rawCat);
      grouped.putIfAbsent(category, () => []).add(item);
    }

    // 2. Sort categories canonically using ItemOrderUtil
    final List<String> sortedCategories = grouped.keys.toList()
      ..sort(ItemOrderUtil.compare);

    // 3. Sort items within each category:
    // Out of Stock (0.000 MT) & Deficit (<0 MT) first, then ascending quantity, then size order
    for (final category in sortedCategories) {
      grouped[category]!.sort((a, b) {
        final double qtyA = a.currentStockMT;
        final double qtyB = b.currentStockMT;

        final bool aZeroOrDeficit = qtyA <= 0.0001;
        final bool bZeroOrDeficit = qtyB <= 0.0001;
        if (aZeroOrDeficit && !bZeroOrDeficit) return -1;
        if (!aZeroOrDeficit && bZeroOrDeficit) return 1;

        final int qtyComp = qtyA.compareTo(qtyB);
        if (qtyComp != 0) return qtyComp;

        return SortingUtils.compareSizes(a.size, b.size);
      });
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final categoryItems = grouped[category]!;
        final double categoryTotal = categoryItems.fold(
          0.0,
          (sum, item) => sum + item.currentStockMT,
        );

        final bool isExpanded = isDetailed || expandedCategories.contains(category);
        final bool isDownloading = categoryDownloading[category] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isExpanded ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Category Card Header (Tap to toggle expansion in Summary Mode) ──
              InkWell(
                onTap: isDetailed ? null : () => onCategoryToggle(category),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  color: isExpanded ? const Color(0xFFFFF7F7) : const Color(0xFFF8FAFC),
                  child: Row(
                    children: [
                      // Warning / Alert Icon Badge
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFECACA), width: 0.5),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Category Name + Low Stock Count Badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              category.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: const Color(0xFFFECACA), width: 0.5),
                                  ),
                                  child: Text(
                                    '${categoryItems.length} ${categoryItems.length == 1 ? 'item' : 'items'} low',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFDC2626),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Aggregated Category Total Tonnage
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${categoryTotal.toStringAsFixed(3)} MT',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: categoryTotal <= 0.0001
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF0F172A),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Category Total',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),

                      // Optional Category PDF Download Button
                      if (onExportCategoryPdf != null) ...[
                        const SizedBox(width: 8),
                        if (isDownloading)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: Padding(
                              padding: EdgeInsets.all(4.0),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          )
                        else
                          IconButton(
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            tooltip: 'Export Category PDF',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () =>
                                onExportCategoryPdf!(category, categoryItems),
                          ),
                      ],

                      // Expand/Collapse Chevron Indicator
                      if (!isDetailed) ...[
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Inline Expanded Nested Items List ──
              if (isExpanded) ...[
                const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: categoryItems.length,
                  separatorBuilder: (context, idx) =>
                      const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, idx) {
                    final item = categoryItems[idx];
                    return _buildNestedSizeRow(item);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNestedSizeRow(ItemVariant item) {
    final String formattedSize = getFormattedSizeDisplay(item.size, null);
    final bool showItemName = item.itemName.isNotEmpty &&
        item.itemName.trim().toLowerCase() != item.category.trim().toLowerCase();

    final double qty = item.currentStockMT;
    final bool isDeficit = qty < -0.0001;
    final bool isZero = !isDeficit && qty.abs() <= 0.0001;
    final bool isZeroOrDeficit = isDeficit || isZero;

    // Status mapping:
    // DEFICIT (< 0 MT) | OUT OF STOCK (0.000 MT) | CRITICAL LOW (> 0 MT)
    final Color badgeBg =
        isZeroOrDeficit ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
    final Color badgeText =
        isZeroOrDeficit ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final IconData statusIcon = isDeficit
        ? Icons.error_outline_rounded
        : (isZero ? Icons.cancel_outlined : Icons.warning_amber_rounded);
    final String statusLabel = isDeficit
        ? 'DEFICIT'
        : (isZero ? 'OUT OF STOCK' : 'CRITICAL LOW');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Status Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: badgeBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              statusIcon,
              size: 14,
              color: badgeText,
            ),
          ),
          const SizedBox(width: 10),

          // Size Details & Status Badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showItemName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      item.itemName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Text(
                  formattedSize,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: badgeText,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (locationFilter == 'ALL' &&
                        item.location.isNotEmpty &&
                        item.location != 'ALL') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFFCBD5E1), width: 0.5),
                        ),
                        child: Text(
                          item.location,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Exact Item Tonnage Metric
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${qty.toStringAsFixed(3)} MT',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: isZeroOrDeficit
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0F172A),
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Balance',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
