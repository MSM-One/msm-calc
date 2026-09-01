import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_permissions.dart';
import '../models/stock_models.dart';
import '../providers/inventory_provider.dart';
import '../services/access_guard.dart';
import '../services/data_repository.dart';
import '../utils/formatters.dart';
import '../utils/item_order_util.dart';
import '../utils/sorting_utils.dart';
import '../widgets/global_view_wrapper.dart';
import '../widgets/m_loader.dart';
import '../widgets/motion_toast.dart';

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
        });
      }
    } catch (e) {
      debugPrint("Error loading charges in SampleRateCalcScreen: $e");
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
    if (cat.contains('ROUND') || cat.contains('FLAT')) {
      return _roundFlatsBasicCtrl;
    }
    return _pipeBasicCtrl;
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
    String sourceRate = sourceCtrl.text.trim();
    if (sourceRate.isEmpty) {
      MotionToast.show(context, "Please enter a rate first", isError: true);
      return;
    }
    setState(() {
      _pipeBasicCtrl.text = sourceRate;
      _angleBasicCtrl.text = sourceRate;
      _channelBasicCtrl.text = sourceRate;
      _sqrBarBasicCtrl.text = sourceRate;
      _roundFlatsBasicCtrl.text = sourceRate;
    });
    MotionToast.show(context, "Rate ₹$sourceRate applied to all base categories!");
  }

  /// Checks if a category should be excluded from the Sample Rate Calculator.
  /// Explicitly filters out 'Binding Wire', 'Nails', 'HR Pipe', and 'MS Structure' / 'MS Structure ISMC'.
  static bool isExcludedCategory(String cat) {
    final upper = cat.toUpperCase().trim();
    return upper == 'BINDING WIRE' ||
        upper == 'NAILS' ||
        upper == 'HR PIPE' ||
        upper == 'MS STRUCTURE' ||
        upper == 'MS STRUCTURE ISMC' ||
        upper == 'MS STRUCTURE (ISMC)' ||
        upper.startsWith('MS STRUCTURE') ||
        upper == 'STRUCTURE ISMC';
  }

  String _generateRateMessage() {
    StringBuffer sb = StringBuffer();
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    sb.writeln("Date: $formattedDate");
    sb.writeln("----------------------------");

    int categoryIndex = 1;
    bool hasAnySelected = false;

    final sortedCategoryKeys = _categories.keys
        .where((cat) => !isExcludedCategory(cat))
        .toList()
      ..sort(ItemOrderUtil.compare);

    for (final category in sortedCategoryKeys) {
      final sizes = _categories[category] ?? [];
      TextEditingController ctrl = _getControllerForCategory(category);
      double catBasic = double.tryParse(ctrl.text) ?? 0;
      if (catBasic > 0) {
        hasAnySelected = true;
        String headerRate = "@${formatIndianCurrency(catBasic.round())}";
        sb.writeln(
            "\n*${categoryIndex++}. ${category.toUpperCase()}* ($headerRate)");
        final sortedSizes = [...sizes]..sort(compareSampleRateSizes);
        for (var size in sortedSizes) {
          if (size.isMissing) continue;
          double finalRate = _calculateFinalRate(category, size.sd);
          final double w = size.weight.toDouble();
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
    }

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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bolt_rounded,
                            color: Color(0xFFD32F2F), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Sample Rates Preview",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: SelectableText(
                    message,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      height: 1.45,
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
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text("Copy Text"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                        ),
                        foregroundColor:
                            isDark ? Colors.white : const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text("Share to WhatsApp"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 1025;

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            "Sample Rate Calc",
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.2,
            ),
          ),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          iconTheme: IconThemeData(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: "Refresh Master Data",
              onPressed: () {
                context.read<InventoryProvider>().fetchSampleRateData(force: true);
                _loadCharges();
                MotionToast.show(context, "Refreshing sample rates...");
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: "Preview & Share",
              onPressed: _showRatePreview,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Consumer<InventoryProvider>(
          builder: (context, inv, _) {
            if (inv.isLoadingSampleRates && inv.sampleRateCategories.isEmpty) {
              return const Center(child: MLoader(size: 60));
            }

            _categories = inv.sampleRateCategories;

            if (inv.sampleRateCategories.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 48, color: Color(0xFF94A3B8)),
                    const SizedBox(height: 12),
                    const Text(
                      "No items found in Master Catalog.",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => inv.fetchSampleRateData(force: true),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text("Retry Loading"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            }

            final sortedCategories = inv.sampleRateCategories.keys
                .where((cat) => !isExcludedCategory(cat))
                .toList()
              ..sort(ItemOrderUtil.compare);

            if ((_selectedCategory == null ||
                    !sortedCategories.contains(_selectedCategory)) &&
                sortedCategories.isNotEmpty) {
              _selectedCategory = sortedCategories.first;
            } else if (sortedCategories.isEmpty) {
              _selectedCategory = null;
            }

            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── LEFT SIDEBAR: BASE RATES CONFIG ──
                  Container(
                    width: 320,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      border: Border(
                        right: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD32F2F)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.tune_rounded,
                                    color: Color(0xFFD32F2F), size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Base Rates Config",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      "Set base rates for live calculation",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 5 Base Rate Inputs
                          _PanelInput(
                            label: "Pipe Basic",
                            controller: _pipeBasicCtrl,
                            isDark: isDark,
                            onApplyAll: () => _applyToAll('MS Pipe'),
                          ),
                          const SizedBox(height: 10),
                          _PanelInput(
                            label: "Angle Basic",
                            controller: _angleBasicCtrl,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _PanelInput(
                            label: "Channel Basic",
                            controller: _channelBasicCtrl,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _PanelInput(
                            label: "SQR Bar Basic",
                            controller: _sqrBarBasicCtrl,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _PanelInput(
                            label: "Round/Flats Basic",
                            controller: _roundFlatsBasicCtrl,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 16),

                          // Quick Broadcast Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _applyToAll('MS Pipe'),
                              icon: const Icon(Icons.copy_all_rounded, size: 15),
                              label: const Text(
                                "Apply Pipe Rate to All",
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1),
                                ),
                                foregroundColor: isDark
                                    ? Colors.white70
                                    : const Color(0xFF475569),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Divider(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                          const SizedBox(height: 10),

                          // NC Discount Toggle Card
                          _buildNcDiscountToggle(isDark),

                          const SizedBox(height: 14),

                          // Calculation Meta Strip
                          _buildChargesMetaCard(isDark),
                        ],
                      ),
                    ),
                  ),

                  // ── RIGHT MAIN PANEL: CANONICAL TABS & PRICING TABLE ──
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Canonical Category Tabs
                              _buildCategoryChips(sortedCategories, isDark),
                              const SizedBox(height: 18),

                              // Table Section
                              if (_selectedCategory != null &&
                                  _categories.containsKey(_selectedCategory))
                                _buildCategorySection(
                                  _selectedCategory!,
                                  _categories[_selectedCategory!]!,
                                  isDark,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // ── MOBILE / NARROW LAYOUT ──
            return SingleChildScrollView(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collapsible Rate Config Card
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(14.0),
                    child: Material(
                      color: Colors.transparent,
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          tilePadding: EdgeInsets.zero,
                          iconColor: const Color(0xFFD32F2F),
                          collapsedIconColor: const Color(0xFF64748B),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD32F2F)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.tune_rounded,
                                    color: Color(0xFFD32F2F), size: 16),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Base Rates Config",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          children: [
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _PanelInput(
                                    label: "Pipe",
                                    controller: _pipeBasicCtrl,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PanelInput(
                                    label: "Angle",
                                    controller: _angleBasicCtrl,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _PanelInput(
                                    label: "Channel",
                                    controller: _channelBasicCtrl,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PanelInput(
                                    label: "SQR Bar",
                                    controller: _sqrBarBasicCtrl,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _PanelInput(
                              label: "Round/Flats",
                              controller: _roundFlatsBasicCtrl,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _applyToAll('MS Pipe'),
                                icon: const Icon(Icons.copy_all_rounded, size: 14),
                                label: const Text(
                                  "Apply Pipe Rate to All",
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  side: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                  foregroundColor: isDark
                                      ? Colors.white70
                                      : const Color(0xFF475569),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Divider(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            _buildNcDiscountToggle(isDark),
                            const SizedBox(height: 8),
                            _buildChargesMetaCard(isDark),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Canonical Category Chips
                  _buildCategoryChips(sortedCategories, isDark),
                  const SizedBox(height: 14),

                  // Responsive Pricing Table
                  if (_selectedCategory != null &&
                      _categories.containsKey(_selectedCategory))
                    _buildCategorySection(
                      _selectedCategory!,
                      _categories[_selectedCategory!]!,
                      isDark,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── CANONICAL CATEGORY PILL TABS ──
  Widget _buildCategoryChips(List<String> sortedCategories, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: sortedCategories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() => _selectedCategory = cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFD32F2F)
                      : (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFD32F2F)
                        : (isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0)),
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFD32F2F).withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  cat.toUpperCase(),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 11.5,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569)),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── NC DISCOUNT TOGGLE CARD ──
  Widget _buildNcDiscountToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "NC Discount (-₹${_ncDiscount.toStringAsFixed(0)})",
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_ncDiscountEnabled) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "ACTIVE",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Deduct ₹${_ncDiscount.toStringAsFixed(0)} before GST",
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch.adaptive(
              value: _ncDiscountEnabled,
              activeTrackColor: const Color(0xFFD32F2F),
              onChanged: (val) => setState(() => _ncDiscountEnabled = val),
            ),
          ),
        ],
      ),
    );
  }

  // ── CHARGES META CARD ──
  Widget _buildChargesMetaCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.5)
            : const Color(0xFFF1F5F9).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                "GST Rate: ${(_gstRate * 100).toStringAsFixed(1)}%",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                "Loading: ₹${_lcRate.toStringAsFixed(0)}/MT",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Formula: (Base + SD + LC${_ncDiscountEnabled ? ' - NC' : ''}) × ${(1 + _gstRate).toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // ── CATEGORY SECTION & HIGH-DENSITY PRICING TABLE ──
  Widget _buildCategorySection(
      String title, List<SampleRateSize> sizes, bool isDark) {
    final sortedSizes = [...sizes]..sort(compareSampleRateSizes);

    final ctrl = _getControllerForCategory(title);
    final double basic = double.tryParse(ctrl.text) ?? 0.0;
    final bool hasBasic = basic > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${sortedSizes.length} sizes",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasBasic
                      ? const Color(0xFFECFDF5)
                      : (isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasBasic
                        ? const Color(0xFFA7F3D0)
                        : (isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Text(
                  hasBasic
                      ? "Base: ₹${formatIndianCurrency(basic.round())}/MT"
                      : "Base Rate Not Set",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasBasic
                        ? const Color(0xFF059669)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pricing Table
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border(
              left: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              right: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(3),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.6)
                      : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  width: 0.5,
                ),
              ),
              children: [
                // Table Header Row
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                  ),
                  children: const [
                    _TableHeaderCell(
                      "SIZE DIMENSION",
                      alignment: Alignment.centerLeft,
                    ),
                    _TableHeaderCell(
                      "SD VALUE",
                      alignment: Alignment.centerRight,
                    ),
                    _TableHeaderCell(
                      "NET COMPUTED RATE",
                      alignment: Alignment.centerRight,
                    ),
                  ],
                ),

                // Table Data Rows
                ...sortedSizes.asMap().entries.map((entry) {
                  final int index = entry.key;
                  final SampleRateSize size = entry.value;
                  final bool isEven = index % 2 == 0;

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

                  final Color rowBg = isEven
                      ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                      : (isDark
                          ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                          : const Color(0xFFF8FAFC));

                  if (size.isMissing) {
                    return TableRow(
                      decoration: BoxDecoration(color: rowBg),
                      children: [
                        _TableCell(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            dispLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const _TableCell(
                          alignment: Alignment.centerRight,
                          child: Text("—",
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8))),
                        ),
                        const _TableCell(
                          alignment: Alignment.centerRight,
                          child: Text("—",
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8))),
                        ),
                      ],
                    );
                  }

                  double finalRate = _calculateFinalRate(title, size.sd);
                  final hasCalculated = finalRate > 0;

                  return TableRow(
                    decoration: BoxDecoration(color: rowBg),
                    children: [
                      // Col 1: Size & Weight
                      _TableCell(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dispLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Col 2: SD Value Badge
                      _TableCell(
                        alignment: Alignment.centerRight,
                        child: size.sd != 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: size.sd > 0
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: size.sd > 0
                                        ? const Color(0xFFA7F3D0)
                                        : const Color(0xFFFDE68A),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  size.sd > 0
                                      ? "+₹${size.sd.toStringAsFixed(0)}"
                                      : "-₹${size.sd.abs().toStringAsFixed(0)}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: size.sd > 0
                                        ? const Color(0xFF059669)
                                        : const Color(0xFFD97706),
                                  ),
                                ),
                              )
                            : const Text(
                                "Base",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                      ),

                      // Col 3: Net Computed Rate
                      _TableCell(
                        alignment: Alignment.centerRight,
                        child: hasCalculated
                            ? Text(
                                "₹ ${formatIndianCurrency(finalRate.round())}/MT",
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF059669),
                                ),
                              )
                            : const Text(
                                "—",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
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

  int compareSampleRateSizes(dynamic a, dynamic b) {
    String aLabel = '';
    if (a is SampleRateSize) {
      aLabel = a.label;
    } else if (a is Map) {
      aLabel = (a['label'] ?? a['size'] ?? '').toString();
    } else {
      aLabel = a.toString();
    }

    String bLabel = '';
    if (b is SampleRateSize) {
      bLabel = b.label;
    } else if (b is Map) {
      bLabel = (b['label'] ?? b['size'] ?? '').toString();
    } else {
      bLabel = b.toString();
    }

    return SortingUtils.compareSizes(aLabel, bLabel);
  }
}

// ── COMPACT ENTERPRISE PANEL INPUT ──
class _PanelInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isDark;
  final VoidCallback? onApplyAll;

  const _PanelInput({
    required this.label,
    required this.controller,
    this.isDark = false,
    this.onApplyAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF374151),
              ),
            ),
            if (onApplyAll != null)
              InkWell(
                onTap: onApplyAll,
                child: const Text(
                  "Apply to All",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD32F2F),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: isDark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF8FAFC),
            prefixText: "₹ ",
            prefixStyle: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── TABLE HEADER CELL ──
class _TableHeaderCell extends StatelessWidget {
  final String title;
  final Alignment alignment;

  const _TableHeaderCell(this.title, {this.alignment = Alignment.centerLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
          color: Color(0xFF64748B),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── TABLE DATA CELL ──
class _TableCell extends StatelessWidget {
  final Widget child;
  final Alignment alignment;

  const _TableCell({required this.child, this.alignment = Alignment.centerLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    );
  }
}
