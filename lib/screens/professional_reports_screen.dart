import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../services/stock_notifier.dart';
import '../services/data_repository.dart';
import '../services/pdf_report_service.dart';
import '../services/excel_report_service.dart';
import '../models/stock_models.dart';
import '../models/report_models.dart';
import '../providers/inventory_provider.dart';
import '../utils/sorting_utils.dart';
import '../widgets/m_loader.dart';
import '../widgets/low_stock_widgets.dart';
import '../widgets/msm_date_filter_sheet.dart';
import '../widgets/motion_toast.dart';
import 'reports/low_stock_report_screen.dart';
import 'reports/todays_summary_screen.dart';
import 'reports/stock_ledger_screen.dart';
import 'reports/reports_dashboard_screen.dart';
import 'reports/desktop_reports_screen.dart';
export 'reports/reports_dashboard_screen.dart';
export 'reports/desktop_reports_screen.dart';
import '../utils/file_download_helper.dart' as download_helper;

import '../services/supabase_service.dart';
import '../services/supabase_realtime_service.dart';

import '../utils/formatters.dart';

String formatNumber(double n) => n.toStringAsFixed(3);

/// Appends " kg" or weight to a size label unless the category is one of the
/// excluded bar/wire types that are measured differently.
String _appendKgSuffix(String category, String sizeLabel) {
  const excludedCategories = [
    'sqr bar',
    'round bar',
    'flats',
    'barbed wire',
    'gate channel',
  ];
  final lower = category.toLowerCase();
  final isExcluded = excludedCategories.any((ex) => lower.contains(ex));
  if (isExcluded) return sizeLabel;
  return formatSizeWithWeight(sizeLabel, null);
}

enum LowStockExportType {
  itemWise,
  sizeWise,
  combined,
}

class ProfessionalReportsScreen extends StatefulWidget {
  final String? initialTabId;
  const ProfessionalReportsScreen({super.key, this.initialTabId});

  @override
  _ProfessionalReportsScreenState createState() =>
      _ProfessionalReportsScreenState();
}

