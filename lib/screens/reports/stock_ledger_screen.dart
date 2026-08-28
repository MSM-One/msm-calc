import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/stock_models.dart';
import '../../services/data_repository.dart';
import '../../utils/sorting_utils.dart';
import '../../utils/formatters.dart';
import '../../widgets/m_loader.dart';
import '../../services/pdf_report_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SAFE PARSING & FORMATTING HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Safe double parser — avoids casting bool, null, or unrelated types to double.
double parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0; // Prevent boolean flags from throwing cast exceptions
}

/// Centralized quantity formatting — exactly 3 decimal places.
String _formatQty(dynamic val, {bool includeSuffix = false}) {
  final double dVal = parseDouble(val);
  final double absVal = dVal.abs() < 0.00001 ? 0.0 : dVal;
  final String formatted = absVal.toStringAsFixed(3);
  return includeSuffix ? "$formatted MT" : formatted;
}

/// Helper to assign consistent category icons.
IconData _getCategoryIcon(String catName) {
  final lower = catName.toLowerCase();
  if (lower.contains('pipe')) return Icons.architecture_rounded;
  if (lower.contains('angle') || lower.contains('channel')) {
    return Icons.grid_view_rounded;
  }
  if (lower.contains('bar') || lower.contains('flat')) {
    return Icons.view_in_ar_rounded;
  }
  if (lower.contains('wire')) return Icons.cable_rounded;
  if (lower.contains('nail')) return Icons.build_rounded;
  if (lower.contains('structure') || lower.contains('ism')) {
    return Icons.domain_rounded;
  }
  return Icons.inventory_2_outlined;
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Aggregated size/SKU balance within a date range.
class SkuLedgerSummary {
  final String itemName;
  final String size;
  final String category;
  final double openingStock;
  final double inwardQty;
  final double outwardQty;
  final double closingStock;

  SkuLedgerSummary({
    required this.itemName,
    required this.size,
    required this.category,
    required dynamic openingStock,
    required dynamic inwardQty,
    required dynamic outwardQty,
    required dynamic closingStock,
  })  : openingStock = parseDouble(openingStock),
        inwardQty = parseDouble(inwardQty),
        outwardQty = parseDouble(outwardQty),
        closingStock = parseDouble(closingStock);

  double get opening => openingStock;
  // ignore: non_constant_identifier_names
  double get opening_mt => openingStock;
  // ignore: non_constant_identifier_names
  double get opening_balance => openingStock;
  double get closing => closingStock;

  String get skuId => '${itemName}_$size';
}

/// Category Group containing unique SKU summaries.
class CategoryLedgerGroup {
  final String categoryId;
  final String categoryName;
  final List<SkuLedgerSummary> skus;

  CategoryLedgerGroup({
    required this.categoryId,
    required this.categoryName,
    required this.skus,
  });

  double get totalOpening =>
      skus.fold(0.0, (sum, s) => sum + parseDouble(s.openingStock));
  double get totalInward =>
      skus.fold(0.0, (sum, s) => sum + parseDouble(s.inwardQty));
  double get totalOutward =>
      skus.fold(0.0, (sum, s) => sum + parseDouble(s.outwardQty));
  double get totalClosing => totalOpening + totalInward - totalOutward;

  int get negativeCount =>
      skus.where((s) => parseDouble(s.closingStock) < 0).length;

  String get statusText {
    final double c = parseDouble(totalClosing);
    if (c > 0) return 'In Stock';
    if (c.abs() < 0.0001) return 'Out of Stock';
    return 'Negative Stock';
  }

  Color get statusBg {
    final double c = parseDouble(totalClosing);
    if (c > 0) return const Color(0xFFDCFCE7);
    if (c.abs() < 0.0001) return const Color(0xFFF3F4F6);
    return const Color(0xFFFEE2E2);
  }

  Color get statusTextColor {
    final double c = parseDouble(totalClosing);
    if (c > 0) return const Color(0xFF15803D);
    if (c.abs() < 0.0001) return const Color(0xFF4B5563);
    return const Color(0xFFB91C1C);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class StockLedgerScreen extends StatefulWidget {
  final bool isLoading;
  final bool isDesktop;
  final String searchQuery;
  final DateTime? startDate;
  final DateTime? endDate;
  final String locationFilter;

  const StockLedgerScreen({
    super.key,
    required this.isLoading,
    this.isDesktop = false,
    this.searchQuery = '',
    this.startDate,
    this.endDate,
    this.locationFilter = 'ALL',
  });

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  static const double kExportBarHeight = 48.0;

  String? _expandedCategoryId;
  List<CategoryLedgerGroup> _cachedCategoryGroups = [];
  List<StockTransaction> _filteredTransactionsForPdf = [];
  bool _isCalculating = true;
  List<StockTransaction>? _lastProcessedTxs;

  DateTime get _effectiveStartDate => widget.startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime get _effectiveEndDate => widget.endDate ?? DateTime.now();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(StockLedgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool fetchNeeded = false;
    bool filterNeeded = false;

    if (widget.startDate != oldWidget.startDate ||
        widget.endDate != oldWidget.endDate ||
        widget.locationFilter != oldWidget.locationFilter) {
      fetchNeeded = true;
    }

    if (widget.searchQuery != oldWidget.searchQuery) {
      filterNeeded = true;
    }

    final txs =
        _lastProcessedTxs ?? DataRepository.allTransactionsNotifier.value;
    if (fetchNeeded) {
      _scheduleLedgerCalculation(txs, force: true);
    } else if (filterNeeded) {
      _recomputeSummariesOnly(txs);
    }
  }

  void _recomputeSummariesOnly(List<StockTransaction> allTransactions) {
    if (!mounted) return;
    _scheduleLedgerCalculation(allTransactions, force: true);
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Size Formatting Helpers ────────────────────────────────────────────────

  bool _lacksPhysicalWeight(String itemName) {
    final lower = itemName.toLowerCase();
    return lower.contains('sqr') ||
        lower.contains('round') ||
        lower.contains('flat') ||
        lower.contains('gate');
  }

  String _formatSize(String itemName, String sizeLabel) {
    if (_lacksPhysicalWeight(itemName)) return sizeLabel;
    double unitWeight = parseDouble(lookupSizeWeight(sizeLabel));
    if (unitWeight == 0) unitWeight = _extractUnitWeight(sizeLabel);
    if ((itemName.toUpperCase() == 'MS ANGLE' || itemName.toUpperCase() == 'ANGLE') && unitWeight > 0) {
      return formatSizeLabel(sizeLabel, itemName, unitWeight);
    }
    return getFormattedSizeDisplay(sizeLabel, unitWeight);
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
        return parseDouble(val);
      }
    } catch (_) {}
    return 0.0;
  }

  // ── Ledger Computation ─────────────────────────────────────────────────────

  void _scheduleLedgerCalculation(List<StockTransaction> allTransactions,
      {bool force = false}) {
    if (!force && _lastProcessedTxs == allTransactions && !_isCalculating) {
      return;
    }
    _lastProcessedTxs = allTransactions;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_isCalculating) {
        setState(() {
          _isCalculating = true;
        });
      }

      Map<String, Map<String, dynamic>> rawLedgerMap;
      try {
        rawLedgerMap = await DataRepository.fetchStockLedgerDataFromRpc(
          startDate: _effectiveStartDate,
          endDate: _effectiveEndDate,
          selectedLocation: widget.locationFilter,
        );
      } catch (e) {
        debugPrint(
            '[StockLedger] Error fetching from RPC, falling back to local: $e');
        rawLedgerMap = {};
      }

      if (rawLedgerMap.isEmpty) {
        rawLedgerMap = DataRepository.calculateStockLedgerData(
          transactions: allTransactions,
          startDate: _effectiveStartDate,
          endDate: _effectiveEndDate,
          selectedLocation: widget.locationFilter,
        );
      }

      if (!mounted) return;
      final result = _computeCategorySummaries(allTransactions, rawLedgerMap);
      if (mounted) {
        setState(() {
          _cachedCategoryGroups = result.categoryGroups;
          _filteredTransactionsForPdf = result.pdfTransactions;
          _isCalculating = false;

          // Preserve expanded category if still present in filtered results
          if (_expandedCategoryId != null &&
              !_cachedCategoryGroups
                  .any((g) => g.categoryId == _expandedCategoryId)) {
            _expandedCategoryId = null;
          }
        });
      }
    });
  }

  ({
    List<CategoryLedgerGroup> categoryGroups,
    List<StockTransaction> pdfTransactions
  }) _computeCategorySummaries(List<StockTransaction> allTxs,
      Map<String, Map<String, dynamic>> rawLedgerMap) {
    final startOfDay =
        DateTime(_effectiveStartDate.year, _effectiveStartDate.month, _effectiveStartDate.day);
    final endOfDay =
        DateTime(_effectiveEndDate.year, _effectiveEndDate.month, _effectiveEndDate.day, 23, 59, 59, 999);

    // 1. Filter by Location
    final locationFilteredTxs = allTxs.where((tx) {
      if (widget.locationFilter == 'ALL') return true;
      final txLoc = tx.location.trim().toUpperCase();
      return txLoc == widget.locationFilter;
    }).toList();

    // Transactions matching date range for PDF export
    final pdfTxs = locationFilteredTxs.where((tx) {
      final txDate = tx.dateTime;
      return (txDate.isAtSameMomentAs(startOfDay) ||
              txDate.isAfter(startOfDay)) &&
          (txDate.isAtSameMomentAs(endOfDay) || txDate.isBefore(endOfDay));
    }).toList();

    final Map<String, List<SkuLedgerSummary>> categorySkuMap = {};

    for (var itemKey in rawLedgerMap.keys) {
      final item = rawLedgerMap[itemKey]!;
      final String itemName = item['itemName']?.toString() ?? '';
      final String size = item['size']?.toString() ?? '';
      final String rawCat = (item['category']?.toString()?.isNotEmpty == true &&
              item['category'] != 'General')
          ? item['category'].toString()
          : (itemName.isNotEmpty ? itemName : detectCategory(itemName));
      final String cat = DataRepository.canonicalizeCategory(rawCat);

      final double opening = parseDouble(
          item['opening'] ?? item['opening_mt'] ?? item['opening_balance']);
      final double inward = parseDouble(item['inward']);
      final double outward = parseDouble(item['outward']);
      final double closing = opening + inward - outward;

      if (['Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB']
              .contains(cat) &&
          opening == 0 &&
          inward == 0 &&
          outward == 0 &&
          closing == 0) {
        continue;
      }

      // Filter by Search Query
      if (widget.searchQuery.isNotEmpty) {
        final query = widget.searchQuery.toLowerCase();
        final matchesItem = itemName.toLowerCase().contains(query);
        final matchesSize = size.toLowerCase().contains(query);
        final matchesCat = cat.toLowerCase().contains(query);
        if (!matchesItem && !matchesSize && !matchesCat) continue;
      }

      final summary = SkuLedgerSummary(
        itemName: itemName,
        size: size,
        category: cat,
        openingStock: opening,
        inwardQty: inward,
        outwardQty: outward,
        closingStock: closing,
      );

      categorySkuMap.putIfAbsent(cat, () => []);
      categorySkuMap[cat]!.add(summary);
    }

    final sortedCatNames = categorySkuMap.keys.toList()
      ..sort(SortingUtils.compareCategories);

    final List<CategoryLedgerGroup> categoryGroups = [];
    for (var catName in sortedCatNames) {
      final skus = categorySkuMap[catName]!;
      skus.sort((a, b) => SortingUtils.compareSizes(a.size, b.size));
      final catId =
          catName.toUpperCase().trim().replaceAll(RegExp(r'\s+'), '_');

      categoryGroups.add(CategoryLedgerGroup(
        categoryId: catId,
        categoryName: catName,
        skus: skus,
      ));
    }

    return (categoryGroups: categoryGroups, pdfTransactions: pdfTxs);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<StockTransaction>>(
      valueListenable: DataRepository.allTransactionsNotifier,
      builder: (context, allTransactions, child) {
        if (_lastProcessedTxs != allTransactions || _isCalculating) {
          _scheduleLedgerCalculation(allTransactions);
        }

        if (_isCalculating || widget.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF9FAFB),
            body: Center(child: MLoader()),
          );
        }

        final categoryGroups = _cachedCategoryGroups;

        double grandOpening = categoryGroups.fold(
            0.0, (sum, g) => sum + parseDouble(g.totalOpening));
        double grandInward = categoryGroups.fold(
            0.0, (sum, g) => sum + parseDouble(g.totalInward));
        double grandOutward = categoryGroups.fold(
            0.0, (sum, g) => sum + parseDouble(g.totalOutward));
        double grandClosing = categoryGroups.fold(
            0.0, (sum, g) => sum + parseDouble(g.totalClosing));

        return Scaffold(
          backgroundColor: const Color(0xFFF9FAFB),
          body: widget.isLoading
              ? const Center(child: MLoader())
              : Column(
                  children: [
                    // ── Enterprise KPI Summary Strip ─────────────────────────
                    if (widget.isDesktop) Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          _buildEnterpriseKpiCard('Opening Stock', _formatQty(grandOpening, includeSuffix: true), const Color(0xFF64748B), Icons.inventory_2_outlined),
                          const SizedBox(width: 12),
                          _buildEnterpriseKpiCard('Period In', _formatQty(grandInward, includeSuffix: true), const Color(0xFF16A34A), Icons.arrow_downward_rounded),
                          const SizedBox(width: 12),
                          _buildEnterpriseKpiCard('Period Out', _formatQty(grandOutward, includeSuffix: true), const Color(0xFFDC2626), Icons.arrow_upward_rounded),
                          const SizedBox(width: 12),
                          _buildEnterpriseKpiCard('Net Remaining', _formatQty(grandClosing, includeSuffix: true), grandClosing >= 0 ? const Color(0xFF0284C7) : const Color(0xFFDC2626), Icons.account_balance_wallet_outlined),
                        ],
                      ),
                    ),
                    
                    // ── Main Content ──────────────────────
                    Expanded(
                      child: categoryGroups.isEmpty
                          ? const Center(
                              child: Text(
                                "No transactions match your search/filters.",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold),
                              ),
                            )
                          : widget.isDesktop
                              ? _EnterpriseStockLedgerTable(
                                  categoryGroups: categoryGroups,
                                  formatSize: _formatSize,
                                  grandOpening: grandOpening,
                                  grandInward: grandInward,
                                  grandOutward: grandOutward,
                                  grandClosing: grandClosing,
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.only(
                                      left: 14, right: 14, top: 4, bottom: 96),
                                  itemCount: categoryGroups.length,
                                  itemBuilder: (context, index) {
                                    final group = categoryGroups[index];
                                    final bool isExpanded =
                                        group.categoryId == _expandedCategoryId;

                                    return _CategorySummaryCard(
                                      group: group,
                                      isExpanded: isExpanded,
                                      formatSize: _formatSize,
                                      onExpansionChanged: (expanded) {
                                        setState(() {
                                          _expandedCategoryId =
                                              expanded ? group.categoryId : null;
                                        });
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          floatingActionButton: widget.isDesktop ? null : SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: kExportBarHeight,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB71C1C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  onPressed: () async {
                    if (_filteredTransactionsForPdf.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("No transactions to export")),
                      );
                      return;
                    }
                    await PdfReportService.generateStockLedgerReport(
                      transactions: _filteredTransactionsForPdf,
                      currentDate: DateTime.now(),
                      startDate: _effectiveStartDate,
                      endDate: _effectiveEndDate,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.white, size: 20),
                  label: const Text(
                    "Export PDF",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnterpriseKpiCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — CATEGORY SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _CategorySummaryCard extends StatelessWidget {
  final CategoryLedgerGroup group;
  final bool isExpanded;
  final String Function(String itemName, String sizeLabel) formatSize;
  final ValueChanged<bool> onExpansionChanged;

  const _CategorySummaryCard({
    required this.group,
    required this.isExpanded,
    required this.formatSize,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final IconData catIcon = _getCategoryIcon(group.categoryName);
    final String closingStr =
        _formatQty(parseDouble(group.totalClosing), includeSuffix: true);
    final int skuCount = group.skus.length;
    final int negCount = group.negativeCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Semantics(
        label:
            "${group.categoryName}, $skuCount sizes, closing stock $closingStr, ${isExpanded ? 'expanded' : 'collapsed'}",
        button: true,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey(group.categoryId),
            initiallyExpanded: isExpanded,
            onExpansionChanged: onExpansionChanged,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(catIcon, color: msmRed, size: 20),
            ),
            title: Text(
              group.categoryName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textDark,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: group.statusBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      group.statusText,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: group.statusTextColor,
                      ),
                    ),
                  ),
                  Text(
                    "· $skuCount ${skuCount == 1 ? 'size' : 'sizes'}",
                    style: const TextStyle(
                      fontSize: 11,
                      color: textGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (negCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Text(
                        "· $negCount negative",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  closingStr,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: parseDouble(group.totalClosing) >= 0
                        ? textDark
                        : const Color(0xFFB91C1C),
                  ),
                ),
                const SizedBox(height: 2),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey,
                  size: 18,
                ),
              ],
            ),
            children: [
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),
              _CategoryDetailTable(
                group: group,
                formatSize: formatSize,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — COLUMNAR DETAIL TABLE (5-column)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryDetailTable extends StatefulWidget {
  final CategoryLedgerGroup group;
  final String Function(String itemName, String sizeLabel) formatSize;

  const _CategoryDetailTable({
    required this.group,
    required this.formatSize,
  });

  @override
  State<_CategoryDetailTable> createState() => _CategoryDetailTableState();
}

class _CategoryDetailTableState extends State<_CategoryDetailTable> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final formatSize = widget.formatSize;

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: PageStorageKey('scroll_${group.categoryId}'),
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Container(
          constraints: const BoxConstraints(minWidth: 640),
          width: 680,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              // ── Table Header ────────────────────────────────────────
              Container(
                color: const Color(0xFFF3F4F6),
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: Text(
                        "SIZE DESCRIPTION",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569)),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        "OPENING",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569)),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        "PERIOD IN",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569)),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        "PERIOD OUT",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569)),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        "NET REMAINING",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Data Rows (Zebra Striping) ──────────────────────────
              ...group.skus.asMap().entries.map((entry) {
                final int idx = entry.key;
                final sku = entry.value;
                return _LedgerSizeRow(
                  sku: sku,
                  isEven: idx % 2 == 0,
                  formatSize: formatSize,
                );
              }),

              // ── Category Subtotal Row ───────────────────────────────
              _LedgerSubtotalRow(group: group),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIZE DATA ROW
// ─────────────────────────────────────────────────────────────────────────────

class _LedgerSizeRow extends StatelessWidget {
  final SkuLedgerSummary sku;
  final bool isEven;
  final String Function(String itemName, String sizeLabel) formatSize;

  const _LedgerSizeRow({
    required this.sku,
    required this.isEven,
    required this.formatSize,
  });

  @override
  Widget build(BuildContext context) {
    final String sizeDisplay = formatSize(sku.itemName, sku.size);
    final String titleText = sizeDisplay.isNotEmpty
        ? "${sku.itemName} - $sizeDisplay"
        : sku.itemName;

    // All numeric values through parseDouble — safe from bool/null casts
    final double openingVal = parseDouble(sku.opening);
    final double inwardVal = parseDouble(sku.inwardQty);
    final double outwardVal = parseDouble(sku.outwardQty);
    final double closingVal = openingVal + inwardVal - outwardVal;
    final bool isNeg = closingVal < 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFF9FAFB),
        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          // Size Description — left-aligned
          SizedBox(
            width: 240,
            child: Text(
              titleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B)),
            ),
          ),
          // Opening — right-aligned neutral
          SizedBox(
            width: 90,
            child: Text(
              _formatQty(openingVal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155)),
            ),
          ),
          // Inward — right-aligned soft green
          SizedBox(
            width: 90,
            child: Text(
              _formatQty(inwardVal),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: inwardVal > 0 ? FontWeight.w700 : FontWeight.normal,
                color: inwardVal > 0
                    ? const Color(0xFF15803D)
                    : const Color(0xFF334155),
              ),
            ),
          ),
          // Outward — right-aligned soft red (positive, no minus sign)
          SizedBox(
            width: 90,
            child: Text(
              _formatQty(outwardVal),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight:
                    outwardVal > 0 ? FontWeight.w700 : FontWeight.normal,
                color: outwardVal > 0
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFF334155),
              ),
            ),
          ),
          // Closing — right-aligned bold with MT suffix
          SizedBox(
            width: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isNeg)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFB91C1C), size: 13),
                  ),
                Flexible(
                  child: Text(
                    _formatQty(closingVal, includeSuffix: true),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isNeg
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY SUBTOTAL ROW
// ─────────────────────────────────────────────────────────────────────────────

class _LedgerSubtotalRow extends StatelessWidget {
  final CategoryLedgerGroup group;

  const _LedgerSubtotalRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final double totalOpening = parseDouble(group.totalOpening);
    final double totalInward = parseDouble(group.totalInward);
    final double totalOutward = parseDouble(group.totalOutward);
    final double totalClosing = parseDouble(group.totalClosing);

    return Container(
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Text(
              "TOTAL ${group.categoryName.toUpperCase()}",
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A)),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _formatQty(totalOpening),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A)),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _formatQty(totalInward),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF15803D)),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _formatQty(totalOutward),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB91C1C)),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _formatQty(totalClosing, includeSuffix: true),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: totalClosing >= 0
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// ENTERPRISE STOCK LEDGER TABLE (Material 3)
// ─────────────────────────────────────────────────────────────────────────────

