import 'package:flutter/material.dart';
import '../models/report_models.dart';
import '../models/stock_models.dart';
import '../services/data_repository.dart';
import '../utils/item_order_util.dart';
import '../utils/sorting_utils.dart';

class _StockState {
  double qty = 0;
  DateTime lastMovement = DateTime(2000);
}

/// Centralized report calculation engine for MSM ERP.
class ReportCalculators {
  static List<StockMovementEntry> calculateStockMovement(
      List<StockTransaction> allTxs,
      List<dynamic> locations,
      DateTime start,
      DateTime end,
      String locationFilter) {
    final filterStart = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final filterEnd = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    Map<String, Map<String, StockMovementEntry>> map = {};

    // 1. Pre-populate map from active inventory list to preserve all catalog items
    for (final v in DataRepository.inventoryListNotifier.value) {
      if (locationFilter != 'ALL' &&
          v.location.toUpperCase() != locationFilter.toUpperCase()) {
        continue;
      }
      final String catName = DataRepository.canonicalizeCategory(v.category);
      if (['Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB']
              .contains(catName) &&
          v.currentStockMT == 0) {
        continue;
      }
      final String key =
          "${catName.toUpperCase()}_${v.itemName.toUpperCase()}";
      map.putIfAbsent(
          key,
          () => {
                v.itemName: StockMovementEntry(
                  category: catName,
                  item: v.itemName,
                  sizes: [],
                )
              });

      final entry = map[key]![v.itemName]!;
      if (!entry.sizes.any((s) => s.label == v.size)) {
        entry.sizes.add(StockSizeMovement(
          label: v.size,
          opening: 0,
          inQty: 0,
          outQty: 0,
          closing: 0,
        ));
      }
    }

    // 2. Iterate transactions
    final targetLoc = locationFilter.trim().toUpperCase();

    for (var tx in allTxs) {
      if (tx.isReversed) continue;
      if (tx.txnId.startsWith('S-17')) continue;
      if (tx.txnId.startsWith('IN_V_')) continue;

      final typeUpper = tx.type.trim().toUpperCase();
      if (typeUpper == 'PURCHASE') continue;

      final txLoc = tx.location.trim().toUpperCase();
      final toLoc = tx.toLocation?.trim().toUpperCase();

      bool isRelevant = false;
      bool isTransferIn = false;
      bool isTransferOut = false;

      if (targetLoc == 'ALL') {
        isRelevant = true;
      } else {
        if (txLoc == targetLoc) {
          isRelevant = true;
          if (tx.type.toUpperCase() == 'TRANSFER') {
            isTransferOut = true;
          }
        }
        if (toLoc == targetLoc && tx.type.toUpperCase() == 'TRANSFER') {
          isRelevant = true;
          isTransferIn = true;
        }
      }

      if (!isRelevant) continue;

      final String rawCat =
          (tx.category.trim().isNotEmpty && tx.category != "General")
              ? tx.category
              : tx.itemName;
      final String catName = DataRepository.canonicalizeCategory(rawCat);

      if (['Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB']
          .contains(catName)) {
        continue;
      }

      final String key =
          "${catName.toUpperCase()}_${tx.itemName.toUpperCase()}";
      if (!map.containsKey(key)) {
        map[key] = {
          tx.itemName: StockMovementEntry(
              category: catName, item: tx.itemName, sizes: [])
        };
      }

      var entry = map[key]![tx.itemName]!;
      var sizeEntry =
          entry.sizes.firstWhere((s) => s.label == tx.sizeLabel, orElse: () {
        var newSize = StockSizeMovement(
            label: tx.sizeLabel, opening: 0, inQty: 0, outQty: 0, closing: 0);
        entry.sizes.add(newSize);
        return newSize;
      });

      final txDate = tx.date;
      final txType = tx.type.toUpperCase();

      bool isAdd = false;
      bool isSub = false;

      if (targetLoc != 'ALL' && txType == 'TRANSFER') {
        if (isTransferIn) isAdd = true;
        if (isTransferOut) isSub = true;
      } else if (txType == 'TRANSFER') {
        isAdd = false;
        isSub = false;
      } else if (['IN', 'RETURN', 'OPENING', 'OPENING_STOCK', 'ADJUSTMENT']
          .contains(txType)) {
        if (txType == 'ADJUSTMENT' && tx.qty < 0) {
          isSub = true;
        } else {
          isAdd = true;
        }
      } else if (['OUT', 'OUTWARD', 'SALE', 'RESERVE'].contains(txType)) {
        isSub = true;
      }

      final bool isOpeningTxn = txType == 'OPENING' ||
          txType == 'OPENING_STOCK' ||
          tx.txnId.startsWith('OPENING-');

      final double qty = tx.qty.abs();

      if (txDate.isBefore(filterStart) || isOpeningTxn) {
        if (isAdd) sizeEntry.opening += qty;
        if (isSub) sizeEntry.opening -= qty;
      } else if (txDate.isAfter(filterEnd)) {
        // ignore future transactions beyond date range
      } else {
        if (isAdd) sizeEntry.inQty += qty;
        if (isSub) sizeEntry.outQty += qty;
      }

      sizeEntry.closing =
          sizeEntry.opening + sizeEntry.inQty - sizeEntry.outQty;
    }

    List<StockMovementEntry> list = [];
    map.forEach((cat, items) {
      for (var entry in items.values) {
        entry.sizes.removeWhere((s) =>
            s.opening == 0 && s.inQty == 0 && s.outQty == 0 && s.closing == 0);
        if (entry.sizes.isNotEmpty) {
          list.add(entry);
        }
      }
    });
    list.sort((a, b) => ItemOrderUtil.compare(a.category, b.category));
    for (var entry in list) {
      entry.sizes.sort((a, b) => SortingUtils.compareSizes(a.label, b.label));
    }
    return list;
  }

