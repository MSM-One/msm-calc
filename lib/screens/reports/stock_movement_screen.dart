import 'package:flutter/material.dart';
import 'stock_ledger_screen.dart';

export 'stock_ledger_screen.dart';

/// Stock Movement Report Screen widget.
class StockMovementScreen extends StatefulWidget {
  final bool isLoading;

  const StockMovementScreen({
    super.key,
    required this.isLoading,
  });

  @override
  State<StockMovementScreen> createState() => _StockMovementScreenState();
}

class _StockMovementScreenState extends State<StockMovementScreen> {
  @override
  Widget build(BuildContext context) {
    return StockLedgerScreen(isLoading: widget.isLoading);
  }
}
