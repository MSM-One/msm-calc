import 'package:flutter/material.dart';
import '../../constants/enterprise_design_tokens.dart';

/// Persistent Elevated Bottom Stock Summary Bar for Enterprise Command Center.
/// Structured as a clean mini data table row with right-aligned tabular values,
/// left-aligned domain labels, and vertical dividers.
class EnterpriseBottomStockBar extends StatelessWidget {
  final double totalStockMT;
  final double yardStockMT;
  final double factoryStockMT;
  final int attentionCount;
  final VoidCallback? onTap;

  const EnterpriseBottomStockBar({
    super.key,
    required this.totalStockMT,
    required this.yardStockMT,
    required this.factoryStockMT,
    required this.attentionCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EnterpriseColors.cardSurface,
        border: Border(
          top: BorderSide(color: EnterpriseColors.borderLight, width: 1),
        ),
        boxShadow: EnterpriseShadows.bottomBarShadow,
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 600;
                  return isNarrow ? _buildNarrowRow() : _buildWideRow();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Column: Domain & Location Summary
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: EnterpriseColors.darkNavy,
                borderRadius: EnterpriseBorders.r8,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.analytics_outlined,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AGGREGATED NET INVENTORY',
                  style: EnterpriseTypography.dataLabel,
                ),
                const SizedBox(height: 2),
                Text(
                  'Yard: ${yardStockMT.toStringAsFixed(3)} MT  ·  Factory: ${factoryStockMT.toStringAsFixed(3)} MT',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: EnterpriseColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),

        // Right Column: Tabular Hero Total & Action
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Vertical Divider
            Container(
              height: 30,
              width: 1,
              color: EnterpriseColors.borderLight,
            ),
            const SizedBox(width: 16),

            // Tabular Total
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NET YARD TOTAL',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: EnterpriseColors.textSubtle,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '${totalStockMT.toStringAsFixed(3)} MT',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: EnterpriseColors.darkNavy,
                    letterSpacing: -0.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: EnterpriseColors.textSecondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Column: Mini Data Table
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: EnterpriseColors.accentEmerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'NET YARD INVENTORY',
                    style: EnterpriseTypography.dataLabel,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Y: ${yardStockMT.toStringAsFixed(1)} MT · F: ${factoryStockMT.toStringAsFixed(1)} MT',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: EnterpriseColors.textSecondary,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Right Column: Aligned Tabular Value
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 28,
              width: 1,
              color: EnterpriseColors.borderLight,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${totalStockMT.toStringAsFixed(3)} MT',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: EnterpriseColors.darkNavy,
                    letterSpacing: -0.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const Text(
                  'TAP FOR LEDGER',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: EnterpriseColors.accentSteel,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: EnterpriseColors.textSubtle,
            ),
          ],
        ),
      ],
    );
  }
}
