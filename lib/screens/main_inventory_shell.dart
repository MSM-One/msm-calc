import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../models/permission_model.dart';
import '../models/user_session_notifier.dart';
import '../services/access_guard.dart';
import '../services/data_repository.dart';
import '../constants/app_colors.dart';
import '../widgets/screen_gate.dart';
import '../widgets/m_loader.dart';
import '../widgets/guarded_metric.dart';
import 'inventory_dashboard_screen.dart';
import 'inventory_in_out_screen.dart';
import '../utils/formatters.dart';
import '../utils/steel_helper.dart';

class MainInventoryShell extends StatefulWidget {
  final int initialTab;
  final String? initialFilter;
  const MainInventoryShell(
      {super.key, this.initialTab = 0, this.initialFilter});

  @override
  State<MainInventoryShell> createState() => _MainInventoryShellState();
}

class _MainInventoryShellState extends State<MainInventoryShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, snapshot, _) {
        // Cache snapshot properties for efficiency
        final canDash = snapshot.canAccessInventoryDash;
        final canCurrent = snapshot.canAccessCurrentStock;
        final canHistory = snapshot.canAccessTransactions;

        final List<Map<String, dynamic>> allTabs = [
          {
            'index': 0,
            'title': 'Dashboard',
            'icon': Icons.dashboard_rounded,
            'allowed': canDash,
            'widget': ScreenGate(
              canAccess: (s) => AccessGuard.can(Permissions.dashboardView),
              screenName: 'Inventory Dashboard',
              child: const StockDashboardScreen(),
            ),
          },
          {
            'index': 1,
            'title': 'Current Stock',
            'icon': Icons.inventory_2_outlined,
            'allowed': canCurrent,
            'widget': ScreenGate(
              canAccess: (s) =>
                  AccessGuard.can(Permissions.screensCurrentStock),
              screenName: 'Current Stock',
              child: const CurrentStockModuleScreen(),
            ),
          },
          {
            'index': 2,
            'title': 'Transaction History',
            'icon': Icons.receipt_long_rounded,
            'allowed': canHistory,
            'widget': ScreenGate(
              canAccess: (s) =>
                  AccessGuard.can(Permissions.screensTransactions),
              screenName: 'Transaction History',
              child: const InventoryInOutScreen(),
            ),
          },
        ];

        final activeTabs = allTabs.where((t) => t['allowed'] == true).toList();

        Widget body;
        if (activeTabs.isEmpty) {
          body = const Scaffold(
            body: Center(
              child: Text(
                "No access available",
                style: TextStyle(color: textGrey, fontWeight: FontWeight.bold),
              ),
            ),
          );
        } else {
          final currentTab = allTabs.firstWhere(
            (t) => t['index'] == _selectedIndex,
            orElse: () => activeTabs.first,
          );
          body = currentTab['widget'] as Widget;
        }

        final bool isMobile = MediaQuery.of(context).size.width < 600;

        return Scaffold(
          extendBody: false, // Changed for mobile to have fixed nav
          body: body,
          bottomNavigationBar: activeTabs.length <= 1
              ? null
              : isMobile
                  ? BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      onTap: (index) {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                      backgroundColor: Colors.white,
                      selectedItemColor: msmRed,
                      unselectedItemColor: Colors.grey.shade500,
                      selectedFontSize: 12,
                      unselectedFontSize: 12,
                      type: BottomNavigationBarType.fixed,
                      elevation: 8,
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.dashboard_rounded),
                          activeIcon: Icon(Icons.dashboard_rounded),
                          label: "Dashboard",
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.inventory_2_outlined),
                          activeIcon: Icon(Icons.inventory_2_rounded),
                          label: "Stock",
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.receipt_long_rounded),
                          activeIcon: Icon(Icons.receipt_long_rounded),
                          label: "Transaction History",
                        ),
                      ],
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: borderLight, width: 0.5)),
                      ),
                      child: BottomNavigationBar(
                        currentIndex: _selectedIndex,
                        onTap: (index) {
                          if (index == 0) {
                            Navigator.of(context).pop();
                            return;
                          }
                          setState(() {
                            _selectedIndex = index;
                          });
                        },
                        elevation: 0,
                        items: allTabs
                            .map((t) => BottomNavigationBarItem(
                                  icon: Icon(t['icon'] as IconData),
                                  activeIcon: Icon(t['icon'] as IconData,
                                      shadows: const [
                                        BoxShadow(
                                          color: Color(
                                              0x33B71C1C), // msmRed with alpha 0.2
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        )
                                      ]),
                                  label: t['title'] as String,
                                ))
                            .toList(),
                      ),
                    ),
        );
      },
    );
  }

  // Legacy mobile floating navbar removed
}

