import 'package:flutter/material.dart';

/// Compact 4-Pillar KPI Ribbon for Executive Dashboard.
/// Displays:
/// 1. Total Stock (MT) — Bold slate
/// 2. Inward Today (MT) — Emerald green (#059669)
/// 3. Outward Today (MT) — Dark slate (#1E293B)
/// 4. Attention / Deficits — Crimson badge (#DC2626)
class CompactKpiRibbon extends StatelessWidget {
  final double totalStockMT;
  final double todayInwardMT;
  final double todayOutwardMT;
  final int attentionDeficitCount;
  final String? totalStockTrend;
  final VoidCallback? onTotalStockTap;
  final VoidCallback? onInwardTap;
  final VoidCallback? onOutwardTap;
  final VoidCallback? onAttentionTap;

  const CompactKpiRibbon({
    super.key,
    required this.totalStockMT,
    required this.todayInwardMT,
    required this.todayOutwardMT,
    required this.attentionDeficitCount,
    this.totalStockTrend,
    this.onTotalStockTap,
    this.onInwardTap,
    this.onOutwardTap,
    this.onAttentionTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        if (width >= 900) {
          // 4 cards in a row
          return Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Total Stock',
                  value: '${totalStockMT.toStringAsFixed(3)} MT',
                  subtitle: totalStockTrend ?? 'Aggregated Net Yard Stock',
                  icon: Icons.inventory_2_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  iconBgColor: const Color(0xFFEFF6FF),
                  valueColor: const Color(0xFF0F172A),
                  badgeText: 'Live',
                  badgeColor: const Color(0xFF10B981),
                  badgeBgColor: const Color(0xFFECFDF5),
                  onTap: onTotalStockTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KpiCard(
                  title: 'Inward Today',
                  value: '+${todayInwardMT.toStringAsFixed(3)} MT',
                  subtitle: 'Receipts & Transfers In',
                  icon: Icons.local_shipping_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBgColor: const Color(0xFFECFDF5),
                  valueColor: const Color(0xFF059669),
                  isPositive: true,
                  onTap: onInwardTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KpiCard(
                  title: 'Outward Today',
                  value: '-${todayOutwardMT.toStringAsFixed(3)} MT',
                  subtitle: 'Sales & Dispatches',
                  icon: Icons.local_shipping_outlined,
                  iconColor: const Color(0xFF1E293B),
                  iconBgColor: const Color(0xFFF1F5F9),
                  valueColor: const Color(0xFF1E293B),
                  onTap: onOutwardTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KpiCard(
                  title: 'Attention / Deficits',
                  value: '$attentionDeficitCount Items',
                  subtitle: attentionDeficitCount > 0
                      ? 'Low stock & negative deficits'
                      : 'All item balances normal',
                  icon: Icons.warning_amber_rounded,
                  iconColor: const Color(0xFFDC2626),
                  iconBgColor: const Color(0xFFFEF2F2),
                  valueColor: const Color(0xFFDC2626),
                  isCritical: attentionDeficitCount > 0,
                  onTap: onAttentionTap,
                ),
              ),
            ],
          );
        } else if (width >= 560) {
          // 2x2 grid
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Total Stock',
                      value: '${totalStockMT.toStringAsFixed(3)} MT',
                      subtitle: totalStockTrend ?? 'Aggregated Net Yard Stock',
                      icon: Icons.inventory_2_rounded,
                      iconColor: const Color(0xFF3B82F6),
                      iconBgColor: const Color(0xFFEFF6FF),
                      valueColor: const Color(0xFF0F172A),
                      badgeText: 'Live',
                      badgeColor: const Color(0xFF10B981),
                      badgeBgColor: const Color(0xFFECFDF5),
                      onTap: onTotalStockTap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'Inward Today',
                      value: '+${todayInwardMT.toStringAsFixed(3)} MT',
                      subtitle: 'Receipts & Inflow',
                      icon: Icons.local_shipping_rounded,
                      iconColor: const Color(0xFF059669),
                      iconBgColor: const Color(0xFFECFDF5),
                      valueColor: const Color(0xFF059669),
                      isPositive: true,
                      onTap: onInwardTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Outward Today',
                      value: '-${todayOutwardMT.toStringAsFixed(3)} MT',
                      subtitle: 'Dispatches & Sales',
                      icon: Icons.local_shipping_outlined,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      valueColor: const Color(0xFF1E293B),
                      onTap: onOutwardTap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'Attention / Deficits',
                      value: '$attentionDeficitCount Items',
                      subtitle: attentionDeficitCount > 0
                          ? 'Low stock & deficits'
                          : 'Balances normal',
                      icon: Icons.warning_amber_rounded,
                      iconColor: const Color(0xFFDC2626),
                      iconBgColor: const Color(0xFFFEF2F2),
                      valueColor: const Color(0xFFDC2626),
                      isCritical: attentionDeficitCount > 0,
                      onTap: onAttentionTap,
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          // Mobile compact vertical list
          return Column(
            children: [
              _KpiCard(
                title: 'Total Stock',
                value: '${totalStockMT.toStringAsFixed(3)} MT',
                subtitle: totalStockTrend ?? 'Aggregated Net Yard Stock',
                icon: Icons.inventory_2_rounded,
                iconColor: const Color(0xFF3B82F6),
                iconBgColor: const Color(0xFFEFF6FF),
                valueColor: const Color(0xFF0F172A),
                badgeText: 'Live',
                badgeColor: const Color(0xFF10B981),
                badgeBgColor: const Color(0xFFECFDF5),
                onTap: onTotalStockTap,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Inward',
                      value: '+${todayInwardMT.toStringAsFixed(3)} MT',
                      subtitle: 'Today',
                      icon: Icons.local_shipping_rounded,
                      iconColor: const Color(0xFF059669),
                      iconBgColor: const Color(0xFFECFDF5),
                      valueColor: const Color(0xFF059669),
                      isPositive: true,
                      onTap: onInwardTap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiCard(
                      title: 'Outward',
                      value: '-${todayOutwardMT.toStringAsFixed(3)} MT',
                      subtitle: 'Today',
                      icon: Icons.local_shipping_outlined,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      valueColor: const Color(0xFF1E293B),
                      onTap: onOutwardTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _KpiCard(
                title: 'Attention / Deficits',
                value: '$attentionDeficitCount Items',
                subtitle: attentionDeficitCount > 0
                    ? 'Requires review & reorder'
                    : 'All balances healthy',
                icon: Icons.warning_amber_rounded,
                iconColor: const Color(0xFFDC2626),
                iconBgColor: const Color(0xFFFEF2F2),
                valueColor: const Color(0xFFDC2626),
                isCritical: attentionDeficitCount > 0,
                onTap: onAttentionTap,
              ),
            ],
          );
        }
      },
    );
  }
}

class _KpiCard extends StatefulWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final Color valueColor;
  final String? badgeText;
  final Color? badgeColor;
  final Color? badgeBgColor;
  final bool isPositive;
  final bool isCritical;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.valueColor,
    this.badgeText,
    this.badgeColor,
    this.badgeBgColor,
    this.isPositive = false,
    this.isCritical = false,
    this.onTap,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          transform: _isHovered
              ? Matrix4.translationValues(0, -2, 0)
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? widget.iconColor.withValues(alpha: 0.5)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.iconColor.withValues(alpha: 0.12)
                    : const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: _isHovered ? 12 : 8,
                offset: Offset(0, _isHovered ? 4 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Title + Icon + Optional Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.badgeText != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: widget.badgeBgColor ?? const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.badgeText!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: widget.badgeColor ?? const Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.iconBgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      widget.icon,
                      size: 17,
                      color: widget.iconColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Middle: Primary Metric Value
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.value,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: widget.valueColor,
                    letterSpacing: -0.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Bottom: Subtitle / Context
              Text(
                widget.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: widget.isCritical
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF94A3B8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
