import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/stock_models.dart';
import '../../services/data_repository.dart';
import '../../services/stock_notifier.dart';
import '../../services/supabase_realtime_service.dart';
import '../../services/supabase_service.dart';
import '../../services/transaction_slip_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/motion_toast.dart';

/// Live Transaction Ledger Table with Real-time Sync, Visual Badges, Gate Pass Printing, and Reversals.
class LiveTransactionLedgerTable extends StatefulWidget {
  final String? initialType;
  final String? initialLocation;
  final VoidCallback? onTransactionChanged;

  const LiveTransactionLedgerTable({
    super.key,
    this.initialType,
    this.initialLocation,
    this.onTransactionChanged,
  });

  @override
  State<LiveTransactionLedgerTable> createState() =>
      _LiveTransactionLedgerTableState();
}

class _LiveTransactionLedgerTableState extends State<LiveTransactionLedgerTable> {
  final DateFormat _timeFormat = DateFormat('dd/MM hh:mm a');
  final TextEditingController _searchCtrl = TextEditingController();

  String _filterType = 'ALL'; // 'ALL', 'IN', 'OUT', 'TRANSFER'
  String _filterLocation = 'ALL'; // 'ALL', 'YARD', 'FACTORY'
  String _searchQuery = '';
  bool _isLoading = false;

  List<StockTransaction> _transactions = [];
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _filterType = widget.initialType!;
    if (widget.initialLocation != null) {
      _filterLocation = widget.initialLocation!.toUpperCase();
    }

    _loadTransactions();
    stockRefreshNotifier.addListener(_loadTransactions);
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _loadTransactions();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    stockRefreshNotifier.removeListener(_loadTransactions);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await SupabaseService.client
          .from('transactions')
          .select()
          .order('date_time', ascending: false)
          .limit(100);

      final List<StockTransaction> list = [];
      for (final row in response as List) {
        try {
          final rowMap = Map<String, dynamic>.from(row as Map);
          final dt = parseTransactionTimestamp(rowMap);

          list.add(
            StockTransaction(
              txnId: (row['txn_id'] ?? row['id'] ?? '').toString(),
              dateTime: dt,
              itemName: (row['item_name'] ?? '').toString(),
              size: (row['size'] ?? row['size_label'] ?? '').toString(),
              type: (row['type'] ?? row['txn_type'] ?? 'IN').toString().toUpperCase(),
              qtyMT: (row['qty_mt'] as num?)?.toDouble() ?? 0.0,
              location: (row['location'] ?? 'YARD').toString().toUpperCase(),
              toLocation: row['to_location']?.toString().toUpperCase(),
              invoiceNo: (row['invoice_no'] ?? row['bill_no'] ?? '').toString(),
              lorryNo: (row['lorry_no'] ?? '').toString(),
              transportCo: (row['transport_co'] ?? row['transport_name'] ?? '').toString(),
              driverName: (row['driver_name'] ?? '').toString(),
              driverPhone: (row['driver_phone'] ?? '').toString(),
              note: (row['note'] ?? '').toString(),
              user: (row['user_name'] ?? row['user'] ?? '').toString(),
              isReversed: row['is_reversed'] == true,
            ),
          );
        } catch (e) {
          debugPrint('[LiveLedgerTable] Row parse error: $e');
        }
      }

