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

class QuotationMenuScreen extends StatelessWidget {
  const QuotationMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: Text(
            "Quotation Tools",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          elevation: 0,
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calculate_rounded,
                          color: Color(0xFFD32F2F),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Select a Tool",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Choose a calculator to begin your quote or rate computation.",
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  MenuOptionCard(
                    title: "MSM Calculator",
                    description:
                        "Calculate weight, dynamic rates, and produce branded quotations for Pipes, Bars, Angles, and Channels.",
                    icon: Icons.calculate_outlined,
                    isPrimary: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const CalculatorScreen(isQuotationMode: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<PermissionSnapshot>(
                    valueListenable: UserSessionNotifier.instance,
                    builder: (context, snapshot, _) {
                      if (!snapshot.canAccessSampleRate) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          MenuOptionCard(
                            title: "Sample Rate Calc",
                            description:
                                "Access the professional compact data table for high-speed multi-category quoting.",
                            icon: Icons.bolt_rounded,
                            isPrimary: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const SampleRateCalcScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),
                  MenuOptionCard(
                    title: "Saved Quotations",
                    description: "View, audit, and share previously generated estimates.",
                    icon: Icons.history_rounded,
                    isPrimary: false,
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Coming Soon")),
                    ),
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

class MenuOptionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const MenuOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandRed = isDark ? Colors.redAccent : const Color(0xFFD32F2F);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? brandRed.withValues(alpha: 0.1)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isPrimary
                      ? Center(
                          child: Image.asset(
                            'assets/msm_icon.jpg',
                            width: 32,
                            errorBuilder: (c, e, s) => Icon(
                              Icons.calculate,
                              color: brandRed,
                              size: 28,
                            ),
                          ),
                        )
                      : Icon(
                          icon,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          size: 26,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                  size: 16,
                ),
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
  // Global Config — loaded from Supabase global_charges
  double gstRate = 0.18;
  double loading = 255;
  double ncDiscount = 3000;
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
  Map<String, List<SizeEntry>> masterSizes = {};

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
            backgroundColor: Colors.red,
          ),
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
              SnackBar(content: Text("Size $labelFull is already added.")),
            );
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

  static const List<String> allowedCategories = [
    'MS PIPE',
    'MS ANGLE',
    'MS CHANNEL',
    'SQR BAR',
    'ROUND BAR',
    'FLATS',
  ];

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

  Future<void> _loadSheetData() async {
    final data = await DataRepository.getSheetDataAsync(null);
    if (!mounted) return;
    if (data['meta'] != null) {
      final meta = data['meta'];
      final double rawGst =
          double.tryParse(meta['gst_rate']?.toString() ?? '0.18') ?? 0.18;
      gstRate = rawGst > 1.0 ? rawGst / 100.0 : rawGst;
      loading =
          double.tryParse(meta['loading_charge']?.toString() ?? '255') ?? 255;
      ncDiscount =
          double.tryParse(meta['nc_discount']?.toString() ?? '3000') ?? 3000;
      debugPrint(
          '[Calculator] Loaded: GST=${(gstRate * 100).toStringAsFixed(2)}% LC=₹$loading NC=₹$ncDiscount');
    }
    final List<dynamic> rawItems = data['items'] ?? [];
    final Map<String, List<SizeEntry>> loadedSizesMap = {};

    for (var itemObj in rawItems) {
      String name = itemObj['name'].toString().trim();
      if (!isAllowedCategory(name)) continue;

      List<dynamic> rawSizes = itemObj['sizes'] ?? [];

      List<SizeEntry> sizeEntries = rawSizes.map((s) {
        String labelFull = s['label']?.toString().trim() ?? '';
        double weight = double.tryParse(s['weight']?.toString() ?? '0') ?? 0.0;
        if (weight == 0) {
          weight =
              globalSizeWeightCache[labelFull] ?? extractUnitWeight(labelFull);
        }

        labelFull = formatSizeDisplay(name, labelFull);
        double sheetSD = double.tryParse(s['sd']?.toString() ?? '0') ?? 0.0;

        return SizeEntry(
          label: labelFull,
          sd: sheetSD,
          unitWeight: weight,
        );
      }).toList();

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Discard Changes?",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text("Any unsaved edits will be lost.",
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            child: const Text("Keep Editing"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text("Discard"),
            onPressed: () {
              Navigator.pop(context);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Reset All Fields?",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          "This will remove all configured products, reset freight, OB, and party details.",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text("Reset All"),
            onPressed: () {
              setState(() {
                items.clear();
                if (itemList.isNotEmpty) {
                  items.add(ItemEntry(itemName: itemList.first));
                }
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
            },
          ),
        ],
      ),
    );
  }

  void _recalcQtyFromNos(SizeEntry size) {
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
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
            } else if (sortBy == "Name Z-A") {
              filtered
                  .sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 20,
                  left: 20,
                  right: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Select Product Category",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.sort_rounded, color: brandRed),
                          onPressed: () {
                            final opts = ["Priority", "Name A-Z", "Name Z-A"];
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: cardColor,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                              ),
                              builder: (c) => Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: opts
                                      .map(
                                        (o) => ListTile(
                                          title: Text(
                                            o,
                                            style: TextStyle(
                                              fontWeight: sortBy == o
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: sortBy == o
                                                  ? brandRed
                                                  : (isDark
                                                      ? Colors.white70
                                                      : const Color(0xFF1E293B)),
                                            ),
                                          ),
                                          onTap: () {
                                            setSheetState(() => sortBy = o);
                                            Navigator.pop(c);
                                          },
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "Search categories...",
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: isDark ? Colors.white60 : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: brandRed, width: 1.5),
                        ),
                      ),
                      onChanged: (val) => setSheetState(() => query = val),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  "No product category found",
                                  style: TextStyle(
                                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) => Divider(
                                height: 1,
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: brandRed.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Image.asset(
                                      _getItemIconPath(name),
                                      width: 22,
                                      height: 22,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.category_rounded,
                                        color: brandRed,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
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
    return item.basic + size.sd + globalFreight + globalOB;
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

  String buildTermsAndConditions([bool ncDiscountEnabled = false]) {
    StringBuffer terms = StringBuffer();
    terms.writeln("*Terms & Conditions*");
    terms.writeln("• Payment Advance");
    terms.writeln("• Transport (Extra)");
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

    int categoryIndex = 1;
    for (var item in items) {
      final activeSizes = widget.isQuotationMode
          ? item.selectedSizes.where((s) => s.qty > 0).toList()
          : item.selectedSizes;
      if (activeSizes.isEmpty) continue;

      double categoryRate = item.basic;
      msg.writeln(
          "*$categoryIndex. ${item.itemName}* (@${formatIndianCurrency(categoryRate)})");
      for (var s in activeSizes) {
        double rate = netRate(item, s);
        final double w = s.unitWeight;
        final formattedWeight =
            w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1);
        String weightSuffix = w != 0 ? " ${formattedWeight}kg" : "";
        String dispLabel = item.itemName == 'MS Angle'
            ? formatSizeLabel(s.label, item.itemName, w)
            : "${s.label}$weightSuffix";

        if (widget.isQuotationMode) {
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

    if (widget.isQuotationMode &&
        (_customerNameCtrl.text.trim().isEmpty ||
            _contactNumberCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Please fill Party Name and Contact No. before generating quote."),
        ),
      );
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
            constraints: const BoxConstraints(maxWidth: 560),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.article_outlined,
                          color: Color(0xFFD32F2F),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isQuotationMode
                                  ? "Quotation Preview"
                                  : "Net Rate Breakdown",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              "Ready for WhatsApp broadcast and clipboard export",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
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
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: SingleChildScrollView(
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? Colors.white
                                : const Color(0xFF1E293B),
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFCBD5E1),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text(
                            "Copy Text",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: message));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("✅ Copied to clipboard!"),
                              ),
                            );
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
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text(
                            "WhatsApp Share",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            safeShare(context, message);
                          },
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
    );
  }

  void _showPreview() {
    _showPreviewDialog();
  }

  @override
  Widget build(BuildContext context) {
    if (loadingData) {
      return const Scaffold(body: Center(child: MLoader(size: 80)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandRed = isDark ? Colors.redAccent : const Color(0xFFD32F2F);
    final double totalAmt = grandTotal();
    final double totalQty = totalQuantity();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        final bool isDesktop = constraints.maxWidth > 950;
        final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
        final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: isMobile
              ? _buildMobileAppBar(brandRed, isDark)
              : _buildDesktopAppBar(brandRed, isDark),
          body: isMobile
              ? _buildMobileBody(totalAmt, totalQty, isDark, brandRed, cardColor)
              : _buildStandardBody(
                  isDesktop, totalAmt, totalQty, isDark, brandRed, cardColor),
          bottomNavigationBar: isDesktop
              ? null
              : _buildMobileStickyBar(
                  totalAmt, totalQty, isDark, brandRed, cardColor),
        );
      },
    );
  }

  PreferredSizeWidget _buildMobileAppBar(Color brandRed, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      surfaceTintColor: Colors.transparent,
      shape: Border(
        bottom: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
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
      title: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isQuotationMode ? 'Quotations' : 'Netrate Calc',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        DateFormat('dd MMM yyyy').format(DateTime.now()),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerAction(Icons.home_outlined, _onHomePressed, isDark),
                const SizedBox(width: 8),
                _headerAction(
                    Icons.restart_alt_rounded, _clearAll, isDark, isDanger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildDesktopAppBar(Color brandRed, bool isDark) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 68,
        surfaceTintColor: Colors.transparent,
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
        shape: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: brandRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.isQuotationMode
                      ? Icons.request_quote_outlined
                      : Icons.calculate_outlined,
                  color: brandRed,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isQuotationMode
                        ? 'Quotations Console'
                        : 'Netrate Calculator',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    widget.isQuotationMode
                        ? 'Enterprise Pricing & Trade Availability Quotation'
                        : 'Real-time Net Rate Computation with SD & Live Surcharges',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd MMM yyyy').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          _headerAction(Icons.home_outlined, _onHomePressed, isDark),
          const SizedBox(width: 8),
          _headerAction(Icons.restart_alt_rounded, _clearAll, isDark,
              isDanger: true),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildMobileBody(double totalAmt, double totalQty, bool isDark,
      Color brandRed, Color cardColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModernSettingsCard(isDark, brandRed, cardColor),
          const SizedBox(height: 14),
          if (widget.isQuotationMode) ...[
            _buildModernPartyCard(isDark, brandRed, cardColor),
            const SizedBox(height: 14),
          ],
          _buildProductHeader(isDark),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((e) =>
              _buildItemCard(e.value, e.key, isDark, brandRed, cardColor)),
          const SizedBox(height: 14),
          _buildAddItemButton(brandRed),
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
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildModernSettingsCard(isDark, brandRed, cardColor),
                    const SizedBox(height: 16),
                    if (widget.isQuotationMode) ...[
                      _buildModernPartyCard(isDark, brandRed, cardColor),
                      const SizedBox(height: 16),
                    ],
                    _buildProductHeader(isDark),
                    const SizedBox(height: 14),
                    ...items.asMap().entries.map((e) => _buildItemCard(
                        e.value, e.key, isDark, brandRed, cardColor)),
                    const SizedBox(height: 16),
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

  Widget _headerAction(IconData icon, VoidCallback onTap, bool isDark,
      {bool isDanger = false}) {
    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDanger
              ? const Color(0xFFD32F2F).withValues(alpha: 0.1)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDanger
                ? const Color(0xFFD32F2F).withValues(alpha: 0.3)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Icon(
          icon,
          color: isDanger
              ? const Color(0xFFD32F2F)
              : (isDark ? Colors.white : const Color(0xFF1E293B)),
          size: 18,
        ),
      ),
      onPressed: onTap,
    );
  }

  Widget _buildModernSettingsCard(
      bool isDark, Color brandRed, Color cardColor) {
    return Container(
      decoration: _standardCardDeco(isDark),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.tune_rounded, "Pricing & Charges", brandRed, isDark),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _modernTextInput(
                  "Freight (₹/MT)",
                  _freightCtrl,
                  (v) => globalFreight = double.tryParse(v) ?? 0,
                  brandRed,
                  isDark,
                  isNumber: true,
                  prefixText: "₹ ",
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _modernTextInput(
                  "OB / Other Billing (₹/MT)",
                  _obCtrl,
                  (v) => globalOB = double.tryParse(v) ?? 0,
                  brandRed,
                  isDark,
                  isNumber: true,
                  prefixText: "₹ ",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernPartyCard(bool isDark, Color brandRed, Color cardColor) {
    return Container(
      decoration: _standardCardDeco(isDark),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.business_outlined, "Party Information", brandRed, isDark),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 480;
              final partyInput = _modernTextInput(
                "Party / Firm Name",
                _customerNameCtrl,
                (v) {},
                brandRed,
                isDark,
                isNumber: false,
                hintText: "Enter client or firm name",
              );
              final contactInput = _modernTextInput(
                "Contact Number",
                _contactNumberCtrl,
                (v) {},
                brandRed,
                isDark,
                isNumber: true,
                isPhone: true,
                hintText: "10-digit mobile",
              );

              if (isNarrow) {
                return Column(
                  children: [
                    partyInput,
                    const SizedBox(height: 12),
                    contactInput,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: partyInput),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: contactInput),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductHeader(bool isDark) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFD32F2F),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Configured Products & Sizes",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              letterSpacing: -0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            "${items.length} ${items.length == 1 ? 'Product' : 'Products'}",
            style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddItemButton(Color brandRed) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: itemList.isEmpty ? null : _showAddItemBottomSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: brandRed.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: brandRed.withValues(alpha: 0.25),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, color: brandRed, size: 20),
            const SizedBox(width: 8),
            Text(
              "Add Another Product",
              style: TextStyle(
                color: brandRed,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
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
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: brandRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.isQuotationMode
                                ? Icons.receipt_long_rounded
                                : Icons.calculate_rounded,
                            color: brandRed,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.isQuotationMode
                                ? "Quotation Summary"
                                : "Net Rate Summary",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _summaryRow(
                            widget.isQuotationMode
                                ? "Quotation Total"
                                : "Total Computed Rate",
                            "₹ ${formatIndianCurrency(totalAmt)}",
                            isDark,
                            false,
                          ),
                          const SizedBox(height: 10),
                          _summaryRow(
                            "Total Quantity",
                            "${totalQty.toStringAsFixed(3)} MT",
                            isDark,
                            false,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          Text(
                            widget.isQuotationMode
                                ? "TOTAL QUOTATION ESTIMATE"
                                : "NET COMPUTED ESTIMATE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "₹ ${formatIndianCurrency(totalAmt)}",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: brandRed,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandRed,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: Text(
                        widget.isQuotationMode
                            ? "PREVIEW & SHARE QUOTE"
                            : "GENERATE & COPY RATE",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      onPressed: () => widget.isQuotationMode
                          ? _showPreviewDialog()
                          : _showPreview(),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(
                          color: Color(0xFF25D366),
                          width: 1.2,
                        ),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        "Share via WhatsApp",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        final msg = _generateMessageText();
                        safeShare(context, msg);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileStickyBar(double totalAmt, double totalQty, bool isDark,
      Color brandRed, Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
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
                  Text(
                    "${totalQty.toStringAsFixed(3)} MT • Estimate",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "₹ ${formatIndianCurrency(totalAmt)}",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandRed,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(
                widget.isQuotationMode ? "Preview" : "Generate",
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              onPressed:
                  widget.isQuotationMode ? _showPreviewDialog : _showPreview,
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _standardCardDeco(bool isDark) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      ),
      boxShadow: isDark
          ? []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  Widget _sectionHeader(
      IconData icon, String title, Color brandRed, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: brandRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: brandRed, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _modernTextInput(
    String label,
    TextEditingController controller,
    Function(String) onChanged,
    Color brandRed,
    bool isDark, {
    bool isNumber = false,
    bool isPhone = false,
    String? prefixText,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      maxLength: isPhone ? 10 : null,
      onChanged: (v) {
        onChanged(v);
        setState(() {});
      },
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1E293B),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        prefixStyle: TextStyle(
          color: isDark ? Colors.white70 : const Color(0xFF64748B),
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
          fontSize: 12,
        ),
        filled: true,
        isDense: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFC),
        counterText: "",
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brandRed, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildItemCard(
      ItemEntry item, int index, bool isDark, Color brandRed, Color cardColor) {
    double itemTotalQty = 0;
    double itemTotalAmt = 0;

    for (var s in item.selectedSizes) {
      itemTotalQty += s.qty;
      itemTotalAmt += netRate(item, s) * s.qty;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        final categoryDropdown = DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: item.itemName,
          dropdownColor: cardColor,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: brandRed),
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            labelText: 'Product Category',
            isDense: true,
            labelStyle: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : const Color(0xFFF8FAFC),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: brandRed, width: 1.5),
            ),
          ),
          items: itemList
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              item.itemName = v;
              item.selectedSizes.clear();
            });
          },
        );

        final baseRateInput = _modernTextInput(
          "Base Rate (₹)",
          item.basicCtrl,
          (v) => setState(() => item.basic = double.tryParse(v) ?? 0),
          brandRed,
          isDark,
          isNumber: true,
          prefixText: "₹ ",
        );

        final deleteProductBtn = Container(
          decoration: BoxDecoration(
            color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFD32F2F),
              size: 20,
            ),
            tooltip: "Delete Product",
            onPressed: () => setState(() => items.removeAt(index)),
          ),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: _standardCardDeco(isDark),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: index == items.length - 1,
              iconColor: brandRed,
              collapsedIconColor:
                  isDark ? Colors.white54 : const Color(0xFF64748B),
              tilePadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 18,
                vertical: isMobile ? 4 : 8,
              ),
              leading: Container(
                decoration: BoxDecoration(
                  color: brandRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  _getItemIconPath(item.itemName),
                  fit: BoxFit.cover,
                  width: isMobile ? 22 : 24,
                  height: isMobile ? 22 : 24,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.inventory_2_outlined,
                    color: brandRed,
                    size: isMobile ? 18 : 20,
                  ),
                ),
              ),
              title: Text(
                item.itemName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: isMobile ? 15 : 16,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (widget.isQuotationMode) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "${itemTotalQty.toStringAsFixed(3)} MT",
                          style: const TextStyle(
                            color: Color(0xFF0284C7),
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "₹ ${formatIndianCurrency(itemTotalAmt)}",
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ] else ...[
                      Text(
                        "@ ₹${formatIndianCurrency(item.basic)} Base • ${item.selectedSizes.length} sizes",
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              childrenPadding: EdgeInsets.fromLTRB(
                isMobile ? 14 : 18,
                0,
                isMobile ? 14 : 18,
                isMobile ? 14 : 18,
              ),
              children: [
                Divider(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                  height: 16,
                ),
                LayoutBuilder(
                  builder: (context, inputConstraints) {
                    final isNarrow = inputConstraints.maxWidth < 450;
                    if (isNarrow) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: categoryDropdown),
                              const SizedBox(width: 8),
                              deleteProductBtn,
                            ],
                          ),
                          const SizedBox(height: 10),
                          baseRateInput,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 3, child: categoryDropdown),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: baseRateInput),
                        const SizedBox(width: 8),
                        deleteProductBtn,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                if (item.selectedSizes.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: widget.isQuotationMode ? 460 : 300,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 110,
                                  child: Text(
                                    "SIZE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 85,
                                  child: Text(
                                    "NET RATE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (widget.isQuotationMode) ...[
                                  if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
                                      .contains(item.itemName))
                                    const SizedBox(
                                      width: 60,
                                      child: Text(
                                        "NOS",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                          color: Color(0xFF64748B),
                                          letterSpacing: 0.4,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  const SizedBox(
                                    width: 75,
                                    child: Text(
                                      "QTY (MT)",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                        letterSpacing: 0.4,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 85,
                                    child: Text(
                                      "AMOUNT",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                        letterSpacing: 0.4,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 28),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...item.selectedSizes.asMap().entries.map(
                                (entry) => _buildSizeRow(
                                    item, entry.key, entry.value, isDark, brandRed),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _buildAddSizeButton(item, brandRed),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSizeRow(
      ItemEntry item, int sizeIndex, SizeEntry s, bool isDark, Color brandRed) {
    final rate = netRate(item, s);
    final int amount = (rate * s.qty).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: InkWell(
              onTap: () => _showAddSizeBottomSheet(item, existingSize: s),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (() {
                          final double w = s.unitWeight;
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
                          fontWeight: FontWeight.w700,
                          color: brandRed,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.edit_outlined,
                      color: brandRed.withValues(alpha: 0.6),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 85,
            child: Text(
              "₹ ${formatIndianCurrency(rate.roundToDouble())}",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ),
          if (widget.isQuotationMode) ...[
            if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
                .contains(item.itemName))
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: TextField(
                  controller: s.nosCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    s.nos = int.tryParse(v) ?? 0;
                    _recalcQtyFromNos(s);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: "0",
                    isDense: true,
                    hintStyle: TextStyle(
                      color:
                          isDark ? Colors.white24 : const Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: brandRed, width: 1.5),
                    ),
                  ),
                ),
              ),
            Container(
              width: 75,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: TextField(
                controller: s.qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
                textAlign: TextAlign.center,
                onChanged: (v) {
                  s.qty = double.tryParse(v) ?? 0;
                  _recalcNosFromQty(s);
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: "0.000",
                  isDense: true,
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: brandRed, width: 1.5),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 85,
              child: Text(
                "₹ ${formatIndianCurrency(amount.toDouble())}",
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            onPressed: () =>
                setState(() => item.selectedSizes.removeAt(sizeIndex)),
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF94A3B8),
              size: 16,
            ),
            tooltip: "Remove Size",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSizeButton(ItemEntry item, Color brandRed) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          backgroundColor: brandRed.withValues(alpha: 0.06),
        ),
        onPressed: () => _showAddSizeBottomSheet(item),
        icon: Icon(Icons.add_rounded, color: brandRed, size: 16),
        label: Text(
          "Add Size Dimension",
          style: TextStyle(
            color: brandRed,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
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
          backgroundColor: const Color(0xFFD32F2F),
        ),
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
