import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../services/data_repository.dart';
import '../services/whatsapp_share_service.dart';
import '../utils/file_download_helper.dart' as download_helper;
import '../utils/formatters.dart';
import '../utils/item_order_util.dart';
import '../utils/sorting_utils.dart';
import '../widgets/dealer_share/category_stock_accordion.dart';
import '../widgets/dealer_share/dealer_share_toolbar.dart';
import '../widgets/m_loader.dart';

/// Lead Enterprise Flutter Implementation: Stock Sheet & Trade Availability Console.
/// Streamlined location-wise trade availability and pricing workflow:
/// 1. DEALER SHARE ACTION TOOLBAR: Location Selector, Real-time Search, WhatsApp Copy, PDF Export, Share.
/// 2. CANONICAL CATEGORY GROUPING: 14 canonical categories strictly in order via ItemOrderUtil.
/// 3. HIGH-DENSITY ITEM & SIZE ROWS: Multi-column grid, Unit Weight, Stock Status, Rate/SD, and Zebra striping.
/// 4. AUDIT & DEFICIT INTEGRITY: Raw deficit balances (e.g., -0.320 MT) preserved without zero-clamping.
/// 5. RESPONSIVE ADAPTATION: Desktop structured grid & Mobile compact tiles with bottom pinned actions.
// -----------------------------------------------------------------------------
// ISOLATE PARAMS & TOP-LEVEL ISOLATE PDF GENERATOR
// -----------------------------------------------------------------------------
class _PdfParams {
  final List<Map<String, dynamic>> selectedRows;
  final String activeLocation;
  final String currentDateStr;
  final Uint8List? templateBytes;

  _PdfParams({
    required this.selectedRows,
    required this.activeLocation,
    required this.currentDateStr,
    this.templateBytes,
  });
}

double _safeDoubleStatic(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString()) ?? 0.0;
}

String _formatItemDescriptionStatic(
    String category, String sizeLabel, dynamic rawUnitWeight) {
  final baseDisplay = formatSizeDisplay(category, sizeLabel);
  final int unitWtInt = (rawUnitWeight as num?)?.toInt() ??
      int.tryParse(rawUnitWeight?.toString() ?? '0') ??
      0;

  String desc = baseDisplay;
  if (!desc.toLowerCase().contains(category.toLowerCase())) {
    desc = '$category $desc';
  }

  if (unitWtInt > 0 && !desc.toLowerCase().contains('kg')) {
    return '$desc ${unitWtInt}kg';
  }
  return desc;
}

