import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../services/data_repository.dart';
import '../widgets/global_view_wrapper.dart';
import '../utils/steel_helper.dart';
import '../utils/sorting_utils.dart';
import '../utils/formatters.dart';
import 'quick_rate_calculator_screen.dart';
import '../models/user_session_notifier.dart';
import '../widgets/responsive_size_picker.dart';
import '../widgets/m_loader.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../constants/app_colors.dart';

class QuotationMenuScreen extends StatelessWidget {
  const QuotationMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text("Quotation Tools",
              style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: isDark ? Colors.white : Colors.black87,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Select a Tool",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 8),
              Text("Choose a calculator to begin your quote.",
                  style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white54 : Colors.grey[600])),
              const SizedBox(height: 32),
              MenuOptionCard(
                  title: "MSM Calculator",
                  description:
                      "Calculate weight and rates for Pipes, Bars, Angles, and Channels.",
                  icon: Icons.calculate,
                  isPrimary: true,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const CalculatorScreen(isQuotationMode: true)))),
              const SizedBox(height: 16),
              ValueListenableBuilder<PermissionSnapshot>(
                  valueListenable: UserSessionNotifier.instance,
                  builder: (context, snapshot, _) {
                    if (!snapshot.canAccessSampleRate)
                      return const SizedBox.shrink();
                    return Column(
                      children: [
                        MenuOptionCard(
                            title: "Sample Rate Calc",
                            description:
                                "Access the professional compact data table for high-speed quoting.",
                            icon: Icons.bolt,
                            isPrimary: true,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const SampleRateCalcScreen()))),
                        const SizedBox(height: 16),
                      ],
                    );
                  }),
              MenuOptionCard(
                  title: "Saved Quotations",
                  description: "View and share previously generated estimates.",
                  icon: Icons.save_alt,
                  isPrimary: false,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Coming Soon")))),
            ],
          ),
        ),
      ),
    );
  }
}

class MenuOptionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const MenuOptionCard(
      {super.key,
      required this.title,
      required this.description,
      required this.icon,
      required this.isPrimary,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandRed = isDark ? Colors.redAccent : const Color(0xFFD32F2F);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? brandRed.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: isPrimary
                            ? brandRed.withValues(alpha: 0.1)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey[100]),
                        borderRadius: BorderRadius.circular(16)),
                    child: isPrimary
                        ? Center(
                            child: Image.asset('assets/msm_icon.jpg',
                                width: 36,
                                errorBuilder: (c, e, s) => Icon(Icons.calculate,
                                    color: brandRed, size: 32)),
                          )
                        : Icon(icon,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                            size: 30)),
                const SizedBox(width: 20),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isPrimary
                                  ? brandRed
                                  : (isDark ? Colors.white : Colors.black87))),
                      const SizedBox(height: 6),
                      Text(description,
                          style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white38 : Colors.grey[600],
                              height: 1.4))
                    ])),
                Icon(Icons.arrow_forward_ios,
                    color: isDark ? Colors.white12 : Colors.grey[300],
                    size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  final bool isQuotationMode;
  const CalculatorScreen({super.key, required this.isQuotationMode});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  // Global Config — all defaults; real values loaded from Supabase global_charges
  double gstRate = 0.18;
  double loading = 255;
  double ncDiscount = 3000; // overridden by nc_discount from global_charges
  double globalFreight = 0;
  double globalOB = 0;

  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _contactNumberCtrl = TextEditingController();

  final TextEditingController _freightCtrl = TextEditingController();
  final TextEditingController _obCtrl = TextEditingController();

  bool gstEnabled = true;
  bool ncDiscountEnabled = true;
  bool loadingData = true;
  List<String> itemList = [];
  // Keys are stored normalized (trimmed, lowercase) for case-insensitive lookup
  Map<String, List<SizeEntry>> masterSizes = {};

  String _normalizeKey(String s) {
    return s.trim().toLowerCase();
  }

  static String _stripSpecialChars(String s) =>
      s.replaceAll(RegExp(r'[\s.\-_]'), '');
  final List<ItemEntry> items = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // --- Hard Navigation Guard ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bool canAccess = widget.isQuotationMode
          ? AccessGuard.can(AppPermissions.screensQuotation)
          : AccessGuard.can(AppPermissions.screensCalculator);

      if (!canAccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Access Denied: Missing Permission"),
              backgroundColor: Colors.red),
        );
        if (mounted) Navigator.pop(context);
      }
    });

    _loadSheetData();
  }

  Future<void> _showAddSizeBottomSheet(ItemEntry item,
      {SizeEntry? existingSize}) async {
    final result =
        await ResponsiveSizePicker.show(context, itemType: item.itemName);

    if (result != null) {
      final labelFull = result['label'].toString();
      final sheetSD = double.tryParse(result['sd']?.toString() ?? '0') ?? 0.0;
      // Extract weight strictly from result['weight'] or globalSizeWeightCache/fallback
      double weight =
          double.tryParse(result['weight']?.toString() ?? '0') ?? 0.0;
      if (weight == 0) {
        weight =
            globalSizeWeightCache[labelFull] ?? extractUnitWeight(labelFull);
      }

      setState(() {
        if (existingSize != null) {
          existingSize.label = labelFull;
          existingSize.sd = sheetSD;
          existingSize.unitWeight = weight;
          _recalcNosFromQty(existingSize);
        } else {
          bool alreadyExists =
              item.selectedSizes.any((s) => s.label == labelFull);
          if (alreadyExists) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Size $labelFull is already added.")));
            return;
          }

          item.selectedSizes.add(SizeEntry(
            label: labelFull,
            sd: sheetSD,
            unitWeight: weight,
          ));
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _customerNameCtrl.dispose();
    _contactNumberCtrl.dispose();
    _freightCtrl.dispose();
    _obCtrl.dispose();
    super.dispose();
  }

  String _getItemIconPath(String itemName) {
    String name = itemName.toLowerCase().trim();
    if (name.contains("pipe") && name.contains("hr")) {
      return "assets/hr_pipe.png";
    }
    if (name.contains("pipe")) return "assets/ms_pipe.png";
    if (name.contains("round")) return "assets/round_bar.png";
    if (name.contains("angle")) return "assets/angle.png";
    if (name.contains("channel")) return "assets/channel.png";
    if (name.contains("flat")) return "assets/flat.png";
    return "assets/msm_icon.jpg";
  }

  Future<void> _loadSheetData() async {
    final data = await DataRepository.getSheetDataAsync(null);
    if (!mounted) return;
    if (data['meta'] != null) {
      final meta = data['meta'];
      // gst_rate may be stored as a fraction '0.18' (legacy cache)
      // or as a percentage '18.00' (new global_charges table via gst_pct key).
      // Normalize: values > 1 are treated as a percentage.
      final double rawGst =
          double.tryParse(meta['gst_rate']?.toString() ?? '0.18') ?? 0.18;
      gstRate = rawGst > 1.0 ? rawGst / 100.0 : rawGst;
      loading =
          double.tryParse(meta['loading_charge']?.toString() ?? '255') ?? 255;
      // Dynamic NC Discount from global_charges.nc_discount
      ncDiscount =
          double.tryParse(meta['nc_discount']?.toString() ?? '3000') ?? 3000;
      debugPrint(
          '[Calculator] Loaded: GST=${(gstRate * 100).toStringAsFixed(2)}% LC=₹$loading NC=₹$ncDiscount');
    }
    final List<dynamic> rawItems = data['items'] ?? [];
    final Map<String, List<SizeEntry>> loadedSizesMap = {};

    for (var itemObj in rawItems) {
      String name = itemObj['name'].toString().trim();
      List<dynamic> rawSizes = itemObj['sizes'] ?? [];

      List<SizeEntry> sizeEntries = rawSizes.map((s) {
        String labelFull = s['label']?.toString().trim() ?? '';
        // 1. Smart Weight Mapping (MUST extract from raw label before cleaning)
        double weight = double.tryParse(s['weight']?.toString() ?? '0') ?? 0.0;
        if (weight == 0) {
          weight =
              globalSizeWeightCache[labelFull] ?? extractUnitWeight(labelFull);
        }

        // 2. Format the display label (e.g., re-adds "kg" and cleans up name)
        labelFull = formatSizeDisplay(name, labelFull);

        // 3. Extract other metadata from sheet data (SD)
        double sheetSD = double.tryParse(s['sd']?.toString() ?? '0') ?? 0.0;

        return SizeEntry(
          label: labelFull,
          sd: sheetSD,
          unitWeight: weight,
        );
      }).toList();

      // ── Use the display name as-is for the itemList, but also store under
      // a normalised key so _getSizesFor() can do a case-insensitive lookup.
      if (loadedSizesMap.containsKey(name)) {
        loadedSizesMap[name]!.addAll(sizeEntries);
      } else {
        loadedSizesMap[name] = sizeEntries;
      }
    }

    setState(() {
      itemList = loadedSizesMap.keys.toList()
        ..sort(SortingUtils.compareCategories);
      masterSizes = loadedSizesMap;
      items.clear();
      if (itemList.isNotEmpty) {
        items.add(ItemEntry(itemName: itemList.first));
      }
      loadingData = false;
    });
  }

  void _onHomePressed() {
    bool hasData = items.isNotEmpty ||
        _customerNameCtrl.text.trim().isNotEmpty ||
        _contactNumberCtrl.text.trim().isNotEmpty;

    if (!hasData) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Discard Quotation?"),
        content: const Text("Unsaved changes will be lost."),
        actions: [
          TextButton(
            child: const Text("Keep Editing"),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text("Discard",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear All?"),
        content: const Text("This will remove all items and reset values."),
        actions: [
          TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context)),
          TextButton(
              child: const Text("Clear",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() {
                  items.clear();
                  globalFreight = 0;
                  globalOB = 0;
                  _freightCtrl.clear();
                  _obCtrl.clear();
                  _customerNameCtrl.clear();
                  _contactNumberCtrl.clear();
                  gstEnabled = true;
                  ncDiscountEnabled = true;
                });
                Navigator.pop(context);
              }),
        ],
      ),
    );
  }

  void _recalcQtyFromNos(SizeEntry size) {
    // Re-verify weight if missing
    if (size.unitWeight <= 0) {
      size.unitWeight = globalSizeWeightCache[size.label.trim()] ??
          extractUnitWeight(size.label);
    }

    if (size.unitWeight <= 0) {
      size.qty = 0;
      size.qtyCtrl.text = '';
      return;
    }

    size.qty = (size.nos * size.unitWeight) / 1000.0;
    size.qtyCtrl.text = size.qty == 0 ? '' : size.qty.toStringAsFixed(3);
  }

  void _recalcNosFromQty(SizeEntry size) {
    // Re-verify weight if missing
    if (size.unitWeight <= 0) {
      size.unitWeight = globalSizeWeightCache[size.label.trim()] ??
          extractUnitWeight(size.label);
    }

    if (size.unitWeight <= 0) {
      size.nos = 0;
      size.nosCtrl.text = '';
      return;
    }

    size.nos = ((size.qty * 1000) / size.unitWeight).round();
    size.nosCtrl.text = size.nos == 0 ? '' : size.nos.toString();
  }

  void _showAddItemBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandRed = isDark ? Colors.redAccent : const Color(0xFFD32F2F);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        String query = "";
        String sortBy = "Priority";
        return StatefulBuilder(
          builder: (context, setSheetState) {
            var filtered =
                applyPrioritizedSearch(query, itemList, (name) => name);

            if (sortBy == "Priority") {
              filtered.sort((a, b) => SortingUtils.compareCategories(a, b));
            } else if (sortBy == "Name A-Z") {
              filtered
                  .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            } else if (sortBy == "Name Z-A")
              filtered
                  .sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    top: 24,
                    left: 16,
                    right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Select Item",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87)),
                        IconButton(
                          icon: Icon(Icons.sort, color: brandRed),
                          onPressed: () {
                            final opts = ["Priority", "Name A-Z", "Name Z-A"];
                            showModalBottomSheet(
                                context: context,
                                backgroundColor: cardColor,
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(24))),
                                builder: (c) => Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: opts
                                              .map((o) => ListTile(
                                                    title: Text(o,
                                                        style: TextStyle(
                                                            fontWeight:
                                                                sortBy == o
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                            color: sortBy == o
                                                                ? brandRed
                                                                : (isDark
                                                                    ? Colors
                                                                        .white70
                                                                    : Colors
                                                                        .black87))),
                                                    onTap: () {
                                                      setSheetState(
                                                          () => sortBy = o);
                                                      Navigator.pop(c);
                                                    },
                                                  ))
                                              .toList()),
                                    ));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                          hintText: "Search Item...",
                          hintStyle: TextStyle(
                              color: isDark ? Colors.white24 : Colors.grey),
                          prefixIcon: Icon(Icons.search,
                              color: isDark ? Colors.white60 : Colors.grey),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade50,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade200)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade200)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: brandRed))),
                      onChanged: (val) => setSheetState(() => query = val),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text("No item found",
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.grey)))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) => Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade100),
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                        color: brandRed.withValues(alpha: 0.05),
                                        shape: BoxShape.circle),
                                    child: Image.asset(_getItemIconPath(name),
                                        width: 24,
                                        height: 24,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.category,
                                            color: brandRed,
                                            size: 20)),
                                  ),
                                  title: Text(name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87)),
                                  trailing: Icon(Icons.chevron_right,
                                      size: 16,
                                      color: isDark
                                          ? Colors.white12
                                          : Colors.grey),
                                  onTap: () => Navigator.pop(context, name),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((selectedItemName) {
      if (selectedItemName != null && selectedItemName is String) {
        final newItem = ItemEntry(itemName: selectedItemName);
        setState(() => items.add(newItem));
        _showAddSizeBottomSheet(newItem);
      }
    });
  }

  double netRate(ItemEntry item, SizeEntry size) {
    double gross = item.basic + size.sd + globalFreight + globalOB + loading;
    double finalVal = gross;
    // NC discount: only deduct ₹3000 for "Binding Wire" and "Nails"
    if (ncDiscountEnabled) {
      finalVal -= ncDiscount;
    }
    if (gstEnabled) finalVal += (finalVal * gstRate);
    return finalVal;
  }

  double grandTotal() {
    double total = 0;
    for (final item in items) {
      for (final s in item.selectedSizes) {
        total += netRate(item, s) * s.qty;
      }
    }
    return total;
  }

  double totalQuantity() {
    double total = 0;
    for (final item in items) {
      for (final s in item.selectedSizes) {
        total += s.qty;
      }
    }
    return total;
  }

  String buildTermsAndConditions(bool ncDiscountEnabled) {
    StringBuffer terms = StringBuffer();
    terms.writeln("*Terms & Conditions*");
    terms.writeln("• Payment Advance");
    terms.writeln("• Loading Charge - (Inclusive)");
    terms.writeln("• Transport (Extra)");
    if (!ncDiscountEnabled) {
      final gstPct = (gstRate * 100).toStringAsFixed(2);
      terms.writeln("• GST - $gstPct % (Inclusive)");
    }
    terms.writeln("• Weight Tolerance - +/-5kg per MT");
    return terms.toString();
  }

  String _generateMessageText() {
    final now = DateTime.now();
    final dateStr =
        "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
    StringBuffer msg = StringBuffer();

    if (widget.isQuotationMode) {
      if (_customerNameCtrl.text.trim().isNotEmpty) {
        msg.writeln("Party Name: ${_customerNameCtrl.text.trim()}");
      }
      if (_contactNumberCtrl.text.trim().isNotEmpty) {
        msg.writeln("Contact No: ${_contactNumberCtrl.text.trim()}");
      }
      msg.writeln("");
      msg.writeln("*Quotation Summary*");
      msg.writeln("───────────────────────");
      msg.writeln(dateStr);
      msg.writeln("");
    } else {
      msg.writeln("*Net Rate Calculation*");
      msg.writeln("");
      msg.writeln(dateStr);
      msg.writeln("");
    }

    // ✅ GROUP ITEMS BY CATEGORY (item.itemName)
    int categoryIndex = 1;
    for (var item in items) {
      // Filter sizes with qty > 0 for quotation, or all for rate mode
      final activeSizes = widget.isQuotationMode
          ? item.selectedSizes.where((s) => s.qty > 0).toList()
          : item.selectedSizes;
      if (activeSizes.isEmpty) continue;

      // Calculate category-level basic rate for header
      double categoryRate = item.basic;
      msg.writeln(
          "*$categoryIndex. ${item.itemName}* (@${formatIndianCurrency(categoryRate)})");
      for (var s in activeSizes) {
        double rate = netRate(item, s);
        final double w = s.unitWeight != null
            ? double.tryParse(s.unitWeight.toString()) ?? 0.0
            : 0.0;
        final formattedWeight =
            w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
        String weightSuffix = w != 0 ? " ${formattedWeight}kg" : "";
        String dispLabel = item.itemName == 'MS Angle'
            ? formatSizeLabel(s.label, item.itemName, w)
            : "${s.label}$weightSuffix";

        if (widget.isQuotationMode) {
          // Round at the presentation layer — spec: Amount = round(qty * netRate)
          final int amount = (rate * s.qty).round();
          msg.writeln(
              "▪ $dispLabel | ${s.qty.toStringAsFixed(3)} MT × ${formatIndianCurrency(rate)} =");
          msg.writeln("  ₹${formatIndianCurrency(amount.toDouble())}/-");
        } else {
          msg.writeln("▪ $dispLabel = ${formatIndianCurrency(rate)} /-");
        }
      }

      msg.writeln("");
      categoryIndex++;
    }

    if (widget.isQuotationMode) {
      msg.writeln("───────────────────────");
      msg.writeln("*Total Weight: ${totalQuantity().toStringAsFixed(3)} MT*");
      msg.writeln("*Total Amount: ₹${formatIndianCurrency(grandTotal())}/-*");
      msg.writeln("");
      msg.writeln("───────────────────────");
    } else {
      msg.writeln("───────────────────────");
    }

    msg.write(buildTermsAndConditions(ncDiscountEnabled));

    return msg.toString();
  }

  void _showPreviewDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandRed = isDark ? Colors.redAccent : const Color(0xFFD32F2F);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    if (_customerNameCtrl.text.trim().isEmpty ||
        _contactNumberCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Please fill Party Name and Contact No. before generating quote.")));
      return;
    }

    String message = _generateMessageText();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFDECEB),
                borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("Quotation Preview",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: isDark ? Colors.white : Colors.black87)),
                ),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12)),
                    child: SingleChildScrollView(
                      child: Text(message,
                          style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  isDark ? Colors.white70 : Colors.black87,
                              side: BorderSide(
                                  color: isDark ? Colors.white10 : Colors.grey),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30))),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text("Copy"),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: message));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("✅ Copied to clipboard!")));
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30))),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text("Share"),
                          onPressed: () {
                            Navigator.pop(context);
                            safeShare(context, message);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Close",
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey,
                          fontSize: 16)),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPreview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    String message = _generateMessageText();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFDECEB),
                borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text("Netrate Preview",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: isDark ? Colors.white : Colors.black87)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                      height: 1,
                      color: isDark
                          ? Colors.white10
                          : Colors.grey.withValues(alpha: 0.3)),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12)),
                    child: SingleChildScrollView(
                      child: Text(message,
                          style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black,
                              height: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor:
                                  isDark ? Colors.white70 : Colors.black87,
                              side: BorderSide(
                                  color: isDark ? Colors.white10 : Colors.grey),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30))),
                          icon: const Icon(Icons.copy, size: 20),
                          label: const Text("Copy",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: message));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("✅ Copied to clipboard!")));
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.share, size: 20),
                          label: const Text("Share",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(context);
                            safeShare(context, message);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Close",
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey,
                          fontSize: 16)),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loadingData)
      return const Scaffold(body: Center(child: MLoader(size: 80)));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandRed = isDark ? Colors.redAccent : const Color(0xFFD32F2F);
    final double totalAmt = grandTotal();
    final double totalQty = totalQuantity();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        final bool isDesktop = constraints.maxWidth > 950;
        final bgColor = isDark
            ? const Color(0xFF121212)
            : (isMobile ? const Color(0xFFF5F7FA) : const Color(0xFFF8F9FA));
        final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return Scaffold(
          backgroundColor: bgColor,
          extendBodyBehindAppBar: true,
          appBar: isMobile
              ? _buildMobileAppBar(brandRed)
              : _buildDesktopAppBar(brandRed, isDark),
          body: isMobile
              ? _buildMobileBody(
                  totalAmt, totalQty, isDark, brandRed, cardColor)
              : _buildStandardBody(
                  isDesktop, totalAmt, totalQty, isDark, brandRed, cardColor),
          bottomNavigationBar: isMobile
              ? _buildMobileStickyBar(
                  totalAmt, totalQty, isDark, brandRed, cardColor)
              : (isDesktop
                  ? null
                  : _buildMobileStickyBar(
                      totalAmt, totalQty, isDark, brandRed, cardColor)),
        );
      },
    );
  }

  PreferredSizeWidget _buildMobileAppBar(Color brandRed) {
    return AppBar(
      backgroundColor: brandRed,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isQuotationMode ? 'Quotation' : 'Netrate Calc',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy').format(DateTime.now()),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerAction(Icons.home_rounded, _onHomePressed, false),
                const SizedBox(width: 8),
                _headerAction(Icons.delete_sweep_rounded, _clearAll, false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildDesktopAppBar(Color brandRed, bool isDark) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: brandRed.withValues(alpha: 0.85),
            elevation: 0,
            centerTitle: false,
            toolbarHeight: 80,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isQuotationMode ? 'Quotation' : 'Netrate Calc',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(DateTime.now()),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            actions: [
              _headerAction(Icons.home_outlined, _onHomePressed, isDark),
              const SizedBox(width: 8),
              _headerAction(Icons.delete_outline, _clearAll, isDark),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody(double totalAmt, double totalQty, bool isDark,
      Color brandRed, Color cardColor) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 72, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModernSettingsCard(isDark, brandRed, cardColor),
          const SizedBox(height: 16),
          if (widget.isQuotationMode) ...[
            _buildModernPartyCard(isDark, brandRed, cardColor),
            const SizedBox(height: 24),
          ],
          _buildProductHeader(isDark),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) =>
              _buildItemCard(e.value, e.key, isDark, brandRed, cardColor)),
          const SizedBox(height: 20),
          _buildAddItemButton(brandRed),
          const SizedBox(height: 80), // Space for sticky bar
        ],
      ),
    );
  }

  Widget _buildStandardBody(bool isDesktop, double totalAmt, double totalQty,
      bool isDark, Color brandRed, Color cardColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, MediaQuery.of(context).padding.top + 100, 24, 120),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildModernSettingsCard(isDark, brandRed, cardColor),
                    const SizedBox(height: 24),
                    if (widget.isQuotationMode) ...[
                      _buildModernPartyCard(isDark, brandRed, cardColor),
                      const SizedBox(height: 32),
                    ],
                    _buildProductHeader(isDark),
                    const SizedBox(height: 16),
                    ...items.asMap().entries.map((e) => _buildItemCard(
                        e.value, e.key, isDark, brandRed, cardColor)),
                    const SizedBox(height: 24),
                    _buildAddItemButton(brandRed),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isDesktop)
          _buildDesktopSidebar(totalAmt, totalQty, isDark, brandRed, cardColor),
      ],
    );
  }

  Widget _headerAction(IconData icon, VoidCallback onTap, bool isDark) {
    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      onPressed: onTap,
    );
  }

  Widget _buildModernSettingsCard(
      bool isDark, Color brandRed, Color cardColor) {
    return Container(
      decoration: _premiumCardDeco(isDark, brandRed),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.settings_outlined, "Pricing Settings", brandRed, isDark),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _buildMinimalSwitch("GST (18%)", gstEnabled,
                      (v) => setState(() => gstEnabled = v), brandRed, isDark)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildMinimalSwitch(
                      "NC Discount",
                      ncDiscountEnabled,
                      (v) => setState(() => ncDiscountEnabled = v),
                      brandRed,
                      isDark)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _modernTextInput(
                      "Freight (₹)",
                      _freightCtrl,
                      (v) => globalFreight = double.tryParse(v) ?? 0,
                      brandRed,
                      isDark,
                      isNumber: true)),
              const SizedBox(width: 16),
              Expanded(
                  child: _modernTextInput(
                      "OB (₹)",
                      _obCtrl,
                      (v) => globalOB = double.tryParse(v) ?? 0,
                      brandRed,
                      isDark,
                      isNumber: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernPartyCard(bool isDark, Color brandRed, Color cardColor) {
    return Container(
      decoration: _premiumCardDeco(isDark, brandRed),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.person_outline, "Party Details", brandRed, isDark),
          const SizedBox(height: 20),
          _modernTextInput(
              "Party Name", _customerNameCtrl, (v) {}, brandRed, isDark,
              isNumber: false),
          const SizedBox(height: 16),
          _modernTextInput(
              "Contact No.", _contactNumberCtrl, (v) {}, brandRed, isDark,
              isNumber: true, isPhone: true),
        ],
      ),
    );
  }

  Widget _buildProductHeader(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        return Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: isDark ? Colors.redAccent : const Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text("Products & Items",
                style: TextStyle(
                    fontSize: isMobile ? 18 : 22,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.5)),
            const Spacer(),
            if (!isMobile)
              Text("${items.length} items added",
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.grey,
                      fontWeight: FontWeight.w600)),
          ],
        );
      },
    );
  }

  Widget _buildAddItemButton(Color brandRed) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        return Align(
          alignment: Alignment.center,
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.02).animate(CurvedAnimation(
                parent: _pulseController, curve: Curves.easeInOut)),
            child: InkWell(
              borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
              onTap: itemList.isEmpty ? null : _showAddItemBottomSheet,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 32 : 48,
                    vertical: isMobile ? 14 : 20),
                decoration: BoxDecoration(
                  color: brandRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
                  border: Border.all(
                      color: brandRed.withValues(alpha: 0.2), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        color: brandRed, size: isMobile ? 22 : 28),
                    const SizedBox(width: 10),
                    Text("Add New Product",
                        style: TextStyle(
                            color: brandRed,
                            fontWeight: FontWeight.w900,
                            fontSize: isMobile ? 15 : 18,
                            letterSpacing: -0.1)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopSidebar(double totalAmt, double totalQty, bool isDark,
      Color brandRed, Color cardColor) {
    return Container(
      width: 380,
      height: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
            left: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade100)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.01),
                    blurRadius: 20,
                    offset: const Offset(-5, 0)),
              ],
      ),
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 32, 24, 24),
      child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: constraints.maxHeight -
                    (MediaQuery.of(context).padding.top + 56)),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Quotation Summary",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.5,
                      )),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summaryRow(
                            "Sub-total",
                            "₹ ${formatIndianCurrency(totalAmt / (gstEnabled ? 1.18 : 1))}",
                            isDark,
                            false),
                        const SizedBox(height: 12),
                        _summaryRow(
                            "GST (18%)",
                            gstEnabled
                                ? "₹ ${formatIndianCurrency(totalAmt - (totalAmt / 1.18))}"
                                : "₹ 0",
                            isDark,
                            false),
                        const SizedBox(height: 12),
                        _summaryRow("Total Quantity",
                            "${totalQty.toStringAsFixed(3)} MT", isDark, false),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFE2E8F0)),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "TOTAL ESTIMATE",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: textGrey,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              child: Text(
                                "₹ ${formatIndianCurrency(totalAmt)}",
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: brandRed,
                                  letterSpacing: -1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 24),
                  _premiumActionButton(
                      "GENERATE RATE",
                      () => widget.isQuotationMode
                          ? _showPreviewDialog()
                          : _showPreview(),
                      brandRed),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: textGrey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            color: textDark,
          ),
        ),
      ],
    );
  }

  Widget _premiumActionButton(
      String label, VoidCallback onTap, Color brandRed) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.01).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: brandRed.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10)),
            BoxShadow(
                color: brandRed.withValues(alpha: 0.1),
                blurRadius: 40,
                offset: const Offset(0, 20)),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandRed,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 70),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
            padding: EdgeInsets.zero,
          ),
          onPressed: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [brandRed, brandRed.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward_rounded, size: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarRow(String label, String value, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.5)),
        ],
      ),
    );
  }

  Widget _buildMobileStickyBar(double totalAmt, double totalQty, bool isDark,
      Color brandRed, Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
            top: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade100,
                width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${totalQty.toStringAsFixed(3)} MT • Estimate",
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      )),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("₹ ${formatIndianCurrency(totalAmt)}",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: -0.5,
                        )),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandRed,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed:
                  widget.isQuotationMode ? _showPreviewDialog : _showPreview,
              child: const Text("Generate",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _premiumCardDeco(bool isDark, Color brandRed) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: isDark
          ? [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8)),
            ]
          : [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
              BoxShadow(
                  color: brandRed.withValues(alpha: 0.06),
                  blurRadius: 25,
                  offset: const Offset(0, 12)),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 40,
                  offset: const Offset(0, 20)),
            ],
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.grey.shade100,
        width: 1.5,
      ),
    );
  }

  Widget _sectionHeader(
      IconData icon, String title, Color brandRed, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: brandRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: brandRed, size: 20),
        ),
        const SizedBox(width: 12),
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87)),
      ],
    );
  }

  Widget _buildMinimalSwitch(String title, bool value, Function(bool) onChanged,
      Color brandRed, bool isDark) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200)),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87),
                  overflow: TextOverflow.ellipsis)),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: brandRed,
            inactiveTrackColor: isDark ? Colors.white24 : Colors.grey.shade300,
            inactiveThumbColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          )
        ]));
  }

  Widget _modernTextInput(String label, TextEditingController controller,
      Function(String) onChanged, Color brandRed, bool isDark,
      {bool isNumber = false, bool isPhone = false}) {
    return TextField(
        controller: controller,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        maxLength: isPhone ? 10 : null,
        onChanged: (v) {
          onChanged(v);
          setState(() {}); // Required for instant global calculations
        },
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? Colors.white60 : Colors.black45,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor:
              isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          counterText: "",
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: brandRed, width: 1.5),
          ),
          floatingLabelStyle:
              TextStyle(color: brandRed, fontWeight: FontWeight.bold),
        ));
  }

  Widget _buildItemCard(
      ItemEntry item, int index, bool isDark, Color brandRed, Color cardColor) {
    double itemTotalQty = 0;
    double itemTotalAmt = 0;

    if (widget.isQuotationMode) {
      for (var s in item.selectedSizes) {
        itemTotalQty += s.qty;
        itemTotalAmt += netRate(item, s) * s.qty;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: EdgeInsets.only(bottom: isMobile ? 16 : 24),
          decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 10))
              ],
              border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  width: 1)),
          child: ExpansionTile(
            initiallyExpanded: index == items.length - 1,
            iconColor: brandRed,
            collapsedIconColor: isDark ? Colors.white54 : Colors.black45,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20), side: BorderSide.none),
            collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20), side: BorderSide.none),
            tilePadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24, vertical: isMobile ? 6 : 10),
            leading: Container(
                decoration: BoxDecoration(
                    color: brandRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(10),
                child: Image.asset(_getItemIconPath(item.itemName),
                    fit: BoxFit.cover,
                    width: isMobile ? 24 : 28,
                    height: isMobile ? 24 : 28,
                    errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.inventory_2_outlined,
                        color: brandRed,
                        size: isMobile ? 20 : 24))),
            title: Text(item.itemName,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: isMobile ? 16 : 18,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.3,
                )),
            subtitle: widget.isQuotationMode
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: brandRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "${itemTotalQty.toStringAsFixed(3)} MT",
                            style: TextStyle(
                                color: brandRed,
                                fontWeight: FontWeight.w900,
                                fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "₹ ${formatIndianCurrency(itemTotalAmt)}",
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text("Configure rates & sizes",
                        style: TextStyle(
                            color:
                                isDark ? Colors.white38 : Colors.grey.shade500,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
            childrenPadding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24, 0, isMobile ? 16 : 24, isMobile ? 16 : 24),
            children: [
              Divider(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  height: 24),
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: item.itemName,
                        dropdownColor: cardColor,
                        icon: Icon(Icons.keyboard_arrow_down_rounded,
                            color: brandRed),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                            labelText: 'Product Type',
                            labelStyle: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black45,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.grey.shade100)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.grey.shade100)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: brandRed, width: 1.5))),
                        items: itemList
                            .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            item.itemName = v;
                            item.selectedSizes.clear();
                          });
                        })),
                const SizedBox(width: 12),
                Container(
                    decoration: BoxDecoration(
                        color: brandRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: IconButton(
                        icon: Icon(Icons.delete_outline_rounded,
                            color: brandRed, size: 24),
                        onPressed: () => setState(() => items.removeAt(index))))
              ]),
              const SizedBox(height: 16),
              _modernTextInput(
                  "Basic Rate (₹)",
                  item.basicCtrl,
                  (v) => setState(() => item.basic = double.tryParse(v) ?? 0),
                  brandRed,
                  isDark,
                  isNumber: true),
              const SizedBox(height: 24),
              if (item.selectedSizes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Expanded(
                          flex: 3,
                          child: Text("Size",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white38 : Colors.black38,
                                  letterSpacing: 0.5))),
                      Expanded(
                          flex: 2,
                          child: Text("Rate",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white38 : Colors.black38,
                                  letterSpacing: 0.5),
                              textAlign: TextAlign.center)),
                      if (widget.isQuotationMode)
                        if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
                            .contains(item.itemName))
                          Expanded(
                              flex: 2,
                              child: Text("Nos",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                      letterSpacing: 0.5),
                                  textAlign: TextAlign.center)),
                      if (widget.isQuotationMode)
                        Expanded(
                            flex: 2,
                            child: Text("Qty (MT)",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    letterSpacing: 0.5),
                                textAlign: TextAlign.center)),
                      if (widget.isQuotationMode)
                        Expanded(
                            flex: 3,
                            child: Text("Amt",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    letterSpacing: 0.5),
                                textAlign: TextAlign.right)),
                      const SizedBox(width: 32)
                    ]),
                  ),
                ),
                ...item.selectedSizes.asMap().entries.map((entry) =>
                    _buildSizeRow(
                        item, entry.key, entry.value, isDark, brandRed)),
                const SizedBox(height: 16),
              ],
              _buildAddSizeButton(item, brandRed),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSizeRow(
      ItemEntry item, int sizeIndex, SizeEntry s, bool isDark, Color brandRed) {
    final rate = netRate(item, s);
    // Precision lock: round at the presentation layer
    final int amount = (rate * s.qty).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => _showAddSizeBottomSheet(item, existingSize: s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color:
                                isDark ? Colors.white10 : Colors.grey.shade200,
                            width: 1))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (() {
                          final double w = s.unitWeight != null
                              ? double.tryParse(s.unitWeight.toString()) ?? 0.0
                              : 0.0;
                          final formattedWeight = w % 1 == 0
                              ? w.toInt().toString()
                              : w.toStringAsFixed(1);
                          String weightSuffix =
                              w != 0 ? " ${formattedWeight}kg" : "";
                          return item.itemName == 'MS Angle'
                              ? formatSizeLabel(s.label, item.itemName, w)
                              : "${s.label}$weightSuffix";
                        })(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: brandRed,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.edit_note_rounded,
                        color: brandRed.withValues(alpha: 0.5), size: 14)
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(rate.toStringAsFixed(0),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                )),
          ),
          if (widget.isQuotationMode) ...[
            if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
                .contains(item.itemName))
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 36),
                      child: TextField(
                        controller: s.nosCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87),
                        textAlign: TextAlign.center,
                        onChanged: (v) {
                          s.nos = int.tryParse(v) ?? 0;
                          _recalcQtyFromNos(s);
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: "0",
                          hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                    if (s.unitWeight <= 0)
                      FittedBox(
                        child: Text(
                          "Master data weight missing",
                          style: TextStyle(
                              color: brandRed,
                              fontSize: 8,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              flex: 2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: TextField(
                  controller: s.qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87),
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    s.qty = double.tryParse(v) ?? 0;
                    _recalcNosFromQty(s);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: "0.0",
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white24 : Colors.grey.shade300),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color:
                              isDark ? Colors.white10 : Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color:
                              isDark ? Colors.white10 : Colors.grey.shade200),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(formatIndianCurrency(amount),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.2,
                  )),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                setState(() => item.selectedSizes.removeAt(sizeIndex)),
            icon: Icon(Icons.remove_circle_outline_rounded,
                color: Colors.grey.shade400, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSizeButton(ItemEntry item, Color brandRed) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 16, vertical: isMobile ? 8 : 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              backgroundColor: brandRed.withValues(alpha: 0.05),
            ),
            onPressed: () => _showAddSizeBottomSheet(item),
            icon: Icon(Icons.add_circle_outline_rounded,
                color: brandRed, size: isMobile ? 18 : 20),
            label: Text("Add Size",
                style: TextStyle(
                  color: brandRed,
                  fontWeight: FontWeight.w900,
                  fontSize: isMobile ? 13 : 14,
                )),
          ),
        );
      },
    );
  }
}

Future<void> safeShare(BuildContext context, String text,
    {String? subject}) async {
  try {
    await Share.share(text, subject: subject);
  } catch (e) {
    debugPrint("Share Error: $e");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Error sharing: $e"),
            backgroundColor: const Color(0xFFD32F2F)),
      );
    }
  }
}

class ItemEntry {
  String itemName;
  double basic;
  List<SizeEntry> selectedSizes;
  final TextEditingController basicCtrl = TextEditingController();
  ItemEntry(
      {required this.itemName, this.basic = 0, List<SizeEntry>? selectedSizes})
      : selectedSizes = selectedSizes ?? [];
}

class SizeEntry {
  String label;
  double sd;
  double unitWeight;
  int nos;
  double qty;
  String? weightError;
  final TextEditingController nosCtrl;
  final TextEditingController qtyCtrl;

  SizeEntry({
    required this.label,
    required this.sd,
    this.unitWeight = 0,
    this.qty = 0,
    this.nos = 0,
    this.weightError,
  })  : nosCtrl = TextEditingController(text: nos == 0 ? '' : nos.toString()),
        qtyCtrl = TextEditingController(text: qty == 0 ? '' : qty.toString());
}
