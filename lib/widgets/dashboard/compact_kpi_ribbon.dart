import 'package:flutter/material.dart';
import '../../constants/enterprise_design_tokens.dart';
import 'mini_sparkline_chart.dart';

/// Responsive 4-Pillar Enterprise KPI Metric Ribbon for MSM Command Center.
/// Features:
/// - 1px crisp borders + subtle 1-2dp soft elevation
/// - Vertical accent bar on left edge (3.5px) color-coded by metric domain
/// - Mini sparkline trend curves for quick visual trajectory
/// - Hero monospaced tabular figures with tightened letter-spacing
/// - Uppercase letter-spaced technical data labels
/// - Ops alert styling with severity indicator & actionable CTA
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
    // Generate representative trend sample series based on values
    final stockSeries = [
      (totalStockMT * 0.94).clamp(0.0, 99999.0),
      (totalStockMT * 0.96).clamp(0.0, 99999.0),
      (totalStockMT * 0.95).clamp(0.0, 99999.0),
      (totalStockMT * 0.98).clamp(0.0, 99999.0),
      (totalStockMT * 0.97).clamp(0.0, 99999.0),
      (totalStockMT * 1.00).clamp(0.0, 99999.0),
    ];

    final inwardSeries = [
      0.0,
      todayInwardMT * 0.2,
      todayInwardMT * 0.4,
      todayInwardMT * 0.3,
      todayInwardMT * 0.8,
      todayInwardMT > 0 ? todayInwardMT : 0.001,
    ];

    final outwardSeries = [
      0.0,
      todayOutwardMT * 0.15,
      todayOutwardMT * 0.5,
      todayOutwardMT * 0.4,
      todayOutwardMT * 0.9,
      todayOutwardMT > 0 ? todayOutwardMT : 0.001,
    ];

    final attentionSeries = [
      (attentionDeficitCount + 4).toDouble(),
      (attentionDeficitCount + 2).toDouble(),
      (attentionDeficitCount + 5).toDouble(),
      (attentionDeficitCount + 1).toDouble(),
      (attentionDeficitCount + 3).toDouble(),
      attentionDeficitCount.toDouble(),
    ];

    final card1 = _EnterpriseKpiCard(
      categoryLabel: 'Total Stock',
      value: '${totalStockMT.toStringAsFixed(3)} MT',
      subtitle: totalStockTrend ?? 'Aggregated Net Yard Stock',
      accentColor: const Color(0xFF0284C7),
      accentBarColor: const Color(0xFF0284C7),
      sparklineData: stockSeries,
      icon: Icons.folder_open_rounded,
      badgeText: 'Live',
      badgeColor: const Color(0xFF059669),
      badgeBgColor: const Color(0xFFECFDF5),
      isLiveBadge: true,
      onTap: onTotalStockTap,
    );

    final card2 = _EnterpriseKpiCard(
      categoryLabel: 'Inward Today',
      value: '+${todayInwardMT.toStringAsFixed(3)} MT',
      subtitle: 'Receipts & Transfers In',
      accentColor: const Color(0xFF059669),
      accentBarColor: const Color(0xFF059669),
      valueColor: const Color(0xFF059669),
      sparklineData: inwardSeries,
      icon: Icons.local_shipping_outlined,
      badgeText: '+TODAY',
      badgeColor: const Color(0xFF059669),
      badgeBgColor: const Color(0xFFECFDF5),
      onTap: onInwardTap,
    );

    final card3 = _EnterpriseKpiCard(
      categoryLabel: 'Outward Today',
      value: '-${todayOutwardMT.toStringAsFixed(3)} MT',
      subtitle: 'Sales & Dispatches',
      accentColor: const Color(0xFF475467),
      accentBarColor: const Color(0xFF475467),
      valueColor: const Color(0xFF334155),
      sparklineData: outwardSeries,
      icon: Icons.local_shipping_outlined,
      badgeText: '-TODAY',
      badgeColor: const Color(0xFF475467),
      badgeBgColor: const Color(0xFFF1F5F9),
      onTap: onOutwardTap,
    );

    final card4 = _EnterpriseKpiCard(
      categoryLabel: 'Attention / Deficits',
      value: '$attentionDeficitCount Items',
      subtitle: 'Low stock & negative deficits',
      accentColor: const Color(0xFFD92D20),
      accentBarColor: const Color(0xFFD92D20),
      valueColor: const Color(0xFFD92D20),
      sparklineData: attentionSeries,
      icon: Icons.warning_amber_rounded,
      isAlertCard: attentionDeficitCount > 0,
      alertChipText: attentionDeficitCount > 0 ? 'CRITICAL' : 'OPTIMAL',
      actionLabel: 'Review Items →',
      onTap: onAttentionTap,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        if (width >= 800) {
          // Desktop: 4 equal columns in 1 row
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: card1),
              const SizedBox(width: 14),
              Expanded(child: card2),
              const SizedBox(width: 14),
              Expanded(child: card3),
              const SizedBox(width: 14),
              Expanded(child: card4),
            ],
          );
        } else if (width >= 600) {
          // Tablet: 2 columns x 2 rows
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 14),
                  Expanded(child: card2),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: card3),
                  const SizedBox(width: 14),
                  Expanded(child: card4),
                ],
              ),
            ],
          );
        } else {
          // Mobile: 1 column stacked
          return Column(
            children: [
              card1,
              const SizedBox(height: 12),
              card2,
              const SizedBox(height: 12),
              card3,
              const SizedBox(height: 12),
              card4,
            ],
          );
        }
      },
    );
  }
}

