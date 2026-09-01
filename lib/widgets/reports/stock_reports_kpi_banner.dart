import 'package:flutter/material.dart';

/// Enterprise KPI Banner Strip for Stock Analytics Dashboard.
/// Displays 4 high-impact metric cards:
/// 1. Total Yard Stock (MT)
/// 2. Today's Inward (MT)
/// 3. Today's Outward (MT)
/// 4. Critical Alerts (Negative Balances & Low Stock)
class StockReportsKpiBanner extends StatelessWidget {
  final double totalStockMT;
  final double inwardMT;
  final double outwardMT;
  final int criticalAlertsCount;
  final String locationLabel;
  final String dateRangeLabel;
  final VoidCallback? onTotalStockTap;
  final VoidCallback? onInwardTap;
  final VoidCallback? onOutwardTap;
  final VoidCallback? onAlertsTap;

  const StockReportsKpiBanner({
    super.key,
    required this.totalStockMT,
    required this.inwardMT,
    required this.outwardMT,
    required this.criticalAlertsCount,
    this.locationLabel = 'All Locations',
    this.dateRangeLabel = 'Today',
    this.onTotalStockTap,
    this.onInwardTap,
    this.onOutwardTap,
    this.onAlertsTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        // Desktop (> 960): 4 cards in a row
        if (width >= 960) {
          return Row(
            children: [
              Expanded(
                child: _KpiMetricCard(
                  title: 'Total Yard Stock',
                  subtitle: locationLabel,
                  value: '${totalStockMT.toStringAsFixed(3)} MT',
                  icon: Icons.warehouse_rounded,
                  accentColor: const Color(0xFF0F172A), // Slate 900
                  tintColor: const Color(0xFFF8FAFC),
                  indicatorLabel: 'Physical Balance',
                  indicatorIcon: Icons.layers_rounded,
                  indicatorColor: const Color(0xFF64748B),
                  onTap: onTotalStockTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KpiMetricCard(
                  title: "Today's Inward",
                  subtitle: dateRangeLabel,
                  value: '+${inwardMT.toStringAsFixed(3)} MT',
                  icon: Icons.trending_up_rounded,
                  accentColor: const Color(0xFF059669), // Emerald 600
                  tintColor: const Color(0xFFECFDF5), // Emerald 50
                  indicatorLabel: 'Incoming Receipts',
                  indicatorIcon: Icons.arrow_upward_rounded,
                  indicatorColor: const Color(0xFF059669),
                  onTap: onInwardTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KpiMetricCard(
                  title: "Today's Outward",
                  subtitle: dateRangeLabel,
                  value: '-${outwardMT.toStringAsFixed(3)} MT',
                  icon: Icons.local_shipping_rounded,
                  accentColor: const Color(0xFF2563EB), // Blue 600
                  tintColor: const Color(0xFFEFF6FF), // Blue 50
                  indicatorLabel: 'Dispatches / Sales',
                  indicatorIcon: Icons.arrow_downward_rounded,
                  indicatorColor: const Color(0xFF2563EB),
                  onTap: onOutwardTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KpiMetricCard(
                  title: 'Critical Alerts',
                  subtitle: 'Needs Attention',
                  value: '$criticalAlertsCount Items',
                  icon: Icons.warning_amber_rounded,
                  accentColor: const Color(0xFFDC2626), // Red 600
                  tintColor: const Color(0xFFFEF2F2), // Red 50
                  indicatorLabel: criticalAlertsCount > 0
                      ? 'Negative / Low Stock'
                      : 'All Stock Balanced',
                  indicatorIcon: criticalAlertsCount > 0
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  indicatorColor: criticalAlertsCount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF059669),
                  isAlert: criticalAlertsCount > 0,
                  onTap: onAlertsTap,
                ),
              ),
            ],
          );
        }

        // Tablet (560 - 959): 2x2 Grid
        if (width >= 560) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiMetricCard(
                      title: 'Total Yard Stock',
                      subtitle: locationLabel,
                      value: '${totalStockMT.toStringAsFixed(3)} MT',
                      icon: Icons.warehouse_rounded,
                      accentColor: const Color(0xFF0F172A),
                      tintColor: const Color(0xFFF8FAFC),
                      indicatorLabel: 'Physical Balance',
                      indicatorIcon: Icons.layers_rounded,
                      indicatorColor: const Color(0xFF64748B),
                      onTap: onTotalStockTap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiMetricCard(
                      title: "Today's Inward",
                      subtitle: dateRangeLabel,
                      value: '+${inwardMT.toStringAsFixed(3)} MT',
                      icon: Icons.trending_up_rounded,
                      accentColor: const Color(0xFF059669),
                      tintColor: const Color(0xFFECFDF5),
                      indicatorLabel: 'Incoming Receipts',
                      indicatorIcon: Icons.arrow_upward_rounded,
                      indicatorColor: const Color(0xFF059669),
                      onTap: onInwardTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _KpiMetricCard(
                      title: "Today's Outward",
                      subtitle: dateRangeLabel,
                      value: '-${outwardMT.toStringAsFixed(3)} MT',
                      icon: Icons.local_shipping_rounded,
                      accentColor: const Color(0xFF2563EB),
                      tintColor: const Color(0xFFEFF6FF),
                      indicatorLabel: 'Dispatches / Sales',
                      indicatorIcon: Icons.arrow_downward_rounded,
                      indicatorColor: const Color(0xFF2563EB),
                      onTap: onOutwardTap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiMetricCard(
                      title: 'Critical Alerts',
                      subtitle: 'Needs Attention',
                      value: '$criticalAlertsCount Items',
                      icon: Icons.warning_amber_rounded,
                      accentColor: const Color(0xFFDC2626),
                      tintColor: const Color(0xFFFEF2F2),
                      indicatorLabel: criticalAlertsCount > 0
                          ? 'Negative / Low Stock'
                          : 'All Stock Balanced',
                      indicatorIcon: criticalAlertsCount > 0
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      indicatorColor: criticalAlertsCount > 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF059669),
                      isAlert: criticalAlertsCount > 0,
                      onTap: onAlertsTap,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        // Mobile (< 560): Stacked / horizontal scroll cards
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              SizedBox(
                width: 240,
                child: _KpiMetricCard(
                  title: 'Total Yard Stock',
                  subtitle: locationLabel,
                  value: '${totalStockMT.toStringAsFixed(3)} MT',
                  icon: Icons.warehouse_rounded,
                  accentColor: const Color(0xFF0F172A),
                  tintColor: const Color(0xFFF8FAFC),
                  indicatorLabel: 'Physical Balance',
                  indicatorIcon: Icons.layers_rounded,
                  indicatorColor: const Color(0xFF64748B),
                  onTap: onTotalStockTap,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 240,
                child: _KpiMetricCard(
                  title: "Today's Inward",
                  subtitle: dateRangeLabel,
                  value: '+${inwardMT.toStringAsFixed(3)} MT',
                  icon: Icons.trending_up_rounded,
                  accentColor: const Color(0xFF059669),
                  tintColor: const Color(0xFFECFDF5),
                  indicatorLabel: 'Incoming Receipts',
                  indicatorIcon: Icons.arrow_upward_rounded,
                  indicatorColor: const Color(0xFF059669),
                  onTap: onInwardTap,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 240,
                child: _KpiMetricCard(
                  title: "Today's Outward",
                  subtitle: dateRangeLabel,
                  value: '-${outwardMT.toStringAsFixed(3)} MT',
                  icon: Icons.local_shipping_rounded,
                  accentColor: const Color(0xFF2563EB),
                  tintColor: const Color(0xFFEFF6FF),
                  indicatorLabel: 'Dispatches / Sales',
                  indicatorIcon: Icons.arrow_downward_rounded,
                  indicatorColor: const Color(0xFF2563EB),
                  onTap: onOutwardTap,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 240,
                child: _KpiMetricCard(
                  title: 'Critical Alerts',
                  subtitle: 'Needs Attention',
                  value: '$criticalAlertsCount Items',
                  icon: Icons.warning_amber_rounded,
                  accentColor: const Color(0xFFDC2626),
                  tintColor: const Color(0xFFFEF2F2),
                  indicatorLabel: criticalAlertsCount > 0
                      ? 'Negative / Low Stock'
                      : 'All Stock Balanced',
                  indicatorIcon: criticalAlertsCount > 0
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  indicatorColor: criticalAlertsCount > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF059669),
                  isAlert: criticalAlertsCount > 0,
                  onTap: onAlertsTap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiMetricCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color tintColor;
  final String indicatorLabel;
  final IconData indicatorIcon;
  final Color indicatorColor;
  final bool isAlert;
  final VoidCallback? onTap;

  const _KpiMetricCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.tintColor,
    required this.indicatorLabel,
    required this.indicatorIcon,
    required this.indicatorColor,
    this.isAlert = false,
    this.onTap,
  });

  @override
  State<_KpiMetricCard> createState() => _KpiMetricCardState();
}

class _KpiMetricCardState extends State<_KpiMetricCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _isHovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isAlert
                ? const Color(0xFFFCA5A5) // Red 300
                : (_isHovered
                    ? widget.accentColor.withValues(alpha: 0.35)
                    : const Color(0xFFE2E8F0)), // Slate 200
            width: widget.isAlert || _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isAlert
                  ? const Color(0xFFDC2626).withValues(alpha: 0.08)
                  : (_isHovered
                      ? const Color(0x14000000)
                      : const Color(0x06000000)),
              blurRadius: _isHovered ? 12 : 6,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Title + Icon Pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569), // Slate 600
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF94A3B8), // Slate 400
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: widget.tintColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.accentColor.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 20,
                          color: widget.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Primary Numeric Display
                  Text(
                    widget.value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: widget.isAlert
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F172A), // Slate 900
                      letterSpacing: -0.5,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Bottom Indicator Badge
                  Row(
                    children: [
                      Icon(
                        widget.indicatorIcon,
                        size: 13,
                        color: widget.indicatorColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.indicatorLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: widget.indicatorColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
