import 'package:flutter/material.dart';

/// Compact, modern action ribbon for Dealer Stock Sheet & Trade Availability console.
/// Provides Location Selector, Real-time Search, Select/Deselect All, Copy WhatsApp, Export PDF, and Share actions.
class DealerShareToolbar extends StatelessWidget {
  final String activeLocation;
  final ValueChanged<String> onLocationChanged;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final int selectedCount;
  final int totalCount;
  final double totalSelectedStockMT;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onCopyWhatsApp;
  final VoidCallback onExportPdf;
  final VoidCallback onShare;
  final bool isExporting;

  const DealerShareToolbar({
    super.key,
    required this.activeLocation,
    required this.onLocationChanged,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.selectedCount,
    required this.totalCount,
    required this.totalSelectedStockMT,
    required this.onToggleSelectAll,
    this.onCopyWhatsApp,
    required this.onExportPdf,
    required this.onShare,
    this.isExporting = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 1050;
        final bool isTablet = constraints.maxWidth >= 650 && !isDesktop;

        if (isDesktop) {
          return _buildDesktopRibbon(context);
        } else if (isTablet) {
          return _buildTabletRibbon(context);
        } else {
          return _buildMobileRibbon(context);
        }
      },
    );
  }

  // ── DESKTOP TOOLBAR (56px Unified Ribbon) ──
  Widget _buildDesktopRibbon(BuildContext context) {
    final bool isAllSelected = totalCount > 0 && selectedCount == totalCount;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Location Segmented Control Pill
          _buildLocationPills(),
          const SizedBox(width: 12),

          // Vertical Separator
          Container(height: 24, width: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(width: 12),

          // 2. Search Field
          Expanded(
            child: _buildSearchField(),
          ),
          const SizedBox(width: 12),

          // 3. Selection Counter & Select All Toggle
          _buildSelectAllButton(isAllSelected),
          const SizedBox(width: 12),

          // Vertical Separator
          Container(height: 24, width: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(width: 12),

          // 4. Action Buttons
          _buildActionButton(
            label: 'Export PDF',
            icon: Icons.picture_as_pdf_outlined,
            color: const Color(0xFFDC2626),
            bgColor: const Color(0xFFFEF2F2),
            borderColor: const Color(0xFFFECACA),
            onTap: isExporting ? null : onExportPdf,
            tooltip: 'Download Letterhead Vector PDF',
            isLoading: isExporting,
          ),
          const SizedBox(width: 8),

          _buildActionButton(
            label: 'Share',
            icon: Icons.share_outlined,
            color: const Color(0xFF475569),
            bgColor: const Color(0xFFF1F5F9),
            borderColor: const Color(0xFFE2E8F0),
            onTap: onShare,
            tooltip: 'Share stock sheet file',
          ),
        ],
      ),
    );
  }

  // ── TABLET TOOLBAR (Stacked Dual Strip) ──
  Widget _buildTabletRibbon(BuildContext context) {
    final bool isAllSelected = totalCount > 0 && selectedCount == totalCount;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildLocationPills(),
              const SizedBox(width: 8),
              Expanded(child: _buildSearchField()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSelectAllButton(isAllSelected),
              const Spacer(),
              _buildActionButton(
                label: 'Export PDF',
                icon: Icons.picture_as_pdf_outlined,
                color: const Color(0xFFDC2626),
                bgColor: const Color(0xFFFEF2F2),
                borderColor: const Color(0xFFFECACA),
                onTap: isExporting ? null : onExportPdf,
                isLoading: isExporting,
              ),
              const SizedBox(width: 6),
              _buildActionButton(
                label: 'Share',
                icon: Icons.share_outlined,
                color: const Color(0xFF475569),
                bgColor: const Color(0xFFF1F5F9),
                borderColor: const Color(0xFFE2E8F0),
                onTap: onShare,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── MOBILE TOOLBAR (Compact Column) ──
  Widget _buildMobileRibbon(BuildContext context) {
    final bool isAllSelected = totalCount > 0 && selectedCount == totalCount;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLocationPills(isFullWidth: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildSearchField()),
              const SizedBox(width: 8),
              _buildSelectAllButton(isAllSelected, compact: true),
            ],
          ),
        ],
      ),
    );
  }

  // ── SUB-WIDGET: Location Segmented Pill Bar ──
  Widget _buildLocationPills({bool isFullWidth = false}) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _buildPillTile('YARD', 'Yard Stock', Icons.warehouse_rounded, isFullWidth),
          const SizedBox(width: 2),
          _buildPillTile('FACTORY', 'Factory Stock', Icons.factory_rounded, isFullWidth),
          const SizedBox(width: 2),
          _buildPillTile('ALL', 'All', Icons.public_rounded, isFullWidth),
        ],
      ),
    );
  }

  Widget _buildPillTile(String code, String label, IconData icon, bool isFullWidth) {
    final bool isSelected = activeLocation.toUpperCase() == code;

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onLocationChanged(code),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isFullWidth) {
      return Expanded(child: tile);
    }
    return tile;
  }

  // ── SUB-WIDGET: Real-Time Search Field ──
  Widget _buildSearchField() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: searchController,
        style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search category or size (e.g. 70x35)...',
          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.cancel_rounded, size: 14, color: Color(0xFF94A3B8)),
                  onPressed: onClearSearch,
                  splashRadius: 12,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        ),
        onChanged: onSearchChanged,
      ),
    );
  }

  // ── SUB-WIDGET: Select All Toggle Button ──
  Widget _buildSelectAllButton(bool isAllSelected, {bool compact = false}) {
    return InkWell(
      onTap: onToggleSelectAll,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isAllSelected ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAllSelected ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAllSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 15,
              color: isAllSelected ? const Color(0xFFDC2626) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              isAllSelected ? 'All Selected' : 'Select All',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isAllSelected ? const Color(0xFFDC2626) : const Color(0xFF475569),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isAllSelected ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$selectedCount / $totalCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isAllSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── SUB-WIDGET: Action Button Builder ──
  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback? onTap,
    String? tooltip,
    bool isLoading = false,
  }) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}
