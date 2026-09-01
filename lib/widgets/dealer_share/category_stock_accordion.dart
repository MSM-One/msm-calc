import 'package:flutter/material.dart';
import '../../utils/formatters.dart';

/// Clean expandable category accordion card displaying high-density item & size rows.
/// Enforces raw deficit integrity (no zero-clamping), multi-column data grid,
/// alternating zebra striping, and quick category WhatsApp text copy.
class CategoryStockAccordion extends StatefulWidget {
  final String categoryName;
  final List<Map<String, dynamic>> items;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final bool? categorySelectionState; // true = all, false = none, null = partial
  final ValueChanged<bool?> onToggleCategorySelection;
  final bool Function(Map<String, dynamic> row) isItemSelected;
  final void Function(Map<String, dynamic> row, bool? selected) onToggleItemSelection;
  final VoidCallback onCopyCategoryWhatsApp;

  const CategoryStockAccordion({
    super.key,
    required this.categoryName,
    required this.items,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.categorySelectionState,
    required this.onToggleCategorySelection,
    required this.isItemSelected,
    required this.onToggleItemSelection,
    required this.onCopyCategoryWhatsApp,
  });

  @override
  State<CategoryStockAccordion> createState() => _CategoryStockAccordionState();
}

class _CategoryStockAccordionState extends State<CategoryStockAccordion> {
  String? _hoveredItemKey;

