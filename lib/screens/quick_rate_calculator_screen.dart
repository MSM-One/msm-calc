import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_permissions.dart';
import '../models/stock_models.dart';
import '../providers/inventory_provider.dart';
import '../services/access_guard.dart';
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
  String? _selectedCategory;

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
    return (basic + sd).toDouble();
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

  /// Allowed canonical categories whitelist (strictly 6 structural categories)
  static const List<String> allowedCategories = [
    'MS PIPE',
    'MS ANGLE',
    'MS CHANNEL',
    'SQR BAR',
    'ROUND BAR',
    'FLATS',
  ];

  /// Checks if a category is part of the 6 allowed structural categories whitelist.
  static bool isAllowedCategory(String cat) {
    final upper = cat.toUpperCase().trim();
    if (upper.contains('HR PIPE') ||
        upper.contains('CR PIPE') ||
        upper.contains('ISMB') ||
        upper.contains('ISMC') ||
        upper.contains('STRUCTURE') ||
        upper.contains('BEAM') ||
        upper.contains('BARBED') ||
        upper.contains('GATE') ||
        upper.contains('BINDING') ||
        upper.contains('NAIL') ||
        upper.contains('ERW')) {
      return false;
    }
    return allowedCategories.any((allowed) =>
        upper == allowed ||
        (allowed == 'MS PIPE' && upper.contains('PIPE')) ||
        (allowed == 'MS ANGLE' && upper.contains('ANGLE')) ||
        (allowed == 'MS CHANNEL' && upper.contains('CHANNEL')) ||
        (allowed == 'SQR BAR' &&
            (upper.contains('SQR') || upper.contains('SQUARE'))) ||
        (allowed == 'ROUND BAR' && upper.contains('ROUND')) ||
        (allowed == 'FLATS' &&
            (upper.contains('FLAT') || upper.contains('FLATS'))));
  }

  /// Checks if a category should be excluded from the Sample Rate Calculator.
  static bool isExcludedCategory(String cat) => !isAllowedCategory(cat);

  String _generateRateMessage({String? specificCategory}) {
    StringBuffer sb = StringBuffer();
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    sb.writeln("Date: $formattedDate");
    sb.writeln("----------------------------");

    int categoryIndex = 1;
    bool hasAnySelected = false;

    final sortedCategoryKeys = _categories.keys
        .where((cat) => !isExcludedCategory(cat))
        .where((cat) {
          if (specificCategory != null &&
              specificCategory.isNotEmpty &&
              specificCategory != 'ALL') {
            return cat.toUpperCase().trim() ==
                specificCategory.toUpperCase().trim();
          }
          return true;
        })
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
    sb.writeln("• Transport (Extra)");
    sb.writeln("• Weight Tolerance - +/-5kg per MT");

    return sb.toString();
  }

  void _shareSampleRates({String? initialCategory}) {
    _showRatePreview(initialCategory: initialCategory);
  }

  Future<void> _launchWhatsApp(String text) async {
    final encoded = Uri.encodeComponent(text);
    final whatsappUrl = Uri.parse("whatsapp://send?text=$encoded");
    final webUrl = Uri.parse("https://api.whatsapp.com/send?text=$encoded");

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) safeShare(context, text, subject: "MSM Steel Rates");
      }
    } catch (e) {
      debugPrint("Error launching WhatsApp: $e");
      if (mounted) safeShare(context, text, subject: "MSM Steel Rates");
    }
  }

  void _showRatePreview({String? initialCategory}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final availableCategories = _categories.keys
        .where((cat) => !isExcludedCategory(cat))
        .toList()
      ..sort(ItemOrderUtil.compare);

    String currentFilter = (initialCategory != null &&
            availableCategories.any((c) =>
                c.toUpperCase().trim() == initialCategory.toUpperCase().trim()))
        ? initialCategory
        : 'ALL';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          String message = _generateRateMessage(
            specificCategory: currentFilter == 'ALL' ? null : currentFilter,
          );

          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                // Modal Drag Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Modal Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.share_rounded,
                                color: Color(0xFFD32F2F), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Share Rates Preview",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                "Formatted for WhatsApp & SMS quotation",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
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

                // Category Filter Pills
                Container(
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: const Text("All Active Categories"),
                          selected: currentFilter == 'ALL',
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: currentFilter == 'ALL'
                                ? Colors.white
                                : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          ),
                          selectedColor: const Color(0xFFD32F2F),
                          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => currentFilter = 'ALL');
                            }
                          },
                        ),
                      ),
                      ...availableCategories.map((cat) {
                        final isSelected = currentFilter == cat;
                        final ctrl = _getControllerForCategory(cat);
                        final hasRate = (double.tryParse(ctrl.text) ?? 0) > 0;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(cat.toUpperCase()),
                                if (hasRate) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            selected: isSelected,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : const Color(0xFF475569)),
                            ),
                            selectedColor: const Color(0xFFD32F2F),
                            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() => currentFilter = cat);
                              }
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                Divider(
                  height: 1,
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),

                // Preview Content Area
                Expanded(
                  child: message.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.info_outline_rounded,
                                    size: 40, color: Color(0xFF94A3B8)),
                                const SizedBox(height: 12),
                                Text(
                                  currentFilter == 'ALL'
                                      ? "No basic rates configured yet.\nPlease enter at least one basic rate in Base Rates Config."
                                      : "No basic rate set for $currentFilter.\nPlease enter a rate in the Base Rates Config panel.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
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

                // Bottom Action Buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
                  child: Row(
                    children: [
                      // Copy Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: message.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(text: message));
                                  MotionToast.show(context, "Rate sheet copied to clipboard!");
                                },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text(
                            "Copy Text",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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
                      const SizedBox(width: 8),

                      // System Share
                      IconButton.filledTonal(
                        onPressed: message.isEmpty
                            ? null
                            : () {
                                safeShare(context, message,
                                    subject: "MSM Steel Rates");
                              },
                        tooltip: "System Share",
                        icon: const Icon(Icons.share_outlined, size: 18),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // WhatsApp Button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: message.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _launchWhatsApp(message);
                                },
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: const Text(
                            "Share to WhatsApp",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
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
          );
        },
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
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: isDark ? Colors.white : const Color(0xFF0F172A), size: 22),
            tooltip: 'Back to Dashboard',
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacementNamed('/home');
              }
            },
          ),
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
                MotionToast.show(context, "Refreshing sample rates...");
              },
            ),
            if (isDesktop)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: ElevatedButton.icon(
                  onPressed: _shareSampleRates,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text(
                    "Share Rates",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              )
            else
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.share_rounded,
                      size: 18, color: Color(0xFFD32F2F)),
                ),
                tooltip: 'Share Sample Rates',
                onPressed: _shareSampleRates,
              ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: isDesktop
            ? null
            : FloatingActionButton.extended(
                onPressed: _shareSampleRates,
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                elevation: 4,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text(
                  "Share Rates",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
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
                          const SizedBox(height: 14),

                          // Desktop Primary Share Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _shareSampleRates,
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: const Text(
                                "Preview & Share Rates",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: const Color(0xFFD32F2F),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
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
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _shareSampleRates,
                                icon: const Icon(Icons.share_rounded, size: 16),
                                label: const Text(
                                  "Preview & Share Rates",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  backgroundColor: const Color(0xFFD32F2F),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _shareSampleRates(initialCategory: title),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.share_rounded,
                              size: 12, color: Color(0xFFD32F2F)),
                          SizedBox(width: 4),
                          Text(
                            "Share",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
