import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Enterprise Export Toolbar for Stock Reports.
/// Houses Date Range Picker, Search Bar, Location Selector, View Toggles, PDF Export, and CSV Export.
class ReportsExportToolbar extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final String selectedDatePreset;
  final String locationFilter;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final VoidCallback onDateRangeTap;
  final ValueChanged<String>? onPresetSelected;
  final ValueChanged<String?> onLocationChanged;
  final VoidCallback onRefresh;
  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;
  final bool isPdfLoading;
  final bool isCsvLoading;
  final bool showViewToggle;
  final bool isDetailedView;
  final ValueChanged<bool>? onViewToggle;
  final bool showActiveOnlyToggle;
  final bool activeOnly;
  final ValueChanged<bool>? onActiveOnlyChanged;
  final String? todayTabMode;
  final ValueChanged<String>? onTodayTabModeChanged;
  final String? todayFlowMode;
  final ValueChanged<String>? onTodayFlowModeChanged;
  final String activeTabId;

  const ReportsExportToolbar({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.selectedDatePreset,
    required this.locationFilter,
    required this.searchController,
    required this.onSearch,
    required this.onDateRangeTap,
    this.onPresetSelected,
    required this.onLocationChanged,
    required this.onRefresh,
    required this.onExportPdf,
    required this.onExportCsv,
    this.isPdfLoading = false,
    this.isCsvLoading = false,
    this.showViewToggle = false,
    this.isDetailedView = false,
    this.onViewToggle,
    this.showActiveOnlyToggle = false,
    this.activeOnly = true,
    this.onActiveOnlyChanged,
    this.todayTabMode,
    this.onTodayTabModeChanged,
    this.todayFlowMode,
    this.onTodayFlowModeChanged,
    required this.activeTabId,
  });

  String _formatDateRange() {
    final bool isSameDay = startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day;
    if (isSameDay) {
      if (selectedDatePreset == 'Today') return 'Today';
      if (selectedDatePreset == 'Yesterday') return 'Yesterday';
      return DateFormat('dd MMM yyyy').format(startDate);
    }
    return '${DateFormat('dd MMM').format(startDate)} - ${DateFormat('dd MMM yy').format(endDate)}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 900;

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Row: Search + Location
                Row(
                  children: [
                    Expanded(child: _buildSearchField()),
                    const SizedBox(width: 8),
                    _buildLocationDropdown(),
                    const SizedBox(width: 8),
                    _buildIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onTap: onRefresh,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Middle Row: Date Range + View Toggles (if any)
                Row(
                  children: [
                    Expanded(child: _buildDateRangeButton()),
                    if (showViewToggle && onViewToggle != null) ...[
                      const SizedBox(width: 8),
                      _buildSummaryDetailedToggle(),
                    ],
                    if (showActiveOnlyToggle) ...[
                      const SizedBox(width: 8),
                      _buildActiveOnlyToggle(),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Bottom Row: Action Buttons (PDF + CSV)
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        label: 'Export PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        color: const Color(0xFFD32F2F), // Brand Red
                        isLoading: isPdfLoading,
                        onTap: onExportPdf,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionButton(
                        label: 'Export CSV',
                        icon: Icons.table_chart_rounded,
                        color: const Color(0xFF059669), // Emerald
                        isLoading: isCsvLoading,
                        onTap: onExportCsv,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        // Desktop Layout (Single / Two Clean Bars)
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 1. Search Bar
              Expanded(
                flex: 3,
                child: _buildSearchField(),
              ),
              const SizedBox(width: 12),

              // 2. Date Range Picker
              _buildDateRangeButton(),
              const SizedBox(width: 10),

              // 3. Location Dropdown
              _buildLocationDropdown(),
              const SizedBox(width: 10),

              // 4. View Toggles (Summary | Detailed)
              if (showViewToggle && onViewToggle != null) ...[
                _buildSummaryDetailedToggle(),
                const SizedBox(width: 10),
              ],

              // 5. Active Movements Only Toggle
              if (showActiveOnlyToggle) ...[
                _buildActiveOnlyToggle(),
                const SizedBox(width: 10),
              ],

              // 5. Refresh Action
              _buildIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh Data',
                onTap: onRefresh,
              ),
              const SizedBox(width: 10),

              // 6. Export PDF
              _buildActionButton(
                label: 'Export PDF',
                icon: Icons.picture_as_pdf_rounded,
                color: const Color(0xFFD32F2F),
                isLoading: isPdfLoading,
                onTap: onExportPdf,
              ),
              const SizedBox(width: 8),

              // 7. Export CSV
              _buildActionButton(
                label: 'Export CSV',
                icon: Icons.table_chart_rounded,
                color: const Color(0xFF059669),
                isLoading: isCsvLoading,
                onTap: onExportCsv,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: onSearch,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
              decoration: const InputDecoration(
                hintText: 'Search items, sizes or categories...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (searchController.text.isNotEmpty)
            InkWell(
              onTap: () {
                searchController.clear();
                onSearch('');
              },
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.close_rounded,
                    size: 16, color: Color(0xFF94A3B8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateRangeButton() {
    return InkWell(
      onTap: onDateRangeTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 15, color: Color(0xFFD32F2F)),
            const SizedBox(width: 8),
            Text(
              _formatDateRange(),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 18, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationDropdown() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: locationFilter,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: Color(0xFF64748B)),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('All Locations')),
            DropdownMenuItem(value: 'YARD', child: Text('Yard Only')),
            DropdownMenuItem(value: 'FACTORY', child: Text('Factory Only')),
          ],
          onChanged: onLocationChanged,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildSummaryDetailedToggle() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption(
            label: 'Summary',
            isSelected: !isDetailedView,
            onTap: () => onViewToggle?.call(false),
          ),
          _buildToggleOption(
            label: 'Detailed',
            isSelected: isDetailedView,
            onTap: () => onViewToggle?.call(true),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOnlyToggle() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption(
            label: 'Active Only',
            isSelected: activeOnly,
            onTap: () => onActiveOnlyChanged?.call(true),
          ),
          _buildToggleOption(
            label: 'All Sizes',
            isSelected: !activeOnly,
            onTap: () => onActiveOnlyChanged?.call(false),
          ),
        ],
      ),
    );
  }



  Widget _buildToggleOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? const Color(0xFFD32F2F)
                : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