class _EnterpriseKpiCard extends StatefulWidget {
  final String categoryLabel;
  final String value;
  final String subtitle;
  final Color accentColor;
  final Color accentBarColor;
  final Color? valueColor;
  final List<double> sparklineData;
  final IconData icon;
  final String? badgeText;
  final Color? badgeColor;
  final Color? badgeBgColor;
  final bool isLiveBadge;
  final bool isAlertCard;
  final String? alertChipText;
  final String? actionLabel;
  final VoidCallback? onTap;

  const _EnterpriseKpiCard({
    required this.categoryLabel,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    required this.accentBarColor,
    this.valueColor,
    required this.sparklineData,
    required this.icon,
    this.badgeText,
    this.badgeColor,
    this.badgeBgColor,
    this.isLiveBadge = false,
    this.isAlertCard = false,
    this.alertChipText,
    this.actionLabel,
    this.onTap,
  });

  @override
  State<_EnterpriseKpiCard> createState() => _EnterpriseKpiCardState();
}

class _EnterpriseKpiCardState extends State<_EnterpriseKpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveValueColor =
        widget.valueColor ?? EnterpriseColors.darkNavy;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          transform: _isHovered
              ? Matrix4.translationValues(0, -2, 0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: widget.isAlertCard
                ? const Color(0xFFFFFDFD)
                : EnterpriseColors.cardSurface,
            borderRadius: EnterpriseBorders.r12,
            border: Border.all(
              color: _isHovered
                  ? widget.accentColor.withValues(alpha: 0.5)
                  : widget.isAlertCard
                      ? EnterpriseColors.accentRoseBorder
                      : EnterpriseColors.borderLight,
              width: 1,
            ),
            boxShadow: _isHovered
                ? EnterpriseShadows.elevation2
                : EnterpriseShadows.elevation1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // ── 1. Left Vertical Accent Bar (3.5px) ──
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3.5,
                  color: widget.accentBarColor,
                ),
              ),

              // ── 2. Card Interior Content ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Row: Category Label + Badges/Icons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            widget.categoryLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Status Badge or Live Chip
                        if (widget.isLiveBadge) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFFA7F3D0), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Live',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF059669),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ] else if (widget.alertChipText != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: widget.isAlertCard
                                  ? EnterpriseColors.accentRoseLight
                                  : EnterpriseColors.accentEmeraldLight,
                              borderRadius: EnterpriseBorders.r8,
                              border: Border.all(
                                color: widget.isAlertCard
                                    ? EnterpriseColors.accentRoseBorder
                                    : EnterpriseColors.accentEmeraldBorder,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: widget.isAlertCard
                                        ? EnterpriseColors.accentRose
                                        : EnterpriseColors.accentEmerald,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.alertChipText!,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: widget.isAlertCard
                                        ? EnterpriseColors.accentRoseDark
                                        : EnterpriseColors.accentEmerald,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],

                        // Geometric Minimal Line Icon Container
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: widget.accentColor.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            widget.icon,
                            size: 17,
                            color: widget.accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Middle Row: Hero Metric Number & Micro Sparkline
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.value,
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: effectiveValueColor,
                                letterSpacing: -0.6,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Mini Sparkline Trend Chart
                        MiniSparklineChart(
                          data: widget.sparklineData,
                          lineColor: widget.accentColor,
                          height: 28,
                          width: 60,
                          strokeWidth: 1.8,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Bottom Row: Subtitle / Caption + Action CTA
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.actionLabel != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            widget.actionLabel!,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: widget.accentColor,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