class _EnterpriseStockLedgerTable extends StatefulWidget {
  final List<CategoryLedgerGroup> categoryGroups;
  final String Function(String, String) formatSize;
  final double grandOpening;
  final double grandInward;
  final double grandOutward;
  final double grandClosing;

  const _EnterpriseStockLedgerTable({
    required this.categoryGroups,
    required this.formatSize,
    required this.grandOpening,
    required this.grandInward,
    required this.grandOutward,
    required this.grandClosing,
  });

  @override
  State<_EnterpriseStockLedgerTable> createState() => _EnterpriseStockLedgerTableState();
}

class _EnterpriseStockLedgerTableState extends State<_EnterpriseStockLedgerTable> {
  final Set<String> _expandedRows = {};

  void _toggleRow(String id) {
    setState(() {
      if (_expandedRows.contains(id)) {
        _expandedRows.remove(id);
      } else {
        _expandedRows.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const SizedBox(width: 40, child: Text("#", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                const Expanded(flex: 3, child: Text("Category / Material", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12))),
                Expanded(flex: 2, child: _rightAlign("Opening (MT)")),
                Expanded(flex: 2, child: _rightAlign("Period In (MT)", color: const Color(0xFF16A34A))),
                Expanded(flex: 2, child: _rightAlign("Period Out (MT)", color: const Color(0xFFDC2626))),
                Expanded(flex: 2, child: _rightAlign("Closing / Balance", color: const Color(0xFF0F172A))),
                const Expanded(flex: 2, child: Center(child: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12)))),
                const SizedBox(width: 60, child: Center(child: Text("Details", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12)))),
              ],
            ),
          ),
          // Table Body
          Expanded(
            child: ListView.separated(
              itemCount: widget.categoryGroups.length,
              separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final group = widget.categoryGroups[index];
                final isExpanded = _expandedRows.contains(group.categoryId);
                return _buildTableRow(index + 1, group, isExpanded);
              },
            ),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const SizedBox(width: 40),
                const Expanded(
                  flex: 3,
                  child: Text("GRAND TOTAL", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: 14)),
                ),
                Expanded(flex: 2, child: _rightAlign(_formatQty(widget.grandOpening), isBold: true)),
                Expanded(flex: 2, child: _rightAlign(_formatQty(widget.grandInward), isBold: true, color: const Color(0xFF16A34A))),
                Expanded(flex: 2, child: _rightAlign(_formatQty(widget.grandOutward), isBold: true, color: const Color(0xFFDC2626))),
                Expanded(flex: 2, child: _rightAlign(_formatQty(widget.grandClosing), isBold: true)),
                const Expanded(flex: 2, child: SizedBox()),
                const SizedBox(width: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightAlign(String text, {bool isBold = false, Color? color}) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
        color: color ?? const Color(0xFF64748B),
        fontSize: 12,
        fontFamily: 'monospace',
      ),
    );
  }

  Widget _buildTableRow(int index, CategoryLedgerGroup group, bool isExpanded) {
    return Column(
      children: [
        InkWell(
          onTap: () => _toggleRow(group.categoryId),
          hoverColor: const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(width: 40, child: Text("$index", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13))),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(_getCategoryIcon(group.categoryName), size: 18, color: const Color(0xFFB71C1C)),
                      const SizedBox(width: 8),
                      Text(group.categoryName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                        child: Text("${group.skus.length}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                      ),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: _rightAlign(_formatQty(parseDouble(group.totalOpening)))),
                Expanded(flex: 2, child: _rightAlign(_formatQty(parseDouble(group.totalInward)), color: const Color(0xFF16A34A))),
                Expanded(flex: 2, child: _rightAlign(_formatQty(parseDouble(group.totalOutward)), color: const Color(0xFFDC2626))),
                Expanded(flex: 2, child: _rightAlign(_formatQty(parseDouble(group.totalClosing)), isBold: true, color: parseDouble(group.totalClosing) < 0 ? const Color(0xFFDC2626) : const Color(0xFF0F172A))),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: group.statusBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(group.statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: group.statusTextColor)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Center(
                    child: Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: const Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.fromLTRB(56, 8, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(flex: 3, child: Text("Size / Spec", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                    Expanded(flex: 2, child: _rightAlign("Opening")),
                    Expanded(flex: 2, child: _rightAlign("In")),
                    Expanded(flex: 2, child: _rightAlign("Out")),
                    Expanded(flex: 2, child: _rightAlign("Closing")),
                    const Expanded(flex: 2, child: SizedBox()), // spacer for status
                    const SizedBox(width: 60), // spacer for details icon
                  ],
                ),
                const SizedBox(height: 8),
                ...group.skus.map((sku) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(widget.formatSize(sku.itemName, sku.size), style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                      ),
                      Expanded(flex: 2, child: _rightAlign(_formatQty(sku.openingStock))),
                      Expanded(flex: 2, child: _rightAlign(_formatQty(sku.inwardQty))),
                      Expanded(flex: 2, child: _rightAlign(_formatQty(sku.outwardQty))),
                      Expanded(flex: 2, child: _rightAlign(_formatQty(sku.closingStock), isBold: true)),
                      const Expanded(flex: 2, child: SizedBox()),
                      const SizedBox(width: 60),
                    ],
                  ),
                )),
              ],
            ),
          ),
      ],
    );
  }
}
