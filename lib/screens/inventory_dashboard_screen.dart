import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/data_repository.dart';
import '../services/access_guard.dart';
import '../models/permission_model.dart';
import '../models/stock_models.dart';
import '../models/user_session_notifier.dart';
import '../constants/app_colors.dart';
import '../widgets/m_loader.dart';
import '../widgets/guarded_metric.dart';
import '../widgets/screen_gate.dart';
import '../services/stock_notifier.dart';
import '../services/supabase_realtime_service.dart';
import 'stock_transaction_screen.dart';
import '../utils/formatters.dart';

class StockDashboardScreen extends StatefulWidget {
  const StockDashboardScreen({super.key});

  @override
  State<StockDashboardScreen> createState() => _StockDashboardScreenState();
}

class _StockDashboardScreenState extends State<StockDashboardScreen> {
  bool _isLoading = true;
  String _userName = "Control Center";
  String? _selectedLocation;
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    stockRefreshNotifier.addListener(_onStockDataChanged);
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _loadData();
    });
    _loadData();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    stockRefreshNotifier.removeListener(_onStockDataChanged);
    super.dispose();
  }

  void _onStockDataChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadData({bool clearCache = false}) async {
    if (mounted) setState(() => _isLoading = true);

    if (clearCache) {
      await DataRepository.clearLocalStockCache();
    }

    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_display_name') ?? "";
    if (_userName.isEmpty) {
      final email = prefs.getString('user_email') ?? "";
      if (email.isNotEmpty) {
        final prefix = email.split('@')[0];
        _userName = prefix[0].toUpperCase() + prefix.substring(1);
      } else {
        _userName = "User";
      }
    }

    await DataRepository.refreshAllStockData(forceRefresh: true);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: MLoader()));
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: bgLight,
      body: RefreshIndicator(
        onRefresh: () => _loadData(clearCache: true),
        color: msmRed,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildModernHeader(isMobile),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 15),
                      ValueListenableBuilder<double>(
                        valueListenable: DataRepository.totalStockNotifier,
                        builder: (context, total, _) =>
                            _buildMainMetricCard(total, isMobile),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<double>(
                              valueListenable: DataRepository.yardStockNotifier,
                              builder: (context, val, _) => _buildSummaryCard(
                                title: "Yard Stock",
                                value: val,
                                icon: Icons.warehouse_rounded,
                                color: msmRed,
                                isSelected: _selectedLocation == 'YARD',
                                onTap: () => setState(() => _selectedLocation =
                                    _selectedLocation == 'YARD'
                                        ? null
                                        : 'YARD'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ValueListenableBuilder<double>(
                              valueListenable:
                                  DataRepository.factoryStockNotifier,
                              builder: (context, val, _) => _buildSummaryCard(
                                title: "Factory Stock",
                                value: val,
                                icon: Icons.factory_rounded,
                                color: Colors.teal,
                                isSelected: _selectedLocation == 'FACTORY',
                                onTap: () => setState(() => _selectedLocation =
                                    _selectedLocation == 'FACTORY'
                                        ? null
                                        : 'FACTORY'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedLocation != null)
                        _buildRelatedDataSection(_selectedLocation!, isMobile),
                      const SizedBox(height: 24),
                      _buildSectionHeader("Operations",
                          "Quick access to inventory tasks", isMobile),
                      const SizedBox(height: 20),
                      _showActionButtons(),
                      SizedBox(height: isMobile ? 40 : 80),
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

  Widget _buildModernHeader(bool isMobile) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 12 : 20, isMobile ? 16 : 24, 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFCC2127), Color(0xFFB01217)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33CC2127),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeaderBackButton(),
                  _buildRightActionCluster(),
                ],
              ),
              const SizedBox(height: 18),
              _buildHeaderTitleBlock(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBackButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTitleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "MSM ERP • INVENTORY OPERATIONS",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Inventory Dashboard",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          "Real-time stock overview & control panel",
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.88),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRightActionCluster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            "LIVE TELEMETRY",
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFDECEC),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Color(0xFFCC2127),
                size: 18,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    final bool isYard = title.toLowerCase().contains("yard");
    final Color iconBg = isYard ? const Color(0xFFFDECEC) : const Color(0xFFE6FFFA);
    final Color iconColor = isYard ? const Color(0xFFCC2127) : const Color(0xFF0D9488);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? color.withValues(alpha: 0.15)
                  : const Color(0x06000000),
              blurRadius: isSelected ? 12 : 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "SELECTED",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: GuardedMetric(
                permission: Permissions.inventoryMetricsView,
                value: "${value.toStringAsFixed(3)} MT",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _showActionButtons() {
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, snapshot, _) {
        return Row(
          children: [
            if (snapshot.canStockIn)
              Expanded(
                child: _buildQuickActionCard(
                  "Stock In",
                  Icons.add_circle_outline_rounded,
                  const Color(0xFF059669),
                  const Color(0xFFECFDF5),
                  () => _navigateToStockTransaction('IN'),
                ),
              ),
            if (snapshot.canStockIn && snapshot.canStockOut)
              const SizedBox(width: 14),
            if (snapshot.canStockOut)
              Expanded(
                child: _buildQuickActionCard(
                  "Stock Out",
                  Icons.remove_circle_outline_rounded,
                  const Color(0xFFCC2127),
                  const Color(0xFFFDECEC),
                  () => _navigateToStockTransaction('OUT'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMainMetricCard(double total, bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showTotalStockDrilldown,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "TOTAL NET STOCK",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: GuardedMetric(
                          permission: Permissions.inventoryMetricsView,
                          value: "${total.toStringAsFixed(3)} MT",
                          style: TextStyle(
                            fontSize: isMobile ? 28 : 34,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        children: [
                          Icon(Icons.auto_graph_rounded,
                              size: 14, color: Color(0xFF059669)),
                          SizedBox(width: 5),
                          Text(
                            "Real-time synchronized",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Color(0xFFCC2127),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(
      String label, IconData icon, Color iconColor, Color iconBgColor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedDataSection(String location, bool isMobile) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Column(
        key: ValueKey(location),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _buildSectionHeader(
              "$location Insights", "Breakdown of current holdings", isMobile),
          const SizedBox(height: 16),
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSubHeader("Recent Activity"),
                      const SizedBox(height: 12),
                      _buildTransactionPreview(location),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSubHeader("Top Stock Items"),
                      const SizedBox(height: 12),
                      _buildStockBreakdownPreview(location),
                    ],
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSubHeader("Recent Activity"),
                const SizedBox(height: 12),
                _buildTransactionPreview(location),
                const SizedBox(height: 24),
                _buildSubHeader("Top Stock Items"),
                const SizedBox(height: 12),
                _buildStockBreakdownPreview(location),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSubHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: textGrey,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTransactionPreview(String location) {
    return ValueListenableBuilder<List<StockTransaction>>(
      valueListenable: DataRepository.allTransactionsNotifier,
      builder: (context, allTxs, _) {
        final locTxs = allTxs
            .where((tx) =>
                tx.location.toUpperCase() == location.toUpperCase() ||
                tx.toLocation?.toUpperCase() == location.toUpperCase())
            .take(3)
            .toList();

        if (locTxs.isEmpty) {
          return _buildEmptyState("No recent activity for $location");
        }

        return Column(
          children: locTxs.map((tx) => _buildMiniTxTile(tx, location)).toList(),
        );
      },
    );
  }

  Widget _buildMiniTxTile(StockTransaction tx, String location) {
    final bool isAddition = ['IN', 'RETURN', 'OPENING'].contains(tx.type) ||
        (tx.type == 'TRANSFER' &&
            tx.toLocation?.toUpperCase() == location.toUpperCase());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isAddition ? Colors.teal : Colors.orange)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAddition
                  ? Icons.add_circle_outline_rounded
                  : Icons.remove_circle_outline_rounded,
              color: isAddition ? Colors.teal : Colors.orange,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.itemName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "${tx.type} • ${tx.size}",
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text(
            "${isAddition ? '+' : '-'}${tx.qtyMT.toStringAsFixed(3)} MT",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: isAddition ? Colors.teal : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockBreakdownPreview(String location) {
    return ValueListenableBuilder<List<ItemVariant>>(
      valueListenable: DataRepository.inventoryListNotifier,
      builder: (context, items, _) {
        final locNorm = StockUtils.normalizeLocation(location);
        final locItems = items
            .where((i) => StockUtils.normalizeLocation(i.location) == locNorm)
            .toList();
        locItems.sort((a, b) => b.currentStockMT.compareTo(a.currentStockMT));
        final topItems = locItems.take(4).toList();

        if (topItems.isEmpty) {
          return _buildEmptyState("Stock is empty in $location");
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          child: Column(
            children: topItems.map((i) => _buildStockRow(i)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildStockRow(ItemVariant item) {
    final String sizeDisplay =
        formatSizeDisplay(item.category, item.size, item.unitWeightKg);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              item.size.isNotEmpty
                  ? "${item.itemName} $sizeDisplay"
                  : item.itemName,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: textDark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            "${item.currentStockMT.toStringAsFixed(3)} MT",
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: textDark),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: borderLight, width: 0.5, style: BorderStyle.solid),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
              color: textGrey, fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  void _showTotalStockDrilldown() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            const Text("Stock Summary",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    letterSpacing: -0.5)),
            const SizedBox(height: 32),
            ValueListenableBuilder<double>(
              valueListenable: DataRepository.yardStockNotifier,
              builder: (context, val, _) => _drilldownRow(
                  "YARD STOCK", val, Colors.indigo, Icons.warehouse_rounded),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<double>(
              valueListenable: DataRepository.factoryStockNotifier,
              builder: (context, val, _) => _drilldownRow(
                  "FACTORY STOCK", val, Colors.teal, Icons.factory_rounded),
            ),
            const SizedBox(height: 12),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: borderLight)),
            ValueListenableBuilder<double>(
              valueListenable: DataRepository.totalStockNotifier,
              builder: (context, val, _) => _drilldownRow(
                  "TOTAL STOCK", val, msmRed, Icons.inventory_2_rounded,
                  isTotal: true),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _drilldownRow(String label, double val, Color color, IconData icon,
      {bool isTotal = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
              color: isTotal ? textDark : textGrey,
              fontSize: isTotal ? 14 : 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Text("${val.toStringAsFixed(3)} MT",
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: textDark,
                fontSize: isTotal ? 18 : 16)),
      ],
    );
  }

  void _navigateToStockTransaction(String type) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (ctx) => ScreenGate(
                  canAccess: (s) =>
                      AccessGuard.can(Permissions.screensStockInventory),
                  screenName: 'Stock Transaction',
                  child: StockTransactionScreen(initialType: type),
                ))).then((_) => _loadData());
  }

  void _showAddItemMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ValueListenableBuilder<PermissionSnapshot>(
        valueListenable: UserSessionNotifier.instance,
        builder: (context, snapshot, _) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Add Transaction",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textDark)),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (snapshot.canStockIn)
                    Expanded(
                      child: _buildQuickActionCard(
                        "Stock In",
                        Icons.add_circle_outline_rounded,
                        const Color(0xFF059669),
                        const Color(0xFFECFDF5),
                        () {
                          Navigator.pop(context);
                          _navigateToStockTransaction('IN');
                        },
                      ),
                    ),
                  if (snapshot.canStockIn && snapshot.canStockOut)
                    const SizedBox(width: 8),
                  if (snapshot.canStockOut)
                    Expanded(
                      child: _buildQuickActionCard(
                        "Stock Out",
                        Icons.remove_circle_outline_rounded,
                        const Color(0xFFCC2127),
                        const Color(0xFFFDECEC),
                        () {
                          Navigator.pop(context);
                          _navigateToStockTransaction('OUT');
                        },
                      ),
                    ),
                  if ((snapshot.canStockIn || snapshot.canStockOut) &&
                      snapshot.canStockTransfer)
                    const SizedBox(width: 8),
                  if (snapshot.canStockTransfer)
                    Expanded(
                      child: _buildQuickActionCard(
                        "Transfer",
                        Icons.swap_horiz_rounded,
                        Colors.indigo,
                        const Color(0xFFEEF2FF),
                        () {
                          Navigator.pop(context);
                          _navigateToStockTransaction('TRANSFER');
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