      if (mounted) {
        setState(() {
          _transactions = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[LiveLedgerTable] Fetch Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<StockTransaction> get _filteredList {
    return _transactions.where((tx) {
      // Type filter
      if (_filterType != 'ALL' && tx.type != _filterType) return false;

      // Location filter
      if (_filterLocation != 'ALL' &&
          tx.location != _filterLocation &&
          tx.toLocation != _filterLocation) {
        return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchVehicle = (tx.lorryNo ?? '').toLowerCase().contains(query);
        final matchItem = tx.itemName.toLowerCase().contains(query);
        final matchSize = tx.size.toLowerCase().contains(query);
        final matchTxId = tx.txnId.toLowerCase().contains(query);
        final matchInvoice = (tx.invoiceNo ?? '').toLowerCase().contains(query);
        return matchVehicle || matchItem || matchSize || matchTxId || matchInvoice;
      }

      return true;
    }).toList();
  }

  Future<void> _promptReversal(StockTransaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Reverse Transaction?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to reverse transaction #${tx.txnId}?\n'
          'This will cancel ${tx.qtyMT.toStringAsFixed(3)} MT of ${tx.itemName} (${tx.size}) and restore the stock ledger.',
          style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm Reversal'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.client
            .from('transactions')
            .update({'is_reversed': true})
            .eq('txn_id', tx.txnId);

        await DataRepository.getERPStockAsync(null, forceRefresh: true);
        notifyStockDataChanged();
        _loadTransactions();
        widget.onTransactionChanged?.call();

        if (mounted) {
          MotionToast.show(context, 'Transaction reversed successfully');
        }
      } catch (e) {
        debugPrint('[LiveLedgerTable] Reversal error: $e');
        if (mounted) {
          MotionToast.show(context, 'Reversal failed: $e', isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredList;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── FILTER & SEARCH TOOLBAR ──
          _buildToolbar(filtered.length),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // ── TABLE CONTENT ──
          Expanded(
            child: _isLoading && _transactions.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 780) {
                            return _buildDesktopTable(filtered);
                          } else {
                            return _buildMobileList(filtered);
                          }
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ── FILTER & SEARCH TOOLBAR ──
  Widget _buildToolbar(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF0F172A)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Live Transaction Ledger',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  '$count entries',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Filters & Search Wrap
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildTypeFilterPill('ALL', 'All'),
              _buildTypeFilterPill('IN', 'Inward'),
              _buildTypeFilterPill('OUT', 'Dispatch'),
              _buildTypeFilterPill('TRANSFER', 'Transfer'),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Search vehicle / item...',
                      hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 14, color: Color(0xFF64748B)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilterPill(String type, String label) {
    final bool isSelected = _filterType == type;
    return InkWell(
      onTap: () => setState(() => _filterType = type),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  // ── DESKTOP DATA TABLE ──
  Widget _buildDesktopTable(List<StockTransaction> list) {
    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 44,
          horizontalMargin: 14,
          columnSpacing: 14,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('TIME', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            DataColumn(label: Text('TYPE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            DataColumn(label: Text('ITEM & SIZE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            DataColumn(numeric: true, label: Text('WEIGHT (MT)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            DataColumn(label: Text('LOCATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            DataColumn(label: Text('VEHICLE / REF', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
          ],
          rows: list.asMap().entries.map((entry) {
            final int index = entry.key;
            final StockTransaction tx = entry.value;
            final bool isZebra = index.isOdd;

            return DataRow(
              color: WidgetStateProperty.resolveWith<Color>((states) {
                if (tx.isReversed) return const Color(0xFFFEF2F2);
                if (states.contains(WidgetState.hovered)) return const Color(0xFFF1F5F9);
                return isZebra ? const Color(0xFFF8FAFC) : Colors.white;
              }),
              cells: [
                // Timestamp
                DataCell(
                  Text(
                    _timeFormat.format(tx.dateTime),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tx.isReversed ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                      decoration: tx.isReversed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                // Type Badge
                DataCell(_buildTypeBadge(tx)),
                // Item & Size
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tx.itemName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tx.isReversed ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                          decoration: tx.isReversed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        formatSizeDisplay(tx.itemName, tx.size),
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                // Weight MT
                DataCell(
                  Text(
                    '${tx.qtyMT.toStringAsFixed(3)} MT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tx.isReversed
                          ? const Color(0xFF94A3B8)
                          : tx.type == 'IN'
                              ? const Color(0xFF059669)
                              : const Color(0xFF0F172A),
                      decoration: tx.isReversed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                // Location
                DataCell(
                  Text(
                    tx.type == 'TRANSFER'
                        ? '${tx.location} ➔ ${tx.toLocation ?? '—'}'
                        : tx.location,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                ),
                // Vehicle / Ref
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        (tx.lorryNo != null && tx.lorryNo!.isNotEmpty)
                            ? tx.lorryNo!
                            : ((tx.invoiceNo != null && tx.invoiceNo!.isNotEmpty) ? tx.invoiceNo! : '—'),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                      ),
                      if (tx.invoiceNo != null &&
                          tx.invoiceNo!.isNotEmpty &&
                          tx.lorryNo != null &&
                          tx.lorryNo!.isNotEmpty)
                        Text(
                          'Ref: ${tx.invoiceNo}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
                // Actions
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Print Gate Pass Slip
                      IconButton(
                        icon: const Icon(Icons.print_outlined, size: 16, color: Color(0xFF475569)),
                        tooltip: 'Print Gate Pass Slip',
                        splashRadius: 16,
                        onPressed: () => TransactionSlipService.printSlip(context, tx),
                      ),
                      // Reverse Transaction (if not already reversed)
                      if (!tx.isReversed)
                        IconButton(
                          icon: const Icon(Icons.undo_rounded, size: 16, color: Color(0xFFDC2626)),
                          tooltip: 'Reverse Transaction',
                          splashRadius: 16,
                          onPressed: () => _promptReversal(tx),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── MOBILE CARD LIST ──
  Widget _buildMobileList(List<StockTransaction> list) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final tx = list[index];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tx.isReversed ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: tx.isReversed ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTypeBadge(tx),
                  Text(
                    '${tx.qtyMT.toStringAsFixed(3)} MT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: tx.isReversed ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${tx.itemName} · ${formatSizeDisplay(tx.itemName, tx.size)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                  decoration: tx.isReversed ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '📍 ${tx.location}${tx.toLocation != null ? ' ➔ ${tx.toLocation}' : ''} · ${_timeFormat.format(tx.dateTime)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print_outlined, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => TransactionSlipService.printSlip(context, tx),
                      ),
                      if (!tx.isReversed) ...[
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.undo_rounded, size: 16, color: Color(0xFFDC2626)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _promptReversal(tx),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── VISUAL BADGES ──
  Widget _buildTypeBadge(StockTransaction tx) {
    if (tx.isReversed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: const Text(
          'REVERSED',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFFDC2626),
          ),
        ),
      );
    }

    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    final String label;

    switch (tx.type) {
      case 'IN':
        bgColor = const Color(0xFFECFDF5);
        textColor = const Color(0xFF059669);
        borderColor = const Color(0xFFA7F3D0);
        label = 'INWARD';
        break;
      case 'OUT':
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF0F172A);
        borderColor = const Color(0xFFCBD5E1);
        label = 'DISPATCH';
        break;
      case 'TRANSFER':
      default:
        bgColor = const Color(0xFFFFFBEB);
        textColor = const Color(0xFFD97706);
        borderColor = const Color(0xFFFDE68A);
        label = 'TRANSFER';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text(
            'No matching transactions found',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