class _ProfessionalReportsScreenState extends State<ProfessionalReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _startDate =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  String _selectedDatePreset = 'Today';
  String _locationFilter = 'ALL';
  List<Map<String, dynamic>> _activeTabs = [];

  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Data lists
  List<StockMovementEntry> _stockReport = [];
  Map<String, Map<String, List<StockMovementEntry>>> _groupedReport = {};
  List<DeadStockEntry> _deadStockReport = [];
  List<DailyMovementEntry> _dailyMovementReport = [];

  // Optimization: Pre-filtered lists
  List<ItemVariant> _filteredLowStock = [];
  List<StockMovementEntry> _filteredStockReport = [];
  Map<String, Map<String, List<StockMovementEntry>>> _filteredGroupedReport =
      {};
  List<String> _filteredSortedCategories = [];
  List<DeadStockEntry> _filteredDeadStock = [];
  List<DailyMovementEntry> _filteredDailyMovement = [];
  Timer? _searchDebounce;

  // Display State
  bool _isDetailedView = false;
  String _todaySummaryTabMode = 'Summary';
  String _todaySummaryFlowMode = 'Inward';
  bool get isDesktop => MediaQuery.of(context).size.width >= 1025;
  bool get isTablet =>
      MediaQuery.of(context).size.width >= 641 &&
      MediaQuery.of(context).size.width <= 1024;
  bool get isMobile => MediaQuery.of(context).size.width <= 640;
  double _kpiTotalInventory = 0;
  String? _selectedCategoryMobile;
  String? _expandedLowStockCategory; // Mobile expansion
  String? _expandedNonMovingCategory; // Mobile expansion
  Set<String> _expandedLowStockCategories = {}; // Desktop multiple expansion
  final Set<String> _expandedStockMovementCategories = {};
  final Map<String, bool> _categoryDownloading = {};
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _initTabs();
    stockRefreshNotifier.addListener(_onStockDataChanged);
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _generateReports(forceRefresh: true);
    });
    int initialIdx = 0;
    if (widget.initialTabId != null) {
      initialIdx =
          _activeTabs.indexWhere((t) => t['id'] == widget.initialTabId);
      if (initialIdx == -1) initialIdx = 0;
      if (widget.initialTabId == 'ledger') {
        final now = DateTime.now();
        _selectedDatePreset = 'This Month';
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day);
      }
    }
    _tabController = TabController(
        length: _activeTabs.length, vsync: this, initialIndex: initialIdx);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        final String currentTabId =
            _activeTabs[_tabController.index]['id'] as String;
        if (currentTabId == 'today' &&
            (_selectedDatePreset == 'This Week' ||
                _selectedDatePreset == 'This Month' ||
                _selectedDatePreset == 'Last Month')) {
          _onDatePresetSelected('Today');
        } else if (currentTabId == 'ledger' &&
            (_selectedDatePreset == 'Today' ||
                _selectedDatePreset == 'Yesterday' ||
                _selectedDatePreset == 'This Week')) {
          _onDatePresetSelected('This Month');
        } else if (currentTabId != 'today' &&
            currentTabId != 'ledger' &&
            (_selectedDatePreset == 'Yesterday' ||
                _selectedDatePreset == 'Last Month')) {
          _onDatePresetSelected('Today');
        } else {
          setState(() {});
        }
      }
    });
    _generateReports();
  }

  void _onStockDataChanged() {
    if (!mounted) return;
    _generateReports(forceRefresh: true);
  }

  void _initTabs() {
    final user = DataRepository.currentUserNotifier.value;
    final allTabs = [
      {
        'title': "Today's Summary",
        'icon': Icons.today_outlined,
        'id': 'today',
        'permission': AppPermissions.reportsTodaySummary,
      },
      {
        'title': 'Stock Movement',
        'icon': Icons.swap_vert_rounded,
        'id': 'movement',
        'permission': AppPermissions.reportsMovement,
      },
      {
        'title': 'Low Stock',
        'icon': Icons.warning_amber_rounded,
        'id': 'low',
        'permission': AppPermissions.reportLowStock,
      },
      {
        'title': 'Non-Moving Stock',
        'icon': Icons.block_outlined,
        'id': 'nonmoving',
        'permission': AppPermissions.reportsNonMoving,
      },
      {
        'title': 'Stock Ledger',
        'icon': Icons.list_alt_rounded,
        'id': 'ledger',
        'permission': AppPermissions.reportStockLedger,
      },
    ];

    _activeTabs = allTabs.where((tab) {
      final perm = tab['permission'] as String;
      if (user != null) {
        return user.hasPermission(perm);
      }
      return AccessGuard.can(perm);
    }).toList();

    if (_activeTabs.isEmpty) {
      _activeTabs = allTabs;
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    stockRefreshNotifier.removeListener(_onStockDataChanged);
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = v;
        _applySearchFilters();
      });
    });
  }

  void _applySearchFilters() {
    final query = _searchQuery.toLowerCase();

    // Low Stock
    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final rawLowStock = invProvider.lowStockItems.where((item) {
      final matchesSearch = query.isEmpty ||
          item.itemName.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);

      if (_locationFilter == 'ALL') return matchesSearch;
      final itemLoc = item.location.trim().toUpperCase();
      final filterLoc = _locationFilter.trim().toUpperCase();
      return matchesSearch && itemLoc == filterLoc;
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
    final List<ItemVariant> lowStockList = uniqueLowStockMap.values.toList();
    lowStockList.sort((a, b) {
      int catComp = SortingUtils.compareCategories(a.category, b.category);
      if (catComp != 0) return catComp;
      int qtyComp = b.currentStockMT.compareTo(a.currentStockMT);
      if (qtyComp != 0) return qtyComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
    _filteredLowStock = lowStockList;

    // Stock Movement
    _filteredStockReport = _stockReport
        .where((e) =>
            e.item.toLowerCase().contains(query) ||
            e.category.toLowerCase().contains(query))
        .toList();
    _filteredGroupedReport =
        ReportCalculators.groupStocksByCategoryAndItem(_filteredStockReport);
    _filteredSortedCategories = _filteredGroupedReport.keys.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    // Non-Moving Stock
    _filteredDeadStock = _deadStockReport.where((e) {
      if (query.isEmpty) return true;
      return e.itemName.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query) ||
          e.size.toLowerCase().contains(query);
    }).toList();

    // Today's Summary
    _filteredDailyMovement = _dailyMovementReport.where((e) {
      if (query.isEmpty) return true;
      return e.itemName.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query);
    }).toList();

    _applyCommonSorting();
  }

  void _applyCommonSorting() {
    // Stock Movement
    _filteredStockReport
        .sort((a, b) => SortingUtils.compareCategories(a.item, b.item));
    for (var entry in _filteredStockReport) {
      entry.sizes.sort((a, b) => SortingUtils.compareSizes(a.label, b.label));
    }

    // Non-Moving
    _filteredDeadStock.sort((a, b) {
      int catComp = SortingUtils.compareCategories(a.category, b.category);
      if (catComp != 0) return catComp;
      int itemComp = a.itemName.compareTo(b.itemName);
      if (itemComp != 0) return itemComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });

    // Daily
    _filteredDailyMovement.sort((a, b) {
      int itemComp = SortingUtils.compareCategories(a.itemName, b.itemName);
      if (itemComp != 0) return itemComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
  }

  Future<void> _generateReports({bool forceRefresh = false}) async {
    final activeTabId = _activeTabs[_tabController.index]['id'];
    debugPrint("[REPORT LOAD] $activeTabId");

    setState(() {
      _isLoading = true;
      _expandedLowStockCategory = null;
      _expandedLowStockCategories.clear();
    });

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
    } catch (e) {
      debugPrint("[REPORT ERROR] $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _processData(List<StockTransaction> txs, List<dynamic> locations,
      [List<StockMovementEntry>? rpcStockEntries]) {
    if (!mounted) return;
    try {
      debugPrint('[DesktopReports] selectedLocation=$_locationFilter');
      debugPrint('[DesktopReports] raw transactions=${txs.length}');

      // Exclude reversed transactions, PURCHASE transaction types & IN_V_ legacy vendor receipt rows
      List<StockTransaction> visibleTxs = txs.where((tx) {
        final typeUpper = tx.type.trim().toUpperCase();
        return !tx.isReversed &&
            typeUpper != 'PURCHASE' &&
            !tx.txnId.startsWith('S-17') &&
            !tx.txnId.startsWith('IN_V_');
      }).toList();

      // Filter transactions by location up-front for ALL calculators
      if (_locationFilter != 'ALL') {
        final filterLoc = _locationFilter.trim().toUpperCase();
        visibleTxs = visibleTxs.where((tx) {
          final rowLoc = tx.location.trim().toUpperCase();
          final toLoc = tx.toLocation?.trim().toUpperCase();
          return rowLoc == filterLoc || toLoc == filterLoc;
        }).toList();
      }

      debugPrint('[DesktopReports] filtered transactions=${visibleTxs.length}');

      if (rpcStockEntries != null && rpcStockEntries.isNotEmpty) {
        _stockReport = rpcStockEntries;
        _groupedReport =
            ReportCalculators.groupStocksByCategoryAndItem(_stockReport);
      } else {
        _calculateStockMovement(visibleTxs, locations);
      }

      try {
        _deadStockReport = ReportCalculators.calculateDeadStock(
            visibleTxs, locations, _endDate);
      } catch (e) {
        debugPrint("[REPORT ERROR] $e");
        _deadStockReport = [];
      }

      try {
        _dailyMovementReport = ReportCalculators.calculateDailyMovement(
            visibleTxs, DateTimeRange(start: _startDate, end: _endDate), _stockReport);
      } catch (e) {
        debugPrint("[REPORT ERROR] $e");
        _dailyMovementReport = [];
      }

      _recomputeKpis();
      _applySearchFilters();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("[REPORT ERROR] $e");
    }
  }

  void _calculateStockMovement(
      List<StockTransaction> allTxs, List<dynamic> locations) {
    _stockReport = ReportCalculators.calculateStockMovement(
        allTxs, locations, _startDate, _endDate, _locationFilter);
    _groupedReport =
        ReportCalculators.groupStocksByCategoryAndItem(_stockReport);
  }

  void _recomputeKpis() {
    _kpiTotalInventory =
        _stockReport.fold(0, (sum, item) => sum + item.closing);
  }

  Future<void> fetchStockMovementData() async {
    await _generateReports();
  }

  void _onDatePresetSelected(String preset) async {
    final now = DateTime.now();
    if (preset == 'Today') {
      setState(() {
        _selectedDatePreset = 'Today';
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day);
      });
      await fetchStockMovementData();
    } else if (preset == 'Yesterday') {
      final yesterday = now.subtract(const Duration(days: 1));
      setState(() {
        _selectedDatePreset = 'Yesterday';
        _startDate =
            DateTime(yesterday.year, yesterday.month, yesterday.day, 0, 0, 0);
        _endDate = DateTime(
            yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
      });
      await fetchStockMovementData();
    } else if (preset == 'This Week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      setState(() {
        _selectedDatePreset = 'This Week';
        _startDate = DateTime(monday.year, monday.month, monday.day);
        _endDate = DateTime(now.year, now.month, now.day);
      });
      await fetchStockMovementData();
    } else if (preset == 'This Month') {
      setState(() {
        _selectedDatePreset = 'This Month';
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day);
      });
      await fetchStockMovementData();
    } else if (preset == 'Last Month') {
      final firstDayThisMonth = DateTime(now.year, now.month, 1);
      final lastDayLastMonth =
          firstDayThisMonth.subtract(const Duration(days: 1));
      final firstDayLastMonth =
          DateTime(lastDayLastMonth.year, lastDayLastMonth.month, 1);
      setState(() {
        _selectedDatePreset = 'Last Month';
        _startDate = firstDayLastMonth;
        _endDate = DateTime(lastDayLastMonth.year, lastDayLastMonth.month,
            lastDayLastMonth.day, 23, 59, 59);
      });
      await fetchStockMovementData();
    } else if (preset == 'Custom') {
      _selectDateRange();
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: msmRed,
              onPrimary: Colors.white,
              onSurface: textDark,
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
      await fetchStockMovementData();
    }
  }

  void _showLocationFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Select Location",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.maps_home_work_outlined),
              title: const Text("ALL"),
              onTap: () {
                setState(() => _locationFilter = "ALL");
                _generateReports();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.factory_outlined),
              title: const Text("FACTORY"),
              onTap: () {
                setState(() => _locationFilter = "FACTORY");
                _generateReports();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warehouse_outlined),
              title: const Text("YARD"),
              onTap: () {
                setState(() => _locationFilter = "YARD");
                _generateReports();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndSharePdf(
      Uint8List bytes, String filename, String shareText) async {
    try {
      if (kIsWeb) {
        // Direct download for desktop web Chrome compatibility
        download_helper.downloadFile(bytes, filename);
      } else {
        final directory = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        final file = File("${directory.path}/$filename");
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], text: shareText);
      }
    } catch (e, st) {
      debugPrint('[ReportsExport] _saveAndSharePdf error: $e');
      debugPrint('[ReportsExport] StackTrace: $st');
      rethrow;
    }
  }

  List<Map<String, dynamic>> _getFilteredLowStockData() {
    final Map<String, Map<String, dynamic>> uniqueMap = {};

    // Use the same data currently displayed on screen (_filteredLowStock)
    for (var item in _filteredLowStock) {
      final key = '${item.itemName}|${item.size}';
      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = {
          'category': item.category,
          'item': item.itemName,
          'size': item.size,
          'qty': item.availableStockMT,
          'closing_mt': item.availableStockMT,
          'low_stock_qty': item.availableStockMT,
        };
      } else {
        final double existing = uniqueMap[key]!['qty'] as double;
        final double aggregated = existing + item.availableStockMT;
        uniqueMap[key]!['qty'] = aggregated;
        uniqueMap[key]!['closing_mt'] = aggregated;
        uniqueMap[key]!['low_stock_qty'] = aggregated;
      }
    }

    final List<Map<String, dynamic>> results = uniqueMap.values.toList();
    results.sort((a, b) {
      int catComp =
          SortingUtils.compareCategories(a['category'], b['category']);
      if (catComp != 0) return catComp;
      return SortingUtils.compareSizes(a['size'], b['size']);
    });

    return results;
  }

  Future<void> _exportLowStockReport(LowStockExportType type) async {
    if (kIsWeb) {
      print("PDF export clicked: low");
    }
    debugPrint('[LowStockExport] type=$type location=$_locationFilter');
    final rows = _getFilteredLowStockData();

    if (rows.isEmpty) {
      MotionToast.show(context, "No low stock data to export", isError: true);
      return;
    }

    try {
      final String timestamp = DateFormat('yyyyMMdd').format(DateTime.now());
      String typeSuffix = '';
      if (type == LowStockExportType.itemWise) typeSuffix = 'item_wise_qty';
      if (type == LowStockExportType.sizeWise) typeSuffix = 'size_wise_qty';
      if (type == LowStockExportType.combined) typeSuffix = 'combined';

      final String fileName = 'low_stock_${typeSuffix}_report_$timestamp.pdf';
      final String typeStr = type.toString().split('.').last;

      final bytes = await PdfReportService.generateLowStockEnhancedPdf(
        rows: rows,
        type: typeStr,
        location: _locationFilter,
        dateRange: 'As of ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
      );

      await _saveAndSharePdf(bytes, fileName, 'Low Stock Report');
    } catch (e) {
      debugPrint('[LowStockExport] Error: $e');
      MotionToast.show(context, "Failed to export Low Stock report: $e",
          isError: true);
    }
  }

  Future<void> _exportPdf({LowStockExportType? lowStockType}) async {
    final tabId = _activeTabs[_tabController.index]['id'];

    // Add console log as requested for desktop web
    if (kIsWeb) {
      print("PDF export clicked: $tabId");
    }

    try {
      if (tabId == 'low') {
        if (lowStockType != null) {
          await _exportLowStockReport(lowStockType);
          return;
        }

        // Fallback or mobile legacy logic if needed, but for desktop we want the menu
        // Use the same data currently displayed on screen (_filteredLowStock)
        List<ItemVariant> items = _filteredLowStock;

        if (items.isEmpty) {
          MotionToast.show(context, 'No low stock data to export',
              isError: true);
          return;
        }

        final bool isDetailPrint = _isDetailedView;
        List<ItemVariant> printItems = items;

        final bytes = await PdfReportService.generateCombinedLowStockPdf(
          entries: printItems,
          location: _locationFilter,
          isDetailed: isDetailPrint,
          startDate: _startDate,
          endDate: _endDate,
        );

        final filename = isDetailPrint
            ? 'MSM_Low_Stock_Detailed.pdf'
            : 'MSM_Low_Stock_Summary.pdf';

        await _saveAndSharePdf(bytes, filename,
            isDetailPrint ? 'MSM Low Stock Detailed' : 'MSM Low Stock Summary');
        return;
      }

      if (tabId == 'nonmoving') {
        final filtered = _filteredDeadStock;

        if (filtered.isEmpty) {
          MotionToast.show(context, 'No non-moving stock data to export',
              isError: true);
          return;
        }

        final bytes = await PdfReportService.generateCombinedDeadStockPdf(
          entries: filtered,
          location: _locationFilter,
          isDetailed: _isDetailedView,
          startDate: _startDate,
          endDate: _endDate,
        );
        await _saveAndSharePdf(bytes, 'MSM_Non_Moving_Stock_Report.pdf',
            'MSM Non-Moving Stock Report');
        return;
      }

      if (tabId == 'ledger') {
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

          if (_searchQuery.isNotEmpty) {
            final query = _searchQuery.toLowerCase();
            final matchesItem = tx.itemName.toLowerCase().contains(query);
            final matchesSize = tx.size.toLowerCase().contains(query);
            final matchesCat = tx.category.toLowerCase().contains(query);
            if (!matchesItem && !matchesSize && !matchesCat) return false;
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

      if (tabId == 'today') {
        final filtered = _filteredDailyMovement;

        if (filtered.isEmpty) {
          MotionToast.show(
              context, 'No movement data to export for the selected period',
              isError: true);
          return;
        }

        final bytes = await PdfReportService.generateDailySummaryPdf(
          date: _startDate,
          entries: filtered,
          selectedMode: _todaySummaryTabMode,
          isOutward: _todaySummaryFlowMode == 'Outward',
          flowMode: _todaySummaryFlowMode,
          startDate: _startDate,
          endDate: _endDate,
        );

        final bool isSameDay = _startDate.year == _endDate.year &&
            _startDate.month == _endDate.month &&
            _startDate.day == _endDate.day;
        final String pdfDateSuffix = isSameDay
            ? DateFormat('yyyyMMdd').format(_startDate)
            : '${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}';
        await _saveAndSharePdf(
            bytes, 'MSM_Summary_$pdfDateSuffix.pdf', 'MSM Summary Report');
        return;
      }

      if (tabId != 'movement') return;

      final filtered = _filteredStockReport;

      if (filtered.isEmpty) {
        MotionToast.show(context, 'No stock movement data to export',
            isError: true);
        return;
      }

      final bytes = await PdfReportService.generateMovementReport(
        entries: filtered,
        startDate: _startDate,
        endDate: _endDate,
        location: _locationFilter,
        isDetailed: _isDetailedView,
        reportTitle: _isDetailedView
            ? 'DETAILED STOCK MOVEMENT REPORT'
            : 'STOCK MOVEMENT SUMMARY',
      );

      final filename =
          'MSM_Inventory_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      await _saveAndSharePdf(bytes, filename, 'MSM Inventory Report');
    } catch (e, st) {
      debugPrint('[ReportsExport] Error exporting PDF: $e');
      debugPrint('[ReportsExport] StackTrace: $st');
      if (mounted) {
        MotionToast.show(context, 'Failed to export report', isError: true);
      }
    }
  }

  Future<void> _exportExcel() async {
    final tabId = _activeTabs[_tabController.index]['id'];

    if (kIsWeb) {
      print("Excel export clicked: $tabId");
    }

    try {
      if (tabId == 'today') {
        final filtered = _filteredDailyMovement;
        if (filtered.isEmpty) {
          MotionToast.show(
              context, 'No movement data to export for the selected period',
              isError: true);
          return;
        }

        final excelBytes = ExcelReportService.generateDailySummaryExcel(
          date: _startDate,
          entries: filtered,
        );

        if (excelBytes == null || excelBytes.isEmpty) {
          MotionToast.show(context, 'Failed to generate Excel file',
              isError: true);
          return;
        }

        final bool isSameDay = _startDate.year == _endDate.year &&
            _startDate.month == _endDate.month &&
            _startDate.day == _endDate.day;
        final String dateSuffix = isSameDay
            ? DateFormat('yyyyMMdd').format(_startDate)
            : '${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}';
        final String filename = 'MSM_Summary_$dateSuffix.xlsx';

        await _saveAndSharePdf(
            Uint8List.fromList(excelBytes), filename, 'MSM Summary Excel');
        return;
      }

      if (tabId == 'movement') {
        final filtered = _filteredStockReport;
        if (filtered.isEmpty) {
          MotionToast.show(context, 'No stock movement data to export',
              isError: true);
          return;
        }

        final excelBytes = ExcelReportService.generateStockMovementExcel(
          entries: filtered,
          startDate: _startDate,
          endDate: _endDate,
          location: _locationFilter,
        );

        if (excelBytes == null || excelBytes.isEmpty) {
          MotionToast.show(context, 'Failed to generate Excel file',
              isError: true);
          return;
        }

        final filename =
            'MSM_Stock_Movement_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
        await _saveAndSharePdf(
            Uint8List.fromList(excelBytes), filename, 'MSM Stock Movement Excel');
        return;
      }

      if (tabId == 'nonmoving') {
        final filtered = _filteredDeadStock;
        if (filtered.isEmpty) {
          MotionToast.show(context, 'No non-moving stock data to export',
              isError: true);
          return;
        }

        final excelBytes = ExcelReportService.generateDeadStockExcel(
          entries: filtered,
        );

        if (excelBytes == null || excelBytes.isEmpty) {
          MotionToast.show(context, 'Failed to generate Excel file',
              isError: true);
          return;
        }

        final filename =
            'MSM_Non_Moving_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
        await _saveAndSharePdf(
            Uint8List.fromList(excelBytes), filename, 'MSM Non-Moving Stock Excel');
        return;
      }
    } catch (e, st) {
      debugPrint('[ReportsExport] Error exporting Excel: $e');
      debugPrint('[ReportsExport] StackTrace: $st');
      if (mounted) {
        MotionToast.show(context, 'Failed to export Excel report: $e',
            isError: true);
      }
    }
  }

  Future<void> _exportCategoryPdf(
      String category, Map<String, List<StockMovementEntry>> items) async {
    if (_categoryDownloading[category] == true) return;

    setState(() {
      _categoryDownloading[category] = true;
    });

    try {
      // Robust category mapping (especially for Nails/NAILS)
      final normalizedCat = SortingUtils.normalizeCategoryName(category);
      Map<String, List<StockMovementEntry>> finalItems = items;

      if (finalItems.isEmpty) {
        debugPrint(
            '[ReportsExport] Items map empty for $category, searching grouped report...');
        final foundKey = _filteredGroupedReport.keys.firstWhere(
            (k) => SortingUtils.normalizeCategoryName(k) == normalizedCat,
            orElse: () => '');
        if (foundKey.isNotEmpty) {
          finalItems = _filteredGroupedReport[foundKey]!;
          debugPrint('[ReportsExport] Found match via key: $foundKey');
        }
      }

      final reportMode = _isDetailedView ? 'Detailed' : 'Summary';
      debugPrint(
          '[ReportsExport] Exporting category=$category location=$_locationFilter mode=$reportMode items=${finalItems.length}');

      double total =
          finalItems.values.expand((x) => x).fold(0, (s, e) => s + e.closing);

      final bytes = await PdfReportService.generateCategoryMovementPdf(
        categoryName: category,
        startDate: _startDate,
        endDate: _endDate,
        location: _locationFilter,
        items: finalItems,
        totalClosing: total,
        isDetailed: _isDetailedView,
      );

      final safeName =
          category.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
      final filename =
          '${safeName}_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

      await _saveAndSharePdf(bytes, filename, 'MSM $category Report');
    } catch (e, st) {
      debugPrint('[ReportsExport] Failed category=$category error=$e');
      debugPrint('[ReportsExport] StackTrace: $st');
      if (mounted) {
        MotionToast.show(context, 'Failed to export $category report',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _categoryDownloading[category] = false;
        });
      }
    }
  }

  Future<void> _exportLowStockCategoryPdf(
      String category, List<Map<String, dynamic>> items) async {
    if (_categoryDownloading[category] == true) return;

    setState(() {
      _categoryDownloading[category] = true;
    });

    try {
      // Per User Request: Export ONLY the selected category
      final bytes = await PdfReportService.generateCombinedLowStockPdf(
        entries:
            _filteredLowStock.where((e) => e.category == category).toList(),
        location: _locationFilter,
        isDetailed: _isDetailedView,
        startDate: _startDate,
        endDate: _endDate,
      );

      final filename =
          'msm_low_stock_${category.toLowerCase().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      await _saveAndSharePdf(
          bytes, filename, 'MSM Low Stock Report: $category');
    } catch (e, st) {
      debugPrint("Error exporting low stock combined PDF: $e");
      debugPrint("Stacktrace: $st");
      if (mounted) {
        MotionToast.show(context, 'Failed to export combined low stock report',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _categoryDownloading[category] = false;
        });
      }
    }
  }

  Future<void> _exportDeadStockCategoryPdf(
      String category, List<DeadStockEntry> items) async {
    if (_categoryDownloading[category] == true) return;

    setState(() {
      _categoryDownloading[category] = true;
    });

    try {
      // Per User Request: Export ONLY the selected category
      final bytes = await PdfReportService.generateCombinedDeadStockPdf(
        entries: items,
        location: _locationFilter,
        isDetailed: _isDetailedView,
        startDate: _startDate,
        endDate: _endDate,
      );

      final filename =
          'msm_non_moving_${category.toLowerCase().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      await _saveAndSharePdf(
          bytes, filename, 'MSM Non-Moving Stock Report: $category');
    } catch (e, st) {
      debugPrint("Error exporting dead stock combined PDF: $e");
      debugPrint("Stacktrace: $st");
      if (mounted) {
        MotionToast.show(
            context, 'Failed to export combined non-moving stock report',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _categoryDownloading[category] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool desktopMode = constraints.maxWidth >= 1025;
          if (desktopMode) {
            return _buildDesktopLayout();
          }
          return _buildMobileLayout();
        },
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return ReportsDashboardScreen(initialTabId: widget.initialTabId);
  }

  Widget _buildMobileLayout() {
    final String activeTabTitle =
        _activeTabs[_tabController.index]['id'] == 'today'
            ? "Today's Summary"
            : (_activeTabs[_tabController.index]['id'] == 'movement'
                ? "Stock Movement"
                : (_activeTabs[_tabController.index]['id'] == 'low'
                    ? "Low Stock"
                    : (_activeTabs[_tabController.index]['id'] == 'ledger'
                        ? "Stock Ledger"
                        : "Non-Moving Stock")));

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      drawer: Drawer(
        width: (MediaQuery.of(context).size.width * 0.84).clamp(240.0, 340.0),
        child: _ReportsSidebar(
          activeTabs: _activeTabs,
          selectedTabId: _activeTabs[_tabController.index]['id'] as String,
          onTabChanged: (id) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context); // Close drawer cleanly FIRST
            }
            Future.delayed(const Duration(milliseconds: 150), () {
              if (!mounted) return;
              final index = _activeTabs.indexWhere((t) => t['id'] == id);
              if (index != -1) {
                _tabController.animateTo(index);
                setState(() {
                  _expandedLowStockCategory = null;
                  _selectedCategoryMobile = null;
                });
              }
            });
          },
        ),
      ),
      bottomNavigationBar: _buildMobileBottomActionBar(context),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              backgroundColor: msmRed,
              elevation: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded,
                      color: Colors.white, size: 24),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: Text(
                activeTabTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () => _generateReports(forceRefresh: true),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(
              child: _buildMobileFilters(),
            ),
          ];
        },
        body: _isLoading ? const Center(child: MLoader()) : _buildContent(),
      ),
    );
  }

  Widget _buildMobileBottomActionBar(BuildContext context) {
    final String tabId = _activeTabs[_tabController.index]['id'] as String;
    if (tabId == 'ledger') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: msmRed,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: _isLoading
            ? null
            : () async {
                setState(() {
                  _isLoading = true;
                });
                try {
                  await _exportPdf();
                } catch (e) {
                  debugPrint("PDF Generation Error tracking: $e");
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.picture_as_pdf_rounded, size: 20),
        label: Text(_isLoading ? "Exporting..." : "Export PDF",
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ),
    );
  }

  Widget _buildContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        TodaySummaryTab(
          isLoading: _isLoading,
          filteredDailyMovement: _filteredDailyMovement,
          selectedTab: _todaySummaryTabMode,
          selectedFlow: _todaySummaryFlowMode,
          dateRangeLabel: _selectedDatePreset == 'Today'
              ? 'today'
              : _selectedDatePreset == 'Yesterday'
                  ? 'yesterday'
                  : _selectedDatePreset == 'Custom'
                      ? 'the selected period'
                      : _selectedDatePreset.toLowerCase(),
          emptyState: _buildEmptyState(
            title: _selectedDatePreset == 'Today'
                ? "No movements today"
                : _selectedDatePreset == 'Yesterday'
                    ? "No movements yesterday"
                    : "No movements for ${_selectedDatePreset.toLowerCase()}",
            subtitle: _selectedDatePreset == 'Today'
                ? "No stock transactions recorded for today"
                : _selectedDatePreset == 'Yesterday'
                    ? "No stock transactions recorded for yesterday"
                    : "No stock transactions recorded for the selected date range",
          ),
          onTabChanged: (tab) {
            setState(() {
              _todaySummaryTabMode = tab;
              _isDetailedView = tab == 'Detailed';
            });
          },
          onFlowChanged: (flow) {
            setState(() {
              _todaySummaryFlowMode = flow;
            });
          },
        ),
        _StockMovementTab(
          isLoading: _isLoading,
          stockReport: _stockReport,
          filteredSortedCategories: _filteredSortedCategories,
          filteredGroupedReport: _filteredGroupedReport,
          filteredStockReport: _filteredStockReport,
          isDetailedView: _isDetailedView,
          selectedCategoryMobile: _selectedCategoryMobile,
          expandedCategories: _expandedStockMovementCategories,
          onCategoryToggle: (cat) {
            setState(() {
              if (_expandedStockMovementCategories.contains(cat)) {
                _expandedStockMovementCategories.remove(cat);
              } else {
                _expandedStockMovementCategories.add(cat);
              }
            });
          },
          onCategorySelect: (cat) =>
              setState(() => _selectedCategoryMobile = cat),
          onCategoryBack: () => setState(() => _selectedCategoryMobile = null),
          categoryDownloading: _categoryDownloading,
          onExportCategoryPdf: _exportCategoryPdf,
          locationFilter: _locationFilter,
          emptyState: _buildEmptyState(),
        ),
        _LowStockTab(
          isLoading: _isLoading,
          filteredLowStock: _filteredLowStock,
          expandedLowStockCategory: _expandedLowStockCategory,
          onCategoryToggle: (cat) {
            setState(() {
              if (_expandedLowStockCategory == cat) {
                _expandedLowStockCategory = null;
              } else {
                _expandedLowStockCategory = cat;
              }
            });
          },
          buildLowStockMobile: _buildLowStockMobile,
          buildLowStockDesktop: _buildLowStockDesktop,
          isDetailedView: _isDetailedView,
          onExportCategory: _exportLowStockCategoryPdf,
          categoryDownloading: _categoryDownloading,
        ),
        _NonMovingStockTab(
          isLoading: _isLoading,
          filteredDeadStock: _filteredDeadStock,
          onExportCategory: _exportDeadStockCategoryPdf,
          emptyState: _buildEmptyState(
            title: 'No non-moving stock',
            subtitle: 'All items have had movement in the selected period',
          ),
          isDetailedView: _isDetailedView,
          expandedCategory: _expandedNonMovingCategory,
          onToggleExpansion: (cat) {
            setState(() {
              _expandedNonMovingCategory =
                  (_expandedNonMovingCategory == cat) ? null : cat;
            });
          },
          selectedCategoryMobile: _selectedCategoryMobile,
          onCategorySelect: (cat) =>
              setState(() => _selectedCategoryMobile = cat),
          onCategoryBack: () => setState(() => _selectedCategoryMobile = null),
          categoryDownloading: _categoryDownloading,
        ),
        StockLedgerScreen(
          isLoading: _isLoading,
          isDesktop: isDesktop,
          searchQuery: _searchQuery,
          startDate: _startDate,
          endDate: _endDate,
          locationFilter: _locationFilter,
        ),
      ],
    );
  }

  Widget _buildMobileFilters() {
    final String tabId = _activeTabs[_tabController.index]['id'] as String;
    final double width = MediaQuery.of(context).size.width;
    final double horizontalPadding = width >= 641 ? 24.0 : 16.0;

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
      color: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 20, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: "Search items...",
                      hintStyle:
                          TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          // Location Selector
          InkWell(
            onTap: _showLocationFilter,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 20, color: Colors.grey.shade500),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Location: $_locationFilter",
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textDark),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildQuickDatePresets(),
          if (tabId == 'today') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildFlowToggleButton(
                          label: "Summary",
                          isSelected: _todaySummaryTabMode == 'Summary',
                          activeColor: msmRed,
                          onTap: () => setState(() {
                            _todaySummaryTabMode = 'Summary';
                            _isDetailedView = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildFlowToggleButton(
                          label: "Detailed",
                          isSelected: _todaySummaryTabMode == 'Detailed',
                          activeColor: msmRed,
                          onTap: () => setState(() {
                            _todaySummaryTabMode = 'Detailed';
                            _isDetailedView = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFlowToggleButton(
                          label: "Inward",
                          isSelected: _todaySummaryFlowMode == 'Inward',
                          activeColor: const Color(0xFF16A34A),
                          onTap: () =>
                              setState(() => _todaySummaryFlowMode = 'Inward'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildFlowToggleButton(
                          label: "Outward",
                          isSelected: _todaySummaryFlowMode == 'Outward',
                          activeColor: const Color(0xFFDC2626),
                          onTap: () =>
                              setState(() => _todaySummaryFlowMode = 'Outward'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildFlowToggleButton(
                          label: "Net Qty",
                          isSelected: _todaySummaryFlowMode == 'Net Qty',
                          activeColor: const Color(0xFF2563EB),
                          onTap: () =>
                              setState(() => _todaySummaryFlowMode = 'Net Qty'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (tabId == 'movement' || tabId == 'low') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildViewToggleButton(
                    label: "Summary",
                    isSelected: !_isDetailedView,
                    onTap: () => setState(() => _isDetailedView = false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildViewToggleButton(
                    label: "Detailed",
                    isSelected: _isDetailedView,
                    onTap: () => setState(() => _isDetailedView = true),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlowToggleButton({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5))
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF475569),
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickDatePresets() {
    final String tabId =
        _activeTabs.isNotEmpty && _tabController.index < _activeTabs.length
            ? (_activeTabs[_tabController.index]['id'] as String? ?? 'today')
            : 'today';
    final presets = tabId == 'today'
        ? ['Today', 'Yesterday', 'Custom']
        : (tabId == 'ledger'
            ? ['This Month', 'Last Month', 'Custom']
            : ['Today', 'This Week', 'This Month', 'Custom']);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: presets.map((preset) {
          final bool isSelected = _selectedDatePreset == preset;
          String labelText = preset;
          if (preset == 'Custom' && isSelected) {
            final bool isSameDay = _startDate.year == _endDate.year &&
                _startDate.month == _endDate.month &&
                _startDate.day == _endDate.day;
            labelText = isSameDay
                ? DateFormat('dd MMM').format(_startDate)
                : "${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM').format(_endDate)}";
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              avatar: preset == 'Custom'
                  ? Icon(Icons.calendar_today_outlined,
                      size: 14,
                      color: isSelected ? Colors.white : Colors.grey.shade700)
                  : null,
              label: Text(
                labelText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF374151),
                ),
              ),
              selected: isSelected,
              selectedColor: msmRed,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? msmRed : Colors.grey.shade300,
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              showCheckmark: false,
              onSelected: (selected) {
                if (selected) {
                  _onDatePresetSelected(preset);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildViewToggleButton(
      {required String label,
      required bool isSelected,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? msmRed : const Color(0xFFF1F3F4),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1A1D21),
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeButtonMobile() {
    final bool isSameDay = _startDate.year == _endDate.year &&
        _startDate.month == _endDate.month &&
        _startDate.day == _endDate.day;
    final String dateText = isSameDay
        ? DateFormat('dd MMM yy').format(_startDate)
        : "${DateFormat('dd MMM yy').format(_startDate)} - ${DateFormat('dd MMM yy').format(_endDate)}";

    return InkWell(
      onTap: _selectDateRange,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dateText,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: textDark),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  double _getAvailableMt(dynamic row) {
    if (row is StockSizeMovement) return row.closing;
    if (row is ItemVariant) return row.currentStockMT;

    final value = row.availableMt ??
        row.netMt ??
        row.balanceMt ??
        row.totalMt ??
        row['availableMt'] ??
        row['netMt'] ??
        row['balanceMt'] ??
        row['totalMt'] ??
        0;

    return double.tryParse(value.toString()) ?? 0;
  }

  String _getCategoryName(dynamic row) {
    if (row is StockMovementEntry) return row.category;
    if (row is ItemVariant) return row.category;

    return (row.category ??
            row.itemName ??
            row.type ??
            row['category'] ??
            row['itemName'] ??
            row['type'] ??
            'Unknown')
        .toString();
  }

  String _getSizeLabel(dynamic row) {
    if (row is StockSizeMovement) return row.label;
    if (row is ItemVariant) return row.size;

    return (row.sizeLabel ??
            row.size ??
            row.itemSize ??
            row['sizeLabel'] ??
            row['size'] ??
            row['itemSize'] ??
            '')
        .toString();
  }

  Widget _buildLowStockDesktop(List<ItemVariant> filtered) {
    final query = _searchQuery.toLowerCase();

    // Group sizes by category where closing stock < 5 MT
    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var entry in _stockReport) {
      final matchesSearch = query.isEmpty ||
          entry.item.toLowerCase().contains(query) ||
          entry.category.toLowerCase().contains(query);
      if (!matchesSearch) continue;

      for (var size in entry.sizes) {
        final available = _getAvailableMt(size);
        if (available < 5) {
          final cat = _getCategoryName(entry);
          grouped.putIfAbsent(cat, () => []);
          grouped[cat]!.add({
            'label': _getSizeLabel(size),
            'qty': available,
            'item': entry.item,
          });
        }
      }
    }

    final cats = grouped.keys.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    if (cats.isEmpty) {
      return _buildEmptyState(
        title: "No low stock items",
        subtitle: "All stock levels are above 5 MT",
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: cats.length,
          itemBuilder: (context, idx) {
            final cat = cats[idx];
            final items = grouped[cat]!;
            // Sort items in descending order of tonnage (higher stock first)
            items.sort((a, b) {
              final double qtyA = (a['qty'] as num).toDouble();
              final double qtyB = (b['qty'] as num).toDouble();
              int qtyComp = qtyB.compareTo(qtyA);
              if (qtyComp != 0) return qtyComp;
              return SortingUtils.compareSizes(a['label'], b['label']);
            });

            final isExpanded =
                _isDetailedView && _expandedLowStockCategories.contains(cat);
            final totalQty =
                items.fold(0.0, (sum, e) => sum + (e['qty'] as double));

            if (isExpanded) {
              return LowStockExpandedCard(
                category: cat,
                totalQty: totalQty,
                isCritical: true,
                isWarning: false,
                onHeaderTap: () =>
                    setState(() => _expandedLowStockCategories.remove(cat)),
                isDownloading: _categoryDownloading[cat] ?? false,
                onDownload: () => _exportLowStockCategoryPdf(cat, items),
                items: items
                    .map((e) => LowStockItemRow(
                          itemName: "${e['item']} - ${e['label']}",
                          qty: e['qty'],
                          isCritical: true,
                          isWarning: false,
                        ))
                    .toList(),
              );
            } else {
              return LowStockCategoryCard(
                category: cat,
                totalQty: totalQty,
                isCritical: true,
                isWarning: false,
                onTap: !_isDetailedView
                    ? () {}
                    : () =>
                        setState(() => _expandedLowStockCategories.add(cat)),
                isDownloading: _categoryDownloading[cat] ?? false,
                onDownload: () => _exportLowStockCategoryPdf(cat, items),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildLowStockMobile(List<ItemVariant> filtered) {
    Map<String, List<ItemVariant>> grouped = {};
    for (var item in filtered) {
      grouped.putIfAbsent(item.category, () => []);
      grouped[item.category]!.add(item);
    }

    final cats = grouped.keys.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    if (cats.isEmpty) {
      return _buildEmptyState(
          title: "No Low Stock Found",
          subtitle: "All items are currently above minimum stock levels.");
    }

    final double width = MediaQuery.of(context).size.width;
    final double paddingValue = width >= 641 ? 24.0 : 16.0;

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 16,
        bottom: 88,
      ),
      itemCount: cats.length,
      itemBuilder: (context, idx) {
        final cat = cats[idx];
        final items = grouped[cat]!;
        // Sort items in descending order of tonnage (higher stock first)
        items.sort((a, b) {
          int qtyComp = b.currentStockMT.compareTo(a.currentStockMT);
          if (qtyComp != 0) return qtyComp;
          return SortingUtils.compareSizes(a.size, b.size);
        });
        final totalQty = items.fold(0.0, (sum, e) => sum + e.currentStockMT);
        final isExpanded = _isDetailedView && _expandedLowStockCategory == cat;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            children: [
              // Header
              InkWell(
                onTap: !_isDetailedView
                    ? null
                    : () {
                        setState(() {
                          _expandedLowStockCategory = isExpanded ? null : cat;
                        });
                      },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: textDark,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              "${items.length} items low in stock",
                              style: const TextStyle(
                                color: textGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "${formatNumber(totalQty)} MT",
                            style: TextStyle(
                              color: totalQty < 0 ? Colors.red : textDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const Text(
                            "Total Low Stock",
                            style: TextStyle(
                              color: textGrey,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _categoryDownloading[cat] == true
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: msmRed),
                            )
                          : GestureDetector(
                              onTap: () {},
                              child: IconButton(
                                icon: const Icon(Icons.download_rounded,
                                    size: 20, color: Colors.grey),
                                onPressed: () => _exportLowStockCategoryPdf(
                                    cat,
                                    items
                                        .map((e) => {
                                              'label': e.size,
                                              'qty': e.currentStockMT,
                                              'item': e.itemName,
                                            })
                                        .toList()),
                              ),
                            ),
                      const SizedBox(width: 12),
                      if (_isDetailedView)
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey.shade400,
                        ),
                    ],
                  ),
                ),
              ),

              // Expanded Section
              if (isExpanded) ...[
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: items.map((e) {
                      return LowStockItemCard(
                        item: {
                          'item_name': e.itemName,
                          'size_description': e.size,
                          'low_stock_qty': e.currentStockMT,
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
      {String title = 'No results found',
      String subtitle = 'Try adjusting your search or filters'}) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.analytics_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            if (subtitle.contains('search'))
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text("Clear Filters"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: msmRed,
                  side: BorderSide(color: msmRed.withValues(alpha: 0.2)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- MODULAR TAB WIDGETS ---

class _StockMovementTab extends StatelessWidget {
  final bool isLoading;
  final List<StockMovementEntry> stockReport;
  final List<String> filteredSortedCategories;
  final Map<String, Map<String, List<StockMovementEntry>>>
      filteredGroupedReport;
  final List<StockMovementEntry> filteredStockReport;
  final bool isDetailedView;
  final String? selectedCategoryMobile;
  final Set<String> expandedCategories;
  final Function(String) onCategoryToggle;
  final Function(String) onCategorySelect;
  final VoidCallback onCategoryBack;
  final Map<String, bool> categoryDownloading;
  final Function(String, Map<String, List<StockMovementEntry>>)
      onExportCategoryPdf;
  final String locationFilter;
  final Widget emptyState;

  const _StockMovementTab({
    required this.isLoading,
    required this.stockReport,
    required this.filteredSortedCategories,
    required this.filteredGroupedReport,
    required this.filteredStockReport,
    required this.isDetailedView,
    required this.selectedCategoryMobile,
    required this.expandedCategories,
    required this.onCategoryToggle,
    required this.onCategorySelect,
    required this.onCategoryBack,
    required this.categoryDownloading,
    required this.onExportCategoryPdf,
    required this.locationFilter,
    required this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: MLoader());
    if (filteredStockReport.isEmpty) return emptyState;

    final double width = MediaQuery.of(context).size.width;
    final bool isMobileOrTablet = width < 1025;

    if (isMobileOrTablet) {
      if (selectedCategoryMobile != null) {
        return _buildCategoryDetailViewMobile(context, selectedCategoryMobile!,
            filteredGroupedReport[selectedCategoryMobile]!);
      }
      return isDetailedView
          ? _buildDetailedListMobile(
              context, filteredSortedCategories, filteredGroupedReport)
          : _buildSummaryListMobile(context, filteredStockReport);
    }

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isDetailedView ? 850 : 720),
        child: isDetailedView
            ? _buildDesktopLayout()
            : _buildSummaryLayoutDesktop(context),
      ),
    );
  }

  Widget _buildSummaryLayoutDesktop(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: filteredSortedCategories.length,
      itemBuilder: (context, idx) {
        final cat = filteredSortedCategories[idx];
        final items = filteredGroupedReport[cat]!;
        double total =
            items.values.expand((x) => x).fold(0.0, (s, e) => s + e.closing);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  cat,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textDark,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 120,
                child: Text(
                  "${formatNumber(total)} MT",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: total < 0 ? Colors.red : textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: filteredSortedCategories.length,
      itemBuilder: (context, idx) {
        final cat = filteredSortedCategories[idx];
        if (!filteredGroupedReport.containsKey(cat)) return const SizedBox();
        return _buildCategoryExpandableCard(cat, filteredGroupedReport[cat]!);
      },
    );
  }

  Widget _buildCategoryExpandableCard(
      String category, Map<String, List<StockMovementEntry>> items) {
    double total =
        items.values.expand((x) => x).fold(0, (s, e) => s + e.closing);
    bool isExpanded = expandedCategories.contains(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
            color: isExpanded ? msmRed.withOpacity(0.1) : Colors.grey.shade100),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          onExpansionChanged: (val) => onCategoryToggle(category),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Color(0xFF1A1D21),
                ),
              ),
              Text(
                locationFilter == 'ALL' ? 'General' : locationFilter,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          trailing: SizedBox(
            width: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                categoryDownloading[category] == true
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: msmRed),
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onExportCategoryPdf(category, items),
                        icon: const Icon(Icons.download_rounded,
                            size: 20, color: Colors.grey),
                      ),
                const SizedBox(width: 12),
                Text(
                  "${formatNumber(total)} MT",
                  style: TextStyle(
                    color: total < 0 ? Colors.red : textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
          children: [
            const Divider(height: 1),
            // Header Row: Item | Opening | Inward | Outward | Closing
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: Colors.grey.shade50,
              child: const Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      "Item",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textGrey),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      "Opening",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textGrey),
                    ),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 90,
                    child: Text(
                      "Inward",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textGrey),
                    ),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 90,
                    child: Text(
                      "Outward",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textGrey),
                    ),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 95,
                    child: Text(
                      "Closing",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textGrey),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: items.entries.expand((entry) {
                  final sortedEntries = entry.value.toList();
                  return sortedEntries.expand((e) =>
                      e.sizes.map((s) => _buildDetailedTableRow(entry.key, s)));
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedTableRow(String itemName, StockSizeMovement size) {
    final displayLabel = _appendKgSuffix(itemName, size.label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade50))),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              displayLabel,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: textDark),
            ),
          ),
          _buildSizeMetric(formatNumber(size.opening), const Color(0xFF64748B),
              width: 90),
          const SizedBox(width: 12),
          _buildSizeMetric(formatNumber(size.inQty), Colors.green.shade600,
              width: 90),
          const SizedBox(width: 12),
          _buildSizeMetric(formatNumber(size.outQty), Colors.red.shade600,
              width: 90),
          const SizedBox(width: 12),
          _buildSizeMetric(formatNumber(size.closing),
              size.closing < 0 ? Colors.red : textDark,
              isBold: true,
              width: 95),
        ],
      ),
    );
  }

  Widget _buildSizeMetric(String value, Color color,
      {bool isBold = false, double width = 100}) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSummaryListMobile(
      BuildContext context, List<StockMovementEntry> entries) {
    final double width = MediaQuery.of(context).size.width;
    final double paddingValue = width >= 641 ? 24.0 : 16.0;

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 16,
        bottom: 88,
      ),
      itemCount: entries.length,
      itemBuilder: (context, idx) {
        final sEntry = entries[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () => onCategorySelect(sEntry.category),
            title: Text(sEntry.item,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textDark)),
            trailing: Text("${formatNumber(sEntry.closing)} MT",
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: sEntry.closing < 0 ? Colors.red : textDark)),
          ),
        );
      },
    );
  }

  Widget _buildDetailedListMobile(BuildContext context, List<String> categories,
      Map<String, Map<String, List<StockMovementEntry>>> grouped) {
    final double width = MediaQuery.of(context).size.width;
    final double paddingValue = width >= 641 ? 24.0 : 16.0;

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 16,
        bottom: 88,
      ),
      itemCount: categories.length,
      itemBuilder: (context, idx) {
        String cat = categories[idx];
        return _buildMobileCategoryCard(context, cat, grouped[cat]!);
      },
    );
  }

  Widget _buildMobileCategoryCard(BuildContext context, String category,
      Map<String, List<StockMovementEntry>> items) {
    double total =
        items.values.expand((x) => x).fold(0, (s, e) => s + e.closing);
    bool isExpanded = expandedCategories.contains(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onCategoryToggle(category),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: textDark)),
                        const Text("General",
                            style: TextStyle(color: textGrey, fontSize: 11)),
                      ],
                    ),
                  ),
                  categoryDownloading[category] == true
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: msmRed))
                      : GestureDetector(
                          onTap: () {},
                          child: IconButton(
                            onPressed: () =>
                                onExportCategoryPdf(category, items),
                            icon: const Icon(Icons.download_rounded,
                                size: 20, color: Colors.grey),
                          ),
                        ),
                  const SizedBox(width: 8),
                  Text("${formatNumber(total)} MT",
                      style: TextStyle(
                          color: total < 0 ? Colors.red : textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: items.entries.expand((entry) {
                  return entry.value.expand((e) => e.sizes.map((s) =>
                      _buildMobileItemCard(s,
                          parentCategory: category, itemName: entry.key)));
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileItemCard(StockSizeMovement size,
      {String? parentCategory, String? itemName}) {
    final displayLabel =
        _appendKgSuffix(parentCategory ?? size.label, size.label);
    final bool isNegative = size.closing < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: textDark),
                ),
              ),
              Text(
                "${formatNumber(size.closing)} MT",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: isNegative ? Colors.red : textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMobileMiniMetric(
                    "OPENING", formatNumber(size.opening), const Color(0xFF64748B)),
              ),
              Expanded(
                child: _buildMobileMiniMetric(
                    "INWARD", formatNumber(size.inQty), Colors.green.shade700),
              ),
              Expanded(
                child: _buildMobileMiniMetric(
                    "OUTWARD", formatNumber(size.outQty), Colors.red.shade700),
              ),
              Expanded(
                child: _buildMobileMiniMetric(
                    "CLOSING", formatNumber(size.closing), isNegative ? Colors.red : textDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMiniMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: textGrey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          "$value MT",
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDetailViewMobile(BuildContext context, String category,
      Map<String, List<StockMovementEntry>> items) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: onCategoryBack),
              Text("Details: $category",
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: textDark)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildMobileCategoryCard(context, category, items),
          ),
        ),
      ],
    );
  }
}

class _NonMovingStockTab extends StatelessWidget {
  final bool isLoading;
  final List<DeadStockEntry> filteredDeadStock;
  final Widget emptyState;
  final Function(String, List<DeadStockEntry>)? onExportCategory;
  final bool isDetailedView;
  final String? expandedCategory;
  final Function(String) onToggleExpansion;
  final String? selectedCategoryMobile;
  final Function(String) onCategorySelect;
  final VoidCallback onCategoryBack;
  final Map<String, bool> categoryDownloading;

  const _NonMovingStockTab({
    required this.isLoading,
    required this.filteredDeadStock,
    required this.emptyState,
    this.onExportCategory,
    required this.isDetailedView,
    this.expandedCategory,
    required this.onToggleExpansion,
    this.selectedCategoryMobile,
    required this.onCategorySelect,
    required this.onCategoryBack,
    required this.categoryDownloading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: MLoader());
    if (filteredDeadStock.isEmpty) return emptyState;

    final double width = MediaQuery.of(context).size.width;
    final bool isMobileOrTablet = width < 1025;

    if (isMobileOrTablet) {
      if (selectedCategoryMobile != null) {
        final cat = selectedCategoryMobile!;
        final items =
            filteredDeadStock.where((e) => e.category == cat).toList();
        return _buildCategoryDetailViewMobile(context, cat, items);
      }
      return _buildDetailedListMobile(context);
    }

    // Desktop: Group by category
    final grouped = <String, List<DeadStockEntry>>{};
    for (var e in filteredDeadStock) {
      grouped.putIfAbsent(e.category, () => []);
      grouped[e.category]!.add(e);
    }
    final sortedCats = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: _buildDetailedLayoutDesktop(sortedCats, grouped),
      ),
    );
  }

  Widget _buildSummaryLayoutDesktop(
      List<String> cats, Map<String, List<DeadStockEntry>> grouped) {
    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: cats.length,
      itemBuilder: (context, idx) {
        final cat = cats[idx];
        final items = grouped[cat]!;
        double total = items.fold(0.0, (sum, e) => sum + e.currentQty);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(cat,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textDark)),
              ),
              SizedBox(
                width: 180,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (categoryDownloading[cat] == true)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: msmRed))
                    else
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.download_rounded,
                            size: 20, color: Colors.grey),
                        onPressed: () => onExportCategory?.call(cat, items),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      "${total.toStringAsFixed(3)} MT",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: total < 0 ? Colors.red : textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailedLayoutDesktop(
      List<String> cats, Map<String, List<DeadStockEntry>> grouped) {
    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: cats.length,
      itemBuilder: (context, idx) {
        final cat = cats[idx];
        final items = grouped[cat]!;
        double total = items.fold(0, (s, e) => s + e.currentQty);
        final isExpanded = expandedCategory == cat;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Theme(
            data: ThemeData().copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: isExpanded,
              onExpansionChanged: (val) => onToggleExpansion(cat),
              trailing: const SizedBox.shrink(),
              title: Row(
                children: [
                  Expanded(
                    child: Text(cat.toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: Color(0xFF1A1D21))),
                  ),
                  SizedBox(
                    width: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (categoryDownloading[cat] == true)
                          const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: msmRed))
                        else
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.download_rounded,
                                size: 20, color: Colors.grey),
                            onPressed: () => onExportCategory?.call(cat, items),
                          ),
                        const SizedBox(width: 12),
                        Text(
                          "${total.toStringAsFixed(3)} MT",
                          style: TextStyle(
                            color: total < 0 ? Colors.red : textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FixedColumnWidth(110),
                      2: FixedColumnWidth(140),
                      3: FixedColumnWidth(110),
                    },
                    children: [
                      TableRow(
                        children: [
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Item",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Size",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Last Movement",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Balance",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                        ],
                      ),
                      for (var e in items)
                        TableRow(
                          children: [
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(e.itemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: textDark))),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(e.size,
                                    style: const TextStyle(color: textDark))),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                e.lastMovementDate != null
                                    ? DateFormat('dd MMM yyyy')
                                        .format(e.lastMovementDate!)
                                    : 'No movement',
                                style: const TextStyle(
                                    color: textGrey, fontSize: 13),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "${e.currentQty.toStringAsFixed(3)} MT",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      e.currentQty < 0 ? Colors.red : textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryListMobile(BuildContext context) {
    final Map<String, List<DeadStockEntry>> grouped = {};
    for (var e in filteredDeadStock) {
      grouped.putIfAbsent(e.category, () => []);
      grouped[e.category]!.add(e);
    }
    final sortedCats = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);
    final double width = MediaQuery.of(context).size.width;
    final double paddingValue = width >= 641 ? 24.0 : 16.0;

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 16,
        bottom: 88,
      ),
      itemCount: sortedCats.length,
      itemBuilder: (context, idx) {
        final cat = sortedCats[idx];
        final items = grouped[cat]!;
        double total = items.fold(0.0, (sum, e) => sum + e.currentQty);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () => onCategorySelect(cat),
            title: Text(cat,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textDark)),
            subtitle: Text("${items.length} items non-moving",
                style: const TextStyle(fontSize: 12, color: textGrey)),
            trailing: Text("${total.toStringAsFixed(3)} MT",
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: total < 0 ? Colors.red : textDark)),
          ),
        );
      },
    );
  }

  Widget _buildDetailedListMobile(BuildContext context) {
    final Map<String, List<DeadStockEntry>> grouped = {};
    for (var e in filteredDeadStock) {
      grouped.putIfAbsent(e.category, () => []);
      grouped[e.category]!.add(e);
    }
    final sortedCats = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);
    final double width = MediaQuery.of(context).size.width;
    final double paddingValue = width >= 641 ? 24.0 : 16.0;

    return ListView.builder(
      padding: EdgeInsets.only(
        left: paddingValue,
        right: paddingValue,
        top: 16,
        bottom: 88,
      ),
      itemCount: sortedCats.length,
      itemBuilder: (context, idx) {
        final cat = sortedCats[idx];
        final items = grouped[cat]!;
        final isExpanded = expandedCategory == cat;
        return _buildMobileDeadStockCategoryCard(
            context, cat, items, isExpanded);
      },
    );
  }

  Widget _buildMobileDeadStockCategoryCard(BuildContext context,
      String category, List<DeadStockEntry> items, bool isExpanded) {
    double total = items.fold(0, (s, e) => s + e.currentQty);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onToggleExpansion(category),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: textDark)),
                        Text("${items.length} items",
                            style:
                                const TextStyle(color: textGrey, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text("${total.toStringAsFixed(3)} MT",
                      style: TextStyle(
                          color: total < 0 ? Colors.red : textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                  const SizedBox(width: 8),
                  categoryDownloading[category] == true
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: msmRed))
                      : GestureDetector(
                          onTap: () {},
                          child: IconButton(
                            onPressed: () =>
                                onExportCategory?.call(category, items),
                            icon: const Icon(Icons.download_rounded,
                                size: 20, color: Colors.grey),
                          ),
                        ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: items
                    .map((e) =>
                        _buildDeadStockItemMobileCard(e, showItemName: true))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryDetailViewMobile(
      BuildContext context, String category, List<DeadStockEntry> items) {
    double total = items.fold(0, (s, e) => s + e.currentQty);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: onCategoryBack),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: textDark)),
                    Text("${items.length} non-moving items",
                        style: const TextStyle(color: textGrey, fontSize: 12)),
                  ],
                ),
              ),
              Text("${total.toStringAsFixed(3)} MT",
                  style: TextStyle(
                      color: total < 0 ? Colors.red : textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
            ],
          ),
        ),
        Expanded(
          child: () {
            Map<String, List<DeadStockEntry>> itemGroups = {};
            for (var e in items) {
              itemGroups.putIfAbsent(e.itemName, () => []);
              itemGroups[e.itemName]!.add(e);
            }
            final itemNames = itemGroups.keys.toList()..sort();

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: itemNames.length,
              itemBuilder: (context, idx) {
                final itemName = itemNames[idx];
                final variants = itemGroups[itemName]!;

                final filteredVariants = variants.where((v) {
                  final vItemName = v.itemName.trim().toLowerCase();
                  final vSize = v.size.trim().toLowerCase();
                  final parentName = itemName.trim().toLowerCase();
                  return !(vItemName == parentName &&
                      (vSize.isEmpty || vSize == parentName));
                }).toList();

                final totalQty = variants.fold(0.0, (s, v) => s + v.currentQty);

                if (filteredVariants.length == 1) {
                  final e = filteredVariants.first;
                  return _buildDeadStockItemMobileCard(e, showItemName: true);
                }

                if (filteredVariants.isEmpty && variants.isNotEmpty) {
                  final e = variants.first;
                  return _buildDeadStockItemMobileCard(e, showItemName: true);
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.02), blurRadius: 10)
                    ],
                  ),
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(itemName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: textDark)),
                          ),
                          Text("${totalQty.toStringAsFixed(3)} MT",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: totalQty < 0 ? Colors.red : textDark,
                                  fontSize: 16)),
                        ],
                      ),
                      children: filteredVariants
                          .map((e) => _buildDeadStockItemMobileCard(e,
                              showItemName: false, isNested: true))
                          .toList(),
                    ),
                  ),
                );
              },
            );
          }(),
        ),
      ],
    );
  }

  Widget _buildDeadStockItemMobileCard(DeadStockEntry e,
      {bool showItemName = true, bool isNested = false}) {
    return Container(
      margin: isNested ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNested ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isNested ? null : Border.all(color: Colors.grey.shade100),
        boxShadow: isNested
            ? []
            : [
                BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showItemName)
                  Text(e.itemName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: textDark)),
                Text(e.size,
                    style: TextStyle(
                        color: textGrey,
                        fontSize: 13,
                        fontWeight:
                            isNested ? FontWeight.w700 : FontWeight.normal)),
                const SizedBox(height: 4),
                Text(
                  "Last movement: ${e.lastMovementDate != null ? DateFormat('dd MMM yyyy').format(e.lastMovementDate!) : 'No movement found'}",
                  style: const TextStyle(color: textGrey, fontSize: 12),
                ),
                Text(
                  "Duration: ${e.daysSinceLastMovement == -1 ? 'N/A' : '${e.daysSinceLastMovement} days'}",
                  style: const TextStyle(color: textGrey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text("${e.currentQty.toStringAsFixed(3)} MT",
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: e.currentQty < 0 ? Colors.red : textDark,
                  fontSize: 16)),
        ],
      ),
    );
  }
}

