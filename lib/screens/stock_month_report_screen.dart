import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/motion_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../services/data_repository.dart';
import '../services/supabase_realtime_service.dart';
import '../models/stock_models.dart';
import '../models/report_models.dart';
import '../constants/app_colors.dart';
import '../services/month_report_export_service.dart';
import '../widgets/shimmer_widget.dart';
import '../utils/sorting_utils.dart';
import '../utils/formatters.dart';

class StockMonthReportScreen extends StatefulWidget {
  const StockMonthReportScreen({super.key});

  @override
  State<StockMonthReportScreen> createState() => _StockMonthReportScreenState();
}

class _StockMonthReportScreenState extends State<StockMonthReportScreen> {
  bool _isLoading = true;
  DateTime _selectedMonth = DateTime.now();
  String _selectedPreset = 'This Month';
  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;

  void _onPresetSelected(String preset) async {
    final now = DateTime.now();
    if (preset == 'Today') {
      setState(() {
        _selectedPreset = 'Today';
        _selectedMonth = DateTime(now.year, now.month, now.day);
      });
      await _loadData();
    } else if (preset == 'This Week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      setState(() {
        _selectedPreset = 'This Week';
        _selectedMonth = DateTime(monday.year, monday.month, monday.day);
      });
      await _loadData();
    } else if (preset == 'This Month') {
      setState(() {
        _selectedPreset = 'This Month';
        _selectedMonth = DateTime(now.year, now.month, 1);
      });
      await _loadData();
    } else if (preset == 'Custom') {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        initialDateRange:
            DateTimeRange(start: _selectedMonth, end: DateTime.now()),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) {
        setState(() {
          _selectedPreset = 'Custom';
          _selectedMonth = picked.start;
        });
        await _loadData();
      }
    }
  }

  List<StockTransaction> _allTxs = [];
  List<StockTransaction> _monthTxs = [];
  List<dynamic> _flatReportList = [];

  @override
  void initState() {
    super.initState();
    _syncSubscription = SupabaseRealtimeService.instance.syncStream.listen((_) {
      if (mounted) _loadData();
    });
    _loadData();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('stock_transactions_v2');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      final all = list.map((e) => StockTransaction.fromJson(e)).toList();
      final lastReset = await DataRepository.getLastResetTimestamp();
      final DateTime resetCutoff = lastReset ?? DateTime(1900);
      _allTxs = all.where((tx) => tx.dateTime.isAfter(resetCutoff)).toList();
      _monthTxs = _allTxs
          .where((tx) =>
              !tx.isReversed &&
              tx.dateTime.year == _selectedMonth.year &&
              tx.dateTime.month == _selectedMonth.month)
          .toList();
    }
    _rebuildFlatReportList();
    if (mounted) setState(() => _isLoading = false);
  }

  void _rebuildFlatReportList() {
    _flatReportList = [];
    final entries = _buildMonthReportEntries();
    String? lastCategory;

    for (var entry in entries) {
      if (entry.category != lastCategory) {
        _flatReportList.add(entry.category);
        lastCategory = entry.category;
      }
      _flatReportList.add(entry);
    }
  }

  void _pickMonth() async {
    showDialog(
        context: context,
        builder: (context) {
          int year = _selectedMonth.year;
          int month = _selectedMonth.month;
          return AlertDialog(
            title: const Text("Select Month"),
            content: StatefulBuilder(builder: (context, setStateDialog) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<int>(
                    value: year,
                    items: List.generate(5, (i) => DateTime.now().year - 2 + i)
                        .map((y) => DropdownMenuItem(
                            value: y, child: Text(y.toString())))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => year = v!),
                  ),
                  DropdownButton<int>(
                    value: month,
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(m.toString())))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => month = v!),
                  ),
                ],
              );
            }),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL")),
              TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(year, month);
                      _isLoading = true;
                    });
                    _loadData();
                    Navigator.pop(context);
                  },
                  child: const Text("OK")),
            ],
          );
        });
  }

  List<MonthReportEntry> _buildMonthReportEntries() {
    final Map<String, Map<String, List<StockTransaction>>> monthGrouped = {};
    for (final tx in _monthTxs) {
      monthGrouped.putIfAbsent(tx.itemName, () => {});
      monthGrouped[tx.itemName]!.putIfAbsent(tx.size, () => []);
      monthGrouped[tx.itemName]![tx.size]!.add(tx);
    }

    final List<MonthReportEntry> entries = [];
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);

    for (final itemEntry in monthGrouped.entries) {
      for (final sizeEntry in itemEntry.value.entries) {
        final itemName = itemEntry.key;
        final size = sizeEntry.key;

        double opening = 0.0;
        for (var tx in _allTxs) {
          if (tx.isReversed) continue;
          if (tx.itemName == itemName &&
              tx.size == size &&
              tx.dateTime.isBefore(startOfMonth)) {
            if (tx.type == 'IN') opening += tx.qtyMT;
            if (tx.type == 'OUT') opening -= tx.qtyMT;
          }
        }

        final sIn = sizeEntry.value
            .where((tx) => tx.type == 'IN')
            .fold(0.0, (sum, tx) => sum + tx.qtyMT);
        final sOut = sizeEntry.value
            .where((tx) => tx.type == 'OUT')
            .fold(0.0, (sum, tx) => sum + tx.qtyMT);

        entries.add(
          MonthReportEntry(
            category: itemName,
            item: size,
            openingQty: opening,
            inQty: sIn,
            outQty: sOut,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final c = SortingUtils.compareCategories(a.category, b.category);
      if (c != 0) return c;
      return a.item.toLowerCase().compareTo(b.item.toLowerCase());
    });
    return entries;
  }

  Future<void> _downloadReportPdf() async {
    if (_monthTxs.isEmpty) {
      MotionToast.show(context, "No monthly data to download.", isError: true);
      return;
    }
    final totalIn = _monthTxs
        .where((tx) => tx.type == 'IN')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    final totalOut = _monthTxs
        .where((tx) => tx.type == 'OUT')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    final entries = _buildMonthReportEntries();
    final pdfBytes = await MonthReportExportService.buildPdf(
      selectedMonth: _selectedMonth,
      entries: entries,
      totalIn: totalIn,
      totalOut: totalOut,
    );
    final fileName = MonthReportExportService.fileName(_selectedMonth);
    await Printing.layoutPdf(name: fileName, onLayout: (_) async => pdfBytes);
  }

  Future<void> _shareReportPdf() async {
    if (_monthTxs.isEmpty) {
      MotionToast.show(context, "No monthly data to share.", isError: true);
      return;
    }
    final totalIn = _monthTxs
        .where((tx) => tx.type == 'IN')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    final totalOut = _monthTxs
        .where((tx) => tx.type == 'OUT')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    final entries = _buildMonthReportEntries();
    final pdfBytes = await MonthReportExportService.buildPdf(
      selectedMonth: _selectedMonth,
      entries: entries,
      totalIn: totalIn,
      totalOut: totalOut,
    );
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: MonthReportExportService.fileName(_selectedMonth),
    );
  }

  Future<void> _shareReportText() async {
    if (_monthTxs.isEmpty) {
      MotionToast.show(context, "No monthly data to share.", isError: true);
      return;
    }
    final totalIn = _monthTxs
        .where((tx) => tx.type == 'IN')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    final totalOut = _monthTxs
        .where((tx) => tx.type == 'OUT')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    final text = MonthReportExportService.buildTextSummary(
      selectedMonth: _selectedMonth,
      entries: _buildMonthReportEntries(),
      totalIn: totalIn,
      totalOut: totalOut,
    );
    await Share.share(
      text,
      subject:
          "MSM Month Report ${MonthReportExportService.monthLabel(_selectedMonth)}",
    );
  }

  void _showShareOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: msmRed),
              title: const Text("Share PDF Report"),
              subtitle: const Text("WhatsApp, Email, Drive, etc."),
              onTap: () async {
                Navigator.pop(context);
                await _shareReportPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined, color: msmRed),
              title: const Text("Share Text Summary"),
              subtitle: const Text("Quick summary in message format."),
              onTap: () async {
                Navigator.pop(context);
                await _shareReportText();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgLight,
        appBar: AppBar(title: const Text("Stock Report")),
        body: Shimmer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(height: 40, width: 150, color: Colors.white),
                const SizedBox(height: 20),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                        3,
                        (i) => Container(
                            width: 80, height: 60, color: Colors.white))),
                const SizedBox(height: 20),
                Expanded(
                    child: ListView.builder(
                        itemCount: 10,
                        itemBuilder: (c, i) => Container(
                            height: 50,
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white))),
              ],
            ),
          ),
        ),
      );
    }

    double totalIn = _monthTxs
        .where((tx) => tx.type == 'IN')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);
    double totalOut = _monthTxs
        .where((tx) => tx.type == 'OUT')
        .fold(0.0, (sum, tx) => sum + tx.qtyMT);

    Map<String, Map<String, List<StockTransaction>>> grouped = {};
    for (var tx in _monthTxs) {
      grouped.putIfAbsent(tx.itemName, () => {});
      grouped[tx.itemName]!.putIfAbsent(tx.size, () => []);
      grouped[tx.itemName]![tx.size]!.add(tx);
    }

    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text("Month Report"),
        actions: [
          IconButton(
            tooltip: "Select Month",
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
          ),
          IconButton(
            tooltip: "Download PDF",
            icon: const Icon(Icons.download_outlined),
            onPressed: _downloadReportPdf,
          ),
          IconButton(
            tooltip: "Share Report",
            icon: const Icon(Icons.share_outlined),
            onPressed: _showShareOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  Text(
                    "${_selectedMonth.month}/${_selectedMonth.year}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(width: 16),
                  Row(children: [
                    _miniStat("IN", totalIn, Colors.teal),
                    const SizedBox(width: 12),
                    _miniStat("OUT", totalOut, Colors.orange),
                    const SizedBox(width: 12),
                    _miniStat("Net", totalIn - totalOut, Colors.blue),
                  ])
                ],
              ),
            ),
          ),
          Expanded(
            child: _flatReportList.isEmpty
                ? const Center(child: Text("No data for this month."))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _flatReportList.length,
                    itemBuilder: (context, index) {
                      final item = _flatReportList[index];
                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(item,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: msmRed)),
                        );
                      } else if (item is MonthReportEntry) {
                        return _buildReportEntryCard(item);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double val, Color color) {
    return Column(children: [
      Text(val.toStringAsFixed(3),
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      Text(label, style: const TextStyle(fontSize: 9))
    ]);
  }

  Widget _resTxt(double val, Color color,
      {bool bold = false, double fontSize = 11}) {
    return Flexible(
        child: Text(
      val.toStringAsFixed(3),
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontSize: fontSize),
    ));
  }

  Widget _reportCol(String label, double val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: textGrey)),
        const SizedBox(height: 2),
        Text(val.toStringAsFixed(3),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildReportEntryCard(MonthReportEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    getFormattedSizeDisplay(entry.item, null),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Closing",
                        style: TextStyle(fontSize: 9, color: textGrey)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        entry.closingQty.toStringAsFixed(3),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: msmRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              // Stack if width is narrow
              bool stack = constraints.maxWidth < 300;
              if (stack) {
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _reportCol(
                            "Opening", entry.openingQty, Colors.blueGrey),
                        _reportCol(
                            "Net", entry.inQty - entry.outQty, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _reportCol("IN", entry.inQty, Colors.teal),
                        _reportCol("OUT", entry.outQty, Colors.orange),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _reportCol("Opening", entry.openingQty, Colors.blueGrey),
                  _reportCol("IN", entry.inQty, Colors.teal),
                  _reportCol("OUT", entry.outQty, Colors.orange),
                  _reportCol("Net", entry.inQty - entry.outQty, Colors.blue),
                ],
              );
            })
          ],
        ),
      ),
    );
  }
}