Future<Uint8List> _generatePdfBytesIsolate(_PdfParams params) async {
  final pdfDoc = pw.Document(
    title: 'Metaroll / MSM One - Available Stock Sheet',
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    ),
  );

  pw.MemoryImage? templateImage;
  if (params.templateBytes != null && params.templateBytes!.isNotEmpty) {
    templateImage = pw.MemoryImage(params.templateBytes!);
  }

  // --- Color Palette ---
  final metarollRed = PdfColor.fromHex('#E30613');
  final darkSlate = PdfColor.fromHex('#1E293B');
  final mediumSlate = PdfColor.fromHex('#334155');
  final gridBorder = PdfColor.fromHex('#E2E8F0');
  final zebraStripe = PdfColor.fromHex('#F9FAFB');
  final greyBarBg = PdfColor.fromHex('#D9DBDA');

  final pageTheme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.only(
        top: 116, left: 30, right: 30, bottom: 25),
    buildBackground: (pw.Context context) {
      if (templateImage != null) {
        return pw.FullPage(
          ignoreMargins: true,
          child: pw.Stack(
            children: [
              pw.Image(
                templateImage,
                fit: pw.BoxFit.fill,
              ),
              // ── Wide mask to cover the entire template date text ──
              pw.Positioned(
                top: 69,
                right: 0,
                child: pw.Container(
                  width: 200,
                  height: 24,
                  color: greyBarBg,
                ),
              ),
              // ── Clean dynamic date label ──
              pw.Positioned(
                top: 73.5,
                right: 30,
                child: pw.Text(
                  'Date : ${params.currentDateStr}',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: darkSlate,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return pw.SizedBox();
    },
  );

  // ── Group & sort rows by category in canonical order ──
  final Map<String, List<Map<String, dynamic>>> grouped = {};
  for (final row in params.selectedRows) {
    final cat = row['category_name']?.toString() ?? 'General';
    grouped.putIfAbsent(cat, () => []).add(row);
  }
  final sortedCategories = grouped.keys.toList()
    ..sort(ItemOrderUtil.compare);

  pdfDoc.addPage(
    pw.MultiPage(
      pageTheme: pageTheme,
      footer: (pw.Context context) => pw.SizedBox(),
      build: (pw.Context context) {
        final List<pw.Widget> content = [];
        final int categoryCount = sortedCategories.length;

        // ── Helper to strip index range suffixes from category header titles ──
        String cleanCategoryTitle(String title) {
          return title.replaceAll(RegExp(r'\s*\(\d+-\d+\)'), '').trim();
        }

        // ── Helper to build a clean 2-column Category Table ──
        pw.Widget buildCategoryTable({
          required String catTitle,
          required List<Map<String, dynamic>> catRows,
          required int startIndex,
          required double col0Flex,
          required double col1Flex,
          required bool showBanner,
        }) {
          final List<pw.TableRow> tableRows = [];
          final String displayTitle = cleanCategoryTitle(catTitle);

          // 1. Red Category Banner
          if (showBanner) {
            tableRows.add(
              pw.TableRow(
                decoration: pw.BoxDecoration(color: metarollRed),
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    child: pw.Text(
                      displayTitle.toUpperCase(),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                  ),
                ],
              ),
            );
          }

          // 2. Dark Sub-Headers Row
          tableRows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(color: darkSlate),
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  child: pw.Text(
                    'Item Description / Size',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Stock Quantity (MT)',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );

          // 3. Item Data Rows with alternating zebra striping
          for (int r = 0; r < catRows.length; r++) {
            final row = catRows[r];
            final sizeLabel = row['size_label']?.toString() ?? '';
            final double stockVal = _safeDoubleStatic(row['current_stock_mt']);
            final desc = _formatItemDescriptionStatic(
                catTitle, sizeLabel, row['unit_weight_kg']);
            final bool isEven = r % 2 == 0;

            tableRows.add(
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: isEven ? zebraStripe : PdfColors.white,
                ),
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4.5),
                    child: pw.Text(
                      desc,
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: mediumSlate,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4.5),
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      '${stockVal.toStringAsFixed(3)} MT',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: stockVal < 0 ? metarollRed : darkSlate,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: gridBorder, width: 0.5),
            ),
            child: pw.Table(
              columnWidths: {
                0: pw.FlexColumnWidth(col0Flex),
                1: pw.FlexColumnWidth(col1Flex),
              },
              children: tableRows,
            ),
          );
        }

        // Layout Rendering Strategy:
        if (categoryCount == 1) {
          final cat = sortedCategories.first;
          final catRows = grouped[cat]!;
          final int totalItems = catRows.length;

          if (totalItems <= 14) {
            content.add(
              buildCategoryTable(
                catTitle: cat,
                catRows: catRows,
                startIndex: 0,
                col0Flex: 3.5,
                col1Flex: 1.5,
                showBanner: true,
              ),
            );
          } else {
            final int mid = (totalItems / 2).ceil();
            final leftRows = catRows.sublist(0, mid);
            final rightRows = catRows.sublist(mid);

            final leftTable = buildCategoryTable(
              catTitle: '$cat (1-$mid)',
              catRows: leftRows,
              startIndex: 0,
              col0Flex: 2.2,
              col1Flex: 1.0,
              showBanner: true,
            );

            final rightTable = buildCategoryTable(
              catTitle: '$cat (${mid + 1}-$totalItems)',
              catRows: rightRows,
              startIndex: mid,
              col0Flex: 2.2,
              col1Flex: 1.0,
              showBanner: false,
            );

            content.add(
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: leftTable),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: rightTable),
                ],
              ),
            );
          }
        } else {
          final List<pw.Widget> allTableBlocks = [];
          const int maxItemsPerBlock = 14;

          for (final cat in sortedCategories) {
            final catRows = grouped[cat]!;
            if (catRows.length <= maxItemsPerBlock) {
              allTableBlocks.add(
                buildCategoryTable(
                  catTitle: cat,
                  catRows: catRows,
                  startIndex: 0,
                  col0Flex: 2.2,
                  col1Flex: 1.0,
                  showBanner: true,
                ),
              );
            } else {
              for (int chunkStart = 0;
                  chunkStart < catRows.length;
                  chunkStart += maxItemsPerBlock) {
                final chunkEnd =
                    (chunkStart + maxItemsPerBlock < catRows.length)
                        ? chunkStart + maxItemsPerBlock
                        : catRows.length;
                final chunkRows = catRows.sublist(chunkStart, chunkEnd);

                allTableBlocks.add(
                  buildCategoryTable(
                    catTitle: cat,
                    catRows: chunkRows,
                    startIndex: chunkStart,
                    col0Flex: 2.2,
                    col1Flex: 1.0,
                    showBanner: chunkStart == 0,
                  ),
                );
              }
            }
          }

          for (int i = 0; i < allTableBlocks.length; i += 2) {
            final leftBlock = allTableBlocks[i];
            if (i + 1 < allTableBlocks.length) {
              final rightBlock = allTableBlocks[i + 1];
              content.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(child: leftBlock),
                    pw.SizedBox(width: 12),
                    pw.Expanded(child: rightBlock),
                  ],
                ),
              );
            } else {
              content.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(child: leftBlock),
                    pw.SizedBox(width: 12),
                    pw.Expanded(child: pw.Container()),
                  ],
                ),
              );
            }
          }
        }

        return content;
      },
    ),
  );

  return pdfDoc.save();
}

