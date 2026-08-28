import 'package:flutter/material.dart';
import '../widgets/motion_toast.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/global_view_wrapper.dart';

import 'package:provider/provider.dart';
import '../models/stock_models.dart';
import '../providers/inventory_provider.dart';
import '../widgets/m_loader.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../utils/sorting_utils.dart';
import '../services/data_repository.dart';

class SampleRateCalcScreen extends StatefulWidget {
  const SampleRateCalcScreen({super.key});

  @override
  State<SampleRateCalcScreen> createState() => _SampleRateCalcScreenState();
}

class _SampleRateCalcScreenState extends State<SampleRateCalcScreen> {
  bool _ncDiscountEnabled = false;
  String? _selectedCategory;

  double _gstRate = 0.18;
  double _lcRate = 255.0;
  double _ncDiscount = 3000.0;
  bool _isLoadingCharges = true;

  // Controllers for Master Rate Panel
  final TextEditingController _pipeBasicCtrl = TextEditingController();
  final TextEditingController _angleBasicCtrl = TextEditingController();
  final TextEditingController _channelBasicCtrl = TextEditingController();
  final TextEditingController _sqrBarBasicCtrl = TextEditingController();
  final TextEditingController _roundFlatsBasicCtrl = TextEditingController();

  Map<String, List<SampleRateSize>> _categories = {};

