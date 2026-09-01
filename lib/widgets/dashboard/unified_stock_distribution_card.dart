import 'package:flutter/material.dart';

/// Unified Stock Distribution Comparison Card.
/// Combines Yard Stock & Factory Stock into a single dual-progress comparison widget:
/// - Yard Stock (X.X% • XXX.XXX MT) in brand red (#D32F2F)
/// - Factory Stock (Y.Y% • YYY.YYY MT) in subtle slate (#94A3B8)
/// - Clean segmented progress bar showing distribution ratio.
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline_rounded,
                      size: 18,
                      color: Color(0xFFD32F2F),
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Stock Distribution',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '• Location Allocation Ratio',
                        style: TextStyle(
                          fontSize: 11.5,
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
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  'Total: ${totalStockMT.toStringAsFixed(3)} MT',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Dual Metrics Indicators
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;

              final yardWidget = _buildLocationStat(
                name: 'Yard Stock',
                icon: Icons.warehouse_rounded,
                weightMT: yardStockMT,
                percentage: yardPctDisplay,
                accentColor: const Color(0xFFD32F2F),
                trend: yardTrend,
                onTap: onYardTap,
              );

              final factoryWidget = _buildLocationStat(
                name: 'Factory Stock',
                icon: Icons.factory_rounded,
                weightMT: factoryStockMT,
                percentage: factoryPctDisplay,
                accentColor: const Color(0xFF64748B),
                trend: factoryTrend,
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
                    const SizedBox(width: 16),
                    Expanded(child: factoryWidget),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 14),

          // Segmented Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 10,
              width: double.infinity,
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  if (yardPct > 0)
                    Flexible(
                      flex: (yardPct * 1000).toInt(),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ),
                  if (factoryPct > 0)
                    Flexible(
                      flex: (factoryPct * 1000).toInt(),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF94A3B8),
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
          const SizedBox(height: 8),

          // Legend Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD32F2F),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Yard (${yardPctDisplay.toStringAsFixed(1)}%)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
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
                      color: Color(0xFF94A3B8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Factory (${factoryPctDisplay.toStringAsFixed(1)}%)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStat({
    required String name,
    required IconData icon,
    required double weightMT,
    required double percentage,
    required Color accentColor,
    String? trend,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${weightMT.toStringAsFixed(3)} MT',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (trend != null)
                Text(
                  trend,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
