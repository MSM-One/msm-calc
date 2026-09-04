import 'package:flutter/material.dart';
import '../../services/data_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/sorting_utils.dart';

/// A card displaying a low stock item with corporate enterprise standards,
/// supporting zero-quantity neutral styling and critical warning deep red styling.
class LowStockItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const LowStockItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    // Robust key bindings mapping from Supabase payload or local object representation
    final String rawSize = item['size_description']?.toString() ??
        item['size_label']?.toString() ??
        item['size']?.toString() ??
        'N/A';
    final String sizeDescription = getFormattedSizeDisplay(
      rawSize,
      item['weight'] ??
          item['unit_weight_kg'] ??
          item['weight_pcs'] ??
          item['weight_val'],
    );

    final String itemName = item['item_name']?.toString() ??
        item['itemName']?.toString() ??
        item['item']?.toString() ??
        'Unknown Item';

    final double qty = ((item['low_stock_qty'] ??
            item['net_stock_mt'] ??
            item['qty'] ??
            item['currentStockMT'] ??
            0.0) as num)
        .toDouble();

    final bool isDeficit = qty < -0.0001;
    final bool isZero = !isDeficit && qty.abs() <= 0.0001;
    final bool isZeroOrDeficit = isDeficit || isZero;

    // Enterprise Visual Rules & Style Mapping
    // Zero & Deficit in Crimson Red (#DC2626), Low Stock in Amber/Orange (#D97706)
    final Color badgeColor =
        isZeroOrDeficit ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
    final Color iconColor =
        isZeroOrDeficit ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final IconData statusIcon = isDeficit
        ? Icons.error_outline_rounded
        : (isZero ? Icons.cancel_outlined : Icons.warning_amber_rounded);
    final String statusText = isDeficit
        ? "DEFICIT"
        : (isZero ? "OUT OF STOCK" : "LOW STOCK");
    final Color qtyColor =
        isZeroOrDeficit ? const Color(0xFFDC2626) : const Color(0xFF0F172A);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isZeroOrDeficit
              ? const Color(0xFFFECACA)
              : Colors.grey.shade100,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon status badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              statusIcon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          // Size & Status Text Block
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  itemName,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  sizeDescription,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Quantity Metric
          Text(
            "${qty.toStringAsFixed(3)} MT",
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: qtyColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// A standalone screen wrapper for displaying Low Stock alerts as an accordion.
class LowStockReportScreen extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const LowStockReportScreen({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final Map<dynamic, Map<String, dynamic>> uniqueSizesMap = {};
    for (var item in items) {
      final sizeId = item['size_id'] ??
          item['size_label'] ??
          item['size_description'] ??
          '${item['item_name'] ?? item['itemName'] ?? item['item']}|${item['size']}';

      double getItemQty(Map<String, dynamic> m) {
        return ((m['low_stock_qty'] ??
                m['closing_mt'] ??
                m['closing_qty'] ??
                m['net_stock_mt'] ??
                m['qty'] ??
                m['currentStockMT'] ??
                0.0) as num)
            .toDouble();
      }

      if (!uniqueSizesMap.containsKey(sizeId)) {
        final newItem = Map<String, dynamic>.from(item);
        final q = getItemQty(newItem);
        newItem['low_stock_qty'] = q;
        newItem['closing_mt'] = q;
        newItem['closing_qty'] = q;
        newItem['net_stock_mt'] = q;
        newItem['qty'] = q;
        newItem['currentStockMT'] = q;
        uniqueSizesMap[sizeId] = newItem;
      } else {
        // Aggregate tonnage if multi-location entries exist
        final existingQty = getItemQty(uniqueSizesMap[sizeId]!);
        final newQty = getItemQty(item);
        final aggregated = existingQty + newQty;
        uniqueSizesMap[sizeId]!['low_stock_qty'] = aggregated;
        uniqueSizesMap[sizeId]!['closing_mt'] = aggregated;
        uniqueSizesMap[sizeId]!['closing_qty'] = aggregated;
        uniqueSizesMap[sizeId]!['net_stock_mt'] = aggregated;
        uniqueSizesMap[sizeId]!['qty'] = aggregated;
        uniqueSizesMap[sizeId]!['currentStockMT'] = aggregated;
      }
    }

    final List<Map<String, dynamic>> deduplicatedList =
        uniqueSizesMap.values.toList();

    // Group items by category
    final Map<String, List<Map<String, dynamic>>> groupedItems = {};
    for (var item in deduplicatedList) {
      final String rawCat = (item['category_name'] ??
              item['category'] ??
              item['item_name'] ??
              item['itemName'] ??
              'General')
          .toString()
          .trim();
      final String categoryName = DataRepository.canonicalizeCategory(rawCat);
      groupedItems.putIfAbsent(categoryName, () => []);
      groupedItems[categoryName]!.add(item);
    }
    final List<String> sortedCategories = groupedItems.keys.toList()
      ..sort(SortingUtils.compareCategories);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      appBar: AppBar(
        title: const Text("Low Stock Alert Details"),
        backgroundColor: const Color(0xFFB71C1C),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
      ),
      body: items.isEmpty
          ? const Center(
              child: Text(
                "All stock levels healthy",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedCategories.length,
              itemBuilder: (context, index) {
                final categoryName = sortedCategories[index];
                final categoryProducts = groupedItems[categoryName]!;

                // Sort items within category: Out of stock (0.000) & Deficit (<0) first, then lowest stock
                categoryProducts.sort((a, b) {
                  final double qtyA = ((a['closing_qty'] ??
                          a['low_stock_qty'] ??
                          a['net_stock_mt'] ??
                          a['qty'] ??
                          a['currentStockMT'] ??
                          0.0) as num)
                      .toDouble();
                  final double qtyB = ((b['closing_qty'] ??
                          b['low_stock_qty'] ??
                          b['net_stock_mt'] ??
                          b['qty'] ??
                          b['currentStockMT'] ??
                          0.0) as num)
                      .toDouble();

                  final bool aZeroOrDeficit = qtyA <= 0.0001;
                  final bool bZeroOrDeficit = qtyB <= 0.0001;
                  if (aZeroOrDeficit && !bZeroOrDeficit) return -1;
                  if (!aZeroOrDeficit && bZeroOrDeficit) return 1;

                  final qtyComp = qtyA.compareTo(qtyB);
                  if (qtyComp != 0) return qtyComp;

                  final sizeA = (a['size_label'] ??
                          a['size_description'] ??
                          a['size'] ??
                          '')
                      .toString();
                  final sizeB = (b['size_label'] ??
                          b['size_description'] ??
                          b['size'] ??
                          '')
                      .toString();
                  return SortingUtils.compareSizes(sizeA, sizeB);
                });

                // Calculate subtotal
                double subtotal = 0.0;
                for (var product in categoryProducts) {
                  final double qty = ((product['closing_qty'] ??
                          product['low_stock_qty'] ??
                          product['net_stock_mt'] ??
                          product['qty'] ??
                          product['currentStockMT'] ??
                          0.0) as num)
                      .toDouble();
                  subtotal += qty;
                }
                final String subtotalText = "${subtotal.toStringAsFixed(3)} MT";

                return Card(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: Text(
                      categoryName.toUpperCase(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    subtitle: Text(
                      subtotalText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB71C1C),
                        fontSize: 13,
                      ),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB71C1C),
                        size: 20,
                      ),
                    ),
                    trailing: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.grey),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    childrenPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: categoryProducts.map((product) {
                      final String rawSize = (product['size_label'] ??
                              product['size_description'] ??
                              product['size'] ??
                              'N/A')
                          .toString();

                      final String sizeLabelFormatted = getFormattedSizeDisplay(
                        rawSize,
                        product['weight'] ??
                            product['unit_weight_kg'] ??
                            product['weight_pcs'] ??
                            product['weight_val'],
                      );

                      final double qty = ((product['closing_qty'] ??
                              product['low_stock_qty'] ??
                              product['net_stock_mt'] ??
                              product['qty'] ??
                              product['currentStockMT'] ??
                              0.0) as num)
                          .toDouble();

                      final String itemName = (product['item_name'] ??
                              product['itemName'] ??
                              product['item'] ??
                              'Unknown')
                          .toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "$itemName - $sizeLabelFormatted",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: qty <= 0.0001
                                      ? const Color(0xFFFEE2E2)
                                      : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  qty < -0.0001
                                      ? "DEFICIT"
                                      : (qty.abs() <= 0.0001
                                          ? "OUT OF STOCK"
                                          : "LOW STOCK"),
                                  style: TextStyle(
                                    color: qty <= 0.0001
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFFD97706),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Text(
                            "${qty.toStringAsFixed(3)} MT",
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: qty <= 0.0001
                                    ? const Color(0xFFDC2626)
                                    : Colors.black87),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
    );
  }
}
