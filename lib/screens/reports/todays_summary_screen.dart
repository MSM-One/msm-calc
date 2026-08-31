import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/report_models.dart';
import '../../services/data_repository.dart';
import '../../utils/sorting_utils.dart';
import '../../utils/formatters.dart';
import '../../widgets/m_loader.dart';

class TodaySummaryTab extends StatefulWidget {
  final bool isLoading;
  final List<DailyMovementEntry> filteredDailyMovement;
  final Widget emptyState;
  final ValueChanged<String>? onTabChanged;
  final ValueChanged<String>? onFlowChanged;
  final String dateRangeLabel;
  final String selectedTab;
  final String selectedFlow;

  const TodaySummaryTab({
    super.key,
    required this.isLoading,
    required this.filteredDailyMovement,
    required this.emptyState,
    this.onTabChanged,
    this.onFlowChanged,
    this.dateRangeLabel = 'today',
    this.selectedTab = 'Summary',
    this.selectedFlow = 'Inward',
  });

  @override
  State<TodaySummaryTab> createState() => _TodaySummaryTabState();
}

class _TodaySummaryTabState extends State<TodaySummaryTab> {
  late String _selectedTab;
  late String _selectedFlow;
  final Set<String> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.selectedTab;
    _selectedFlow = widget.selectedFlow;
    if (_selectedTab == 'Detailed') {
      _expandAllCategories();
    }
  }

  @override
  void didUpdateWidget(covariant TodaySummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _selectedTab = widget.selectedTab;
      if (_selectedTab == 'Detailed') {
        _expandAllCategories();
      } else {
        _expandedCategories.clear();
      }
    }
    if (oldWidget.selectedFlow != widget.selectedFlow) {
      _selectedFlow = widget.selectedFlow;
    }
  }

  void _expandAllCategories() {
    for (var e in widget.filteredDailyMovement) {
      final rawCat = e.itemName.isNotEmpty
          ? e.itemName
          : (e.category.isNotEmpty ? e.category : 'Other');
      final name = DataRepository.canonicalizeCategory(rawCat);
      _expandedCategories.add(name);
    }
  }

  String formatNumber(double n) => n.toStringAsFixed(3);

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

  Color _getFlowColor(double val) {
    if (_selectedFlow == 'Inward') return const Color(0xFF16A34A);
    if (_selectedFlow == 'Outward') return const Color(0xFFDC2626);
    if (val > 0) return const Color(0xFF16A34A);
    if (val < 0) return const Color(0xFFDC2626);
    return const Color(0xFF2563EB);
  }

  Color _getFlowBgColor(double val) {
    if (_selectedFlow == 'Inward') return const Color(0xFFDCFCE7);
    if (_selectedFlow == 'Outward') return const Color(0xFFFEE2E2);
    if (val > 0) return const Color(0xFFDCFCE7);
    if (val < 0) return const Color(0xFFFEE2E2);
    return const Color(0xFFDBEAFE);
  }

  String _formatSignedNumber(double val) {
    final String formatted = val.abs().toStringAsFixed(3);
    if (_selectedFlow == 'Net Qty') {
      if (val < 0) return "-$formatted";
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return const Center(child: MLoader());
    if (widget.filteredDailyMovement.isEmpty) return widget.emptyState;

    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 1025;

    // 1. Calculate Grand Totals across all transactions for KPI strip
    double grandOpening = 0.0;
    double grandInward = 0.0;
    double grandOutward = 0.0;
    double grandClosing = 0.0;
    final Set<String> activeCategoriesSet = {};

    for (var e in widget.filteredDailyMovement) {
      grandOpening += e.openingQty;
      grandInward += e.inQty;
      grandOutward += e.outQty;
      grandClosing += e.closingQty;
      final rawCat = e.itemName.isNotEmpty
          ? e.itemName
          : (e.category.isNotEmpty ? e.category : 'Other');
      activeCategoriesSet.add(DataRepository.canonicalizeCategory(rawCat));
    }

    // 2. Group items by Category for table & views
    final Map<String, List<Map<String, dynamic>>> categoryMap = {};
    for (var e in widget.filteredDailyMovement) {
      final rawCat = e.itemName.isNotEmpty
          ? e.itemName
          : (e.category.isNotEmpty ? e.category : 'Other');
      final String categoryGroup = DataRepository.canonicalizeCategory(rawCat);
      categoryMap.putIfAbsent(categoryGroup, () => []);

      double weight = lookupSizeWeight(e.size);
      if (weight == 0) {
        weight = _extractUnitWeight(e.size);
      }

      categoryMap[categoryGroup]!.add({
        'size_label': e.size,
        'weight': weight > 0 ? weight : null,
        'opening_qty': e.openingQty,
        'in_qty': e.inQty,
        'out_qty': e.outQty,
        'closing_qty': e.closingQty,
        'net_qty': e.inQty - e.outQty,
      });
    }

    // Process category objects
    final List<Map<String, dynamic>> processedCategories = [];
    categoryMap.forEach((categoryName, items) {
      items.sort((a, b) => SortingUtils.compareSizes(
          a['size_label'] as String, b['size_label'] as String));

      final double totalOpen =
          items.fold(0.0, (sum, it) => sum + (it['opening_qty'] as double? ?? 0.0));
      final double totalIn =
          items.fold(0.0, (sum, it) => sum + (it['in_qty'] as double? ?? 0.0));
      final double totalOut =
          items.fold(0.0, (sum, it) => sum + (it['out_qty'] as double? ?? 0.0));
      final double totalClosing =
          items.fold(0.0, (sum, it) => sum + (it['closing_qty'] as double? ?? 0.0));
      final double totalNet = totalIn - totalOut;

      processedCategories.add({
        'name': categoryName,
        'opening_qty': totalOpen,
        'in_qty': totalIn,
        'out_qty': totalOut,
        'closing_qty': totalClosing,
        'net_qty': totalNet,
        'items': items,
      });
    });

    processedCategories.sort((a, b) => SortingUtils.compareCategories(
        a['name'] as String, b['name'] as String));

    if (isDesktop) {
      return _buildDesktopEnterpriseView(
        grandOpening: grandOpening,
        grandInward: grandInward,
        grandOutward: grandOutward,
        grandClosing: grandClosing,
        activeCategoriesCount: activeCategoriesSet.length,
        categories: processedCategories,
      );
    }

    final double paddingValue = width >= 641 ? 24.0 : 16.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: _selectedTab == 'Summary'
          ? _buildMobileSummaryView(paddingValue, processedCategories)
          : _buildMobileDetailedView(paddingValue, processedCategories),
    );
  }

  // ===========================================================================
  // DESKTOP ENTERPRISE VIEW (KPI STRIP + MATERIAL 3 DATA TABLE)
  // ===========================================================================
  Widget _buildDesktopEnterpriseView({
    required double grandOpening,
    required double grandInward,
    required double grandOutward,
    required double grandClosing,
    required int activeCategoriesCount,
    required List<Map<String, dynamic>> categories,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top KPI Metrics Strip (4 Cards)
          _buildKpiMetricsStrip(
            opening: grandOpening,
            inward: grandInward,
            outward: grandOutward,
            closing: grandClosing,
            activeCount: activeCategoriesCount,
          ),
          const SizedBox(height: 24),

          // 2. Enterprise Data Table Container
          _buildEnterpriseTableCard(categories),
        ],
      ),
    );
  }

  Widget _buildKpiMetricsStrip({
    required double opening,
    required double inward,
    required double outward,
    required double closing,
    required int activeCount,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final double cardWidth = (constraints.maxWidth - 48) / 4;

      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _buildKpiCard(
            width: cardWidth.clamp(220.0, 380.0),
            title: "Total Opening Stock",
            value: "${opening.toStringAsFixed(3)} MT",
            badgeText: "Opening Balance",
            badgeColor: const Color(0xFF475569),
            badgeBg: const Color(0xFFF1F5F9),
            icon: Icons.inventory_2_outlined,
            accentColor: const Color(0xFF475569),
          ),
          _buildKpiCard(
            width: cardWidth.clamp(220.0, 380.0),
            title: "Total Inward Movement",
            value: "${inward.toStringAsFixed(3)} MT",
            badgeText: "Stock Inflow",
            badgeColor: const Color(0xFF16A34A),
            badgeBg: const Color(0xFFDCFCE7),
            icon: Icons.south_west_rounded,
            accentColor: const Color(0xFF16A34A),
          ),
          _buildKpiCard(
            width: cardWidth.clamp(220.0, 380.0),
            title: "Total Outward Movement",
            value: "${outward.toStringAsFixed(3)} MT",
            badgeText: "Dispatched",
            badgeColor: const Color(0xFFDC2626),
            badgeBg: const Color(0xFFFEE2E2),
            icon: Icons.north_east_rounded,
            accentColor: const Color(0xFFDC2626),
          ),
          _buildKpiCard(
            width: cardWidth.clamp(220.0, 380.0),
            title: "Total Closing Stock",
            value: "${closing.toStringAsFixed(3)} MT",
            badgeText: "Current Balance",
            badgeColor: const Color(0xFFC81E1E),
            badgeBg: const Color(0xFFFEE2E2),
            icon: Icons.account_balance_wallet_rounded,
            accentColor: const Color(0xFFC81E1E),
          ),
        ],
      );
    });
  }

  Widget _buildKpiCard({
    required double width,
    required String title,
    required String value,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: textDark,
              fontFamily: 'monospace',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textGrey.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterpriseTableCard(List<Map<String, dynamic>> categories) {
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                "No $_selectedFlow movement records found for ${widget.dateRangeLabel}.",
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final double grandOpen = categories.fold(
        0.0, (sum, cat) => sum + (cat['opening_qty'] as double? ?? 0.0));
    final double grandIn = categories.fold(
        0.0, (sum, cat) => sum + (cat['in_qty'] as double? ?? 0.0));
    final double grandOut = categories.fold(
        0.0, (sum, cat) => sum + (cat['out_qty'] as double? ?? 0.0));
    final double grandClosing = categories.fold(
        0.0, (sum, cat) => sum + (cat['closing_qty'] as double? ?? 0.0));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    "#",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    "CATEGORY / MATERIAL",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    "OPENING (MT)",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    "INWARD (MT)",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16A34A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    "OUTWARD (MT)",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDC2626),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    "CLOSING (MT)",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: msmRed,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Center(
                    child: Text(
                      "FLOW STATUS",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Center(
                    child: Text(
                      "DETAILS",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (context, idx) =>
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final String catName = (cat['name'] as String? ?? '').toUpperCase();
              final double openQty = cat['opening_qty'] as double? ?? 0.0;
              final double inQty = cat['in_qty'] as double? ?? 0.0;
              final double outQty = cat['out_qty'] as double? ?? 0.0;
              final double closingQty = cat['closing_qty'] as double? ?? 0.0;
              final double netQty = cat['net_qty'] as double? ?? 0.0;
              final List items = cat['items'] as List? ?? [];
              final bool isExpanded = _expandedCategories.contains(cat['name']);

              return _EnterpriseTableRow(
                index: index + 1,
                categoryName: catName,
                rawCategoryName: cat['name'] as String,
                openQty: openQty,
                inQty: inQty,
                outQty: outQty,
                closingQty: closingQty,
                netQty: netQty,
                items: items,
                isExpanded: isExpanded,
                selectedFlow: _selectedFlow,
                onToggleExpand: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedCategories.remove(cat['name']);
                    } else {
                      _expandedCategories.add(cat['name'] as String);
                    }
                  });
                },
              );
            },
          ),

          // Grand Total Pinned Bottom Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border(top: BorderSide(color: Color(0xFFCBD5E1), width: 1.5)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  flex: 3,
                  child: Text(
                    "TOTAL MOVEMENT SUMMARY",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    "${grandOpen.toStringAsFixed(3)} MT",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    "${grandIn.toStringAsFixed(3)} MT",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF16A34A),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    "${grandOut.toStringAsFixed(3)} MT",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFDC2626),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    "${grandClosing.toStringAsFixed(3)} MT",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: msmRed,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 130),
                const SizedBox(width: 70),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MOBILE VIEWS (SUMMARY & DETAILED)
  // ===========================================================================
  Widget _buildMobileSummaryView(
      double paddingValue, List<Map<String, dynamic>> categories) {
    final double grandClosingMt = categories.fold(
        0.0, (sum, cat) => sum + (cat['closing_qty'] as double? ?? 0.0));

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 8.0,
        bottom: 88.0,
      ),
      itemCount: categories.length + 1,
      itemBuilder: (context, index) {
        if (index == categories.length) {
          return Container(
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL CLOSING',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: textDark,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: msmRed.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    "${grandClosingMt.toStringAsFixed(3)} MT",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: msmRed,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final cat = categories[index];
        final String catName = (cat['name'] as String? ?? '').toUpperCase();
        final double openQty = cat['opening_qty'] as double? ?? 0.0;
        final double inQty = cat['in_qty'] as double? ?? 0.0;
        final double outQty = cat['out_qty'] as double? ?? 0.0;
        final double closingQty = cat['closing_qty'] as double? ?? 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    catName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: textDark,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      "${closingQty.toStringAsFixed(3)} MT",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: msmRed,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Open: ${openQty.toStringAsFixed(3)}",
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "In: +${inQty.toStringAsFixed(3)}",
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    "Out: -${outQty.toStringAsFixed(3)}",
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileDetailedView(
      double paddingValue, List<Map<String, dynamic>> categories) {
    final double grandTotalMt = categories.fold(0.0, (sum, cat) {
      final inQty = cat['in_qty'] as double? ?? 0.0;
      final outQty = cat['out_qty'] as double? ?? 0.0;
      final qty = _selectedFlow == 'Inward'
          ? inQty
          : _selectedFlow == 'Outward'
              ? outQty
              : (inQty - outQty);
      return sum + qty;
    });

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 8.0,
        bottom: 88.0,
      ),
      itemCount: categories.length + 1,
      itemBuilder: (context, index) {
        if (index == categories.length) {
          return Container(
            margin: const EdgeInsets.only(top: 4, bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: textDark,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _getFlowBgColor(grandTotalMt),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getFlowColor(grandTotalMt).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    "${_formatSignedNumber(grandTotalMt)} MT",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: _getFlowColor(grandTotalMt),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final cat = categories[index];
        final String catName = (cat['name'] as String? ?? '').toUpperCase();
        final inQty = cat['in_qty'] as double? ?? 0.0;
        final outQty = cat['out_qty'] as double? ?? 0.0;
        final double displayQty = _selectedFlow == 'Inward'
            ? inQty
            : _selectedFlow == 'Outward'
                ? outQty
                : (inQty - outQty);
        final List items = cat['items'] as List? ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      catName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: msmRed,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getFlowBgColor(displayQty),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "${_formatSignedNumber(displayQty)} MT",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _getFlowColor(displayQty),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context, idx) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, idx) {
                  final item = items[idx] as Map<String, dynamic>;
                  final String sizeLabel = item['size_label'] ?? '';
                  final parsedWeight =
                      double.tryParse(item['weight']?.toString() ?? '');
                  final double w = parsedWeight != null && parsedWeight > 0
                      ? parsedWeight
                      : lookupSizeWeight(sizeLabel);
                  final String formattedWeight =
                      w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
                  final String weightStr =
                      w != 0 ? "${formattedWeight}kg" : "";
                  final String itemDescription = (catName.toUpperCase() == 'MS ANGLE' || catName.toUpperCase() == 'ANGLE')
                      ? formatSizeLabel(sizeLabel, catName, w)
                      : (weightStr.isNotEmpty && !sizeLabel.toLowerCase().contains('kg')
                          ? "$sizeLabel $weightStr"
                          : sizeLabel);
                  final double itemIn = item['in_qty'] as double? ?? 0.0;
                  final double itemOut = item['out_qty'] as double? ?? 0.0;
                  final double itemQty = _selectedFlow == 'Inward'
                      ? itemIn
                      : _selectedFlow == 'Outward'
                          ? itemOut
                          : (itemIn - itemOut);

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          itemDescription,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: textDark,
                          ),
                        ),
                        Text(
                          "${_formatSignedNumber(itemQty)} MT",
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: _getFlowColor(itemQty),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// ENTERPRISE DATA TABLE ROW WITH ACCORDION SIZE BREAKDOWN
// =============================================================================
class _EnterpriseTableRow extends StatefulWidget {
  final int index;
  final String categoryName;
  final String rawCategoryName;
  final double openQty;
  final double inQty;
  final double outQty;
  final double closingQty;
  final double netQty;
  final List items;
  final bool isExpanded;
  final String selectedFlow;
  final VoidCallback onToggleExpand;

  const _EnterpriseTableRow({
    required this.index,
    required this.categoryName,
    required this.rawCategoryName,
    required this.openQty,
    required this.inQty,
    required this.outQty,
    required this.closingQty,
    required this.netQty,
    required this.items,
    required this.isExpanded,
    required this.selectedFlow,
    required this.onToggleExpand,
  });

  @override
  State<_EnterpriseTableRow> createState() => _EnterpriseTableRowState();
}

class _EnterpriseTableRowState extends State<_EnterpriseTableRow> {
  bool _isHovered = false;

  Color _getStatusColor() {
    if (widget.inQty > 0 && widget.outQty > 0) return const Color(0xFF7C3AED); // Purple
    if (widget.inQty > 0) return const Color(0xFF16A34A); // Green
    if (widget.outQty > 0) return const Color(0xFFDC2626); // Crimson
    return const Color(0xFF64748B); // Slate
  }

  String _getStatusText() {
    if (widget.inQty > 0 && widget.outQty > 0) return "IN & OUT FLOW";
    if (widget.inQty > 0) return "INWARD ONLY";
    if (widget.outQty > 0) return "OUTWARD ONLY";
    return "NO MOVEMENT";
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final statusText = _getStatusText();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        color: _isHovered ? const Color(0xFFF8FAFC) : Colors.white,
        child: Column(
          children: [
            InkWell(
              onTap: widget.onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        "${widget.index}",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textGrey.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: msmRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.category_rounded,
                              size: 16,
                              color: msmRed,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.categoryName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: textDark,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (widget.items.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    "${widget.items.length} size variants",
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: textGrey.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        "${widget.openQty.toStringAsFixed(3)} MT",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade800,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        widget.inQty > 0
                            ? "+${widget.inQty.toStringAsFixed(3)} MT"
                            : "—",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: widget.inQty > 0
                              ? const Color(0xFF16A34A)
                              : Colors.grey.shade400,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        widget.outQty > 0
                            ? "-${widget.outQty.toStringAsFixed(3)} MT"
                            : "—",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: widget.outQty > 0
                              ? const Color(0xFFDC2626)
                              : Colors.grey.shade400,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: Text(
                        "${widget.closingQty.toStringAsFixed(3)} MT",
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: msmRed,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Center(
                        child: IconButton(
                          icon: Icon(
                            widget.isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: widget.isExpanded ? msmRed : textGrey,
                          ),
                          onPressed: widget.onToggleExpand,
                          tooltip: widget.isExpanded
                              ? "Hide sizes"
                              : "Inspect size variants",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Inline Nested Size Breakdown Table
            if (widget.isExpanded && widget.items.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(52, 0, 24, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Subheader
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(Icons.straighten_rounded,
                              size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 8),
                          Text(
                            "SIZE BREAKDOWN FOR ${widget.categoryName}",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEDE9FE),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              "SIZE / SPECIFICATION",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B21B6)),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "UNIT WT (KG)",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B21B6)),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "OPENING (MT)",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B21B6)),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "INWARD (MT)",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B21B6)),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "OUTWARD (MT)",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B21B6)),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "CLOSING (MT)",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF5B21B6)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.items.length,
                      separatorBuilder: (context, idx) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, idx) {
                        final it = widget.items[idx] as Map<String, dynamic>;
                        final String sizeLabel = it['size_label'] ?? '';
                        final parsedW =
                            double.tryParse(it['weight']?.toString() ?? '');
                        final double w = parsedW != null && parsedW > 0
                            ? parsedW
                            : lookupSizeWeight(sizeLabel);
                        final double openM = it['opening_qty'] as double? ?? 0.0;
                        final double inM = it['in_qty'] as double? ?? 0.0;
                        final double outM = it['out_qty'] as double? ?? 0.0;
                        final double closeM = it['closing_qty'] as double? ?? (openM + inM - outM);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          color: idx % 2 == 1
                              ? Colors.white
                              : const Color(0xFFFAFAFA),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  sizeLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textDark,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  w > 0 ? "${w.toStringAsFixed(1)} kg" : "—",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  "${openM.toStringAsFixed(3)}",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  inM > 0
                                      ? "+${inM.toStringAsFixed(3)}"
                                      : "—",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: inM > 0
                                        ? const Color(0xFF16A34A)
                                        : Colors.grey.shade400,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  outM > 0
                                      ? "-${outM.toStringAsFixed(3)}"
                                      : "—",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: outM > 0
                                        ? const Color(0xFFDC2626)
                                        : Colors.grey.shade400,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  "${closeM.toStringAsFixed(3)}",
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: msmRed,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