  static Map<String, Map<String, List<StockMovementEntry>>>
      groupStocksByCategoryAndItem(List<StockMovementEntry> reports) {
    Map<String, Map<String, List<StockMovementEntry>>> grouped = {};
    for (var r in reports) {
      final String cat = DataRepository.canonicalizeCategory(r.category);
      grouped.putIfAbsent(cat, () => {});
      grouped[cat]!.putIfAbsent(r.item, () => []);
      grouped[cat]![r.item]!.add(r);
    }
    return grouped;
  }

  static List<DeadStockEntry> calculateDeadStock(List<StockTransaction> allTxs,
      List<dynamic> locations, DateTime referenceDate) {
    final cutoff = referenceDate.subtract(const Duration(days: 15));
    Map<String, Map<String, _StockState>> stockMap = {};

    // 1. Initialize with all items from locations to handle items with NO movement
    for (var loc in locations) {
      if (loc == null || loc is! Map) continue;
      final rawItems = loc['items'];
      final Map<dynamic, dynamic> items = (rawItems is Map) ? rawItems : {};

      items.forEach((itemName, sizes) {
        if (itemName == null) return;
        stockMap.putIfAbsent(itemName.toString(), () => {});
        if (sizes is Map) {
          sizes.forEach((size, qty) {
            if (size == null) return;
            stockMap[itemName.toString()]!
                .putIfAbsent(size.toString(), () => _StockState());
            stockMap[itemName.toString()]![size.toString()]!.qty =
                (qty as num?)?.toDouble() ?? 0.0;
          });
        }
      });
    }

    // 2. Update with transaction history to find last movement
    for (var tx in allTxs) {
      final localDate = tx.date;
      final txDate = DateTime(localDate.year, localDate.month, localDate.day);
      final refDate =
          DateTime(referenceDate.year, referenceDate.month, referenceDate.day);

      if (txDate.isAfter(refDate)) continue;

      stockMap.putIfAbsent(tx.itemName, () => {});
      stockMap[tx.itemName]!.putIfAbsent(tx.sizeLabel, () => _StockState());

      var state = stockMap[tx.itemName]![tx.sizeLabel]!;
      final stateLastMovement = DateTime(state.lastMovement.year,
          state.lastMovement.month, state.lastMovement.day);
      if (txDate.isAfter(stateLastMovement)) {
        state.lastMovement = tx.date;
      }
    }

    List<DeadStockEntry> dead = [];
    stockMap.forEach((item, sizes) {
      sizes.forEach((size, state) {
        if (state.qty > 3.0) {
          bool isNonMoving = false;
          final stateLastMovement = DateTime(state.lastMovement.year,
              state.lastMovement.month, state.lastMovement.day);
          final deadCutoff = DateTime(cutoff.year, cutoff.month, cutoff.day);
          if (state.lastMovement.year < 2005) {
            isNonMoving = true;
          } else if (stateLastMovement.isBefore(deadCutoff)) {
            isNonMoving = true;
          }

          if (isNonMoving) {
            String category = "General";
            try {
              final txWithItem = allTxs.firstWhere((t) => t.itemName == item);
              category =
                  DataRepository.canonicalizeCategory(txWithItem.category);
            } catch (_) {
              category = DataRepository.canonicalizeCategory(item);
            }

            dead.add(DeadStockEntry(
              category: category,
              itemName: item,
              size: size,
              currentQty: state.qty,
              daysSinceLastMovement: state.lastMovement.year < 2005
                  ? -1
                  : referenceDate.difference(state.lastMovement).inDays,
              lastMovementDate:
                  state.lastMovement.year < 2005 ? null : state.lastMovement,
            ));
          }
        }
      });
    });

    dead.sort((a, b) {
      int catComp = ItemOrderUtil.compare(a.category, b.category);
      if (catComp != 0) return catComp;
      int itemComp = a.itemName.compareTo(b.itemName);
      if (itemComp != 0) return itemComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
    return dead;
  }

  static List<DailyMovementEntry> calculateDailyMovement(
      List<StockTransaction> allTxs,
      [DateTimeRange? dateRange,
      List<StockMovementEntry>? stockReport]) {
    final DateTime start = dateRange != null
        ? DateTime(
            dateRange.start.year, dateRange.start.month, dateRange.start.day)
        : DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final DateTime end = dateRange != null
        ? DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day,
            23, 59, 59, 999)
        : DateTime(DateTime.now().year, DateTime.now().month,
            DateTime.now().day, 23, 59, 59, 999);

    Map<String, DailyMovementEntry> map = {};

    if (stockReport != null && stockReport.isNotEmpty) {
      for (var entry in stockReport) {
        final String canonicalCat =
            DataRepository.canonicalizeCategory(entry.category);
        for (var s in entry.sizes) {
          final String key =
              "${canonicalCat.toUpperCase()}_${entry.item.toUpperCase()}_${s.label.toUpperCase()}";
          map[key] = DailyMovementEntry(
            category: canonicalCat,
            itemName: entry.item,
            size: s.label,
            openingQty: s.opening,
            inQty: s.inQty,
            outQty: s.outQty,
            closingQty: s.closing,
          );
        }
      }
    } else {
      for (var tx in allTxs) {
        if (tx.isReversed) continue;
        if (tx.txnId.startsWith('S-17')) continue;
        if (tx.txnId.startsWith('IN_V_')) continue;

        final typeUpper = tx.type.trim().toUpperCase();
        if (typeUpper == 'PURCHASE') continue;
        if (typeUpper == 'OPENING' ||
            typeUpper == 'OPENING_STOCK' ||
            tx.txnId.startsWith('OPENING-')) {
          continue;
        }

        final txDate = tx.dateTime;
        if (txDate.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            txDate.isBefore(end.add(const Duration(milliseconds: 1)))) {
          final String rawCat =
              (tx.category.trim().isNotEmpty && tx.category != "General")
                  ? tx.category
                  : tx.itemName;
          final String canonicalCat =
              DataRepository.canonicalizeCategory(rawCat);

          final String key =
              "${canonicalCat.toUpperCase()}_${tx.itemName.toUpperCase()}_${tx.sizeLabel.toUpperCase()}";
          map.putIfAbsent(
              key,
              () => DailyMovementEntry(
                    category: canonicalCat,
                    itemName: tx.itemName,
                    size: tx.sizeLabel,
                    openingQty: 0,
                    inQty: 0,
                    outQty: 0,
                    closingQty: 0,
                  ));
          var entry = map[key]!;
          if (typeUpper == 'IN' ||
              typeUpper == 'INWARD' ||
              typeUpper == 'RETURN' ||
              typeUpper == 'ADJUSTMENT') {
            entry.inQty += tx.qty.abs();
          } else if (typeUpper == 'OUT' ||
              typeUpper == 'OUTWARD' ||
              typeUpper == 'SALE' ||
              typeUpper == 'RESERVE') {
            entry.outQty += tx.qty.abs();
          }
          entry.closingQty = entry.openingQty + entry.inQty - entry.outQty;
        }
      }
    }
    final list = map.values.toList();
    list.sort((a, b) {
      int itemComp = ItemOrderUtil.compare(a.category, b.category);
      if (itemComp != 0) return itemComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
    return list;
  }
}
