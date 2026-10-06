import 'package:flutter/material.dart';

/// Item descriptor for sub-reports in the analytics dashboard.
class ReportSubTabItem {
  final String id;
  final String label;
  final IconData icon;
  final int? badgeCount;
  final String? permission;

  const ReportSubTabItem({
    required this.id,
    required this.label,
    required this.icon,
    this.badgeCount,
    this.permission,
  });
}

/// Compact SegmentedControl / FilterBar for switching between sub-reports:
/// ['Today\'s Summary', 'Stock Movement', 'Stock Ledger', 'Low Stock', 'Non-Moving']
class ReportsSubTabBar extends StatelessWidget {
  final String activeTabId;
  final ValueChanged<String> onTabSelected;
  final List<ReportSubTabItem> tabs;

  static const List<ReportSubTabItem> defaultTabs = [
    ReportSubTabItem(
      id: 'today',
      label: "Today's Summary",
      icon: Icons.today_rounded,
    ),
    ReportSubTabItem(
      id: 'movement',
      label: 'Stock Movement',
      icon: Icons.swap_vert_rounded,
    ),
    ReportSubTabItem(
      id: 'ledger',
      label: 'Stock Ledger',
      icon: Icons.receipt_long_rounded,
    ),
    ReportSubTabItem(
      id: 'low',
      label: 'Low Stock',
      icon: Icons.warning_amber_rounded,
    ),
    ReportSubTabItem(
      id: 'nonmoving',
      label: 'Non-Moving',
      icon: Icons.hourglass_empty_rounded,
    ),
  ];

  const ReportsSubTabBar({
    super.key,
    required this.activeTabId,
    required this.onTabSelected,
    this.tabs = defaultTabs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate 100
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)), // Slate 200
      ),
      padding: const EdgeInsets.all(4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: tabs.map((tab) {
            final bool isSelected = activeTabId == tab.id;
            return _TabButton(
              item: tab,
              isSelected: isSelected,
              onTap: () => onTabSelected(tab.id),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  final ReportSubTabItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const Color brandRed = Color(0xFFD32F2F); // Solid brand red
    final bool isSelected = widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? brandRed
              : (_isHovered ? Colors.white : Colors.transparent),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected
                ? brandRed
                : (_isHovered
                    ? const Color(0xFFCBD5E1)
                    : Colors.transparent),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: brandRed.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : (_isHovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      )
                    ]
                  : null),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.item.icon,
                    size: 15,
                    color: isSelected
                        ? Colors.white
                        : (_isHovered
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF475569)), // Slate 600
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (_isHovered
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF334155)), // Slate 700
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (widget.item.badgeCount != null &&
                      widget.item.badgeCount! > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.25)
                            : const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.item.badgeCount}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