  @override
  void initState() {
    super.initState();
    _loadCharges();

    // --- Hard Navigation Guard ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AccessGuard.cannot(AppPermissions.screensSampleRate)) {
        MotionToast.show(context, "Access Denied: Missing Permission",
            isError: true);
        if (mounted) Navigator.pop(context);
      } else {
        final inv = context.read<InventoryProvider>();
        if (inv.sampleRateCategories.isEmpty) {
          inv.fetchSampleRateData();
        }
      }
    });

    _pipeBasicCtrl.addListener(_onRateChanged);
    _angleBasicCtrl.addListener(_onRateChanged);
    _channelBasicCtrl.addListener(_onRateChanged);
    _sqrBarBasicCtrl.addListener(_onRateChanged);
    _roundFlatsBasicCtrl.addListener(_onRateChanged);
  }

  Future<void> _loadCharges() async {
    try {
      final data = await DataRepository.getSheetDataAsync(null);
      final meta = data['meta'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          _gstRate =
              double.tryParse(meta['gst_rate']?.toString() ?? '0.18') ?? 0.18;
          _lcRate =
              double.tryParse(meta['loading_charge']?.toString() ?? '255') ??
                  255.0;
          _ncDiscount =
              double.tryParse(meta['nc_discount']?.toString() ?? '3000') ??
                  3000.0;
          _isLoadingCharges = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading charges in SampleRateCalcScreen: $e");
      if (mounted) {
        setState(() {
          _isLoadingCharges = false;
        });
      }
    }
  }

  void _onRateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pipeBasicCtrl.dispose();
    _angleBasicCtrl.dispose();
    _channelBasicCtrl.dispose();
    _sqrBarBasicCtrl.dispose();
    _roundFlatsBasicCtrl.dispose();
    super.dispose();
  }

  TextEditingController _getControllerForCategory(String category) {
    String cat = category.toUpperCase().trim();
    if (cat.contains('PIPE')) return _pipeBasicCtrl;
    if (cat.contains('ANGLE')) return _angleBasicCtrl;
    if (cat.contains('CHANNEL')) return _channelBasicCtrl;
    if (cat.contains('SQR') || cat.contains('SQUARE')) return _sqrBarBasicCtrl;
    if (cat.contains('ROUND') || cat.contains('FLAT'))
      return _roundFlatsBasicCtrl;
    return _pipeBasicCtrl; // default
  }

  double _calculateFinalRate(String category, num sd) {
    final String selectedCategory = category.toUpperCase().trim();
    double basic = 0.0;

    if (selectedCategory == 'MS CHANNEL') {
      basic = double.tryParse(_channelBasicCtrl.text) ?? 0.0;
    } else {
      TextEditingController ctrl = _getControllerForCategory(category);
      String rateText = ctrl.text;
      basic = double.tryParse(rateText) ?? 0.0;
    }

    if (basic == 0.0) return 0.0;

    double loading = _lcRate;

    double subtotal = (basic + sd + loading).toDouble();
    if (_ncDiscountEnabled) {
      subtotal -= _ncDiscount;
    }
    return subtotal * (1 + _gstRate);
  }

  void _applyToAll(String sourceCategory) {
    TextEditingController sourceCtrl =
        _getControllerForCategory(sourceCategory);
    String sourceRate = sourceCtrl.text;
    setState(() {
      _pipeBasicCtrl.text = sourceRate;
      _angleBasicCtrl.text = sourceRate;
      _channelBasicCtrl.text = sourceRate;
      _sqrBarBasicCtrl.text = sourceRate;
      _roundFlatsBasicCtrl.text = sourceRate;
    });
    MotionToast.show(context, "Rate $sourceRate applied to all categories!");
  }

  String _generateRateMessage() {
    StringBuffer sb = StringBuffer();
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    sb.writeln("Date: $formattedDate");
    sb.writeln("----------------------------");

    int categoryIndex = 1;
    bool hasAnySelected = false;

    _categories.forEach((category, sizes) {
      TextEditingController ctrl = _getControllerForCategory(category);
      double catBasic = double.tryParse(ctrl.text) ?? 0;
      if (catBasic > 0) {
        hasAnySelected = true;
        String headerRate = "@${formatIndianCurrency(catBasic.round())}";
        sb.writeln(
            "\n*${categoryIndex++}. ${category.toUpperCase()}* ($headerRate)");
        final sortedSizes = [...sizes]..sort(compareSampleRateSizes);
        for (var size in sortedSizes) {
          if (size.isMissing) continue; // Skip missing sizes in shared text
          double finalRate = _calculateFinalRate(category, size.sd);
          final double w = size.weight != null
              ? double.tryParse(size.weight.toString()) ?? 0.0
              : 0.0;
          final formattedWeight =
              w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
          String weightSuffix = w != 0 ? " ${formattedWeight}kg" : "";
          String dispLabel = category.trim() == 'MS Angle'
              ? formatSizeLabel(size.label, category, w)
              : "${size.label}$weightSuffix";
          sb.writeln(
              "▪ $dispLabel = ${formatIndianCurrency(finalRate.round())} /-");
        }
      }
    });

    if (!hasAnySelected) return "";

    sb.writeln("\n───────────────────────");
    sb.writeln("*Terms & Conditions*");
    sb.writeln("• Payment Advance");
    sb.writeln("• Loading Charge - (Inclusive)");
    sb.writeln("• Transport (Extra)");
    if (!_ncDiscountEnabled) {
      sb.writeln(
          "• GST - ${(_gstRate * 100).toStringAsFixed(2)} % (Inclusive)");
    }
    sb.writeln("• Weight Tolerance - +/-5kg per MT");

    return sb.toString();
  }

  void _showRatePreview() {
    String message = _generateRateMessage();
    if (message.isEmpty) {
      MotionToast.show(context, "Enter at least one basic rate to preview.",
          isError: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Rate Preview",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textDark)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SelectableText(
                    message,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 10, 20, 10 + MediaQuery.of(context).padding.bottom),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: message));
                        MotionToast.show(context, "Copied to Clipboard");
                      },
                      icon: const Icon(Icons.copy, size: 20),
                      label: const Text("Copy"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: msmRed),
                        foregroundColor: msmRed,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Share.share(message);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text("Share to WhatsApp"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: msmRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 1025;

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: msmBg,
        appBar: AppBar(
          title: const Text(
            "Sample Rate Calc",
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: msmRed,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.white),
              tooltip: "Preview & Share",
              onPressed: _showRatePreview,
            ),
          ],
        ),
        body: Consumer<InventoryProvider>(
          builder: (context, inv, _) {
            if (inv.isLoadingSampleRates && inv.sampleRateCategories.isEmpty) {
              return const Center(child: MLoader(size: 60));
            }

            _categories = inv.sampleRateCategories;

            if (inv.sampleRateCategories.isEmpty) {
              return const Center(
                  child: Text("No items found in Google Sheet."));
            }

            if (_selectedCategory == null &&
                inv.sampleRateCategories.isNotEmpty) {
              _selectedCategory = inv.sampleRateCategories.keys.first;
            }

            // Desktop layout: Side-by-side
            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left panel: Rates & Settings
                  Container(
                    width: 320,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          right: BorderSide(color: borderLight, width: 1)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.tune_rounded, color: msmRed, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "Pricing Settings",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: textDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _PanelInput(
                              label: "Pipe Basic", controller: _pipeBasicCtrl),
                          const SizedBox(height: 14),
                          _PanelInput(
                              label: "Angle Basic",
                              controller: _angleBasicCtrl),
                          const SizedBox(height: 14),
                          _PanelInput(
                              label: "Channel Basic",
                              controller: _channelBasicCtrl),
                          const SizedBox(height: 14),
                          _PanelInput(
                              label: "SQR Bar Basic",
                              controller: _sqrBarBasicCtrl),
                          const SizedBox(height: 14),
                          _PanelInput(
                              label: "Round/Flats Basic",
                              controller: _roundFlatsBasicCtrl),
                          const SizedBox(height: 24),
                          const Divider(color: borderLight),
                          const SizedBox(height: 12),
                          _buildNcDiscountToggle(),
                        ],
                      ),
                    ),
                  ),

                  // Right panel: Category switcher & Table
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCategoryChips(inv),
                              const SizedBox(height: 20),
                              if (_selectedCategory != null &&
                                  _categories.containsKey(_selectedCategory))
                                _buildCategorySection(_selectedCategory!,
                                    _categories[_selectedCategory!]!),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // Mobile layout: Pinned vertical scroll
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basic Rates card
                  Card(
                    color: Colors.white,
                    elevation: 2,
                    shadowColor: kPremiumShadow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: borderLight),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        tilePadding: EdgeInsets.zero,
                        iconColor: msmRed,
                        title: const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: msmRed, size: 20),
                            SizedBox(width: 8),
                            Text(
                              "Rates & Settings",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: textDark),
                            ),
                          ],
                        ),
                        children: [
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _PanelInput(
                                      label: "Pipe",
                                      controller: _pipeBasicCtrl)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _PanelInput(
                                      label: "Angle",
                                      controller: _angleBasicCtrl)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _PanelInput(
                                      label: "Channel",
                                      controller: _channelBasicCtrl)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _PanelInput(
                                      label: "SQR Bar",
                                      controller: _sqrBarBasicCtrl)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _PanelInput(
                              label: "Round/Flats",
                              controller: _roundFlatsBasicCtrl),
                          const SizedBox(height: 16),
                          const Divider(color: borderLight),
                          _buildNcDiscountToggle(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Category chips & Table
                  _buildCategoryChips(inv),
                  const SizedBox(height: 16),
                  if (_selectedCategory != null &&
                      _categories.containsKey(_selectedCategory))
                    _buildCategorySection(
                        _selectedCategory!, _categories[_selectedCategory!]!),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryChips(InventoryProvider inv) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: inv.sampleRateCategories.keys.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: isSelected ? msmRed : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : borderLight,
                    width: 1,
                  ),
                ),
                child: Text(
                  cat.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSelected ? Colors.white : textDark,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNcDiscountToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "NC Discount",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              Text(
                "Apply extra discount to total",
                style: TextStyle(
                    fontSize: 11, color: textGrey, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Switch.adaptive(
            value: _ncDiscountEnabled,
            activeColor: msmRed,
            onChanged: (val) => setState(() => _ncDiscountEnabled = val),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String title, List<SampleRateSize> sizes) {
    final sortedSizes = [...sizes]..sort(compareSampleRateSizes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.white,
          elevation: 2,
          shadowColor: kPremiumShadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: borderLight),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(3),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                    color: borderLight.withValues(alpha: 0.5), width: 1),
              ),
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFFFDFDFD)),
                  children: [
                    _TableCell(Text("Size Label",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: textDark))),
                    _TableCell(Text("SD Value",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: textDark))),
                    _TableCell(Text("Final Net Rate",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: textDark))),
                  ],
                ),
                ...sortedSizes.map((size) {
                  String weightText = '';
                  final double? wVal = double.tryParse(size.weight.toString());
                  final String lowerLabel = size.label.toLowerCase();
                  final String lowerTitle = title.toLowerCase();

                  final bool isExcluded = lowerTitle.contains('sqr bar') ||
                      lowerTitle.contains('square bar') ||
                      lowerTitle.contains('round bar') ||
                      lowerTitle.contains('flats') ||
                      lowerTitle.contains('flat') ||
                      lowerTitle.contains('gate channel') ||
                      lowerTitle.contains('binding wire') ||
                      lowerTitle.contains('barbed wire') ||
                      lowerLabel.contains('18g') ||
                      lowerLabel.contains('random');

                  if (wVal != null && wVal != 0 && !isExcluded) {
                    final formattedWeight = wVal % 1 == 0
                        ? wVal.toInt().toString()
                        : wVal.toStringAsFixed(1);
                    weightText = " ${formattedWeight}kg";
                  }

                  String dispLabel = (title.trim() == 'MS Angle')
                      ? formatSizeLabel(size.label, title, wVal ?? 0.0)
                      : "${size.label}$weightText";

                  // If missing, show dash for values
                  if (size.isMissing) {
                    return TableRow(
                      children: [
                        _TableCell(Text(dispLabel,
                            style: const TextStyle(
                                fontSize: 13,
                                color: textGrey,
                                fontStyle: FontStyle.italic))),
                        _TableCell(const Text("-",
                            style: TextStyle(fontSize: 12, color: textGrey))),
                        _TableCell(const Text("-",
                            style: TextStyle(fontSize: 14, color: textGrey))),
                      ],
                    );
                  }

                  double finalRate = _calculateFinalRate(title, size.sd);
                  final hasCalculated = finalRate > 0;

                  return TableRow(
                    children: [
                      _TableCell(Text(dispLabel,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: textDark))),
                      _TableCell(
                        hasCalculated
                            ? Text("+${size.sd.toStringAsFixed(0)}",
                                style: const TextStyle(
                                    fontSize: 12, color: textGrey))
                            : const Text("-",
                                style:
                                    TextStyle(fontSize: 12, color: textGrey)),
                      ),
                      _TableCell(
                        hasCalculated
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: msmRed.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: msmRed.withValues(alpha: 0.15),
                                      width: 0.5),
                                ),
                                child: Text(
                                  "₹ ${formatIndianCurrency(finalRate.round())}",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: msmRed,
                                  ),
                                ),
                              )
                            : const Text("-",
                                style:
                                    TextStyle(fontSize: 14, color: textGrey)),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // --- Sorting Helpers ---
  double extractThickness(String sizeLabel) {
    final match = RegExp(r'\((\d+(?:\.\d+)?)\)').firstMatch(sizeLabel);
    if (match == null) return double.infinity;
    return double.tryParse(match.group(1)!) ?? double.infinity;
  }

  double extractMainSize(String sizeLabel) {
    final label = sizeLabel.toUpperCase();

    final odMatch = RegExp(r'(\d+(?:\.\d+)?)\s*OD').firstMatch(label);
    if (odMatch != null) {
      return double.tryParse(odMatch.group(1)!) ?? double.infinity;
    }

    final xMatch =
        RegExp(r'(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)').firstMatch(label);
    if (xMatch != null) {
      return double.tryParse(xMatch.group(1)!) ?? double.infinity;
    }

    final inchMatch = RegExp(r'(\d+(?:\.\d+)?)\s*"').firstMatch(label);
    if (inchMatch != null) {
      return double.tryParse(inchMatch.group(1)!) ?? double.infinity;
    }

    final numberMatch = RegExp(r'\d+(?:\.\d+)?').firstMatch(label);
    if (numberMatch != null) {
      return double.tryParse(numberMatch.group(0)!) ?? double.infinity;
    }

    return double.infinity;
  }

  int compareSampleRateSizes(dynamic a, dynamic b) {
    String aLabel = '';
    if (a is SampleRateSize)
      aLabel = a.label;
    else if (a is Map)
      aLabel = (a['label'] ?? a['size'] ?? '').toString();
    else
      aLabel = a.toString();

    String bLabel = '';
    if (b is SampleRateSize)
      bLabel = b.label;
    else if (b is Map)
      bLabel = (b['label'] ?? b['size'] ?? '').toString();
    else
      bLabel = b.toString();

    return SortingUtils.compareSizes(aLabel, bLabel);
  }
}

class _PanelInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _PanelInput({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textGrey,
              letterSpacing: 0.3,
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8F9FB),
              prefixIcon:
                  const Icon(Icons.currency_rupee, size: 14, color: msmRed),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: msmRed, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final Widget child;
  const _TableCell(this.child);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: child,
    );
  }
}
