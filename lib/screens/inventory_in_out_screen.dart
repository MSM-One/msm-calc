import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/stock_notifier.dart';
import '../widgets/inventory/live_transaction_ledger_table.dart';

/// Enterprise Transaction History Screen.
/// Dedicated full-screen log viewer for Inward, Dispatch, Yard Transfers, and Adjustments.
class TransactionHistoryScreen extends StatefulWidget {
  final String? initialType;
  final String? initialMaterial;
  final String? initialSize;
  final String? initialLocation;

  const TransactionHistoryScreen({
    super.key,
    this.initialType,
    this.initialMaterial,
    this.initialSize,
    this.initialLocation,
  });

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

/// Backward-compatibility alias
typedef InventoryInOutScreen = TransactionHistoryScreen;

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _isRefreshing = false;

  Future<void> _refreshAll() async {
    setState(() => _isRefreshing = true);
    await DataRepository.getERPStockAsync(null, forceRefresh: true);
    notifyStockDataChanged();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LiveTransactionLedgerTable(
            initialType: widget.initialType,
            initialLocation: widget.initialLocation,
            onTransactionChanged: _refreshAll,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
        tooltip: 'Back to Dashboard',
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            // Fallback for direct tab navigation
            Navigator.of(context).pushReplacementNamed('/dashboard');
          }
        },
      ),
      title: const Text(
        'Transaction History',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        // Live Realtime Indicator Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 7, color: Color(0xFF10B981)),
              SizedBox(width: 5),
              Text(
                'Live Sync',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Refresh Button
        IconButton(
          icon: _isRefreshing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded,
                  size: 20, color: Color(0xFF475569)),
          tooltip: 'Refresh Stock & Ledger',
          onPressed: _isRefreshing ? null : _refreshAll,
        ),
        const SizedBox(width: 8),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
      ),
    );
  }
}
