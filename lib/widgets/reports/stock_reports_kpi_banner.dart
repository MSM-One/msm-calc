import 'package:flutter/material.dart';

/// Compact Horizontal Metric Ribbon for Stock Reports & Analytics.
/// Height: 48px, Background: #FFFFFF, Bottom Border: 1px solid #E2E8F0.
/// Displays summary pills inline:
/// - Total Stock: 530.800 MT (Slate)
/// - Period In: +31.960 MT (Emerald Green)
/// - Period Out: -60.020 MT (Crimson Red)
/// - Alerts: 2 (Amber/Red chip)
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
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Total Stock Pill
            _buildMetricPill(
              label: 'Total Stock',
              value: '${totalStockMT.toStringAsFixed(3)} MT',
              valueColor: const Color(0xFF0F172A), // Slate 900
              badgeBg: const Color(0xFFF1F5F9), // Slate 100
              badgeBorder: const Color(0xFFCBD5E1),
              icon: Icons.inventory_2_rounded,
              iconColor: const Color(0xFF475569),
              onTap: onTotalStockTap,
            ),
            const SizedBox(width: 10),

            // 2. Period In Pill
            _buildMetricPill(
              label: 'Period In',
              value: '+${inwardMT.toStringAsFixed(3)} MT',
              valueColor: const Color(0xFF059669), // Emerald 600
              badgeBg: const Color(0xFFECFDF5), // Emerald 50
              badgeBorder: const Color(0xFFA7F3D0),
              icon: Icons.arrow_downward_rounded,
              iconColor: const Color(0xFF059669),
              onTap: onInwardTap,
            ),
            const SizedBox(width: 10),

            // 3. Period Out Pill
            _buildMetricPill(
              label: 'Period Out',
              value: '-${outwardMT.toStringAsFixed(3)} MT',
              valueColor: const Color(0xFFDC2626), // Crimson Red
              badgeBg: const Color(0xFFFEF2F2), // Red 50
              badgeBorder: const Color(0xFFFECACA),
              icon: Icons.arrow_upward_rounded,
              iconColor: const Color(0xFFDC2626),
              onTap: onOutwardTap,
            ),
            const SizedBox(width: 10),

            // 4. Alerts Pill
            _buildAlertPill(
              count: criticalAlertsCount,
              onTap: onAlertsTap,
            ),

            if (locationLabel != 'All Locations' && locationLabel.isNotEmpty) ...[
              const SizedBox(width: 12),
              Container(
                height: 20,
                width: 1,
                color: const Color(0xFFE2E8F0),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      locationLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required String value,
    required Color valueColor,
    required Color badgeBg,
    required Color badgeBorder,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: badgeBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(
              '$label: ',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: valueColor,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertPill({
    required int count,
    VoidCallback? onTap,
  }) {
    final bool hasAlerts = count > 0;
    final Color bg =
        hasAlerts ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC);
    final Color border =
        hasAlerts ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0);
    final IconData icon = hasAlerts
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline_rounded;
    final Color iconCol =
        hasAlerts ? const Color(0xFFDC2626) : const Color(0xFF10B981);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconCol),
            const SizedBox(width: 6),
            const Text(
              'Alerts: ',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: hasAlerts
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: hasAlerts ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
