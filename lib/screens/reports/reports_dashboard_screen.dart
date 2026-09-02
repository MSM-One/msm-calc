import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_permissions.dart';
import '../../models/report_models.dart';
import '../../models/stock_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/access_guard.dart';
import '../../services/csv_report_service.dart';
import '../../services/data_repository.dart';
import '../../services/pdf_report_service.dart';
import '../../services/stock_notifier.dart';
import '../../services/supabase_realtime_service.dart';
import '../../services/report_calculators.dart';
import '../../utils/file_download_helper.dart' as download_helper;
import '../../utils/item_order_util.dart';
import '../../utils/sorting_utils.dart';
import '../../widgets/motion_toast.dart';
import '../../widgets/reports/enterprise_stock_movement_table.dart';
import '../../widgets/reports/reports_export_toolbar.dart';
import '../../widgets/reports/reports_sub_tab_bar.dart';
import '../../widgets/reports/stock_reports_kpi_banner.dart';
import 'low_stock_report_screen.dart';
import 'stock_ledger_screen.dart';
import 'todays_summary_screen.dart';

/// Enterprise Stock Reports Dashboard Screen.
/// Refactored to highest enterprise UI/UX analytics standard:
/// 1. Top 4-card metric strip (Total Yard Stock, Inward, Outward, Critical Alerts)
/// 2. Sub-report SegmentedControl / FilterBar
/// 3. Standardized high-contrast Data Tables with Canonical Category Ordering
/// 4. Compact Export Toolbar (Date Picker, Search, Location, PDF & CSV export)
class ReportsDashboardScreen extends StatefulWidget {
  final String? initialTabId;

  const ReportsDashboardScreen({super.key, this.initialTabId});

  @override
  State<ReportsDashboardScreen> createState() => _ReportsDashboardScreenState();
}

class _ReportsDashboardScreenState extends State<ReportsDashboardScreen> {
  // Navigation & Tabs
  late String _activeTabId;
  List<ReportSubTabItem> _availableTabs = [];

  // Filter State
  DateTime _startDate =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  String _selectedDatePreset = 'Today';
  String _locationFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // View Modes
  bool _isDetailedView = true;
  String _todaySummaryTabMode = 'Summary';
  String _todaySummaryFlowMode = 'Inward';

  // Expansion Sets
  final Set<String> _expandedMovementCategories = {};

  // Data Loading & Reports
  bool _isLoading = false;
  bool _isPdfExporting = false;
  bool _isCsvExporting = false;
  final Map<String, bool> _categoryDownloading = {};
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  // Data Lists
  List<StockMovementEntry> _stockReport = [];
  Map<String, Map<String, List<StockMovementEntry>>> _groupedReport = {};
  List<DeadStockEntry> _deadStockReport = [];
  List<DailyMovementEntry> _dailyMovementReport = [];

  // Filtered Datasets
  List<StockMovementEntry> _filteredStockReport = [];
  Map<String, Map<String, List<StockMovementEntry>>> _filteredGroupedReport = {};
  List<ItemVariant> _filteredLowStock = [];
  List<DeadStockEntry> _filteredDeadStock = [];
  List<DailyMovementEntry> _filteredDailyMovement = [];

  // Metrics
  double _kpiTotalStockMT = 0.0;
  double _kpiInwardMT = 0.0;
  double _kpiOutwardMT = 0.0;
  int _kpiCriticalAlertsCount = 0;

  @override
  void initState() {
    super.initState();
    _activeTabId = widget.initialTabId ?? 'today';
    if (_activeTabId == 'ledger') {
      final now = DateTime.now();
      _selectedDatePreset = 'This Month';
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month, now.day);
    }

