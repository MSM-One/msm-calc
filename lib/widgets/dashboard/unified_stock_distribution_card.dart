import 'package:flutter/material.dart';
import '../../constants/enterprise_design_tokens.dart';

/// Stock Distribution & Location Allocation Ratio Card for MSM Command Center.
/// Features:
/// - Header: "LOCATION ALLOCATION & RATIO" + Total Metric Chip ("687.235 MT NET")
/// - Dual Ratio Panels: Yard Stock (Steel Navy) and Factory Stock (Charcoal Slate)
/// - Segmented multi-tone progress bar with high contrast
/// - Clean legend underneath with precise percentages
class UnifiedStockDistributionCard extends StatelessWidget {
  final double yardStockMT;
  final double factoryStockMT;
  final double totalStockMT;
  final String? yardTrend;
  final String? factoryTrend;
  final VoidCallback? onYardTap;
  final VoidCallback? onFactoryTap;

  const UnifiedStockDistributionCard({
    super.key,
    required this.yardStockMT,
    required this.factoryStockMT,
    required this.totalStockMT,
    this.yardTrend,
    this.factoryTrend,
    this.onYardTap,
    this.onFactoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final double safeTotal = totalStockMT > 0 ? totalStockMT : 0.0001;
    final double yardPct =
        totalStockMT > 0 ? (yardStockMT / safeTotal).clamp(0.0, 1.0) : 0.0;
    final double factoryPct =
        totalStockMT > 0 ? (factoryStockMT / safeTotal).clamp(0.0, 1.0) : 0.0;

    final double yardPctDisplay = yardPct * 100;
    final double factoryPctDisplay = factoryPct * 100;

    return Container(
      decoration: BoxDecoration(
        color: EnterpriseColors.cardSurface,
        borderRadius: EnterpriseBorders.r14,
        border: Border.all(color: EnterpriseColors.borderLight, width: 1),
        boxShadow: EnterpriseShadows.elevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top Accent Bar ──
          Container(
            height: 3.0,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFCC2127),
                  EnterpriseColors.darkNavy,
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row: Pie chart icon + "Stock Distribution · Location Allocation Ratio", right badge "Total: X.XXX MT"
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFFECDCA),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.pie_chart_outline_rounded,
                              size: 16,
                              color: Color(0xFFCC2127),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Stock Distribution',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '· Location Allocation Ratio',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFCBD5E1), width: 1),
                      ),
                      child: Text(
                        'Total: ${totalStockMT.toStringAsFixed(3)} MT',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Dual Ratio Panels
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;

                    final yardWidget = _buildLocationPanel(
                      name: 'Yard Stock',
                      icon: Icons.warehouse_outlined,
                      weightMT: yardStockMT,
                      percentage: yardPctDisplay,
                      accentBarColor: const Color(0xFFCC2127),
                      iconColor: const Color(0xFFCC2127),
                      iconBgColor: const Color(0xFFFEF3F2),
                      iconBorderColor: const Color(0xFFFECDCA),
                      onTap: onYardTap,
                    );

                    final factoryWidget = _buildLocationPanel(
                      name: 'Factory Stock',
                      icon: Icons.factory_outlined,
                      weightMT: factoryStockMT,
                      percentage: factoryPctDisplay,
                      accentBarColor: const Color(0xFF64748B),
                      iconColor: const Color(0xFF475467),
                      iconBgColor: const Color(0xFFF1F5F9),
                      iconBorderColor: const Color(0xFFE2E8F0),
                      onTap: onFactoryTap,
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          yardWidget,
                          const SizedBox(height: 10),
                          factoryWidget,
                        ],
                      );
                    } else {
                      return Row(
                        children: [
                          Expanded(child: yardWidget),
                          const SizedBox(width: 12),
                          Expanded(child: factoryWidget),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Rounded Segmented Dual-Color Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 8,
                    width: double.infinity,
                    color: const Color(0xFFF1F5F9),
                    child: Row(
                      children: [
                        if (yardPct > 0)
                          Flexible(
                            flex: (yardPct * 1000).toInt().clamp(1, 1000),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFFCC2127),
                              ),
                            ),
                          ),
                        if (factoryPct > 0)
                          Flexible(
                            flex: (factoryPct * 1000).toInt().clamp(1, 1000),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        if (yardPct == 0 && factoryPct == 0)
                          Expanded(
                            child: Container(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Clean Technical Legend Underneath with circular dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFCC2127),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Yard (${yardPctDisplay.toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475467),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF64748B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Factory (${factoryPctDisplay.toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475467),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPanel({
    required String name,
    required IconData icon,
    required double weightMT,
    required double percentage,
    required Color accentBarColor,
    required Color iconColor,
    required Color iconBgColor,
    required Color iconBorderColor,
    VoidCallback? onTap,
  }) {
    return _InteractivePanel(
      onTap: onTap,
      accentBarColor: accentBarColor,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: EnterpriseBorders.r8,
              border: Border.all(color: iconBorderColor, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: EnterpriseTypography.dataLabel,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${percentage.toStringAsFixed(1)}% · ${weightMT.toStringAsFixed(3)} MT',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: EnterpriseColors.darkNavy,
                      letterSpacing: -0.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: EnterpriseColors.textSubtle,
          ),
        ],
      ),
    );
  }
}

class _InteractivePanel extends StatefulWidget {
  final Widget child;
  final Color accentBarColor;
  final VoidCallback? onTap;

  const _InteractivePanel({
    required this.child,
    required this.accentBarColor,
    this.onTap,
  });

  @override
  State<_InteractivePanel> createState() => _InteractivePanelState();
}

class _InteractivePanelState extends State<_InteractivePanel> {
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          transform: _isHovered
              ? Matrix4.translationValues(0, -2, 0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: _isHovered
                ? EnterpriseColors.cardSurfaceHover
                : EnterpriseColors.backgroundSecondary,
            borderRadius: EnterpriseBorders.r10,
            border: Border.all(
              color: _isHovered
                  ? widget.accentBarColor.withValues(alpha: 0.5)
                  : EnterpriseColors.borderLight,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3.0,
                  color: widget.accentBarColor,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