class _LowStockTab extends StatelessWidget {
  final bool isLoading;
  final List<ItemVariant> filteredLowStock;
  final String? expandedLowStockCategory;
  final Function(String) onCategoryToggle;
  final Widget Function(List<ItemVariant>) buildLowStockMobile;
  final Widget Function(List<ItemVariant>) buildLowStockDesktop;
  final bool isDetailedView;
  final Function(String, List<Map<String, dynamic>>) onExportCategory;
  final Map<String, bool> categoryDownloading;

  const _LowStockTab({
    required this.isLoading,
    required this.filteredLowStock,
    required this.expandedLowStockCategory,
    required this.onCategoryToggle,
    required this.buildLowStockMobile,
    required this.buildLowStockDesktop,
    required this.isDetailedView,
    required this.onExportCategory,
    required this.categoryDownloading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: MLoader());
    if (filteredLowStock.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 80, color: Colors.green),
            SizedBox(height: 16),
            Text("All stock levels healthy",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textDark)),
          ],
        ),
      );
    }

    final double width = MediaQuery.of(context).size.width;
    final bool isMobileOrTablet = width < 1025;

    if (isMobileOrTablet) {
      return buildLowStockMobile(filteredLowStock);
    }

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    Map<String, List<ItemVariant>> grouped = {};
    for (var item in filteredLowStock) {
      grouped.putIfAbsent(item.category, () => []);
      grouped[item.category]!.add(item);
    }
    final sortedCats = grouped.keys.toList()
      ..sort(SortingUtils.compareCategories);

    return ListView.builder(
      padding: const EdgeInsets.all(32),
      itemCount: sortedCats.length,
      itemBuilder: (context, idx) {
        final cat = sortedCats[idx];
        final items = grouped[cat]!;
        items.sort((a, b) => SortingUtils.compareSizes(a.size, b.size));
        final totalQty = items.fold(0.0, (sum, e) => sum + e.currentStockMT);
        final isCritical =
            items.any((e) => e.currentStockMT <= (e.minStock * 0.3));
        final isExpanded = expandedLowStockCategory == cat;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Theme(
            data: ThemeData().copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: isExpanded,
              onExpansionChanged: (val) => onCategoryToggle(cat),
              trailing: const SizedBox.shrink(),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 20,
                      color: isCritical ? msmRed : const Color(0xFFE67E22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(cat.toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: Color(0xFF1A1D21))),
                  ),
                  SizedBox(
                    width: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (categoryDownloading[cat] == true)
                          const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: msmRed))
                        else
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.download_rounded,
                                size: 20, color: Colors.grey),
                            onPressed: () => onExportCategory(
                                cat,
                                items
                                    .map((e) => {
                                          'item': e.itemName,
                                          'label': e.size,
                                          'qty': e.currentStockMT,
                                        })
                                    .toList()),
                          ),
                        const SizedBox(width: 12),
                        Text(
                          "${formatNumber(totalQty)} MT",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: totalQty < 0 ? Colors.red : textDark,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FixedColumnWidth(110),
                      2: FixedColumnWidth(110),
                      3: FixedColumnWidth(100),
                    },
                    children: [
                      TableRow(
                        children: [
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Item",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Size",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Balance",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text("Status",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600))),
                        ],
                      ),
                      for (var e in items)
                        TableRow(
                          children: [
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(e.itemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: textDark))),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(e.size,
                                    style: const TextStyle(color: textDark))),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "${formatNumber(e.currentStockMT)} MT",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: e.currentStockMT < 0
                                      ? Colors.red
                                      : textDark,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                e.currentStockMT <= (e.minStock * 0.3)
                                    ? "Critical"
                                    : "Warning",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: e.currentStockMT <= (e.minStock * 0.3)
                                      ? msmRed
                                      : const Color(0xFFE67E22),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReportsPremiumHeader extends StatelessWidget {
  final TabController tabController;
  final List<Map<String, dynamic>> activeTabs;
  final TextEditingController searchController;
  final Function(String) onSearch;
  final VoidCallback onRefresh;
  final VoidCallback onDateRange;
  final DateTime startDate;
  final DateTime endDate;
  final String locationFilter;
  final Function(String?) onLocationChange;
  final VoidCallback onLocationTap;
  final VoidCallback onExportPdf;
  final VoidCallback? onExportExcel;
  final Function(LowStockExportType)? onExportLowStock;
  final bool isDesktop;
  final bool isDetailedView;
  final Function(bool) onViewToggle;
  final String? selectedDatePreset;
  final Function(String)? onDatePresetSelected;
  final String? todaySummaryTabMode;
  final Function(String)? onTodaySummaryTabModeChanged;
  final String? todaySummaryFlowMode;
  final Function(String)? onTodaySummaryFlowModeChanged;

  const _ReportsPremiumHeader({
    required this.tabController,
    required this.activeTabs,
    required this.searchController,
    required this.onSearch,
    required this.onRefresh,
    required this.onDateRange,
    required this.startDate,
    required this.endDate,
    required this.locationFilter,
    required this.onLocationChange,
    required this.onLocationTap,
    required this.onExportPdf,
    this.onExportExcel,
    this.onExportLowStock,
    required this.isDesktop,
    required this.isDetailedView,
    required this.onViewToggle,
    this.selectedDatePreset,
    this.onDatePresetSelected,
    this.todaySummaryTabMode,
    this.onTodaySummaryTabModeChanged,
    this.todaySummaryFlowMode,
    this.onTodaySummaryFlowModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final String currentTabId = activeTabs.isNotEmpty &&
            tabController.index < activeTabs.length
        ? (activeTabs[tabController.index]['id'] as String? ?? '')
        : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeTabs[tabController.index]['title'] as String,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 40,
                    height: 3,
                    decoration: BoxDecoration(
                      color: msmRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _buildSearchBar(),
              const SizedBox(width: 16),
              _buildHeaderAction(Icons.refresh_rounded, onRefresh, tooltip: "Refresh Data"),
              if (onExportExcel != null) ...[
                const SizedBox(width: 12),
                _buildExcelAction(),
              ],
              const SizedBox(width: 12),
              _buildPdfAction(),
            ],
          ),
          const SizedBox(height: 24),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildLocationSelector(),
                if (currentTabId == 'today') ...[
                  const SizedBox(width: 12),
                  _buildDesktopDatePresets(),
                  const SizedBox(width: 12),
                  _buildTodayViewToggle(),
                  const SizedBox(width: 12),
                  _buildTodayFlowToggle(),
                ] else if (currentTabId == 'ledger') ...[
                  const SizedBox(width: 12),
                  _buildDateSelector(),
                  const SizedBox(width: 12),
                  _buildDesktopDatePresets(),
                ] else ...[
                  if (currentTabId == 'movement' ||
                      currentTabId == 'low') ...[
                    const SizedBox(width: 12),
                    _buildViewToggle(),
                  ],
                  if (currentTabId == 'movement' ||
                      currentTabId == 'low' ||
                      currentTabId == 'nonmoving') ...[
                    const SizedBox(width: 12),
                    _buildDateSelector(),
                  ],
                ],
                if (!isDesktop) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 300,
                    child: TabBar(
                      controller: tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: msmRed,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: msmRed,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14),
                      tabs: activeTabs
                          .map((t) => Tab(text: t['title'] as String))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDatePresets() {
    final String currentTabId = activeTabs.isNotEmpty &&
            tabController.index < activeTabs.length
        ? (activeTabs[tabController.index]['id'] as String? ?? '')
        : '';
    final presets = currentTabId == 'today'
        ? ['Today', 'Yesterday', 'Custom']
        : (currentTabId == 'ledger'
            ? ['This Month', 'Last Month', 'Custom']
            : ['Today', 'This Week', 'This Month', 'Custom']);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: presets.map((preset) {
          final isSelected = selectedDatePreset == preset;
          String labelText = preset;
          if (preset == 'Custom' && isSelected && currentTabId != 'ledger') {
            final isSameDay = startDate.year == endDate.year &&
                startDate.month == endDate.month &&
                startDate.day == endDate.day;
            labelText = isSameDay
                ? DateFormat('dd MMM').format(startDate)
                : "${DateFormat('dd MMM').format(startDate)} - ${DateFormat('dd MMM').format(endDate)}";
          }
          return InkWell(
            onTap: () {
              if (onDatePresetSelected != null) {
                onDatePresetSelected!(preset);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected ? msmRed : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: msmRed.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preset == 'Custom') ...[
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    labelText,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTodayViewToggle() {
    final mode =
        todaySummaryTabMode ?? (isDetailedView ? 'Detailed' : 'Summary');
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(
            "Summary",
            mode == 'Summary',
            () {
              if (onTodaySummaryTabModeChanged != null) {
                onTodaySummaryTabModeChanged!('Summary');
              }
              onViewToggle(false);
            },
          ),
          _toggleBtn(
            "Detailed",
            mode == 'Detailed',
            () {
              if (onTodaySummaryTabModeChanged != null) {
                onTodaySummaryTabModeChanged!('Detailed');
              }
              onViewToggle(true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTodayFlowToggle() {
    final currentFlow = todaySummaryFlowMode ?? 'Inward';
    final flows = [
      {'label': 'Inward', 'color': const Color(0xFF16A34A)},
      {'label': 'Outward', 'color': const Color(0xFFDC2626)},
      {'label': 'Net Qty', 'color': const Color(0xFF2563EB)},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: flows.map((f) {
          final label = f['label'] as String;
          final color = f['color'] as Color;
          final isSelected = currentFlow == label;

          return InkWell(
            onTap: () {
              if (onTodaySummaryFlowModeChanged != null) {
                onTodaySummaryFlowModeChanged!(label);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        )
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPdfAction() {
    return Tooltip(
      message: "Export PDF (.pdf)",
      child: _buildHeaderAction(Icons.picture_as_pdf_rounded, onExportPdf,
          isPrimary: true),
    );
  }

  Widget _buildExcelAction() {
    return Tooltip(
      message: "Export Excel (.xlsx)",
      child: InkWell(
        onTap: onExportExcel,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.table_chart_rounded,
              color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: 320,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: onSearch,
              decoration: const InputDecoration(
                hintText: "Search items or sizes...",
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ),
          if (searchController.text.isNotEmpty)
            InkWell(
              onTap: () {
                searchController.clear();
                onSearch('');
              },
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.close_rounded, size: 18, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon, VoidCallback onTap,
      {bool isPrimary = false, String? tooltip}) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPrimary ? msmRed : const Color(0xFFF1F3F4),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: msmRed.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(icon,
            color: isPrimary ? Colors.white : Colors.grey.shade700, size: 22),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _toggleBtn("Summary", !isDetailedView, () => onViewToggle(false)),
          _toggleBtn("Detailed", isDetailedView, () => onViewToggle(true)),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4)
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: active ? msmRed : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final df = DateFormat('dd MMM yyyy');
    return InkWell(
      onTap: onDateRange,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: msmRed),
            const SizedBox(width: 10),
            Text(
              "${df.format(startDate)} - ${df.format(endDate)}",
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: locationFilter,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: textDark),
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: textDark, fontSize: 13),
          items: ['ALL', 'YARD', 'FACTORY']
              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
              .toList(),
          onChanged: onLocationChange,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class ReportCalculators {
  static List<StockMovementEntry> calculateStockMovement(
      List<StockTransaction> allTxs,
      List<dynamic> locations,
      DateTime start,
      DateTime end,
      String locationFilter) {
    final filterStart = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final filterEnd = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    Map<String, Map<String, StockMovementEntry>> map = {};

    // 1. Pre-populate map from active inventory list to preserve all catalog items (including 0-movement items like MS Structure ISMC)
    for (final v in DataRepository.inventoryListNotifier.value) {
      if (locationFilter != 'ALL' &&
          v.location.toUpperCase() != locationFilter.toUpperCase()) {
        continue;
      }
      final String catName = DataRepository.canonicalizeCategory(v.category);
      if (['Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB']
              .contains(catName) &&
          v.currentStockMT == 0) {
        continue;
      }
      final String key =
          "${catName.toUpperCase()}_${v.itemName.toUpperCase()}";
      map.putIfAbsent(
          key,
          () => {
                v.itemName: StockMovementEntry(
                  category: catName,
                  item: v.itemName,
                  sizes: [],
                )
              });
      var entry = map[key]![v.itemName]!;
      if (!entry.sizes.any((s) => s.label == v.size)) {
        entry.sizes.add(StockSizeMovement(
          label: v.size,
          opening: 0,
          inQty: 0,
          outQty: 0,
          closing: 0,
        ));
      }
    }

    for (var tx in allTxs) {
      if (tx.isReversed) continue;
      if (tx.txnId.startsWith('S-17')) continue;
      if (tx.txnId.startsWith('IN_V_')) continue;

      final String txLoc = tx.location.trim().toUpperCase();
      final String? toLoc = tx.toLocation?.trim().toUpperCase();
      final String targetLoc = locationFilter.trim().toUpperCase();

      bool isRelevant = false;
      bool isTransferIn = false;
      bool isTransferOut = false;

      if (targetLoc == 'ALL') {
        isRelevant = true;
      } else {
        if (txLoc == targetLoc) {
          isRelevant = true;
          if (tx.type.toUpperCase() == 'TRANSFER') {
            isTransferOut = true;
          }
        }
        if (toLoc == targetLoc && tx.type.toUpperCase() == 'TRANSFER') {
          isRelevant = true;
          isTransferIn = true;
        }
      }

      if (!isRelevant) continue;

      final String rawCat =
          (tx.category.trim().isNotEmpty && tx.category != "General")
              ? tx.category
              : tx.itemName;
      final String catName = DataRepository.canonicalizeCategory(rawCat);

      if (['Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB']
          .contains(catName)) {
        continue;
      }

      final String key =
          "${catName.toUpperCase()}_${tx.itemName.toUpperCase()}";
      if (!map.containsKey(key)) {
        map[key] = {
          tx.itemName: StockMovementEntry(
              category: catName, item: tx.itemName, sizes: [])
        };
      }

      var entry = map[key]![tx.itemName]!;
      var sizeEntry =
          entry.sizes.firstWhere((s) => s.label == tx.sizeLabel, orElse: () {
        var newSize = StockSizeMovement(
            label: tx.sizeLabel, opening: 0, inQty: 0, outQty: 0, closing: 0);
        entry.sizes.add(newSize);
        return newSize;
      });

      final txDate = tx.date;
      final txType = tx.type.toUpperCase();

      bool isAdd = false;
      bool isSub = false;

      if (targetLoc != 'ALL' && txType == 'TRANSFER') {
        if (isTransferIn) isAdd = true;
        if (isTransferOut) isSub = true;
      } else if (txType == 'TRANSFER') {
        isAdd = false;
        isSub = false;
      } else if (['IN', 'RETURN', 'OPENING', 'OPENING_STOCK', 'ADJUSTMENT']
          .contains(txType)) {
        if (txType == 'ADJUSTMENT' && tx.qty < 0) {
          isSub = true;
        } else {
          isAdd = true;
        }
      } else if (['OUT', 'OUTWARD', 'SALE', 'RESERVE'].contains(txType)) {
        isSub = true;
      }

      final bool isOpeningTxn = txType == 'OPENING' ||
          txType == 'OPENING_STOCK' ||
          tx.txnId.startsWith('OPENING-');

      final double qty = tx.qty.abs();

      if (txDate.isBefore(filterStart) || isOpeningTxn) {
        if (isAdd) sizeEntry.opening += qty;
        if (isSub) sizeEntry.opening -= qty;
      } else if (txDate.isAfter(filterEnd)) {
        // ignore future transactions beyond date range
      } else {
        if (isAdd) sizeEntry.inQty += qty;
        if (isSub) sizeEntry.outQty += qty;
      }

      sizeEntry.closing =
          sizeEntry.opening + sizeEntry.inQty - sizeEntry.outQty;
    }

    List<StockMovementEntry> list = [];
    map.forEach((cat, items) {
      for (var entry in items.values) {
        entry.sizes.removeWhere((s) =>
            s.opening == 0 && s.inQty == 0 && s.outQty == 0 && s.closing == 0);
        if (entry.sizes.isNotEmpty) {
          list.add(entry);
        }
      }
    });
    list.sort((a, b) => SortingUtils.compareCategories(a.item, b.item));
    for (var entry in list) {
      entry.sizes.sort((a, b) => SortingUtils.compareSizes(a.label, b.label));
    }
    return list;
  }

  static Map<String, Map<String, List<StockMovementEntry>>>
      groupStocksByCategoryAndItem(List<StockMovementEntry> reports) {
    Map<String, Map<String, List<StockMovementEntry>>> grouped = {};
    for (var r in reports) {
      final String cat = DataRepository.canonicalizeCategory(r.category);
      grouped.putIfAbsent(cat, () => {});
      grouped[cat]!.putIfAbsent(r.item, () => []);
      grouped[cat]![r.item]!.add(r);
    }
    return grouped;
  }

  static List<DeadStockEntry> calculateDeadStock(List<StockTransaction> allTxs,
      List<dynamic> locations, DateTime referenceDate) {
    final cutoff = referenceDate.subtract(const Duration(days: 15));
    Map<String, Map<String, _StockState>> stockMap = {};

    // 1. Initialize with all items from locations to handle items with NO movement
    for (var loc in locations) {
      if (loc == null || loc is! Map) continue;
      final rawItems = loc['items'];
      final Map<dynamic, dynamic> items = (rawItems is Map) ? rawItems : {};

      items.forEach((itemName, sizes) {
        if (itemName == null) return;
        stockMap.putIfAbsent(itemName.toString(), () => {});
        if (sizes is Map) {
          sizes.forEach((size, qty) {
            if (size == null) return;
            stockMap[itemName.toString()]!
                .putIfAbsent(size.toString(), () => _StockState());
            stockMap[itemName.toString()]![size.toString()]!.qty =
                (qty as num?)?.toDouble() ?? 0.0;
          });
        }
      });
    }

    // 2. Update with transaction history to find last movement
    for (var tx in allTxs) {
      final localDate = tx.date;
      final txDate = DateTime(localDate.year, localDate.month, localDate.day);
      final refDate =
          DateTime(referenceDate.year, referenceDate.month, referenceDate.day);

      // Rule: Ignore future transactions relative to filter reference (usually today)
      if (txDate.isAfter(refDate)) continue;

      stockMap.putIfAbsent(tx.itemName, () => {});
      stockMap[tx.itemName]!.putIfAbsent(tx.sizeLabel, () => _StockState());

      var state = stockMap[tx.itemName]![tx.sizeLabel]!;
      final stateLastMovement = DateTime(state.lastMovement.year,
          state.lastMovement.month, state.lastMovement.day);
      if (txDate.isAfter(stateLastMovement)) {
        state.lastMovement = tx.date;
      }
    }

    List<DeadStockEntry> dead = [];
    stockMap.forEach((item, sizes) {
      sizes.forEach((size, state) {
        // Rule: current stock > 3 MT AND (no movement for 15+ days OR never moved)
        if (state.qty > 3.0) {
          bool isNonMoving = false;
          final stateLastMovement = DateTime(state.lastMovement.year,
              state.lastMovement.month, state.lastMovement.day);
          final deadCutoff = DateTime(cutoff.year, cutoff.month, cutoff.day);
          if (state.lastMovement.year < 2005) {
            isNonMoving = true;
          } else if (stateLastMovement.isBefore(deadCutoff)) {
            isNonMoving = true;
          }

          if (isNonMoving) {
            // Find category from transactions or default
            String category = "General";
            try {
              final txWithItem = allTxs.firstWhere((t) => t.itemName == item);
              category =
                  DataRepository.canonicalizeCategory(txWithItem.category);
            } catch (_) {
              category = DataRepository.canonicalizeCategory(item);
            }

            dead.add(DeadStockEntry(
              category: category,
              itemName: item,
              size: size,
              currentQty: state.qty,
              daysSinceLastMovement: state.lastMovement.year < 2005
                  ? -1
                  : referenceDate.difference(state.lastMovement).inDays,
              lastMovementDate:
                  state.lastMovement.year < 2005 ? null : state.lastMovement,
            ));
          }
        }
      });
    });

    dead.sort((a, b) {
      int catComp = SortingUtils.compareCategories(a.category, b.category);
      if (catComp != 0) return catComp;
      int itemComp = a.itemName.compareTo(b.itemName);
      if (itemComp != 0) return itemComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
    return dead;
  }

  static List<DailyMovementEntry> calculateDailyMovement(
      List<StockTransaction> allTxs,
      [DateTimeRange? dateRange,
      List<StockMovementEntry>? stockReport]) {
    final DateTime start = dateRange != null
        ? DateTime(
            dateRange.start.year, dateRange.start.month, dateRange.start.day)
        : DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final DateTime end = dateRange != null
        ? DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day,
            23, 59, 59, 999)
        : DateTime(DateTime.now().year, DateTime.now().month,
            DateTime.now().day, 23, 59, 59, 999);

    Map<String, DailyMovementEntry> map = {};

    // 1. If stockReport is provided, pre-populate all categories and sizes
    if (stockReport != null && stockReport.isNotEmpty) {
      for (var entry in stockReport) {
        final String canonicalCat =
            DataRepository.canonicalizeCategory(entry.category);
        for (var s in entry.sizes) {
          final String key =
              "${canonicalCat.toUpperCase()}_${entry.item.toUpperCase()}_${s.label.toUpperCase()}";
          map[key] = DailyMovementEntry(
            category: canonicalCat,
            itemName: entry.item,
            size: s.label,
            openingQty: s.opening,
            inQty: s.inQty,
            outQty: s.outQty,
            closingQty: s.closing,
          );
        }
      }
    } else {
      for (var tx in allTxs) {
        if (tx.isReversed) continue;
        if (tx.txnId.startsWith('S-17')) continue;
        if (tx.txnId.startsWith('IN_V_')) continue;

        final typeUpper = tx.type.trim().toUpperCase();
        if (typeUpper == 'PURCHASE') continue;
        if (typeUpper == 'OPENING' ||
            typeUpper == 'OPENING_STOCK' ||
            tx.txnId.startsWith('OPENING-')) {
          continue;
        }

        final txDate = tx.dateTime;
        if (txDate.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            txDate.isBefore(end.add(const Duration(milliseconds: 1)))) {
          final String rawCat =
              (tx.category.trim().isNotEmpty && tx.category != "General")
                  ? tx.category
                  : tx.itemName;
          final String canonicalCat =
              DataRepository.canonicalizeCategory(rawCat);

          final String key =
              "${canonicalCat.toUpperCase()}_${tx.itemName.toUpperCase()}_${tx.sizeLabel.toUpperCase()}";
          map.putIfAbsent(
              key,
              () => DailyMovementEntry(
                    category: canonicalCat,
                    itemName: tx.itemName,
                    size: tx.sizeLabel,
                    openingQty: 0,
                    inQty: 0,
                    outQty: 0,
                    closingQty: 0,
                  ));
          var entry = map[key]!;
          if (typeUpper == 'IN' ||
              typeUpper == 'INWARD' ||
              typeUpper == 'RETURN' ||
              typeUpper == 'ADJUSTMENT') {
            entry.inQty += tx.qty.abs();
          } else if (typeUpper == 'OUT' ||
              typeUpper == 'OUTWARD' ||
              typeUpper == 'SALE' ||
              typeUpper == 'RESERVE') {
            entry.outQty += tx.qty.abs();
          }
          entry.closingQty = entry.openingQty + entry.inQty - entry.outQty;
        }
      }
    }
    final list = map.values.toList();
    list.sort((a, b) {
      int itemComp = SortingUtils.compareCategories(a.itemName, b.itemName);
      if (itemComp != 0) return itemComp;
      return SortingUtils.compareSizes(a.size, b.size);
    });
    return list;
  }
}

class _StockState {
  double qty = 0;
  DateTime lastMovement = DateTime(2000);
}

class _ReportsSidebar extends StatelessWidget {
  final List<Map<String, dynamic>> activeTabs;
  final String selectedTabId;
  final Function(String) onTabChanged;

  const _ReportsSidebar({
    required this.activeTabs,
    required this.selectedTabId,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 1025;

    final overviewTabs = activeTabs.where((t) => t['id'] == 'today').toList();
    final inventoryTabs = activeTabs.where((t) => t['id'] != 'today').toList();

    return Container(
      width: isDesktop ? 280 : (screenWidth * 0.84).clamp(240.0, 340.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ReportsDrawerHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (overviewTabs.isNotEmpty) ...[
                      const DrawerSectionLabel(
                        label: 'OVERVIEW',
                        topPadding: 16,
                      ),
                      ...overviewTabs.map((tab) {
                        final String id = tab['id'] as String;
                        return ReportsDrawerItem(
                          title: tab['title'] as String,
                          icon: tab['icon'] as IconData,
                          isSelected: id == selectedTabId,
                          onTap: () => onTabChanged(id),
                        );
                      }),
                    ],
                    if (inventoryTabs.isNotEmpty) ...[
                      const DrawerSectionLabel(
                        label: 'INVENTORY REPORTS',
                        topPadding: 20,
                      ),
                      ...inventoryTabs.map((tab) {
                        final String id = tab['id'] as String;
                        return ReportsDrawerItem(
                          title: tab['title'] as String,
                          icon: tab['icon'] as IconData,
                          isSelected: id == selectedTabId,
                          onTap: () => onTabChanged(id),
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const _SupportCenterCard(),
          ],
        ),
      ),
    );
  }
}

class _ReportsDrawerHeader extends StatelessWidget {
  const _ReportsDrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: msmRedSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: msmRed,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Reports",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Inventory insights and reports",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: textDark, size: 20),
            tooltip: "Close drawer",
            onPressed: () {
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                Scaffold.of(context).closeDrawer();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

class DrawerSectionLabel extends StatelessWidget {
  final String label;
  final double topPadding;

  const DrawerSectionLabel({
    super.key,
    required this.label,
    this.topPadding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 8, left: 4, right: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: textGrey,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class ReportsDrawerItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const ReportsDrawerItem({
    super.key,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color selectedBg = msmRedSoft;
    const Color selectedTextColor = Color(0xFF991B1B);

    return Semantics(
      label: title,
      selected: isSelected,
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: const BoxConstraints(minHeight: 48),
        child: Material(
          color: isSelected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (isSelected)
                  Positioned(
                    left: 0,
                    top: 6,
                    bottom: 6,
                    width: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: msmRed,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: isSelected
                            ? msmRed
                            : textDark.withValues(alpha: 0.7),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? selectedTextColor : textDark,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (!isSelected) ...[
                        Icon(
                          Icons.chevron_right_rounded,
                          color: textGrey.withValues(alpha: 0.5),
                          size: 18,
                        ),
                      ],
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

class _SupportCenterCard extends StatelessWidget {
  final VoidCallback? onTap;

  const _SupportCenterCard({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Support Center. Need help? Visit Support Center",
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap ?? () {},
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: msmRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      color: msmRed,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Need help?",
                          style: TextStyle(
                            color: textGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Visit Support Center",
                          style: TextStyle(
                            color: textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: textGrey,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final List<Map<String, dynamic>> activeTabs;
  final TabController tabController;
  final VoidCallback onBack;
  final VoidCallback onExportPdf;
  final double minHeight;
  final double maxHeight;
  final double topPadding;
  final Function(int)? onTabTap;

  ReportsHeaderDelegate({
    required this.title,
    required this.activeTabs,
    required this.tabController,
    required this.onBack,
    required this.onExportPdf,
    required this.minHeight,
    required this.maxHeight,
    required this.topPadding,
    this.onTabTap,
  });

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  bool shouldRebuild(covariant ReportsHeaderDelegate oldDelegate) => true;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final reverseProgress = 1.0 - progress;

    return Container(
      decoration: BoxDecoration(
        color: msmRed,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24 * reverseProgress),
          bottomRight: Radius.circular(24 * reverseProgress),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      onPressed: onBack),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900))),
                  IconButton(
                      icon: const Icon(Icons.picture_as_pdf_rounded,
                          color: Colors.white, size: 22),
                      onPressed: onExportPdf),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            if (reverseProgress > 0.5) ...[
              const Spacer(),
              Opacity(
                opacity: (reverseProgress * 2 - 1.0).clamp(0.0, 1.0),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TabBar(
                    controller: tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: activeTabs
                        .map((t) => Tab(text: t['title'] as String))
                        .toList(),
                    onTap: onTabTap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MovementSummaryCard extends StatelessWidget {
  final double totalIn;
  final double totalOut;
  final double totalNet;

  const _MovementSummaryCard(
      {required this.totalIn, required this.totalOut, required this.totalNet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metric("Inflow", formatNumber(totalIn), Colors.green),
          _metric("Outflow", formatNumber(totalOut), Colors.red),
          _metric("Net", formatNumber(totalNet),
              totalNet >= 0 ? Colors.blue : Colors.orange),
        ],
      ),
    );
  }

  Widget _metric(String label, String val, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text("$val MT",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
      ],
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