    _initTabs();
    stockRefreshNotifier.addListener(_onStockDataChanged);
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _loadReports(forceRefresh: true);
    });

    _loadReports();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    stockRefreshNotifier.removeListener(_onStockDataChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onStockDataChanged() {
    if (!mounted) return;
    _loadReports(forceRefresh: true);
  }

  void _initTabs() {
    final user = DataRepository.currentUserNotifier.value;
    final List<ReportSubTabItem> allTabs = [
      const ReportSubTabItem(
        id: 'today',
        label: "Today's Summary",
        icon: Icons.today_rounded,
        permission: AppPermissions.reportsTodaySummary,
      ),
      const ReportSubTabItem(
        id: 'movement',
        label: 'Stock Movement',
        icon: Icons.swap_vert_rounded,
        permission: AppPermissions.reportsMovement,
      ),
      const ReportSubTabItem(
        id: 'ledger',
        label: 'Stock Ledger',
        icon: Icons.receipt_long_rounded,
        permission: AppPermissions.reportStockLedger,
      ),
      const ReportSubTabItem(
        id: 'low',
        label: 'Low Stock',
        icon: Icons.warning_amber_rounded,
        permission: AppPermissions.reportLowStock,
      ),
      const ReportSubTabItem(
        id: 'nonmoving',
        label: 'Non-Moving',
        icon: Icons.hourglass_empty_rounded,
        permission: AppPermissions.reportsNonMoving,
      ),
    ];

    _availableTabs = allTabs.where((tab) {
      if (tab.permission == null) return true;
      if (user != null) {
        return user.hasPermission(tab.permission!);
      }
      return AccessGuard.can(tab.permission!);
    }).toList();

    if (_availableTabs.isEmpty) {
      _availableTabs = allTabs;
    }

    if (!_availableTabs.any((t) => t.id == _activeTabId)) {
      _activeTabId = _availableTabs.first.id;
    }
  }

  void _onTabSelected(String tabId) {
    if (_activeTabId == tabId) return;
    setState(() {
      _activeTabId = tabId;
      if (tabId == 'today' &&
          (_selectedDatePreset == 'This Week' ||
              _selectedDatePreset == 'This Month' ||
              _selectedDatePreset == 'Last Month')) {
        _onDatePresetSelected('Today');
      } else if (tabId == 'ledger' &&
          (_selectedDatePreset == 'Today' ||
              _selectedDatePreset == 'Yesterday' ||
              _selectedDatePreset == 'This Week')) {
        _onDatePresetSelected('This Month');
      }
    });
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = query;
        _applySearchFilters();
      });
    });
  }

  void _onDatePresetSelected(String preset) {
    final now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, now.day);
    DateTime end = DateTime(now.year, now.month, now.day);

    if (preset == 'Today') {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day);
    } else if (preset == 'Yesterday') {
      final yest = now.subtract(const Duration(days: 1));
      start = DateTime(yest.year, yest.month, yest.day);
      end = DateTime(yest.year, yest.month, yest.day);
    } else if (preset == 'This Week') {
      start = now.subtract(Duration(days: now.weekday - 1));
      start = DateTime(start.year, start.month, start.day);
      end = DateTime(now.year, now.month, now.day);
    } else if (preset == 'This Month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month, now.day);
    } else if (preset == 'Last Month') {
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      final lastDayPrevMonth = DateTime(now.year, now.month, 0);
      start = prevMonth;
      end = lastDayPrevMonth;
    } else if (preset == 'Custom') {
      _selectCustomDateRange();
      return;
    }

    setState(() {
      _selectedDatePreset = preset;
      _startDate = start;
      _endDate = end;
    });

    _loadReports();
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD32F2F),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDatePreset = 'Custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReports();
    }
  }

  Future<void> _loadReports({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    try {
      final erpData = await DataRepository.getERPStockAsync(null);
      final locations = erpData['locations'] as List<dynamic>? ?? [];

      final rpcStockEntries = await DataRepository.fetchStockMovementEntries(
        startDate: _startDate,
        endDate: _endDate,
        location: _locationFilter,
      );

      final txList = await DataRepository.fetchStockMovement(
        startDate: _startDate,
        endDate: _endDate,
        location: _locationFilter,
      );

      _processData(txList, locations, rpcStockEntries);
    } catch (e, st) {
      debugPrint('[ReportsDashboardScreen] load error: $e');
      debugPrint('[ReportsDashboardScreen] stackTrace: $st');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _processData(
    List<StockTransaction> txs,
    List<dynamic> locations, [
    List<StockMovementEntry>? rpcStockEntries,
  ]) {
    if (!mounted) return;
    try {
      List<StockTransaction> visibleTxs = txs.where((tx) {
        final typeUpper = tx.type.trim().toUpperCase();
        return !tx.isReversed &&
            typeUpper != 'PURCHASE' &&
            !tx.txnId.startsWith('S-17') &&
            !tx.txnId.startsWith('IN_V_');
      }).toList();

      if (_locationFilter != 'ALL') {
        final filterLoc = _locationFilter.trim().toUpperCase();
        visibleTxs = visibleTxs.where((tx) {
          final rowLoc = tx.location.trim().toUpperCase();
          final toLoc = tx.toLocation?.trim().toUpperCase();
          return rowLoc == filterLoc || toLoc == filterLoc;
        }).toList();
      }

      if (rpcStockEntries != null && rpcStockEntries.isNotEmpty) {
        _stockReport = rpcStockEntries;
        _groupedReport =
            ReportCalculators.groupStocksByCategoryAndItem(_stockReport);
      } else {
        _stockReport = ReportCalculators.calculateStockMovement(
            visibleTxs, locations, _startDate, _endDate, _locationFilter);
        _groupedReport =
            ReportCalculators.groupStocksByCategoryAndItem(_stockReport);
      }

      try {
        _deadStockReport = ReportCalculators.calculateDeadStock(
            visibleTxs, locations, _endDate);
      } catch (_) {
        _deadStockReport = [];
      }

      try {
        _dailyMovementReport = ReportCalculators.calculateDailyMovement(
          visibleTxs,
          DateTimeRange(start: _startDate, end: _endDate),
          _stockReport,
        );
      } catch (_) {
        _dailyMovementReport = [];
      }

      _recomputeKpis();
      _applySearchFilters();
    } catch (e) {
      debugPrint('[ReportsDashboardScreen] process data error: $e');
    }
  }

  void _recomputeKpis() {
    _kpiTotalStockMT =
        _stockReport.fold(0.0, (sum, item) => sum + item.closing);
    _kpiInwardMT =
        _stockReport.fold(0.0, (sum, item) => sum + item.inQty);
    _kpiOutwardMT =
        _stockReport.fold(0.0, (sum, item) => sum + item.outQty);

    // Count negative closing balances + low stock items
    int negativeCount = 0;
    for (final entry in _stockReport) {
      for (final size in entry.sizes) {
        if (size.closing < 0) negativeCount++;
      }
    }

    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final lowStockCount = invProvider.lowStockItems.length;
    _kpiCriticalAlertsCount = negativeCount + (lowStockCount > 0 ? 1 : 0);

    // Expand all categories by default for high visual density
    if (_expandedMovementCategories.isEmpty) {
      _expandedMovementCategories.addAll(_groupedReport.keys);
    }
  }

  void _applySearchFilters() {
    final query = _searchQuery.toLowerCase().trim();

    // Stock Movement Filtering
    _filteredStockReport = _stockReport.where((e) {
      if (query.isEmpty) return true;
      final matchName = e.item.toLowerCase().contains(query);
      final matchCat = e.category.toLowerCase().contains(query);
      final matchSize =
          e.sizes.any((s) => s.label.toLowerCase().contains(query));
      return matchName || matchCat || matchSize;
    }).toList();

    _filteredGroupedReport =
        ReportCalculators.groupStocksByCategoryAndItem(_filteredStockReport);

    // Low Stock Filtering
    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final rawLowStock = invProvider.lowStockItems.where((item) {
      final matchesSearch = query.isEmpty ||
          item.itemName.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.size.toLowerCase().contains(query);

      if (_locationFilter == 'ALL') return matchesSearch;
      return matchesSearch &&
          item.location.trim().toUpperCase() ==
              _locationFilter.trim().toUpperCase();
    }).toList();

    final Map<String, ItemVariant> uniqueLowStockMap = {};
    for (var item in rawLowStock) {
      final key = '${item.itemName}|${item.size}';
      if (!uniqueLowStockMap.containsKey(key)) {
        uniqueLowStockMap[key] = item;
      } else {
        final existing = uniqueLowStockMap[key]!;
        uniqueLowStockMap[key] = ItemVariant(
          itemName: existing.itemName,
          category: existing.category,
          size: existing.size,
          currentStockMT: existing.currentStockMT + item.currentStockMT,
          minStock: existing.minStock,
          location: existing.location,
          yardTotal: existing.yardTotal,
          factoryTotal: existing.factoryTotal,
        );
      }
    }
    _filteredLowStock = uniqueLowStockMap.values.toList()
      ..sort((a, b) {
        int catComp = ItemOrderUtil.compare(a.category, b.category);
        if (catComp != 0) return catComp;
        int qtyComp = b.currentStockMT.compareTo(a.currentStockMT);
        if (qtyComp != 0) return qtyComp;
        return SortingUtils.compareSizes(a.size, b.size);
      });

    // Non-Moving Filtering
    _filteredDeadStock = _deadStockReport.where((e) {
      if (query.isEmpty) return true;
      return e.itemName.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query) ||
          e.size.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        int catComp = ItemOrderUtil.compare(a.category, b.category);
        if (catComp != 0) return catComp;
        return a.itemName.compareTo(b.itemName);
      });

    // Daily Movement Filtering
    _filteredDailyMovement = _dailyMovementReport.where((e) {
      if (query.isEmpty) return true;
      return e.itemName.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query) ||
          e.size.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        int catComp = ItemOrderUtil.compare(a.category, b.category);
        if (catComp != 0) return catComp;
        return SortingUtils.compareSizes(a.size, b.size);
      });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // EXPORT HANDLERS (PDF & CSV)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _handleExportPdf() async {
    if (_isPdfExporting) return;
    setState(() => _isPdfExporting = true);

    try {
      if (_activeTabId == 'movement') {
        if (_filteredStockReport.isEmpty) {
          MotionToast.show(context, 'No stock movement data to export',
              isError: true);
          return;
        }
        final bytes = await PdfReportService.generateMovementReport(
          startDate: _startDate,
          endDate: _endDate,
          location: _locationFilter,
          entries: _filteredStockReport,
          isDetailed: _isDetailedView,
        );
        final filename =
            'MSM_Stock_Movement_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
        await _saveAndSharePdf(bytes, filename, 'MSM Stock Movement Report');
      } else if (_activeTabId == 'today') {
        if (_filteredDailyMovement.isEmpty) {
          MotionToast.show(context, "No today's summary data to export",
              isError: true);
          return;
        }
        final bytes = await PdfReportService.generateDailySummaryPdf(
          date: _startDate,
          entries: _filteredDailyMovement,
          selectedMode: _todaySummaryTabMode,
          isOutward: _todaySummaryFlowMode == 'Outward',
          flowMode: _todaySummaryFlowMode,
          startDate: _startDate,
          endDate: _endDate,
        );
        final filename =
            'MSM_Daily_Summary_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
        await _saveAndSharePdf(bytes, filename, 'MSM Daily Summary Report');
      } else if (_activeTabId == 'low') {
        if (_filteredLowStock.isEmpty) {
          MotionToast.show(context, 'No low stock data to export',
              isError: true);
          return;
        }
        final bytes = await PdfReportService.generateCombinedLowStockPdf(
          entries: _filteredLowStock,
          location: _locationFilter,
          isDetailed: _isDetailedView,
          startDate: _startDate,
          endDate: _endDate,
        );
        final filename =
            'MSM_Low_Stock_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
        await _saveAndSharePdf(bytes, filename, 'MSM Low Stock Report');
      } else if (_activeTabId == 'nonmoving') {
        if (_filteredDeadStock.isEmpty) {
          MotionToast.show(context, 'No non-moving stock data to export',
              isError: true);
          return;
        }
        final bytes = await PdfReportService.generateCombinedDeadStockPdf(
          entries: _filteredDeadStock,
          location: _locationFilter,
          isDetailed: _isDetailedView,
          startDate: _startDate,
          endDate: _endDate,
        );
        final filename =
            'MSM_Non_Moving_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
        await _saveAndSharePdf(bytes, filename, 'MSM Non-Moving Stock Report');
      } else if (_activeTabId == 'ledger') {
        final allTxs = DataRepository.allTransactionsNotifier.value;
        final filteredTxs = allTxs.where((tx) {
          if (tx.isReversed) return false;
          if (_locationFilter != 'ALL') {
            final txLoc = tx.location.trim().toUpperCase();
            final toLoc = tx.toLocation?.trim().toUpperCase();
            if (txLoc != _locationFilter.toUpperCase() &&
                toLoc != _locationFilter.toUpperCase()) {
              return false;
            }
          }
          final txDate =
              DateTime(tx.dateTime.year, tx.dateTime.month, tx.dateTime.day);
          final filterStart =
              DateTime(_startDate.year, _startDate.month, _startDate.day);
          final filterEnd =
              DateTime(_endDate.year, _endDate.month, _endDate.day);

          if (!((txDate.isAtSameMomentAs(filterStart) ||
                  txDate.isAfter(filterStart)) &&
              (txDate.isAtSameMomentAs(filterEnd) ||
                  txDate.isBefore(filterEnd)))) {
            return false;
          }
          return true;
        }).toList();

        if (filteredTxs.isEmpty) {
          MotionToast.show(context, 'No transactions to export', isError: true);
          return;
        }

        await PdfReportService.generateStockLedgerReport(
          transactions: filteredTxs,
          currentDate: DateTime.now(),
          startDate: _startDate,
          endDate: _endDate,
        );
        return;
      }
    } catch (e, st) {
      debugPrint('[ReportsDashboardScreen] PDF Export error: $e');
      debugPrint('[ReportsDashboardScreen] stackTrace: $st');
      if (mounted) {
        MotionToast.show(context, 'Failed to export PDF: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isPdfExporting = false);
      }
    }
  }

  Future<void> _handleExportCsv() async {
    if (_isCsvExporting) return;
    setState(() => _isCsvExporting = true);

    try {
      if (_activeTabId == 'movement') {
        if (_filteredStockReport.isEmpty) {
          MotionToast.show(context, 'No data to export to CSV', isError: true);
          return;
        }
        await CsvReportService.exportStockMovementCsv(
          startDate: _startDate,
          endDate: _endDate,
          location: _locationFilter,
          entries: _filteredStockReport,
        );
      } else if (_activeTabId == 'today') {
        if (_filteredDailyMovement.isEmpty) {
          MotionToast.show(context, 'No data to export to CSV', isError: true);
          return;
        }
        await CsvReportService.exportTodaySummaryCsv(
          flowMode: _todaySummaryFlowMode,
          entries: _filteredDailyMovement,
          location: _locationFilter,
        );
      } else if (_activeTabId == 'low') {
        if (_filteredLowStock.isEmpty) {
          MotionToast.show(context, 'No data to export to CSV', isError: true);
          return;
        }
        await CsvReportService.exportLowStockCsv(
          items: _filteredLowStock,
          location: _locationFilter,
        );
      } else if (_activeTabId == 'nonmoving') {
        if (_filteredDeadStock.isEmpty) {
          MotionToast.show(context, 'No data to export to CSV', isError: true);
          return;
        }
        await CsvReportService.exportDeadStockCsv(
          entries: _filteredDeadStock,
          location: _locationFilter,
        );
      } else if (_activeTabId == 'ledger') {
        final allTxs = DataRepository.allTransactionsNotifier.value;
        await CsvReportService.exportStockLedgerCsv(
          transactions: allTxs,
          location: _locationFilter,
        );
      }
      if (mounted) {
        MotionToast.show(context, 'CSV Exported successfully!');
      }
    } catch (e, st) {
      debugPrint('[ReportsDashboardScreen] CSV Export error: $e');
      debugPrint('[ReportsDashboardScreen] stackTrace: $st');
      if (mounted) {
        MotionToast.show(context, 'Failed to export CSV: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isCsvExporting = false);
      }
    }
  }

  Future<void> _exportCategoryPdf(
      String category, Map<String, List<StockMovementEntry>> items) async {
    if (_categoryDownloading[category] == true) return;
    setState(() => _categoryDownloading[category] = true);

    try {
      final double total =
          items.values.expand((x) => x).fold(0.0, (s, e) => s + e.closing);

      final bytes = await PdfReportService.generateCategoryMovementPdf(
        categoryName: category,
        startDate: _startDate,
        endDate: _endDate,
        location: _locationFilter,
        items: items,
        totalClosing: total,
        isDetailed: _isDetailedView,
      );

      final safeName =
          category.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
      final filename =
          '${safeName}_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

      await _saveAndSharePdf(bytes, filename, 'MSM $category Report');
    } catch (e, st) {
      debugPrint('[ReportsDashboardScreen] category PDF error: $e');
      debugPrint('[ReportsDashboardScreen] stackTrace: $st');
      if (mounted) {
        MotionToast.show(context, 'Failed to export $category report',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _categoryDownloading[category] = false);
      }
    }
  }

  Future<void> _saveAndSharePdf(
      Uint8List bytes, String filename, String shareText) async {
    if (kIsWeb) {
      download_helper.downloadFile(bytes, filename);
    } else {
      final directory = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: shareText);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI BUILD
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate 50
      body: SafeArea(
        child: Column(
          children: [
            // 1. Sticky Compact Horizontal Metric Ribbon (48px)
            StockReportsKpiBanner(
              totalStockMT: _kpiTotalStockMT,
              inwardMT: _kpiInwardMT,
              outwardMT: _kpiOutwardMT,
              criticalAlertsCount: _kpiCriticalAlertsCount,
              locationLabel: _locationFilter == 'ALL'
                  ? 'All Locations'
                  : (_locationFilter == 'YARD'
                      ? 'Yard Stock'
                      : 'Factory Stock'),
              dateRangeLabel: _selectedDatePreset == 'Custom'
                  ? '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM').format(_endDate)}'
                  : _selectedDatePreset,
              onTotalStockTap: () => _onTabSelected('movement'),
              onInwardTap: () {
                setState(() {
                  _todaySummaryFlowMode = 'Inward';
                  _onTabSelected('today');
                });
              },
              onOutwardTap: () {
                setState(() {
                  _todaySummaryFlowMode = 'Outward';
                  _onTabSelected('today');
                });
              },
              onAlertsTap: () => _onTabSelected('low'),
            ),

            // Top Control Bar (Sub-tabs & Export toolbar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Sub-Report Tab Switcher Bar
                  Row(
                    children: [
                      Expanded(
                        child: ReportsSubTabBar(
                          activeTabId: _activeTabId,
                          tabs: _availableTabs,
                          onTabSelected: _onTabSelected,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 3. Compact Export Toolbar
                  ReportsExportToolbar(
                    startDate: _startDate,
                    endDate: _endDate,
                    selectedDatePreset: _selectedDatePreset,
                    locationFilter: _locationFilter,
                    searchController: _searchController,
                    onSearch: _onSearchChanged,
                    onDateRangeTap: _selectCustomDateRange,
                    onPresetSelected: _onDatePresetSelected,
                    onLocationChanged: (val) {
                      if (val != null) {
                        setState(() => _locationFilter = val);
                        _loadReports();
                      }
                    },
                    onRefresh: () => _loadReports(forceRefresh: true),
                    onExportPdf: _handleExportPdf,
                    onExportCsv: _handleExportCsv,
                    isPdfLoading: _isPdfExporting,
                    isCsvLoading: _isCsvExporting,
                    showViewToggle: _activeTabId == 'movement' ||
                        _activeTabId == 'low' ||
                        _activeTabId == 'today',
                    isDetailedView: _isDetailedView,
                    onViewToggle: (val) => setState(() => _isDetailedView = val),
                    todayTabMode: _todaySummaryTabMode,
                    onTodayTabModeChanged: (val) {
                      setState(() {
                        _todaySummaryTabMode = val;
                        _isDetailedView = val == 'Detailed';
                      });
                    },
                    todayFlowMode: _todaySummaryFlowMode,
                    onTodayFlowModeChanged: (val) =>
                        setState(() => _todaySummaryFlowMode = val),
                    activeTabId: _activeTabId,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Main Sub-Report Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFD32F2F),
                        ),
                      )
                    : _buildActiveTabContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTabId) {
      case 'today':
        return TodaySummaryTab(
          isLoading: _isLoading,
          filteredDailyMovement: _filteredDailyMovement,
          selectedTab: _todaySummaryTabMode,
          selectedFlow: _todaySummaryFlowMode,
          dateRangeLabel: _selectedDatePreset.toLowerCase(),
          emptyState: _buildEmptyState(
            title: 'No movements for ${_selectedDatePreset.toLowerCase()}',
            subtitle: 'No stock movements recorded in this period',
          ),
          onTabChanged: (tab) {
            setState(() {
              _todaySummaryTabMode = tab;
              _isDetailedView = tab == 'Detailed';
            });
          },
          onFlowChanged: (flow) {
            setState(() => _todaySummaryFlowMode = flow);
          },
        );

      case 'movement':
        return EnterpriseStockMovementTable(
          groupedReport: _filteredGroupedReport,
          isDetailed: _isDetailedView,
          expandedCategories: _expandedMovementCategories,
          onCategoryToggle: (cat) {
            setState(() {
              if (_expandedMovementCategories.contains(cat)) {
                _expandedMovementCategories.remove(cat);
              } else {
                _expandedMovementCategories.add(cat);
              }
            });
          },
          onExportCategoryPdf: _exportCategoryPdf,
          categoryDownloading: _categoryDownloading,
          locationFilter: _locationFilter,
          emptyState: _buildEmptyState(
            title: 'No stock movement records',
            subtitle: 'No transactions found for the selected period & location',
          ),
        );

      case 'ledger':
        return StockLedgerScreen(
          isLoading: _isLoading,
          isDesktop: true,
          searchQuery: _searchQuery,
          startDate: _startDate,
          endDate: _endDate,
          locationFilter: _locationFilter,
        );

      case 'low':
        return _buildLowStockContent();

      case 'nonmoving':
        return _buildNonMovingContent();

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLowStockContent() {
    if (_filteredLowStock.isEmpty) {
      return _buildEmptyState(
        title: 'All items well stocked',
        subtitle: 'No items currently below safety threshold levels',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _filteredLowStock.length,
      itemBuilder: (context, index) {
        final item = _filteredLowStock[index];
        final itemMap = {
          'category': item.category,
          'item_name': item.itemName,
          'size': item.size,
          'qty': item.currentStockMT,
          'currentStockMT': item.currentStockMT,
          'location': item.location,
        };
        return LowStockItemCard(item: itemMap);
      },
    );
  }

  Widget _buildNonMovingContent() {
    if (_filteredDeadStock.isEmpty) {
      return _buildEmptyState(
        title: 'No non-moving stock',
        subtitle: 'All items have active movements in the selected period',
      );
    }

    final df = DateFormat('dd MMM yyyy');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _filteredDeadStock.length,
      itemBuilder: (context, index) {
        final item = _filteredDeadStock[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x04000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hourglass_empty_rounded,
                  size: 20,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.itemName} - ${item.size}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Category: ${item.category} • Inactive for ${item.daysSinceLastMovement} days',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (item.lastMovementDate != null)
                      Text(
                        'Last moved: ${df.format(item.lastMovementDate!)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${item.currentQty.toStringAsFixed(3)} MT',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: item.currentQty < 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F172A),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Balance',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.analytics_outlined,
                size: 48,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
