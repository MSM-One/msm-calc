import 'package:flutter/material.dart';

// Shared stock refresh signal for Dashboard/Transactions/Current Stock.
final ValueNotifier<int> stockRefreshNotifier = ValueNotifier<int>(0);

void notifyStockDataChanged() {
  stockRefreshNotifier.value++;
}