class DealerStockShareScreen extends StatefulWidget {
  final String? initialLocation;
  const DealerStockShareScreen({super.key, this.initialLocation});

  @override
  State<DealerStockShareScreen> createState() =>
      _DealerStockShareScreenState();
}

class _DealerStockShareScreenState extends State<DealerStockShareScreen> {
  bool _isLoading = true;
  bool _isExporting = false;

  // Step 1: Location Filter ('YARD', 'FACTORY', 'ALL')
  String _activeLocation = 'YARD';

  // Step 2 & 3: Hierarchical Stock Data & Selection Tracking
  List<Map<String, dynamic>> _rawStockList = [];
  final Map<String, bool> _selectedItemKeys = {};

  // Accordion Expand State: Key: category_name, Value: bool
  final Map<String, bool> _expandedCategories = {};

  // Search Filter
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null && widget.initialLocation!.isNotEmpty) {
      _activeLocation = widget.initialLocation!.toUpperCase();
    }
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Fetches stock records for current location filter
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final list =
          await DataRepository.fetchDealerStockChart(_activeLocation);

      _selectedItemKeys.clear();
      // Select all by default for fast sharing
      for (final row in list) {
        _selectedItemKeys[_getItemKey(row)] = true;
      }

      if (mounted) {
        setState(() {
          _rawStockList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DealerStockShareScreen] Error loading stock sheet: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Unique key for an item row
  String _getItemKey(Map<String, dynamic> row) {
    final cat = row['category_name']?.toString() ?? 'General';
    final size = row['size_label']?.toString() ?? '';
    return '${cat}_$size';
  }

  double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  // ---------------------------------------------------------------------------
  // SELECTION HELPERS
  // ---------------------------------------------------------------------------
  bool _isItemSelected(Map<String, dynamic> row) {
    final key = _getItemKey(row);
    return _selectedItemKeys[key] ?? true;
  }

  void _toggleItemSelection(Map<String, dynamic> row, bool? selected) {
    final key = _getItemKey(row);
    setState(() {
      _selectedItemKeys[key] = selected ?? false;
    });
  }

  bool? _getCategorySelectionState(
      String category, List<Map<String, dynamic>> categoryRows) {
    if (categoryRows.isEmpty) return false;
    int selectedCount = 0;
    for (final row in categoryRows) {
      if (_isItemSelected(row)) selectedCount++;
    }
    if (selectedCount == 0) return false;
    if (selectedCount == categoryRows.length) return true;
    return null; // Indeterminate state
  }

  void _toggleCategorySelection(
      List<Map<String, dynamic>> categoryRows, bool? selectAll) {
    final targetState = selectAll ?? false;
    setState(() {
      for (final row in categoryRows) {
        final key = _getItemKey(row);
        _selectedItemKeys[key] = targetState;
      }
    });
  }

  void _selectAllGlobal(bool select) {
    setState(() {
      for (final row in _rawStockList) {
        final key = _getItemKey(row);
        _selectedItemKeys[key] = select;
      }
    });
  }

  /// Returns selected stock rows formatted and sorted in canonical order
  List<Map<String, dynamic>> _getSelectedStockRows() {
    final selected = _rawStockList.where((row) {
      return _isItemSelected(row);
    }).toList();

    selected.sort((a, b) {
      final catA = a['category_name']?.toString() ?? '';
      final catB = b['category_name']?.toString() ?? '';
      final catCmp = ItemOrderUtil.compare(catA, catB);
      if (catCmp != 0) return catCmp;

      final sizeA = a['size_label']?.toString() ?? '';
      final sizeB = b['size_label']?.toString() ?? '';
      return SortingUtils.compareSizes(sizeA, sizeB);
    });

    return selected;
  }

  /// Grouped stock map for Accordion view
  Map<String, List<Map<String, dynamic>>> _getGroupedStockMap() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in _rawStockList) {
      final cat = row['category_name']?.toString() ?? 'General';

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final sizeLabel = row['size_label']?.toString().toLowerCase() ?? '';
        final matchesCat = cat.toLowerCase().contains(q);
        final matchesSize = sizeLabel.contains(q);
        if (!matchesCat && !matchesSize) continue;
      }

      grouped.putIfAbsent(cat, () => []).add(row);
    }

    grouped.forEach((cat, rows) {
      rows.sort((a, b) {
        final sizeA = a['size_label']?.toString() ?? '';
        final sizeB = b['size_label']?.toString() ?? '';
        return SortingUtils.compareSizes(sizeA, sizeB);
      });
    });

    return grouped;
  }

  double _calculateTotalStock(List<Map<String, dynamic>> rows) {
    return rows.fold(0.0, (sum, r) => sum + _safeDouble(r['current_stock_mt']));
  }

  // ---------------------------------------------------------------------------
  // ACTIONS: WHATSAPP COPY & SHARE
  // ---------------------------------------------------------------------------
  void _copyAllWhatsApp() {
    final grouped = _getGroupedStockMap();
    final selectedKeys = _selectedItemKeys.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();

    if (selectedKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one item to copy.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final text = WhatsappShareService.formatFullStockBroadcast(
      location: _activeLocation,
      groupedStock: grouped,
      selectedItemKeys: selectedKeys,
    );

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Stock sheet copied to clipboard (${selectedKeys.length} items)!'),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyCategoryWhatsApp(String category, List<Map<String, dynamic>> rows) {
    final selectedKeys = _selectedItemKeys.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();

    final text = WhatsappShareService.formatCategoryBroadcast(
      category: category,
      rows: rows,
      location: _activeLocation,
      selectedItemKeys: selectedKeys,
    );

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('$category copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleShare() {
    final selectedKeys = _selectedItemKeys.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();

    final grouped = _getGroupedStockMap();
    final text = WhatsappShareService.formatFullStockBroadcast(
      location: _activeLocation,
      groupedStock: grouped,
      selectedItemKeys: selectedKeys.isNotEmpty ? selectedKeys : null,
    );

    Share.share(
      text,
      subject: 'MSM Stock Sheet - $_activeLocation (${_dateFormat.format(DateTime.now())})',
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT PIPELINE: VECTOR PDF WITH OFFICIAL LETTERHEAD TEMPLATE
  // ---------------------------------------------------------------------------
  Future<void> _exportAndSharePDF() async {
    final selectedRows = _getSelectedStockRows();
    if (selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one stock item to export.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isExporting) return;
    setState(() {
      _isExporting = true;
    });

    try {
      final currentDateStr = _dateFormat.format(DateTime.now());

      Uint8List? templateBytes;
      try {
        final bd = await rootBundle.load('assets/template_stock_sheet.jpeg');
        templateBytes = bd.buffer.asUint8List();
      } catch (e) {
        debugPrint(
            '[DealerStockShareScreen] Error loading template_stock_sheet.jpeg: $e');
      }

      final Uint8List bytes = await compute(
        _generatePdfBytesIsolate,
        _PdfParams(
          selectedRows: selectedRows,
          activeLocation: _activeLocation,
          currentDateStr: currentDateStr,
          templateBytes: templateBytes,
        ),
      );

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'MSM_Stock_Sheet_${_activeLocation}_$dateStr.pdf';

      if (kIsWeb) {
        download_helper.downloadFile(bytes, fileName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF downloaded successfully!')),
          );
        }
      } else {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          text:
              'Metaroll / MSM One - Available Stock Sheet ($_activeLocation Stock - ${_dateFormat.format(DateTime.now())})',
        );
      }
    } catch (e) {
      debugPrint('[DealerStockShareScreen] PDF Export Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // MAIN BUILD & UI STRUCTURE
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final selectedRows = _getSelectedStockRows();
    final double totalSelectedStockMT = _calculateTotalStock(selectedRows);
    final groupedMap = _getGroupedStockMap();

    final sortedCategories = groupedMap.keys.toList()
      ..sort(ItemOrderUtil.compare);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: Color(0xFF0F172A), size: 22),
          tooltip: 'Back to Dashboard',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.share_rounded, size: 18, color: Color(0xFFDC2626)),
            ),
            const SizedBox(width: 10),
            const Text(
              'Stock Sheet',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            tooltip: 'Refresh Stock Data',
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MLoader(size: 60),
                  SizedBox(height: 16),
                  Text(
                    'Loading Stock Sheet...',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isDesktop = constraints.maxWidth >= 900;

                return Stack(
                  children: [
                    SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 20 : 12,
                        16,
                        isDesktop ? 20 : 12,
                        isDesktop ? 24 : 90,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. DEALER SHARE ACTION TOOLBAR
                          DealerShareToolbar(
                            activeLocation: _activeLocation,
                            onLocationChanged: (loc) {
                              if (_activeLocation != loc) {
                                setState(() => _activeLocation = loc);
                                _loadData();
                              }
                            },
                            searchController: _searchCtrl,
                            searchQuery: _searchQuery,
                            onSearchChanged: (q) =>
                                setState(() => _searchQuery = q.trim()),
                            onClearSearch: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            selectedCount: selectedRows.length,
                            totalCount: _rawStockList.length,
                            totalSelectedStockMT: totalSelectedStockMT,
                            onToggleSelectAll: () {
                              final bool isAll = _rawStockList.isNotEmpty &&
                                  selectedRows.length == _rawStockList.length;
                              _selectAllGlobal(!isAll);
                            },
                            onCopyWhatsApp: _copyAllWhatsApp,
                            onExportPdf: _exportAndSharePDF,
                            onShare: _handleShare,
                            isExporting: _isExporting,
                          ),
                          const SizedBox(height: 16),

                          // 2. EMPTY STATE OR CANONICAL ACCORDION LIST
                          if (sortedCategories.isEmpty)
                            _buildEmptyState()
                          else
                            ...sortedCategories.map((cat) {
                              final categoryRows = groupedMap[cat]!;
                              final bool? catSelection =
                                  _getCategorySelectionState(cat, categoryRows);
                              final bool isExpanded =
                                  _expandedCategories[cat] ?? true;

                              return CategoryStockAccordion(
                                categoryName: cat,
                                items: categoryRows,
                                isExpanded: isExpanded,
                                onToggleExpand: () {
                                  setState(() {
                                    _expandedCategories[cat] = !isExpanded;
                                  });
                                },
                                categorySelectionState: catSelection,
                                onToggleCategorySelection: (val) =>
                                    _toggleCategorySelection(categoryRows, val),
                                isItemSelected: _isItemSelected,
                                onToggleItemSelection: _toggleItemSelection,
                                onCopyCategoryWhatsApp: () =>
                                    _copyCategoryWhatsApp(cat, categoryRows),
                              );
                            }),
                        ],
                      ),
                    ),

                    // 3. MOBILE PINNED BOTTOM ACTION BAR
                    if (!isDesktop)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildMobileBottomBar(
                            selectedRows.length, totalSelectedStockMT),
                      ),

                    // 4. EXPORT LOADING OVERLAY DIALOG
                    if (_isExporting) _buildExportOverlay(),
                  ],
                );
              },
            ),
    );
  }

  // ── EMPTY STATE ──
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          const Text(
            'No matching stock items found',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try adjusting your search query or location filter.'
                : 'No active stock items registered for location "$_activeLocation".',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── MOBILE PINNED BOTTOM ACTION BAR ──
  Widget _buildMobileBottomBar(int selectedCount, double totalSelectedMT) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _copyAllWhatsApp,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(
                  'Copy WhatsApp (${totalSelectedMT.toStringAsFixed(1)} MT)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _isExporting ? null : _exportAndSharePDF,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  // ── EXPORT LOADING OVERLAY ──
  Widget _buildExportOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 20),
          content: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                strokeWidth: 3,
              ),
              SizedBox(width: 18),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preparing PDF...',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Formatting branded Stock Sheet',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
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
