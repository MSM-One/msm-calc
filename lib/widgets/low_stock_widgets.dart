import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// ─────────────────────────────────────────────
// Low Stock Item Row (inside expanded card)
// ─────────────────────────────────────────────
class LowStockItemRow extends StatelessWidget {
  final String itemName;
  final double qty;
  final bool isCritical;
  final bool isWarning;

  const LowStockItemRow({
    super.key,
    required this.itemName,
    required this.qty,
    required this.isCritical,
    required this.isWarning,
  });

  @override
  Widget build(BuildContext context) {
    final Color qtyColor = isCritical
        ? msmRed
        : (isWarning ? const Color(0xFFE67E22) : Colors.black87);
    final Color iconColor = isCritical ? msmRed : const Color(0xFFE67E22);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isCritical ? msmRed.withValues(alpha: 0.3) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: iconColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              itemName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color:
                    isCritical ? msmRed.withValues(alpha: 0.9) : Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${qty.toStringAsFixed(3)} MT",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: qtyColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Low Stock Category Card (collapsed state)
// ─────────────────────────────────────────────
class LowStockCategoryCard extends StatelessWidget {
  final String category;
  final double totalQty;
  final bool isCritical;
  final bool isWarning;
  final VoidCallback onTap;
  final bool isDownloading;
  final VoidCallback? onDownload;

  const LowStockCategoryCard({
    super.key,
    required this.category,
    required this.totalQty,
    required this.isCritical,
    required this.isWarning,
    required this.onTap,
    this.isDownloading = false,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final bool showWarningIcon = isCritical || isWarning;
    final Color nameColor = isCritical ? msmRed : Colors.black87;
    final Color qtyColor = totalQty < 0 ? msmRed : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (showWarningIcon) ...[
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: isCritical ? msmRed : const Color(0xFFE67E22),
              ),
              const SizedBox(width: 10),
            ] else
              const SizedBox(width: 30),
            Expanded(
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: nameColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onDownload != null) ...[
              isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: msmRed),
                    )
                  : IconButton(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download_rounded,
                          size: 20, color: Colors.grey),
                    ),
              const SizedBox(width: 8),
            ],
            Text(
              "${totalQty.toStringAsFixed(3)} MT",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: qtyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Low Stock Expanded Card
// ─────────────────────────────────────────────
class LowStockExpandedCard extends StatelessWidget {
  final String category;
  final double totalQty;
  final bool isCritical;
  final bool isWarning;
  final VoidCallback onHeaderTap;
  final List<Widget> items;
  final bool isDownloading;
  final VoidCallback? onDownload;

  const LowStockExpandedCard({
    super.key,
    required this.category,
    required this.totalQty,
    required this.isCritical,
    required this.isWarning,
    required this.onHeaderTap,
    required this.items,
    this.isDownloading = false,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final Color nameColor = isCritical ? msmRed : Colors.black87;
    final Color qtyColor = totalQty < 0 ? msmRed : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expanded header
          GestureDetector(
            onTap: onHeaderTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isCritical
                    ? msmRed.withValues(alpha: 0.04)
                    : Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: isCritical ? msmRed : const Color(0xFFE67E22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: nameColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onDownload != null) ...[
                    isDownloading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: msmRed),
                          )
                        : IconButton(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_rounded,
                                size: 20, color: Colors.grey),
                          ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    "${totalQty.toStringAsFixed(3)} MT",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: qtyColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.expand_less,
                      size: 20, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          // Item rows
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shared Search Filters (for mobile filter bar)
// ─────────────────────────────────────────────
class LowStockSearchFilters extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final DateTime startDate;
  final DateTime endDate;
  final String locationFilter;
  final VoidCallback onDateRangeTap;
  final VoidCallback onLocationTap;

  const LowStockSearchFilters({
    super.key,
    required this.searchController,
    required this.onSearch,
    required this.startDate,
    required this.endDate,
    required this.locationFilter,
    required this.onDateRangeTap,
    required this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search field
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: searchController,
            onChanged: onSearch,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: "Search reports...",
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon:
                  Icon(Icons.search, size: 20, color: Colors.grey.shade500),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Filter row
        Row(
          children: [
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: onDateRangeTap,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 15, color: msmRed),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "${_fmt(startDate)} - ${_fmt(endDate)}",
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1D21)),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onLocationTap,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      locationFilter,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1D21)),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.filter_list_rounded,
                        size: 16, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return "${d.day} ${months[d.month - 1]} ${d.year}";
  }
}
