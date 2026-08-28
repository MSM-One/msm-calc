import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../widgets/m_loader.dart';
import '../services/data_repository.dart';
import '../services/stock_notifier.dart';
import '../services/supabase_realtime_service.dart';
import '../models/stock_models.dart';
import '../constants/app_colors.dart';
import '../utils/formatters.dart';
import '../services/supabase_service.dart';
import '../repositories/reports_repository.dart';

class Debouncer {
  final int milliseconds;
  VoidCallback? action;
  Debouncer({required this.milliseconds});
  void run(VoidCallback action) {
    if (this.action != null)
      return; // Simplified for safety, properly we would use a Timer
    action();
  }
}

class TransactionHistoryScreen extends StatefulWidget {
  final String? initialType;
  final String? filterItem;
  final String? filterSize;

  const TransactionHistoryScreen({
    super.key,
    this.initialType,
    this.filterItem,
    this.filterSize,
  });

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String _filterType = 'ALL';
  late DateTime _startDate;
  late DateTime _endDate;
  String _lorrySearchQuery = "";
  final TextEditingController _lorrySearchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Debouncer _debouncer = Debouncer(milliseconds: 300);

  bool _isLoading = false;
  bool _isMoreLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 25;

  /// Cached display name read from SharedPreferences (set at Google Sign-In).
  /// Used alongside email for RBAC matching so both old (email) and
  /// new (display name) transactions are visible to the owner.
  String _currentDisplayName = '';

  List<StockTransaction> _allTxs = [];
  List<StockTransaction> _filteredTxs = [];
  List<dynamic> _flatList = [];
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    if (widget.initialType != null) _filterType = widget.initialType!;
    stockRefreshNotifier.addListener(_onStockDataChanged);
    _scrollCtrl.addListener(_scrollListener);
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _loadInitialData();
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    stockRefreshNotifier.removeListener(_onStockDataChanged);
    _scrollCtrl.dispose();
    _lorrySearchCtrl.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 300 &&
        !_isLoading &&
        !_isMoreLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  void _onStockDataChanged() {
    if (!mounted) return;
    _loadData();
  }

  Future<void> _loadInitialData() async {
    final lastReset = await DataRepository.getLastResetTimestamp();
    final prefs = await SharedPreferences.getInstance();

    // Load the user's display name for RBAC matching.
    _currentDisplayName = prefs.getString('user_display_name') ?? '';

    final raw = prefs.getString('stock_transactions_v2');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _allTxs = list
          .map((e) => StockTransaction.fromJson(e))
          .where((tx) => tx.dateTime.isAfter(lastReset ?? DateTime(1900)))
          .where((tx) => tx.type != 'PURCHASE' && !tx.txnId.startsWith('IN_V_'))
          .toList();
      _applyFilters();
      setState(() {});
    }

