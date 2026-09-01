import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/data_repository.dart';
import '../services/stock_notifier.dart';
import '../widgets/inventory/compact_transaction_entry_panel.dart';
import '../widgets/inventory/live_transaction_ledger_table.dart';

/// Enterprise Inventory In & Out Warehouse Console Screen.
/// Provides side-by-side transaction recording and live transaction ledger on desktop,
/// and smooth segmented navigation on mobile.
class InventoryInOutScreen extends StatefulWidget {
  final String? initialType;
  final String? initialMaterial;
  final String? initialSize;
  final String? initialLocation;

  const InventoryInOutScreen({
    super.key,
    this.initialType,
    this.initialMaterial,
    this.initialSize,
    this.initialLocation,
  });

  @override
  State<InventoryInOutScreen> createState() => _InventoryInOutScreenState();
}

class _InventoryInOutScreenState extends State<InventoryInOutScreen> {
  int _mobileTabIndex = 0; // 0 = Entry Form, 1 = Live Ledger
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 980;

            if (isDesktop) {
              return _buildDesktopLayout();
            } else {
              return _buildMobileLayout();
            }
          },
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
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory Operations Console',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Daily Inward, Dispatch & Yard Transfers · Real-time Ledger',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
        ],
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
              : const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF475569)),
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

  // ── DESKTOP SIDE-BY-SIDE LAYOUT ──
  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Pane: Compact Transaction Entry Panel (~420px)
          SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: CompactTransactionEntryPanel(
                initialType: widget.initialType,
                initialMaterial: widget.initialMaterial,
                initialSize: widget.initialSize,
                initialLocation: widget.initialLocation,
                onTransactionSubmitted: _refreshAll,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Right Pane: Live Transaction Ledger Table (Expanded)
          Expanded(
            child: LiveTransactionLedgerTable(
              initialType: widget.initialType,
              initialLocation: widget.initialLocation,
              onTransactionChanged: _refreshAll,
            ),
          ),
        ],
      ),
    );
  }

  // ── MOBILE / TABLET TABBED LAYOUT ──
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Mobile Segmented Switcher
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildMobileTabButton(
                  index: 0,
                  label: 'New Transaction',
                  icon: Icons.edit_note_rounded,
                ),
              ),
              Expanded(
                child: _buildMobileTabButton(
                  index: 1,
                  label: 'Live Ledger',
                  icon: Icons.receipt_long_rounded,
                ),
              ),
            ],
          ),
        ),

        // Body Content
        Expanded(
          child: _mobileTabIndex == 0
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: CompactTransactionEntryPanel(
                    initialType: widget.initialType,
                    initialMaterial: widget.initialMaterial,
                    initialSize: widget.initialSize,
                    initialLocation: widget.initialLocation,
                    onTransactionSubmitted: () {
                      _refreshAll();
                      setState(() => _mobileTabIndex = 1);
                    },
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: LiveTransactionLedgerTable(
                    initialType: widget.initialType,
                    initialLocation: widget.initialLocation,
                    onTransactionChanged: _refreshAll,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMobileTabButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = _mobileTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _mobileTabIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
