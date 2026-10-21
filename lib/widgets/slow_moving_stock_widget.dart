import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../constants/app_colors.dart';
import '../models/report_models.dart';
import '../services/data_repository.dart';
import '../screens/inventory_history_screen.dart';
import '../utils/formatters.dart';

class SlowMovingStockWidget extends StatelessWidget {
  const SlowMovingStockWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DeadStockEntry>>(
      valueListenable: DataRepository.nonMovingStockNotifier,
      builder: (context, deadItems, _) {
        if (deadItems.isEmpty) return const SizedBox.shrink();

        // Only show top 5 as requested
        final displayItems = deadItems.take(5).toList();

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.amber.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: FaIcon(
                        FontAwesomeIcons.triangleExclamation,
                        color: Colors.amber[800],
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Attention: Slow Moving Stock",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayItems.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 60),
                itemBuilder: (context, index) {
                  final item = displayItems[index];
                  final bool neverSold = item.daysSinceLastMovement >= 999;

                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TransactionHistoryScreen(
                            filterItem: item.itemName,
                            filterSize: item.size,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  getFormattedSizeDisplay(item.size, null),
                                  style: TextStyle(
                                    color: textGrey.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "${item.currentQty.toStringAsFixed(3)} MT",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: textDark,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                neverSold
                                    ? "Never Sold"
                                    : "${item.daysSinceLastMovement} days idle",
                                style: TextStyle(
                                  color:
                                      Colors.amber[900]?.withValues(alpha: 0.8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right,
                              size: 16, color: textGrey.withValues(alpha: 0.3)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