  @override
  Widget build(BuildContext context) {
    final double categoryTotalMT = widget.items.fold(
      0.0,
      (sum, r) => sum + ((r['current_stock_mt'] as num?)?.toDouble() ?? 0.0),
    );

    final int selectedItemsCount =
        widget.items.where((r) => widget.isItemSelected(r)).length;

    final bool isDeficitCategory = categoryTotalMT < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.categorySelectionState == true
              ? const Color(0xFFDC2626)
              : const Color(0xFFE2E8F0),
          width: widget.categorySelectionState == true ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── CATEGORY HEADER BAR ──
          _buildCategoryHeader(
            categoryTotalMT: categoryTotalMT,
            selectedCount: selectedItemsCount,
            isDeficit: isDeficitCategory,
          ),

          // ── EXPANDED HIGH-DENSITY ROWS ──
          if (widget.isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildItemsDataGrid(context),
            _buildCategorySubtotalFooter(categoryTotalMT),
          ],
        ],
      ),
    );
  }

  // ── HEADER ROW ──
  Widget _buildCategoryHeader({
    required double categoryTotalMT,
    required int selectedCount,
    required bool isDeficit,
  }) {
    return InkWell(
      onTap: widget.onToggleExpand,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            // Checkbox for Category Selection
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: widget.categorySelectionState,
                tristate: true,
                activeColor: const Color(0xFFDC2626),
                onChanged: widget.onToggleCategorySelection,
              ),
            ),
            const SizedBox(width: 6),

            // Category Name & Selection Pill
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    widget.categoryName,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: selectedCount > 0
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: selectedCount > 0
                          ? Border.all(color: const Color(0xFFFCA5A5))
                          : null,
                    ),
                    child: Text(
                      '$selectedCount / ${widget.items.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selectedCount > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Quick Category Copy WhatsApp Button
            Tooltip(
              message: 'Copy ${widget.categoryName} WhatsApp text',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onCopyCategoryWhatsApp,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded,
                            size: 13, color: Color(0xFF10B981)),
                        SizedBox(width: 4),
                        Text(
                          'WhatsApp',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Category Total Tonnage Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: isDeficit ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDeficit ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDeficit) ...[
                    const Icon(Icons.warning_amber_rounded,
                        size: 13, color: Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '${categoryTotalMT.toStringAsFixed(3)} MT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDeficit
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),

            // Expand Arrow Icon
            Icon(
              widget.isExpanded
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

  // ── DATA GRID OF ITEMS & SIZES ──
  Widget _buildItemsDataGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 650;

        return Column(
          children: [
            // Grid Header Row (Desktop / Tablet)
            if (!isCompact) _buildGridHeaderRow(),

            // Item Data Rows with alternating zebra striping
            ...List.generate(widget.items.length, (index) {
              final row = widget.items[index];
              final bool isEven = index % 2 == 0;
              final bool isSelected = widget.isItemSelected(row);
              final String itemKey = '${row['category_name']}_${row['size_label']}';
              final bool isHovered = _hoveredItemKey == itemKey;

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredItemKey = itemKey),
                onExit: (_) => setState(() => _hoveredItemKey = null),
                child: isCompact
                    ? _buildMobileItemRow(row, isSelected, isEven, isHovered)
                    : _buildDesktopItemRow(row, isSelected, isEven, isHovered),
              );
            }),
          ],
        );
      },
    );
  }

  // ── DESKTOP GRID HEADER ──
  Widget _buildGridHeaderRow() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
      ),
      child: const Row(
        children: [
          SizedBox(width: 32), // Checkbox spacing
          SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              'SIZE & SECTION',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'UNIT WEIGHT',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'STATUS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'AVAILABLE QTY',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.3,
              ),
            ),
          ),
          SizedBox(width: 8),
        ],
      ),
    );
  }

  // ── DESKTOP ITEM ROW ──
  Widget _buildDesktopItemRow(
    Map<String, dynamic> row,
    bool isSelected,
    bool isEven,
    bool isHovered,
  ) {
    final sizeLabel = row['size_label']?.toString() ?? '';
    final double stockMT = (row['current_stock_mt'] as num?)?.toDouble() ?? 0.0;
    final double unitWt = (row['unit_weight_kg'] as num?)?.toDouble() ?? 0.0;

    final bool isDeficit = stockMT < 0;
    final bool isAvailable = stockMT > 0;

    Color rowBgColor;
    if (isSelected) {
      rowBgColor = const Color(0xFFFEF2F2);
    } else if (isHovered) {
      rowBgColor = const Color(0xFFF1F5F9);
    } else if (isEven) {
      rowBgColor = const Color(0xFFF8FAFC);
    } else {
      rowBgColor = Colors.white;
    }

    return InkWell(
      onTap: () => widget.onToggleItemSelection(row, !isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: rowBgColor,
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: isSelected,
                activeColor: const Color(0xFFDC2626),
                onChanged: (val) => widget.onToggleItemSelection(row, val),
              ),
            ),
            const SizedBox(width: 8),

            // Col 1: Size & Section Display
            Expanded(
              flex: 4,
              child: Text(
                formatSizeDisplay(widget.categoryName, sizeLabel),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Col 2: Unit Weight
            Expanded(
              flex: 2,
              child: Text(
                unitWt > 0 ? '${unitWt.toStringAsFixed(2)} kg' : '—',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Col 3: Stock Status Indicator
            Expanded(
              flex: 2,
              child: _buildStatusPill(isAvailable: isAvailable, isDeficit: isDeficit),
            ),

            // Col 4: Available Quantity (Strictly X.XXX MT)
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isDeficit) ...[
                    const Icon(Icons.warning_amber_rounded,
                        size: 13, color: Color(0xFFDC2626)),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    '${stockMT.toStringAsFixed(3)} MT',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isDeficit
                          ? const Color(0xFFDC2626)
                          : (isAvailable ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ── MOBILE ITEM ROW ──
  Widget _buildMobileItemRow(
    Map<String, dynamic> row,
    bool isSelected,
    bool isEven,
    bool isHovered,
  ) {
    final sizeLabel = row['size_label']?.toString() ?? '';
    final double stockMT = (row['current_stock_mt'] as num?)?.toDouble() ?? 0.0;
    final double unitWt = (row['unit_weight_kg'] as num?)?.toDouble() ?? 0.0;

    final bool isDeficit = stockMT < 0;

    return InkWell(
      onTap: () => widget.onToggleItemSelection(row, !isSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFEF2F2)
              : (isEven ? const Color(0xFFF8FAFC) : Colors.white),
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: isSelected,
                activeColor: const Color(0xFFDC2626),
                onChanged: (val) => widget.onToggleItemSelection(row, val),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatSizeDisplay(widget.categoryName, sizeLabel),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  if (unitWt > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${unitWt.toStringAsFixed(2)} kg',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDeficit) ...[
                      const Icon(Icons.warning_amber_rounded,
                          size: 13, color: Color(0xFFDC2626)),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      '${stockMT.toStringAsFixed(3)} MT',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDeficit
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isDeficit
                      ? 'Deficit'
                      : (stockMT > 0 ? 'Available' : 'Zero Stock'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDeficit
                        ? const Color(0xFFDC2626)
                        : (stockMT > 0 ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── STATUS PILL BUILDER ──
  Widget _buildStatusPill({required bool isAvailable, required bool isDeficit}) {
    if (isDeficit) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 6, color: Color(0xFFDC2626)),
            SizedBox(width: 4),
            Text(
              'Deficit',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      );
    }

    if (isAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
            SizedBox(width: 4),
            Text(
              'Available',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF059669),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: Color(0xFF94A3B8)),
          SizedBox(width: 4),
          Text(
            'Zero',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // ── SUBTOTAL FOOTER ──
  Widget _buildCategorySubtotalFooter(double categoryTotalMT) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Subtotal (${widget.categoryName})',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          Text(
            '${categoryTotalMT.toStringAsFixed(3)} MT',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: categoryTotalMT < 0
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
