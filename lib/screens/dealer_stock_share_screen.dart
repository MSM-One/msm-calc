import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../constants/app_colors.dart';
import '../services/data_repository.dart';
import '../utils/file_download_helper.dart' as download_helper;
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import '../widgets/m_loader.dart';

/// Lead Enterprise Flutter Implementation: Stock Sheet Module
/// Streamlined location-wise stock sheet sharing workflow:
/// 1. Location Segmented Selector ('YARD', 'FACTORY', 'ALL')
/// 2. Combined Search & Selection Header with active counter pill
/// 3. Clean 2-Column Accordion Cards (Category subtotals in bold black)
/// 4. Official Metaroll Letterhead Vector PDF Export (Portrait A4)
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

  // ── Group & sort rows by category ──
  final Map<String, List<Map<String, dynamic>>> grouped = {};
  for (final row in params.selectedRows) {
    final cat = row['category_name']?.toString() ?? 'General';
    grouped.putIfAbsent(cat, () => []).add(row);
  }
  final sortedCategories = grouped.keys.toList()
    ..sort(SortingUtils.compareCategories);

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

          // 1. Red Category Banner (Rendered ONLY ONCE at the start of the category)
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

          // 2. Dark Sub-Headers Row (Item Description / Size | Stock Quantity (MT))
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
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Stock Quantity (MT)',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );

          // 3. Item Data Rows
          for (int i = 0; i < catRows.length; i++) {
            final row = catRows[i];
            final catName = row['category_name']?.toString() ?? displayTitle;
            final desc = _formatItemDescriptionStatic(
              catName,
              row['size_label']?.toString() ?? '',
              row['unit_weight_kg'],
            );
            final stock = _safeDoubleStatic(row['current_stock_mt']);
            final rowBg = (startIndex + i).isOdd ? zebraStripe : PdfColors.white;

            tableRows.add(
              pw.TableRow(
                decoration: pw.BoxDecoration(color: rowBg),
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    child: pw.Text(
                      desc,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: mediumSlate,
                      ),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      '${stock.toStringAsFixed(3)} MT',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: metarollRed,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Table(
              border: pw.TableBorder.all(color: gridBorder, width: 0.25),
              columnWidths: {
                0: pw.FlexColumnWidth(col0Flex),
                1: pw.FlexColumnWidth(col1Flex),
              },
              children: tableRows,
            ),
          );
        }

        if (categoryCount == 1) {
          // ── CASE 1: STRICT SINGLE CATEGORY MODE (Option B: One Single Continuous Table) ──
          final cat = sortedCategories.first;
          final catRows = grouped[cat]!;

          content.add(
            pw.SizedBox(
              width: double.infinity,
              child: buildCategoryTable(
                catTitle: cat,
                catRows: catRows,
                startIndex: 0,
                col0Flex: 1.2, // 1.2 : 0.8 ratio brings quantity column 80% closer to item description text
                col1Flex: 0.8,
                showBanner: true,
              ),
            ),
          );
        } else {
          // ── CASE 2: MULTI-CATEGORY MODE (Option A: 2-Column Side-by-Side Split Grid) ──
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
              // Multi-category export with >14 items: chunk into sub-blocks for 2-column grid layout
              for (int chunkStart = 0; chunkStart < catRows.length; chunkStart += maxItemsPerBlock) {
                final chunkEnd = (chunkStart + maxItemsPerBlock < catRows.length)
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
    final loc = row['location']?.toString() ?? 'YARD';
    return '$cat|$size|$loc';
  }

  /// Helper for safe double conversion
  double _safeDouble(dynamic val) {
    return (val as num?)?.toDouble() ??
        double.tryParse(val?.toString() ?? '0') ??
        0.0;
  }

  /// Formats combined size string: Size Label + Unit Weight in kg
  String _formatCombinedSizeString(
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

  // ---------------------------------------------------------------------------
  // SELECTION HELPERS
  // ---------------------------------------------------------------------------
  bool _isItemSelected(Map<String, dynamic> row) {
    final key = _getItemKey(row);
    return _selectedItemKeys[key] ?? false;
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

  /// Returns selected stock rows formatted and sorted
  List<Map<String, dynamic>> _getSelectedStockRows() {
    final selected = _rawStockList.where((row) {
      return _isItemSelected(row);
    }).toList();

    selected.sort((a, b) {
      final catA = a['category_name']?.toString() ?? '';
      final catB = b['category_name']?.toString() ?? '';
      final catCmp = SortingUtils.compareCategories(catA, catB);
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
  // EXPORT PIPELINE: VECTOR PDF WITH OFFICIAL LETTERHEAD TEMPLATE
  // ---------------------------------------------------------------------------
  Future<void> _exportAndSharePDF() async {
    final selectedRows = _getSelectedStockRows();
    if (selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one stock item to share.'),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        iconTheme: const IconThemeData(color: kMetarollGray),
        title: const Text(
          'Stock Sheet',
          style: TextStyle(
            color: kMetarollGray,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kMetarollGray),
            tooltip: 'Refresh Stock Data',
            onPressed: _loadData,
          ),
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
                      color: kMetarollGray,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    // 1. LOCATION SEGMENTED CONTROL BAR
                    _buildLocationSegmentedControl(),

                    // 2. COMBINED SEARCH BAR & SELECTION HEADER WITH COUNTER PILL
                    _buildSearchAndSelectionHeader(
                        selectedRows.length, totalSelectedStockMT),

                    // 3. CLEAN CATEGORY ACCORDION CARDS WITH 2-COLUMN LIST
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        child: _buildAccordionCategoryList(),
                      ),
                    ),
                  ],
                ),

                // 4. STREAMLINED BOTTOM ACTION BAR ([Export PDF Document])
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomActionBar(),
                ),

                // Export Loading Overlay Dialog
                if (_isExporting)
                  Container(
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFE11D48)),
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
                                    color: kMetarollGray,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Formatting selected stock sheet',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1 WIDGET: LOCATION SEGMENTED CONTROL
  // ---------------------------------------------------------------------------
  Widget _buildLocationSegmentedControl() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildLocationSegmentTile(
                'YARD', 'Yard Stock', Icons.warehouse_rounded),
            const SizedBox(width: 4),
            _buildLocationSegmentTile(
                'FACTORY', 'Factory Stock', Icons.factory_rounded),
            const SizedBox(width: 4),
            _buildLocationSegmentTile(
                'ALL', 'All Locations', Icons.public_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSegmentTile(
      String code, String label, IconData iconData) {
    final bool isSelected = _activeLocation == code;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_activeLocation != code) {
              setState(() {
                _activeLocation = code;
              });
              _loadData();
            }
          },
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconData,
                  size: 15,
                  color: isSelected ? kMetarollRed : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? kMetarollRed : const Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2 WIDGET: SELECTION & SEARCH HEADER
  // ---------------------------------------------------------------------------
  Widget _buildSearchAndSelectionHeader(
      int selectedCount, double totalSelectedStock) {
    final bool isAllSelected = _rawStockList.isNotEmpty &&
        selectedCount == _rawStockList.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 13, color: kMetarollGray),
                decoration: InputDecoration(
                  hintText: 'Search category or size...',
                  hintStyle:
                      const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  prefixIcon:
                      const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.cancel_rounded, size: 16, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectAllGlobal(!isAllSelected),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isAllSelected
                      ? const Color(0xFFFEF2F2)
                      : kMetarollRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isAllSelected
                        ? const Color(0xFFFCA5A5)
                        : kMetarollRed.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAllSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 16,
                      color: kMetarollRed,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isAllSelected ? 'Deselect All' : 'Select All',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: kMetarollRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 3 WIDGET: CLEAN CATEGORY ACCORDION CARDS WITH 2-COLUMN LIST
  // ---------------------------------------------------------------------------
  Widget _buildAccordionCategoryList() {
    final groupedMap = _getGroupedStockMap();

    if (groupedMap.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Text(
          'No items found matching the selected location & search query.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    final sortedCategories = groupedMap.keys.toList()
      ..sort(SortingUtils.compareCategories);

    return Column(
      children: sortedCategories.map((cat) {
        final categoryRows = groupedMap[cat]!;
        final bool? catSelection =
            _getCategorySelectionState(cat, categoryRows);
        final bool isExpanded =
            _expandedCategories[cat] ?? _searchQuery.isNotEmpty;
        final double catStockMT = _calculateTotalStock(categoryRows);

        final int catSelectedCount =
            categoryRows.where((r) => _isItemSelected(r)).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: catSelection == true
                  ? kMetarollRed
                  : const Color(0xFFE2E8F0),
              width: catSelection == true ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedCategories[cat] = !isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: catSelection,
                        tristate: true,
                        activeColor: kMetarollRed,
                        onChanged: (val) =>
                            _toggleCategorySelection(categoryRows, val ?? false),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              cat,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: catSelectedCount > 0
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: catSelectedCount > 0
                                    ? Border.all(
                                        color: const Color(0xFFFCA5A5))
                                    : null,
                              ),
                              child: Text(
                                '$catSelectedCount / ${categoryRows.length}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: catSelectedCount > 0
                                      ? kMetarollRed
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${catStockMT.toStringAsFixed(3)} MT',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Container(
                  color: const Color(0xFFFAFAFA),
                  child: Column(
                    children: [
                      ...categoryRows.map((row) {
                        final bool isSelected = _isItemSelected(row);
                        final sizeLabel = row['size_label']?.toString() ?? '';
                        final stock = _safeDouble(row['current_stock_mt']);

                        return InkWell(
                          onTap: () =>
                              _toggleItemSelection(row, !isSelected),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            color: isSelected
                                ? const Color(0xFFFEF2F2).withValues(alpha: 0.6)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 32,
                                  child: Checkbox(
                                    value: isSelected,
                                    activeColor: kMetarollRed,
                                    onChanged: (val) =>
                                        _toggleItemSelection(row, val),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatCombinedSizeString(
                                        cat, sizeLabel, row['unit_weight_kg']),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? kMetarollGray
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${stock.toStringAsFixed(3)} MT',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: kMetarollRed,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal ($cat)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              '${catStockMT.toStringAsFixed(3)} MT',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 4 WIDGET: STREAMLINED BOTTOM ACTION BAR ([Export PDF Document])
  // ---------------------------------------------------------------------------
  Widget _buildBottomActionBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.9),
            Colors.white,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFEF1C24),
                Color(0xFFB80910),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF1C24).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportAndSharePDF,
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
            label: const Text(
              'Export PDF Document',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