class CurrentStockModuleScreen extends StatelessWidget {
  const CurrentStockModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text("Current Stock"),
        elevation: 0,
        backgroundColor: msmRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                DataRepository.refreshAllStockData(forceRefresh: true),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ItemVariant>>(
        valueListenable: DataRepository.inventoryListNotifier,
        builder: (context, items, child) {
          if (DataRepository.isSyncing.value && items.isEmpty) {
            return const Center(child: MLoader(size: 80));
          }
          if (items.isEmpty) {
            DataRepository.getERPStockAsync(null);
          }

          final Map<String, List<Map<String, dynamic>>> locationStock = {
            'YARD': [],
            'FACTORY': [],
          };

          final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {
            'YARD': {},
            'FACTORY': {},
          };

          for (final item in items) {
            final loc = StockUtils.normalizeLocation(item.location);
            if (loc != 'YARD' && loc != 'FACTORY') continue;

            grouped[loc]!.putIfAbsent(item.itemName, () => []);
            grouped[loc]![item.itemName]!.add({
              'size': item.size,
              'qtyMT': item.currentStockMT > 0 ? item.currentStockMT : 0.0,
            });
          }

          for (final loc in grouped.keys) {
            for (final itemName in grouped[loc]!.keys) {
              final variants = grouped[loc]![itemName]!;
              double totalQty = variants.fold(
                  0.0, (sum, v) => sum + (v['qtyMT'] as double));
              variants.sort((a, b) =>
                  (b['qtyMT'] as double).compareTo(a['qtyMT'] as double));

              locationStock[loc]!.add({
                'itemName': itemName,
                'totalQty': totalQty,
                'variants': variants,
              });
            }
            locationStock[loc]!.sort(
                (a, b) => b['totalQty'].compareTo(a['totalQty']));
          }

          double yardTotal = (locationStock['YARD'] ?? [])
              .fold(0.0, (sum, item) => sum + item['totalQty']);
          double factoryTotal = (locationStock['FACTORY'] ?? [])
              .fold(0.0, (sum, item) => sum + item['totalQty']);
          double grandTotal = yardTotal + factoryTotal;

          return RefreshIndicator(
            onRefresh: () =>
                DataRepository.refreshAllStockData(forceRefresh: true),
            color: msmRed,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Overview Grid Cards
                      LayoutBuilder(builder: (context, c) {
                        bool useRow = c.maxWidth > 550;
                        List<Widget> cards = [
                          Expanded(
                            flex: useRow ? 1 : 0,
                            child: _buildMetricCard(
                                "TOTAL STOCK",
                                "${grandTotal.toStringAsFixed(3)} MT",
                                Icons.analytics_rounded,
                                msmRed),
                          ),
                          if (!useRow) const SizedBox(height: 12),
                          if (useRow) const SizedBox(width: 12),
                          Expanded(
                            flex: useRow ? 1 : 0,
                            child: _buildMetricCard(
                                "YARD TOTAL",
                                "${yardTotal.toStringAsFixed(3)} MT",
                                Icons.warehouse_rounded,
                                Colors.indigo),
                          ),
                          if (!useRow) const SizedBox(height: 12),
                          if (useRow) const SizedBox(width: 12),
                          Expanded(
                            flex: useRow ? 1 : 0,
                            child: _buildMetricCard(
                                "FACTORY TOTAL",
                                "${factoryTotal.toStringAsFixed(3)} MT",
                                Icons.factory_rounded,
                                Colors.teal),
                          ),
                        ];
                        return useRow
                            ? Row(children: cards)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: cards);
                      }),
                      const SizedBox(height: 24),

                      const Text(
                        "LOCATIONS",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: textGrey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildLocationCard(
                          context, 'YARD', locationStock['YARD'] ?? []),
                      const SizedBox(height: 16),
                      _buildLocationCard(
                          context, 'FACTORY', locationStock['FACTORY'] ?? []),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: textGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                GuardedMetric(
                  permission: Permissions.inventoryMetricsView,
                  value: value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(
      BuildContext context, String title, List<Map<String, dynamic>> items) {
    final double total = items.fold(0.0, (sum, item) => sum + item['totalQty']);
    final topItems = items.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) =>
                  CurrentStockLocationItemsScreen(location: title),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: msmRed.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          title == 'YARD'
                              ? Icons.warehouse_rounded
                              : Icons.factory_rounded,
                          color: msmRed,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                          Text(
                            "${items.length} Material Categories",
                            style: const TextStyle(
                              fontSize: 12,
                              color: textGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: textGrey, size: 14),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              if (topItems.isNotEmpty) ...[
                const Text(
                  "TOP STOCK BY CATEGORY",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: textGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...topItems.map((item) {
                  final double percentage =
                      total > 0 ? (item['totalQty'] / total) * 100 : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item['itemName']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textDark),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percentage / 100,
                              backgroundColor: Colors.grey.shade100,
                              color: msmRed,
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "${(item['totalQty'] as double).toStringAsFixed(1)} MT",
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: textDark),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "TOTAL STOCK",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: textGrey,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      GuardedMetric(
                        permission: Permissions.inventoryMetricsView,
                        value: "${total.toStringAsFixed(3)} MT",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      "ONLINE",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CurrentStockLocationItemsScreen extends StatelessWidget {
  final String location;
  const CurrentStockLocationItemsScreen({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: msmRed,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 22),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
        title: Text("$location Stock",
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _buildAvailableStockFromTransactions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: MLoader(size: 80));
          }
          final data = snapshot.data ?? <String, dynamic>{};
          final items =
              (data[location] as List<Map<String, dynamic>>?) ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text("No available stock.",
                  style: TextStyle(color: textGrey)),
            );
          }

          double totalWeight = items.fold(0.0,
              (sum, e) => sum + ((e['totalQty'] as num?)?.toDouble() ?? 0.0));

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Overview Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "TOTAL LOCATION STOCK",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: textGrey,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${totalWeight.toStringAsFixed(3)} MT",
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: textDark,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: msmRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${items.length} Categories",
                            style: const TextStyle(
                              color: msmRed,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Category List
                  ...items.map((item) {
                    final itemName = item['itemName']?.toString() ?? 'Unknown';
                    final totalQty =
                        (item['totalQty'] as num?)?.toDouble() ?? 0.0;
                    final isLow = totalQty < 5.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.01),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ScreenGate(
                                canAccess: (s) => AccessGuard.can(
                                    Permissions.screensStockDetail),
                                screenName: itemName,
                                child: CurrentStockItemDetailsScreen(
                                  location: location,
                                  itemName: itemName,
                                ),
                              ),
                            ),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isLow
                                ? Colors.orange.shade50
                                : Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            itemName.toLowerCase().contains('pipe')
                                ? Icons.adjust_rounded
                                : Icons.grid_view_rounded,
                            color: isLow ? Colors.orange : Colors.blueGrey,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          itemName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: textDark,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isLow
                                      ? Colors.red.shade50
                                      : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isLow ? "Low Stock" : "In Stock",
                                  style: TextStyle(
                                    color: isLow
                                        ? Colors.red.shade700
                                        : Colors.teal.shade700,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GuardedMetric(
                              permission: Permissions.inventoryQuantityView,
                              value: "${totalQty.toStringAsFixed(3)} MT",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isLow ? Colors.red.shade800 : textDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right_rounded,
                                color: textGrey, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CurrentStockItemDetailsScreen extends StatelessWidget {
  final String location;
  final String itemName;
  const CurrentStockItemDetailsScreen({
    super.key,
    required this.location,
    required this.itemName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: msmRed,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 22),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
        title: Text(itemName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _buildAvailableStockFromTransactions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: MLoader(size: 80));
          }
          final data = snapshot.data ?? <String, dynamic>{};
          final items =
              (data[location] as List<Map<String, dynamic>>?) ?? const [];
          final item = items.cast<Map<String, dynamic>?>().firstWhere(
                (e) => e?['itemName']?.toString() == itemName,
                orElse: () => null,
              );
          if (item == null) {
            return const Center(
              child: Text("No available sizes.",
                  style: TextStyle(color: textGrey)),
            );
          }
          final List<Map<String, dynamic>> variants =
              (item['variants'] as List<Map<String, dynamic>>?) ?? [];
          if (variants.isEmpty) {
            return const Center(
              child: Text("No available sizes.",
                  style: TextStyle(color: textGrey)),
            );
          }

          double totalQty = (item['totalQty'] as num?)?.toDouble() ?? 0.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Overview Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$location Stock".toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: textGrey,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              itemName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: textDark,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              "TOTAL CATEGORY STOCK",
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: textGrey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${totalQty.toStringAsFixed(3)} MT",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: msmRed,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Size List
                  ...variants.map((v) {
                    final size = v['size']?.toString() ?? 'Size';
                    final qty = (v['qtyMT'] as num?)?.toDouble() ?? 0.0;
                    final isLow = qty < 5.0;
                    double unitWeight = lookupSizeWeight(size);
                    if (unitWeight == 0) {
                      unitWeight = extractUnitWeight(size);
                    }
                    final formattedWeight = unitWeight % 1 == 0
                        ? unitWeight.toInt().toString()
                        : unitWeight.toStringAsFixed(1);
                    final String weightSuffix =
                        (unitWeight > 0) ? " ${formattedWeight}kg" : "";
                    final String sizeDisplay = itemName == 'MS Angle'
                        ? formatSizeLabel(size, itemName, unitWeight)
                        : "$size$weightSuffix";

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.01),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isLow
                                ? Colors.red.shade50
                                : Colors.teal.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isLow
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: isLow ? Colors.red : Colors.teal,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          sizeDisplay,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: textDark,
                          ),
                        ),
                        trailing: GuardedMetric(
                          permission: Permissions.inventoryQuantityView,
                          value: "${qty.toStringAsFixed(3)} MT",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: isLow ? Colors.red.shade800 : textDark,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<Map<String, dynamic>> _buildAvailableStockFromTransactions() async {
  List<ItemVariant> items = DataRepository.inventoryListNotifier.value;
  if (items.isEmpty) {
    await DataRepository.getERPStockAsync(null, forceRefresh: true);
    items = DataRepository.inventoryListNotifier.value;
  }

  final Map<String, List<Map<String, dynamic>>> locationStock = {
    'YARD': [],
    'FACTORY': [],
  };

  final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {
    'YARD': {},
    'FACTORY': {},
  };

  for (final item in items) {
    final loc = StockUtils.normalizeLocation(item.location);
    if (loc != 'YARD' && loc != 'FACTORY') continue;

    grouped[loc]!.putIfAbsent(item.itemName, () => []);
    grouped[loc]![item.itemName]!.add({
      'size': item.size,
      'qtyMT': item.currentStockMT > 0 ? item.currentStockMT : 0.0,
    });
  }

  for (final loc in grouped.keys) {
    for (final itemName in grouped[loc]!.keys) {
      final variants = grouped[loc]![itemName]!;
      double totalQty = variants.fold(
          0.0, (sum, v) => sum + (v['qtyMT'] as double));
      variants.sort(
          (a, b) => (b['qtyMT'] as double).compareTo(a['qtyMT'] as double));

      locationStock[loc]!.add({
        'itemName': itemName,
        'totalQty': totalQty,
        'variants': variants,
      });
    }
    locationStock[loc]!.sort(
        (a, b) => b['totalQty'].compareTo(a['totalQty']));
  }
  return locationStock;
}
