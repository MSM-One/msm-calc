import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String? _selectedCategory;

  // Controllers for Master Rate Panel
  final TextEditingController _pipeBasicCtrl = TextEditingController();
  final TextEditingController _angleBasicCtrl = TextEditingController();
  final TextEditingController _channelBasicCtrl = TextEditingController();
  final TextEditingController _sqrBarBasicCtrl = TextEditingController();
  final TextEditingController _roundFlatsBasicCtrl = TextEditingController();

  // Dynamic controller map for any master catalog categories
  final Map<String, TextEditingController> _dynamicControllers = {};

  // Global & Formula Toggles
  bool _gstEnabled = true;
  bool _ncDiscountEnabled = false;
  final bool _hasLoadingCharge = true;

  double get _loading => DataRepository.currentCharges.lcRate > 0
      ? DataRepository.currentCharges.lcRate
      : (double.tryParse(DataRepository.sheetDataNotifier.value['meta']?['loading_charge']?.toString() ?? '255') ?? 255.0);

  double get _ncDiscount => DataRepository.currentCharges.ncDiscount > 0
      ? DataRepository.currentCharges.ncDiscount
      : (double.tryParse(DataRepository.sheetDataNotifier.value['meta']?['nc_discount']?.toString() ?? '3000') ?? 3000.0);

  double get _gstRate {
    final chargesGst = DataRepository.currentCharges.gstRate;
    if (chargesGst > 0) {
      return chargesGst > 1.0 ? chargesGst / 100.0 : chargesGst;
    }
    final rawGst = double.tryParse(DataRepository.sheetDataNotifier.value['meta']?['gst_rate']?.toString() ?? '0.18') ?? 0.18;
    return rawGst > 1.0 ? rawGst / 100.0 : rawGst;
  }

  final double _freight = 0.0;
  final double _ob = 0.0;

  bool _isRemovalMode = false;
  Map<String, List<SampleRateSize>> _categories = {};
  final Map<String, List<SampleRateSize>> _customAddedSizes = {};
  final Map<String, Set<String>> _removedSizeLabels = {};

  void _addCustomSize(String category, SampleRateSize size) {
    setState(() {
      _removedSizeLabels[category]?.remove(size.label);
      final inv = context.read<InventoryProvider>();
      final baseList = inv.sampleRateCategories[category] ?? [];
      if (!baseList.any((s) => s.label == size.label)) {
        final list = _customAddedSizes.putIfAbsent(category, () => []);
        if (!list.any((s) => s.label == size.label)) {
          list.add(size);
        }
      }
    });
    MotionToast.show(context, "Added ${size.label} to $category");
  }

  void _removeSizeFromCategory(String category, SampleRateSize size) {
    setState(() {
      _customAddedSizes[category]?.removeWhere((s) => s.label == size.label);
      _removedSizeLabels.putIfAbsent(category, () => {}).add(size.label);
    });
    MotionToast.show(context, "Removed ${size.label} from $category");
  }

  void _resetCategoryToDefaults(String category) {
    setState(() {
      _customAddedSizes.remove(category);
      _removedSizeLabels.remove(category);
      _isRemovalMode = false;
    });
    MotionToast.show(context, "Reset $category to benchmark defaults");
  }

  bool _isCategoryModified(String category) {
    final hasCustom = (_customAddedSizes[category] ?? []).isNotEmpty;
    final hasRemoved = (_removedSizeLabels[category] ?? {}).isNotEmpty;
    return hasCustom || hasRemoved;
  }

  void _showAddSizeModal(BuildContext context, String category, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddSizeBottomSheet(
        category: category,
        isDark: isDark,
        existingSizes: _categories[category] ?? [],
        onSizeSelected: (size) => _addCustomSize(category, size),
      ),
    );
  }

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
    for (final ctrl in _dynamicControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _getControllerForCategory(String category) {
    String cat = category.toUpperCase().trim();
    if (cat == 'MS PIPE' || (cat.contains('PIPE') && !cat.contains('HR') && !cat.contains('CR') && !cat.contains('ERW'))) {
      return _pipeBasicCtrl;
    }
    if (cat == 'MS ANGLE' || cat.contains('ANGLE')) return _angleBasicCtrl;
    if (cat == 'MS CHANNEL' || cat.contains('CHANNEL')) return _channelBasicCtrl;
    if (cat == 'SQR BAR' || (cat.contains('SQR') || cat.contains('SQUARE'))) {
      return _sqrBarBasicCtrl;
    }
    if (cat == 'ROUND BAR' || cat == 'FLATS' || cat.contains('ROUND') || cat.contains('FLAT')) {
      return _roundFlatsBasicCtrl;
    }
    return _dynamicControllers.putIfAbsent(
      cat,
      () => TextEditingController()..addListener(_onRateChanged),
    );
  }

  double _calculateFinalRate(String category, num sd) {
    TextEditingController ctrl = _getControllerForCategory(category);
    String rateText = ctrl.text.trim();
    double basic = double.tryParse(rateText) ?? 0.0;

    if (basic == 0.0) return 0.0;

    double effectiveBase =
        basic + sd.toDouble() + (_hasLoadingCharge ? _loading : 0.0);
    if (_ncDiscountEnabled) {
      effectiveBase -= _ncDiscount;
    }
    double netBeforeGst = effectiveBase + _freight + _ob;
    double finalNetRate =
        _gstEnabled ? (netBeforeGst * (1.0 + _gstRate)) : netBeforeGst;
    return finalNetRate;
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
      for (final ctrl in _dynamicControllers.values) {
        ctrl.text = sourceRate;
      }
    });
    MotionToast.show(context, "Rate ₹$sourceRate applied to all categories!");
  }

  static const Set<String> _allowedCoreCategories = {
    'MS PIPE',
    'MS ANGLE',
    'MS CHANNEL',
    'SQR BAR',
    'ROUND BAR',
    'FLATS',
  };

  static bool _isAllowedCategory(String category) {
    final cat = category.toUpperCase().trim();
    if (_allowedCoreCategories.contains(cat)) return true;
    if (cat == 'PIPE' || cat == 'MS PIPES') return true;
    if (cat == 'ANGLE' || cat == 'MS ANGLES') return true;
    if (cat == 'CHANNEL' || cat == 'MS CHANNELS') return true;
    if (cat == 'SQUARE BAR' || cat == 'SQ BAR' || cat == 'MS SQR BAR') return true;
    if (cat == 'ROUND' || cat == 'MS ROUND' || cat == 'MS ROUND BAR') return true;
    if (cat == 'FLAT' || cat == 'MS FLAT' || cat == 'MS FLATS') return true;
    return false;
  }

  String _generateRateMessage({String? specificCategory}) {
    StringBuffer sb = StringBuffer();
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    sb.writeln("Date: $formattedDate");
    sb.writeln("----------------------------");

    int categoryIndex = 1;
    bool hasAnySelected = false;

    final sortedCategoryKeys = _categories.keys
        .where(_isAllowedCategory)
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
          String baseLabel = size.label.trim().replaceAll(
              RegExp(r'\s*\(?\d*[\.,]?\d*\s*kg\)?$', caseSensitive: false), "");
          final double w = size.weight.toDouble();
          final formattedWeight =
              w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
          final lowerTitle = category.toLowerCase();
          final bool isExcluded = lowerTitle.contains('sqr bar') ||
              lowerTitle.contains('square bar') ||
              lowerTitle.contains('round bar') ||
              lowerTitle.contains('flats') ||
              lowerTitle.contains('flat') ||
              lowerTitle.contains('gate channel') ||
              lowerTitle.contains('binding wire') ||
              lowerTitle.contains('barbed wire');
          String weightSuffix = (w != 0 && !isExcluded) ? " ${formattedWeight}kg" : "";
          String dispLabel = category.trim() == 'MS Angle'
              ? formatSizeLabel(baseLabel, category, w)
              : "$baseLabel$weightSuffix";
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
      sb.writeln("• GST - 18.00 % (Inclusive)");
    }
    sb.write("• Weight Tolerance - +/-5kg per MT");

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
        .where(_isAllowedCategory)
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
            IconButton(
              icon: Icon(
                Icons.share_rounded,
                size: 20,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              tooltip: 'Share Sample Rates',
              onPressed: _shareSampleRates,
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: null,
        body: Consumer<InventoryProvider>(
          builder: (context, inv, _) {
            if (inv.isLoadingSampleRates && inv.sampleRateCategories.isEmpty) {
              return const Center(child: MLoader(size: 60));
            }

            final Map<String, List<SampleRateSize>> combinedCategories = {};
            for (final entry in inv.sampleRateCategories.entries) {
              final cat = entry.key;
              final baseList = entry.value;
              final customList = _customAddedSizes[cat] ?? [];
              final removed = _removedSizeLabels[cat] ?? {};

              final mergedList = <SampleRateSize>[];
              for (final s in [...baseList, ...customList]) {
                if (!removed.contains(s.label)) {
                  if (!mergedList.any((existing) => existing.label == s.label)) {
                    mergedList.add(s);
                  }
                }
              }
              combinedCategories[cat] = mergedList;
            }

            for (final entry in _customAddedSizes.entries) {
              final cat = entry.key;
              if (!combinedCategories.containsKey(cat)) {
                final removed = _removedSizeLabels[cat] ?? {};
                combinedCategories[cat] = entry.value
                    .where((s) => !removed.contains(s.label))
                    .toList();
              }
            }

            _categories = combinedCategories;

            if (_categories.isEmpty) {
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

            final sortedCategories = _categories.keys
                .where(_isAllowedCategory)
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
                          const SizedBox(height: 14),

                          Row(
                            children: [
                              Expanded(
                                child: _buildModernToggleTile(
                                  title: "GST (18%)",
                                  value: _gstEnabled,
                                  onChanged: (v) =>
                                      setState(() => _gstEnabled = v),
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildModernToggleTile(
                                  title: "NC Discount",
                                  value: _ncDiscountEnabled,
                                  onChanged: (v) =>
                                      setState(() => _ncDiscountEnabled = v),
                                  isDark: isDark,
                                ),
                              ),
                            ],
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
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collapsible Rate Config Card on Mobile
                  Material(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 0,
                    child: Container(
                      decoration: BoxDecoration(
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
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                        initiallyExpanded: _pipeBasicCtrl.text.isEmpty &&
                            _angleBasicCtrl.text.isEmpty &&
                            _channelBasicCtrl.text.isEmpty &&
                            _sqrBarBasicCtrl.text.isEmpty &&
                            _roundFlatsBasicCtrl.text.isEmpty,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Color(0xFFD32F2F),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          "Rate Settings & Inputs",
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: Text(
                          _pipeBasicCtrl.text.isNotEmpty
                              ? "Pipe: ₹${formatIndianCurrency((double.tryParse(_pipeBasicCtrl.text) ?? 0).round())} • GST ${_gstEnabled ? '18%' : 'Off'}"
                              : "Tap to set Pipe, Angle, Channel basic rates",
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        children: [
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
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernToggleTile(
                                  title: "GST (18%)",
                                  value: _gstEnabled,
                                  onChanged: (v) =>
                                      setState(() => _gstEnabled = v),
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildModernToggleTile(
                                  title: "NC Discount",
                                  value: _ncDiscountEnabled,
                                  onChanged: (v) =>
                                      setState(() => _ncDiscountEnabled = v),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                  // Canonical Category Chips (Horizontal Scroll)
                  _buildCategoryChips(sortedCategories, isDark),
                  const SizedBox(height: 12),

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
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
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

    final isModified = _isCategoryModified(title);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header Bar (Single Compact Row)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 450;
              final isUltraCompact = constraints.maxWidth < 360;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Title + Size count badge
                  Flexible(
                    flex: 4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title.toUpperCase(),
                            style: TextStyle(
                              fontSize: isUltraCompact ? 11.5 : 12.5,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${sortedSizes.length} sizes",
                              style: TextStyle(
                                fontSize: isUltraCompact ? 9 : 10,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Right: Action button group
                  Flexible(
                    flex: 6,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Base Rate Status Chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                                  ? "Base: ₹${formatIndianCurrency(basic.round())}"
                                  : (isCompact ? "Base: —" : "Base Rate Not Set"),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: hasBasic
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // "+ Add" Action Button
                          Tooltip(
                            message: "+ Add Size",
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _showAddSizeModal(context, title, isDark),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3.5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF475569)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.add_circle_outline,
                                        size: 13, color: Color(0xFFD32F2F)),
                                    SizedBox(width: 3),
                                    Text(
                                      "+ Add",
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFD32F2F),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // "- Remove" Toggle Button
                          Tooltip(
                            message: "- Remove Size",
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                setState(() {
                                  _isRemovalMode = !_isRemovalMode;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: _isRemovalMode
                                      ? (isDark
                                          ? const Color(0xFF7F1D1D)
                                              .withValues(alpha: 0.3)
                                          : const Color(0xFFFEE2E2))
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _isRemovalMode
                                        ? const Color(0xFFDC2626)
                                        : (isDark
                                            ? const Color(0xFF475569)
                                            : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isRemovalMode
                                          ? Icons.check_circle_outline
                                          : Icons.remove_circle_outline,
                                      size: 13,
                                      color: _isRemovalMode
                                          ? const Color(0xFFDC2626)
                                          : (isDark
                                              ? const Color(0xFFE2E8F0)
                                              : const Color(0xFF475569)),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _isRemovalMode ? "Done" : "- Remove",
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: _isRemovalMode
                                            ? const Color(0xFFDC2626)
                                            : (isDark
                                                ? const Color(0xFFE2E8F0)
                                                : const Color(0xFF475569)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Optional Reset Defaults button if modified
                          if (isModified) ...[
                            const SizedBox(width: 2),
                            IconButton(
                              tooltip: "Reset Defaults",
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(3),
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              onPressed: () => _resetCategoryToDefaults(title),
                              icon: Icon(
                                Icons.restore_rounded,
                                size: 15,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
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
                      alignment: Alignment.center,
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

                  String baseLabel = size.label.trim().replaceAll(
                      RegExp(r'\s*\(?\d*[\.,]?\d*\s*kg\)?$', caseSensitive: false), "");
                  String weightText = '';
                  final double? wVal = double.tryParse(size.weight.toString());
                  final String lowerTitle = title.toLowerCase();

                  final bool isExcluded = lowerTitle.contains('sqr bar') ||
                      lowerTitle.contains('square bar') ||
                      lowerTitle.contains('round bar') ||
                      lowerTitle.contains('flats') ||
                      lowerTitle.contains('flat') ||
                      lowerTitle.contains('gate channel') ||
                      lowerTitle.contains('binding wire') ||
                      lowerTitle.contains('barbed wire');

                  if (wVal != null && wVal != 0 && !isExcluded) {
                    final formattedWeight = wVal % 1 == 0
                        ? wVal.toInt().toString()
                        : wVal.toStringAsFixed(1);
                    weightText = " ${formattedWeight}kg";
                  }

                  String dispLabel = (title.trim() == 'MS Angle')
                      ? formatSizeLabel(baseLabel, title, wVal ?? 0.0)
                      : "$baseLabel$weightText";

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
                          alignment: Alignment.center,
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
                      // Col 1: Size & Weight + Custom Tag + Delete Action (flex: 4)
                      _TableCell(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            if (_isRemovalMode) ...[
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _removeSizeFromCategory(title, size),
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 6.0),
                                  child: Icon(
                                    Icons.remove_circle,
                                    size: 16,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      dispLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (size.isCustom) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E3A8A).withValues(alpha: 0.4)
                                            : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isDark
                                              ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                                              : const Color(0xFFBFDBFE),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: const Text(
                                        "CUSTOM",
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF2563EB),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!_isRemovalMode && size.isCustom)
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _removeSizeFromCategory(title, size),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Col 2: SD Value Badge (flex: 2, Center Aligned)
                      _TableCell(
                        alignment: Alignment.center,
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
                                    fontSize: 10.5,
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
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                      ),

                      // Col 3: Net Computed Rate (flex: 3, Right Aligned)
                      _TableCell(
                        alignment: Alignment.centerRight,
                        child: hasCalculated
                            ? Text(
                                "₹${formatIndianCurrency(finalRate.round())}",
                                style: const TextStyle(
                                  fontSize: 12,
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

  Widget _buildModernToggleTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFFD32F2F),
              inactiveTrackColor:
                  isDark ? Colors.white24 : const Color(0xFFCBD5E1),
              inactiveThumbColor: Colors.white,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
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
      constraints: const BoxConstraints(minHeight: 38),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          color: Color(0xFF64748B),
          letterSpacing: 0.3,
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
      constraints: const BoxConstraints(minHeight: 44),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: child,
    );
  }
}

// ── ADD SIZE BOTTOM SHEET / MODAL ──
class _AddSizeBottomSheet extends StatefulWidget {
  final String category;
  final bool isDark;
  final List<SampleRateSize> existingSizes;
  final ValueChanged<SampleRateSize> onSizeSelected;

  const _AddSizeBottomSheet({
    required this.category,
    required this.isDark,
    required this.existingSizes,
    required this.onSizeSelected,
  });

  @override
  State<_AddSizeBottomSheet> createState() => _AddSizeBottomSheetState();
}

class _AddSizeBottomSheetState extends State<_AddSizeBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<SampleRateSize> _allMasterSizes = [];
  List<SampleRateSize> _filteredSizes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadSizes();
  }

  void _loadSizes() {
    final inv = context.read<InventoryProvider>();
    final masterList = inv.getMasterSizesForCategory(widget.category);
    setState(() {
      _allMasterSizes = masterList;
      _filteredSizes = masterList;
      _isLoading = false;
    });
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredSizes = _allMasterSizes);
    } else {
      final cleanQ = q.replaceAll('"', '').replaceAll("'", '').replaceAll(' ', '');
      setState(() {
        _filteredSizes = _allMasterSizes.where((s) {
          final label = s.label.toLowerCase();
          final cleanLabel = label.replaceAll('"', '').replaceAll("'", '').replaceAll(' ', '');
          final w = s.weight.toString();
          final sd = s.sd.toString();
          return label.contains(q) ||
              cleanLabel.contains(cleanQ) ||
              w.contains(q) ||
              sd.contains(q);
        }).toList();
      });
    }
  }

  bool _isSizeAlreadyAdded(SampleRateSize size) {
    String cleanA = _cleanForCompare(size.label);
    return widget.existingSizes.any((existing) {
      if (existing.label.trim().toUpperCase() == size.label.trim().toUpperCase()) return true;
      String cleanB = _cleanForCompare(existing.label);
      return cleanA == cleanB;
    });
  }

  String _cleanForCompare(String s) {
    return s
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('”', '')
        .replaceAll('“', '')
        .replaceAll('’', '')
        .replaceAll('‘', '')
        .replaceAll('×', 'X')
        .replaceAll('x', 'X')
        .replaceAll('*', 'X')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          height: mediaQuery.size.height * 0.82,
          margin: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                          child: const Icon(
                            Icons.add_circle_outline,
                            color: Color(0xFFD32F2F),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Add Size: ${widget.category}",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              "${_allMasterSizes.length} master sizes cataloged",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF64748B),
                      ),
                      tooltip: "Close",
                    ),
                  ],
                ),
              ),

              // Search Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: false,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: "Search size (e.g. 2\", 50x50, 2.5mm)...",
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // List of Master Sizes
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredSizes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 40,
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchCtrl.text.isEmpty
                                      ? "No master sizes found for ${widget.category}"
                                      : "No matching sizes found for \"${_searchCtrl.text}\"",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredSizes.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 0.5,
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                            itemBuilder: (context, index) {
                              final size = _filteredSizes[index];
                              final isAdded = _isSizeAlreadyAdded(size);

                              String weightSuffix = '';
                              final w = size.weight.toDouble();
                              if (w > 0) {
                                final fw = w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
                                weightSuffix = " (${fw} kg)";
                              }

                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: isAdded
                                    ? null
                                    : () {
                                        widget.onSizeSelected(size);
                                        Navigator.pop(context);
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isAdded
                                            ? Icons.check_circle_rounded
                                            : Icons.add_circle_outline_rounded,
                                        size: 20,
                                        color: isAdded
                                            ? const Color(0xFF10B981)
                                            : (isDark ? Colors.white70 : const Color(0xFFD32F2F)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "${size.label}$weightSuffix",
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: isAdded
                                                    ? (isDark
                                                        ? const Color(0xFF64748B)
                                                        : const Color(0xFF94A3B8))
                                                    : (isDark
                                                        ? Colors.white
                                                        : const Color(0xFF0F172A)),
                                                decoration: isAdded ? TextDecoration.none : null,
                                              ),
                                            ),
                                            if (size.sd != 0)
                                              Text(
                                                size.sd > 0
                                                    ? "SD: +₹${size.sd.toStringAsFixed(0)}"
                                                    : "SD: -₹${size.sd.abs().toStringAsFixed(0)}",
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: size.sd > 0
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFFD97706),
                                                ),
                                              )
                                            else
                                              const Text(
                                                "SD: Base Rate",
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isAdded)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFFA7F3D0),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: const Text(
                                            "Added",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF059669),
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF1E293B)
                                                : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isDark
                                                  ? const Color(0xFF334155)
                                                  : const Color(0xFFCBD5E1),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.add, size: 12, color: Color(0xFFD32F2F)),
                                              SizedBox(width: 2),
                                              Text(
                                                "Add",
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFFD32F2F),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