    await _loadData(reset: true);
  }

  Future<void> _loadData({bool reset = false}) async {
    if (reset) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _offset = 0;
        _hasMore = true;
      });
    } else {
      if (!mounted) return;
      if (_isMoreLoading) return;
      _isMoreLoading = true;
      setState(() {});
    }

    try {
      await DataRepository.ensureMasterLookupData();
      final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
      final String startStr = dateFmt.format(_startDate);
      final String endStr = dateFmt.format(_endDate);

      dynamic response;
      try {
        var query = SupabaseService.client
            .from('transactions')
            .select('*')
            .not('txn_type', 'eq', 'PURCHASE')
            .not('txn_id', 'like', 'IN_V_%');

        response = await query
            .order('created_at', ascending: false)
            .range(_offset, _offset + _limit - 1);
      } catch (e) {
        debugPrint('[InventoryHistoryScreen] Error loading transactions: $e');
        response = [];
      }

      List<StockTransaction> freshHist = (response as List).map((row) {
        DateTime dt = ReportsRepository.parseRowDateTime(row);

        return StockTransaction(
          txnId: row['txn_id']?.toString() ?? row['id'].toString(),
          dateTime: dt,
          itemName: DataRepository.resolveItemName(row),
          size: DataRepository.resolveSizeLabel(row),
          type: row['normalized_type']?.toString() ??
              row['txn_type']?.toString() ??
              row['type']?.toString() ??
              'IN',
          qtyMT: (row['qty_mt'] as num?)?.toDouble() ?? 0.0,
          location: row['location']?.toString() ?? 'YARD',
          toLocation: row['to_location']?.toString(),
          reason: row['reason']?.toString(),
          note: row['note']?.toString(),
          invoiceNo: row['invoice_no']?.toString(),
          lorryNo: row['lorry_no']?.toString(),
          transportCo: row['transport_co']?.toString(),
          driverName: row['driver_name']?.toString(),
          driverPhone: row['driver_phone']?.toString(),
          partyName:
              row['party_name']?.toString() ?? row['vendor_name']?.toString(),
          contactNo: row['contact_no']?.toString(),
          batchId: row['batch_id']?.toString(),
          user: row['user']?.toString(),
          isReversed: row['is_reversed'] == true,
        );
      }).toList();

      if (reset) {
        _allTxs = freshHist;
      } else {
        _allTxs.addAll(freshHist);
      }

      _hasMore = freshHist.length == _limit;
      _offset += freshHist.length;

      _applyFilters();
    } catch (e) {
      debugPrint("Error loading transactions from Supabase: $e");
    } finally {
      _isMoreLoading = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadData();
  }

  void _applyFilters() {
    final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
    final String startStr = dateFmt.format(_startDate);
    final String endStr = dateFmt.format(_endDate);

    _filteredTxs = _allTxs.where((tx) {
      if (tx.isReversed) return false;

      bool matchType = _filterType == 'ALL' || tx.type == _filterType;
      if (_filterType == 'REVERSED') {
        matchType = tx.isReversed;
      }

      final txDateStr = dateFmt.format(tx.dateTime);
      bool matchDate = (startStr == endStr)
          ? (txDateStr == startStr)
          : (txDateStr.compareTo(startStr) >= 0 &&
              txDateStr.compareTo(endStr) <= 0);

      bool matchLorry = true;
      if (_lorrySearchQuery.isNotEmpty) {
        matchLorry = (tx.lorryNo ?? "")
            .toLowerCase()
            .contains(_lorrySearchQuery.toLowerCase());
      }

      bool matchItem =
          widget.filterItem == null || tx.itemName == widget.filterItem;
      bool matchSize =
          widget.filterSize == null || tx.size == widget.filterSize;

      return matchType && matchDate && matchLorry && matchItem && matchSize;
    }).toList();
    _filteredTxs.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    _rebuildFlatList();
  }

  void _rebuildFlatList() {
    _flatList = [];
    String? lastDateStr;
    final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
    for (var tx in _filteredTxs) {
      final dateStr = dateFmt.format(tx.dateTime);
      if (dateStr != lastDateStr) {
        final label = _getDateLabel(tx.dateTime);
        _flatList.add(label);
        lastDateStr = dateStr;
      }
      _flatList.add(tx);
    }
  }

  void _confirmReverse(StockTransaction tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reverse Transaction?"),
        content: Text(
            "This will nullify ${tx.qtyMT.toStringAsFixed(3)} MT of ${tx.itemName} and restore stock balance. This action cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _reverseTx(tx);
              },
              child: const Text("REVERSE",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _reverseTx(StockTransaction tx) async {
    try {
      await SupabaseService.client
          .from('transactions')
          .update({'is_reversed': true}).eq('txn_id', tx.txnId);

      _loadData(reset: true);
      notifyStockDataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transaction reversed successfully")));
    } catch (e) {
      debugPrint("Error reversing transaction: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error reversing transaction: $e")));
    }
  }

  String _getDateLabel(DateTime date) {
    final now = DateTime.now();
    final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
    final String dateStr = dateFmt.format(date);
    final String todayStr = dateFmt.format(now);
    final String yesterdayStr =
        dateFmt.format(now.subtract(const Duration(days: 1)));

    if (dateStr == todayStr) return "TODAY";
    if (dateStr == yesterdayStr) return "YESTERDAY";

    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: _buildModernAppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              _buildPremiumHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(child: MLoader(size: 60))
                    : _filteredTxs.isEmpty
                        ? const Center(
                            child: Text("No transactions found.",
                                style: TextStyle(color: textGrey)))
                        : RefreshIndicator(
                            onRefresh: () => _loadData(reset: true),
                            color: msmRed,
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _flatList.length + (_hasMore ? 1 : 0),
                              itemBuilder: (ctx, idx) {
                                if (idx == _flatList.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(32.0),
                                    child: Center(child: MLoader(size: 40)),
                                  );
                                }

                                final item = _flatList[idx];
                                if (item is String) {
                                  return _buildDateHeader(item);
                                } else if (item is StockTransaction) {
                                  return _buildTransactionCard(item);
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: msmRed,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: const Text(
        "Transaction History",
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: () => _loadData(reset: true),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildPremiumHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: textGrey, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lorrySearchCtrl,
                    cursorColor: msmRed,
                    style: const TextStyle(
                        color: textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      hintText: "Search Lorry No...",
                      hintStyle: TextStyle(color: textGrey, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) {
                      _debouncer.run(() {
                        setState(() => _lorrySearchQuery = val);
                        _applyFilters();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTypeChip("ALL"),
                      _buildTypeChip("IN"),
                      _buildTypeChip("OUT"),
                      _buildTypeChip("TRANSFER"),
                      _buildTypeChip("RETURN"),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildDateFilterChip(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterChip() {
    return InkWell(
      onTap: () => _showQuickDateFilterBottomSheet(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded, color: textGrey, size: 12),
            const SizedBox(width: 6),
            Text(
              "${DateFormat('dd MMM yy').format(_startDate)} - ${DateFormat('dd MMM yy').format(_endDate)}",
              style: const TextStyle(
                  color: textDark, fontWeight: FontWeight.bold, fontSize: 11),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: textGrey, size: 14),
          ],
        ),
      ),
    );
  }

  bool _isRange(DateTime start, DateTime end) {
    return _startDate.year == start.year &&
        _startDate.month == start.month &&
        _startDate.day == start.day &&
        _endDate.year == end.year &&
        _endDate.month == end.month &&
        _endDate.day == end.day;
  }

  void _showQuickDateFilterBottomSheet(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final last7Days = today.subtract(const Duration(days: 7));
    final thisMonth = DateTime(now.year, now.month, 1);

    final isTodaySelected = _isRange(today, today);
    final isYesterdaySelected = _isRange(yesterday, yesterday);
    final isLast7Selected = _isRange(last7Days, today);
    final isThisMonthSelected = _isRange(thisMonth, today);
    final isCustomSelected = !isTodaySelected &&
        !isYesterdaySelected &&
        !isLast7Selected &&
        !isThisMonthSelected;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Select Date Filter",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 10.0,
                  children: [
                    _buildFilterChip(
                      label: 'Today',
                      isSelected: isTodaySelected,
                      onTap: () {
                        _updateDates(today, today);
                      },
                    ),
                    _buildFilterChip(
                      label: 'Yesterday',
                      isSelected: isYesterdaySelected,
                      onTap: () {
                        _updateDates(yesterday, yesterday);
                      },
                    ),
                    _buildFilterChip(
                      label: 'Last 7 Days',
                      isSelected: isLast7Selected,
                      onTap: () {
                        _updateDates(last7Days, today);
                      },
                    ),
                    _buildFilterChip(
                      label: 'This Month',
                      isSelected: isThisMonthSelected,
                      onTap: () {
                        _updateDates(thisMonth, today);
                      },
                    ),
                    _buildFilterChip(
                      label: 'Custom Range',
                      isSelected: isCustomSelected,
                      onTap: () async {
                        Navigator.pop(ctx);
                        final DateTimeRange? pickedRange =
                            await showDateRangePicker(
                          context: context,
                          initialDateRange:
                              DateTimeRange(start: _startDate, end: _endDate),
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (pickedRange != null) {
                          setState(() {
                            _startDate = DateTime(pickedRange.start.year,
                                pickedRange.start.month, pickedRange.start.day);
                            _endDate = DateTime(pickedRange.end.year,
                                pickedRange.end.month, pickedRange.end.day);
                          });
                          _loadData(reset: true);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFB71C1C) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF212121),
          ),
        ),
      ),
    );
  }

  void _updateDates(DateTime start, DateTime end) {
    setState(() {
      _startDate = DateTime(start.year, start.month, start.day);
      _endDate = DateTime(end.year, end.month, end.day);
    });
    _loadData(reset: true);
    Navigator.pop(context);
  }

  Widget _buildTypeChip(String type) {
    bool isSelected = _filterType == type;
    return GestureDetector(
      onTap: () {
        setState(() => _filterType = type);
        _applyFilters();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? msmRed : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey.shade200,
          ),
        ),
        child: Text(
          type,
          style: TextStyle(
            color: isSelected ? Colors.white : textDark,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 10,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: textGrey.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_rounded, size: 64, color: textGrey),
          ),
          const SizedBox(height: 16),
          const Text("No transactions found",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: textGrey)),
          const Text("Try adjusting your filters",
              style: TextStyle(fontSize: 14, color: textGrey)),
        ],
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: msmRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: msmRed,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: borderLight, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(StockTransaction tx) {
    final isOut = tx.type == 'OUT';
    final isTransfer = tx.type == 'TRANSFER';
    final isReturn = tx.type == 'RETURN';

    Color typeColor = Colors.teal;
    IconData typeIcon = Icons.arrow_downward_rounded;

    if (isOut) {
      typeColor = msmRed;
      typeIcon = Icons.arrow_upward_rounded;
    } else if (isTransfer) {
      typeColor = Colors.indigo;
      typeIcon = Icons.swap_horiz_rounded;
    } else if (isReturn) {
      typeColor = Colors.orange.shade800;
      typeIcon = Icons.keyboard_return_rounded;
    }

    double unitWeight = lookupSizeWeight(tx.size);
    if (unitWeight == 0) {
      unitWeight = _extractUnitWeight(tx.size);
    }
    final formattedWeight = unitWeight % 1 == 0
        ? unitWeight.toInt().toString()
        : unitWeight.toStringAsFixed(1);
    final String weightSuffix = (unitWeight > 0) ? " ${formattedWeight}kg" : "";
    final String sizeDisplay = tx.itemName == 'MS Angle'
        ? formatSizeLabel(tx.size, tx.itemName, unitWeight)
        : "${tx.size}$weightSuffix";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onLongPress: () => _confirmReverse(tx),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.itemName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$sizeDisplay • ${tx.location}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (tx.lorryNo != null && tx.lorryNo!.isNotEmpty)
                        Text(
                          "Lorry: ${tx.lorryNo}",
                          style: const TextStyle(
                              fontSize: 11,
                              color: msmRed,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      // "Entry by" attribution - prioritized for admins
                      if (tx.user != null && tx.user!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "Entry by: ${tx.user}",
                            style: TextStyle(
                              fontSize: 10,
                              color: (DataRepository
                                          .currentUserNotifier.value?.isAdmin ??
                                      false)
                                  ? Colors.indigo
                                      .shade700 // Clearly visible for admins
                                  : textGrey.withValues(alpha: 0.7),
                              fontWeight: (DataRepository
                                          .currentUserNotifier.value?.isAdmin ??
                                      false)
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontStyle: (DataRepository
                                          .currentUserNotifier.value?.isAdmin ??
                                      false)
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${tx.qtyMT.toStringAsFixed(3)} MT",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tx.type,
                        style: TextStyle(
                          color: typeColor.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _extractUnitWeight(String sizeLabel) {
  if (sizeLabel.isEmpty) return 0.0;
  try {
    final RegExp regex = RegExp(r'\(([^)]+)\)');
    final match = regex.firstMatch(sizeLabel);
    if (match != null) {
      final String val = match.group(1)!.replaceAll(RegExp(r'[^0-9.]'), '');
      if (sizeLabel.contains("1.2")) return 4.0;
      if (sizeLabel.contains("1.6")) return 4.0;
      if (sizeLabel.contains("2.0")) return 5.0;
      return double.tryParse(val) ?? 0.0;
    }
  } catch (_) {}
  return 0.0;
}
