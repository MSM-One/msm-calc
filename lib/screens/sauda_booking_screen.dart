import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/global_view_wrapper.dart';
import '../constants/app_colors.dart';
import '../utils/steel_helper.dart';
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../widgets/responsive_size_picker.dart';
import '../widgets/motion_toast.dart';
import '../models/delivery_order_model.dart';
import '../widgets/delivery_order_dialog.dart';
import '../services/data_repository.dart';

class SaudaBookingScreen extends StatefulWidget {
  const SaudaBookingScreen({super.key});

  @override
  State<SaudaBookingScreen> createState() => _SaudaBookingScreenState();
}

class _SaudaBookingScreenState extends State<SaudaBookingScreen> {
  final TextEditingController firmNameCtrl = TextEditingController();
  final TextEditingController vehicleCtrl = TextEditingController();
  final TextEditingController remarksCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  DateTime bookingDate = DateTime.now();
  String _documentTitle = 'SAUDA BOOK / DELIVERY ORDER';
  List<SaudaItem> items = [];

  @override
  void initState() {
    super.initState();

    // --- Hard Navigation Guard ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AccessGuard.cannot(AppPermissions.screensSaudaBooking)) {
        MotionToast.show(context, "Access Denied: Missing Permission",
            isError: true);
        if (mounted) Navigator.pop(context);
      }
    });

    _loadSavedData();
    // Pre-fetch inventory data & warm up lookup caches
    final provider = context.read<InventoryProvider>();
    provider.loadSaudaData();
    DataRepository.ensureMasterLookupData();

    _dateCtrl.text = DateFormat('dd MMM yyyy').format(bookingDate);
    if (items.isEmpty) addItem();
  }

  @override
  void dispose() {
    firmNameCtrl.dispose();
    vehicleCtrl.dispose();
    remarksCtrl.dispose();
    _dateCtrl.dispose();
    for (var item in items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      firmNameCtrl.text = prefs.getString('sauda_firm') ?? "";
      vehicleCtrl.text = prefs.getString('sauda_vehicle') ?? "";
      remarksCtrl.text = prefs.getString('sauda_remarks') ?? "";
      _documentTitle = prefs.getString('sauda_document_title') ??
          'SAUDA BOOK / DELIVERY ORDER';
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sauda_firm', firmNameCtrl.text);
    await prefs.setString('sauda_vehicle', vehicleCtrl.text);
    await prefs.setString('sauda_remarks', remarksCtrl.text);
    await prefs.setString('sauda_document_title', _documentTitle);
  }

  void addItem() {
    setState(() {
      items.add(SaudaItem(key: UniqueKey()));
    });
  }

  void removeItem(int index) {
    setState(() {
      items.removeAt(index);
    });
  }

  double getTotalEffectiveQty() {
    double total = 0;
    for (var item in items) {
      if (item.isPiecesItem()) continue;
      total += item.getTotalQty();
    }
    return total;
  }

  String _generateSaudaMessage(bool includeDetails) {
    String dateStr = DateFormat('dd/MM/yyyy').format(bookingDate);
    String effQty = getTotalEffectiveQty().toStringAsFixed(3);
    StringBuffer msg = StringBuffer();
    msg.writeln("*Sauda Booking*");
    msg.writeln("Date: $dateStr");
    msg.writeln("*Firm: ${firmNameCtrl.text}*");
    if (vehicleCtrl.text.isNotEmpty) {
      msg.writeln("Vehicle No.: ${vehicleCtrl.text.toUpperCase()}");
    }
    msg.writeln("*Total Qty (MT): $effQty MT*");
    msg.writeln("");

    for (int i = 0; i < items.length; i++) {
      var item = items[i];
      if (item.itemType == null ||
          (item.getTotalQty() == 0 && !item.manualMode)) {
        continue;
      }
      String unit = item.isPiecesItem() ? "Pcs" : "MT";
      String totalQtyStr =
          item.getTotalQty().toStringAsFixed(item.isPiecesItem() ? 0 : 3);
      msg.writeln("*Item #${i + 1}: ${item.itemType}*");
      msg.writeln("Order Type: *${item.orderType ?? '-'}*");
      if (item.rateType != null) msg.writeln("Rate Type: ${item.rateType}");
      if (item.rate > 0) msg.writeln("Rate: ${item.rate.toStringAsFixed(0)}");
      if (item.basicRate > 0) {
        msg.writeln("Basic Rate (Auto): ${item.basicRate.toStringAsFixed(2)}");
      }
      msg.writeln("*Total Qty: $totalQtyStr $unit*");

      if (includeDetails) {
        if (item.manualMode) {
          msg.writeln("Manual Qty Entry: $totalQtyStr $unit");
        } else {
          for (int j = 0; j < item.sizes.length; j++) {
            var s = item.sizes[j];
            if (s.size.isEmpty) continue;
            String label = s.sizeDescriptionLabel(item.itemType);
            if (item.isPiecesItem()) {
              msg.writeln(
                  "• $label x ${s.nos.toStringAsFixed(0)} = ${s.total.toStringAsFixed(0)} Pcs"
                      .replaceAll("nullkg", "")
                      .replaceAll(" kg", "kg")
                      .replaceAll("  ", " ")
                      .trim());
            } else {
              String nosLabel = (item.itemType == "Binding Wire")
                  ? "Bundles"
                  : (item.itemType == "Nails")
                      ? "Bags"
                      : "Nos";
              msg.writeln(
                  "• $label x ${s.nos.toStringAsFixed(0)} $nosLabel = ${s.total.toStringAsFixed(3)} MT"
                      .replaceAll("nullkg", "")
                      .replaceAll(" kg", "kg")
                      .replaceAll("  ", " ")
                      .trim());
            }
          }
        }
      }
      msg.writeln("──────────────────");
    }

    if (remarksCtrl.text.isNotEmpty) {
      msg.writeln("\n*Remarks:*");
      msg.writeln(remarksCtrl.text);
    }

    msg.writeln("\nThank you for choosing Metaroll!");
    return msg.toString();
  }

  DeliveryOrderDataModel _buildDeliveryOrderModel() {
    final String dateStr = DateFormat('yyyy-MM-dd').format(bookingDate);
    final String safeLorry =
        vehicleCtrl.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final String autoPoNo =
        "DO-${DateFormat('yyyyMMdd').format(bookingDate)}-${safeLorry.isNotEmpty ? safeLorry : '01'}";

    // Detect overall bill type
    String detectedBillType = "BILL";
    for (var item in items) {
      if (item.orderType != null && item.orderType!.toUpperCase() == "NC") {
        detectedBillType = "NC";
        break;
      }
    }

    final List<DeliveryOrderItemModel> deliveryItems = [];

    for (var item in items) {
      if (item.itemType == null) continue;
      final List<DeliveryOrderSizeModel> sizeModels = [];

      if (item.manualMode) {
        if (item.manualQty > 0) {
          sizeModels.add(
            DeliveryOrderSizeModel(
              size: "Manual Quantity",
              qty: item.manualQty,
              rate: item.rate > 0 ? item.rate : item.basicRate,
              bd: "${item.manualQty.toStringAsFixed(3)} MT",
              nos: 1,
              unitWeight: 0,
            ),
          );
        }
      } else {
        for (var s in item.sizes) {
          if (s.size.isEmpty && s.total <= 0 && s.nos <= 0) continue;
          double qty = s.total;
          double nos = s.nos;
          double weight = s.weight;
          if (weight <= 0) {
            weight = SteelHelper.extractWeightKg(s.size,
                category: item.itemType);
          }
          String bdStr = "";
          if (item.isPiecesItem()) {
            bdStr = "${nos.toStringAsFixed(0)} Pcs";
          } else {
            String nosUnit = (item.itemType == "Binding Wire")
                ? "Bundles"
                : (item.itemType == "Nails")
                    ? "Bags"
                    : "Pcs";
            bdStr =
                "${nos.toStringAsFixed(0)} $nosUnit x ${weight.toStringAsFixed(2)} kg = ${qty.toStringAsFixed(3)} MT";
          }

          sizeModels.add(
            DeliveryOrderSizeModel(
              size: s.sizeDescriptionLabel(item.itemType),
              qty: qty,
              rate: item.rate > 0 ? item.rate : item.basicRate,
              bd: bdStr,
              nos: nos,
              unitWeight: weight,
            ),
          );
        }
      }

      if (sizeModels.isNotEmpty || item.getTotalQty() > 0) {
        String itemRateType = "";
        if (item.orderType != null && item.orderType!.isNotEmpty) {
          if (item.rateType != null && item.rateType!.isNotEmpty) {
            itemRateType = "${item.orderType} | ${item.rateType}";
          } else {
            itemRateType = item.orderType!;
          }
        } else if (item.rateType != null && item.rateType!.isNotEmpty) {
          itemRateType = item.rateType!;
        } else {
          itemRateType = detectedBillType;
        }

        deliveryItems.add(
          DeliveryOrderItemModel(
            item: item.itemType!,
            saudaRate: item.rate > 0
                ? item.rate
                : (item.basicRate > 0 ? item.basicRate : "-"),
            rateType: itemRateType,
            balanceQty: item.getTotalQty(),
            sizes: sizeModels,
          ),
        );
      }
    }

    return DeliveryOrderDataModel(
      documentTitle: _documentTitle,
      poNo: autoPoNo,
      poDate: dateStr,
      dealerName: firmNameCtrl.text.trim(),
      billingName: firmNameCtrl.text.trim(),
      billingAddress: "",
      consigneeName: firmNameCtrl.text.trim(),
      dispatchAddress: "",
      orderDate: dateStr,
      billType: detectedBillType,
      ob: "",
      freight: "To Pay",
      lorryNo: vehicleCtrl.text.trim().toUpperCase(),
      note: remarksCtrl.text.trim(),
      signedBy: "",
      approvedBy: "",
      items: deliveryItems,
    );
  }

  void _showDeliveryOrderPrintDialog() {
    if (firmNameCtrl.text.trim().isEmpty) {
      MotionToast.show(context, "Please enter Firm Name before printing",
          isError: true);
      return;
    }
    _saveData();
    final model = _buildDeliveryOrderModel();
    DeliveryOrderPrintDialog.show(context, model: model);
  }

  void _showPreviewDialog(bool forDetails) {
    if (firmNameCtrl.text.isEmpty) {
      MotionToast.show(context, "Please enter Firm Name", isError: true);
      return;
    }
    _saveData();
    showDialog(
        context: context,
        builder: (context) {
          bool showDetails = forDetails;
          return StatefulBuilder(builder: (context, setDialogState) {
            String message = _generateSaudaMessage(showDetails);
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(20),
                height: 550,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Preview Order",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: textDark)),
                            Switch(
                                value: showDetails,
                                activeThumbColor: msmRed,
                                onChanged: (val) {
                                  setDialogState(() => showDetails = val);
                                })
                          ]),
                      const Text(
                          "Toggle switch to show/hide item size breakdown",
                          style: TextStyle(color: textGrey, fontSize: 11.5)),
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 10),
                      Expanded(
                          child: SingleChildScrollView(
                              child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0))),
                                  child: Text(message,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.45,
                                          color: textDark))))),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: textDark,
                                    side: const BorderSide(
                                        color: Color(0xFFD1D5DB)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10))),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text("Copy",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: message));
                                  MotionToast.show(
                                      context, "Copied to clipboard!");
                                })),
                        const SizedBox(width: 8),
                        Expanded(
                            child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    elevation: 0),
                                icon: const Icon(Icons.share_rounded, size: 16),
                                label: const Text("Share",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.pop(context);
                                  safeShare(context, message);
                                })),
                        const SizedBox(width: 8),
                        Expanded(
                            child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: msmRed,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    elevation: 0),
                                icon: const Icon(Icons.print_rounded, size: 16),
                                label: const Text("Print",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showDeliveryOrderPrintDialog();
                                })),
                      ]),
                      const SizedBox(height: 8),
                      Center(
                          child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Close",
                                  style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13)))),
                    ]),
              ),
            );
          });
        });
  }

  void _recalcMTFromNos(SaudaItem item, SaudaSize size) {
    if (item.isPiecesItem()) {
      size.total = size.nos;
      size.mtCtrl.text = size.total > 0 ? size.total.toStringAsFixed(0) : "";
      return;
    }
    double w = size.weight;
    if (w <= 0) {
      w = SteelHelper.extractWeightKg(size.size, category: item.itemType);
    }
    if (w <= 0) {
      size.total = 0;
      size.mtCtrl.text = '';
      return;
    }
    size.total = (size.nos * w) / 1000.0;
    size.mtCtrl.text = size.total == 0 ? '' : size.total.toStringAsFixed(3);
  }

  void _recalcNosFromMT(SaudaItem item, SaudaSize size) {
    if (item.isPiecesItem()) {
      size.nos = size.total;
      size.nosCtrl.text = size.nos > 0 ? size.nos.toStringAsFixed(0) : "";
      return;
    }
    double w = size.weight;
    if (w <= 0) {
      w = SteelHelper.extractWeightKg(size.size, category: item.itemType);
    }
    if (w <= 0) {
      size.nos = 0;
      size.nosCtrl.text = '';
      return;
    }
    size.nos = ((size.total * 1000) / w).roundToDouble();
    size.nosCtrl.text = size.nos == 0 ? '' : size.nos.toStringAsFixed(0);
  }

  void _resetForm() {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                title: const Row(
                  children: [
                    Icon(Icons.refresh_rounded, color: Color(0xFFDC2626)),
                    SizedBox(width: 8),
                    Text("Reset Form?",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: const Text(
                  "This will clear all booking line items and firm details.",
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel",
                          style: TextStyle(color: Color(0xFF64748B)))),
                  ElevatedButton(
                      onPressed: () {
                        setState(() {
                          items.clear();
                          addItem();
                          firmNameCtrl.clear();
                          vehicleCtrl.clear();
                          remarksCtrl.clear();
                          bookingDate = DateTime.now();
                          _dateCtrl.text =
                              DateFormat('dd MMM yyyy').format(bookingDate);
                        });
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Reset"))
                ]));
  }

  @override
  Widget build(BuildContext context) {
    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        extendBodyBehindAppBar: false,
        appBar: _buildModernAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth > 920;
            bool isMobile = constraints.maxWidth < 600;
            return SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 14 : 24, vertical: 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Basic Details Section
                              _buildSectionCard(
                                title: "Basic Details",
                                icon: Icons.assignment_outlined,
                                child: _buildBasicDetailsFields(isMobile),
                              ),
                              const SizedBox(height: 16),

                              // Items & Rates Section Header
                              _buildSectionTitle("Items & Rates"),
                              const SizedBox(height: 8),

                              // Item Cards List
                              ...items.asMap().entries.map(
                                  (e) => _buildSaudaItemCard(e.value, e.key)),

                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 16),
                                child: _buildAddItemButton(),
                              ),

                              // Other Details / Remarks Section
                              _buildSectionCard(
                                title: "Other Details",
                                icon: Icons.notes_rounded,
                                child: TextField(
                                  controller: remarksCtrl,
                                  maxLines: 3,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF0F172A)),
                                  decoration: msmInputDeco(
                                      "Remarks / Instructions",
                                      hint:
                                          "Optional delivery, terms, or transport notes"),
                                  onChanged: (_) => _saveData(),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isDesktop) _buildSummarySidebar(),
                ],
              ),
            );
          },
        ),
        bottomNavigationBar: MediaQuery.of(context).size.width <= 920
            ? _buildMobileFooter()
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 0,
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
      title: const Text(
        "Sauda & Delivery Order",
        style: TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: Color(0xFF475569), size: 20),
          tooltip: "Reset Form",
          onPressed: _resetForm,
        ),
        const SizedBox(width: 8),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    IconData icon = Icons.info_outline,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: msmRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      fontSize: 13.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _buildBasicDetailsFields(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDocumentTitleSelector(),
        const SizedBox(height: 12),
        if (isMobile) ...[
          InkWell(
            onTap: () => _pickDate(),
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: msmInputDeco(
                "Booking Date",
                prefix: const Icon(Icons.calendar_month_outlined,
                    size: 16, color: msmRed),
              ),
              child: Text(
                _dateCtrl.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: vehicleCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: msmInputDeco(
              "Vehicle / Lorry No.",
              prefix: const Icon(Icons.local_shipping_outlined,
                  size: 16, color: Color(0xFF64748B)),
              hint: "e.g. MH-20-DE-1234",
            ),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
            onChanged: (_) => _saveData(),
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(),
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: msmInputDeco(
                      "Booking Date",
                      prefix: const Icon(Icons.calendar_month_outlined,
                          size: 16, color: msmRed),
                    ),
                    child: Text(
                      _dateCtrl.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: vehicleCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: msmInputDeco(
                    "Vehicle / Lorry No.",
                    prefix: const Icon(Icons.local_shipping_outlined,
                        size: 16, color: Color(0xFF64748B)),
                    hint: "e.g. MH-20-DE-1234",
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                  onChanged: (_) => _saveData(),
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        TextField(
          controller: firmNameCtrl,
          decoration: msmInputDeco(
            "Firm / Customer Name",
            prefix: const Icon(Icons.business_outlined,
                size: 16, color: Color(0xFF64748B)),
            hint: "Enter client firm name",
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          onChanged: (_) => _saveData(),
        ),
      ],
    );
  }

  void _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: bookingDate.isAfter(today) ? now : bookingDate,
      firstDate: DateTime(2020),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: msmRed,
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        bookingDate = picked;
        _dateCtrl.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  Widget _buildSummarySidebar() {
    double totalQty = getTotalEffectiveQty();
    return Container(
      width: 380,
      height: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 16, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSidebarHeader(totalQty),
          Expanded(child: _buildSidebarItemList()),
          _buildSidebarFooter(),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(double totalQty) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Booking Summary",
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  "Total Quantity",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  "${totalQty.toStringAsFixed(3)} MT",
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItemList() {
    final activeItems = items.where((i) => i.itemType != null).toList();
    if (activeItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 40, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text(
              "No items added yet",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activeItems.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        final item = activeItems[index];
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                _getItemIconPath(item.itemType!),
                width: 20,
                height: 20,
                errorBuilder: (ctx, err, st) =>
                    const Icon(Icons.category, color: msmRed, size: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemType!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    "${item.orderType ?? '-'} | ${item.rateType ?? '-'}",
                    style:
                        const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              "${item.getTotalQty().toStringAsFixed(3)} ${item.isPiecesItem() ? 'Pcs' : 'MT'}",
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: msmRed,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebarFooter() {
    final double totalQty = getTotalEffectiveQty();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    "Total Booked Tonnage",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${totalQty.toStringAsFixed(3)} MT",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: msmRed,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: msmRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text(
              "Print Delivery Order",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            onPressed: _showDeliveryOrderPrintDialog,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.share_outlined, size: 15),
            label: const Text(
              "Share Order Text",
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            onPressed: () => _showPreviewDialog(true),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFooter() {
    final double totalQty = getTotalEffectiveQty();
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 8, 14, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          )
        ],
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sleek Tonnage Summary Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    "Total Quantity Booked",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: msmRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${totalQty.toStringAsFixed(3)} MT",
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: msmRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Balanced Action Buttons Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.share_outlined, size: 14),
                  onPressed: () => _showPreviewDialog(true),
                  label: const Text(
                    "Share Order",
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: msmRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.print_rounded, size: 15),
                  onPressed: _showDeliveryOrderPrintDialog,
                  label: const Text(
                    "Print Order",
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTitleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Document Title for Print",
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _documentTitle,
          decoration: msmInputDeco(
            "Print Title",
            prefix: const Icon(Icons.print_outlined, size: 16, color: msmRed),
          ),
          dropdownColor: Colors.white,
          items: const [
            DropdownMenuItem(
              value: 'SAUDA BOOK / DELIVERY ORDER',
              child: Text(
                'SAUDA BOOK / DELIVERY ORDER (Default)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'DELIVERY ORDER',
              child: Text(
                'DELIVERY ORDER',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'SAUDA BOOK',
              child: Text(
                'SAUDA BOOK',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _documentTitle = val);
              _saveData();
            }
          },
        ),
      ],
    );
  }

  Widget _buildAddItemButton() {
    return OutlinedButton.icon(
      onPressed: addItem,
      icon: const Icon(Icons.add_circle_outline, size: 16, color: msmRed),
      label: const Text("+ Add Material Item",
          style: TextStyle(
              color: msmRed, fontWeight: FontWeight.bold, fontSize: 12.5)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 42),
        side: BorderSide(color: msmRed.withValues(alpha: 0.3), width: 1.2),
        backgroundColor: msmRed.withValues(alpha: 0.02),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            color: msmRed,
            borderRadius: BorderRadius.circular(2),
          ),
          margin: const EdgeInsets.only(right: 8),
        ),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            fontSize: 14.5,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  void _openItemPicker(SaudaItem item) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: const SaudaItemPicker(),
        );
      },
    ).then((v) {
      if (v != null && mounted) {
        final provider = context.read<InventoryProvider>();
        setState(() {
          item.itemType = v;
          item.calculateAll(provider.sheetLoading, provider.sheetGst);
        });
      }
    });
  }

  Widget _buildSaudaItemCard(SaudaItem item, int index) {
    final bool hasProduct = item.itemType != null && item.itemType!.isNotEmpty;
    final String unit = item.isPiecesItem() ? 'Pcs' : 'MT';
    final double totalQty = item.getTotalQty();
    final String totalStr = item.isPiecesItem()
        ? totalQty.toStringAsFixed(0)
        : totalQty.toStringAsFixed(3);
    final String titleText =
        hasProduct ? item.itemType! : "Tap to select product";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: index == items.length - 1,
            leading: InkWell(
              onTap: () => _openItemPicker(item),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(
                  _getItemIconPath(item.itemType ?? ""),
                  width: 22,
                  height: 22,
                  errorBuilder: (ctx, err, st) =>
                      const Icon(Icons.category, color: msmRed, size: 18),
                ),
              ),
            ),
            title: InkWell(
              onTap: !hasProduct ? () => _openItemPicker(item) : null,
              child: Text(
                titleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: hasProduct ? const Color(0xFF0F172A) : msmRed,
                ),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: hasProduct
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: totalQty > 0
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: totalQty > 0
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFFE2E8F0),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          "$totalStr $unit",
                          style: TextStyle(
                            color: totalQty > 0
                                ? const Color(0xFF065F46)
                                : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    )
                  : const Text(
                      "Tap to choose item category",
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasProduct)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded,
                        color: msmRed, size: 18),
                    tooltip: "Change Product",
                    onPressed: () => _openItemPicker(item),
                  ),
                if (index > 0)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626), size: 18),
                    tooltip: "Remove Item",
                    onPressed: () => removeItem(index),
                  ),
                const Icon(Icons.expand_more_rounded,
                    color: Color(0xFF64748B)),
              ],
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              // Row 1: Order Type & Rate Type
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: item.orderType,
                      decoration: msmInputDeco("Order Type"),
                      items: ["Bill", "NC"]
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600))))
                          .toList(),
                      onChanged: (v) {
                        final provider = context.read<InventoryProvider>();
                        setState(() {
                          item.orderType = v;
                          item.calculateAll(
                              provider.sheetLoading, provider.sheetGst);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: item.rateType,
                      decoration: msmInputDeco("Rate Type"),
                      items: ["Basic", "Net"]
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600))))
                          .toList(),
                      onChanged: (v) {
                        final provider = context.read<InventoryProvider>();
                        setState(() {
                          item.rateType = v;
                          item.calculateAll(
                              provider.sheetLoading, provider.sheetGst);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: Rate & Basic (Auto)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: item.rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                      decoration: msmInputDeco("Rate (₹)"),
                      onChanged: (v) {
                        final provider = context.read<InventoryProvider>();
                        item.rate = double.tryParse(v) ?? 0;
                        item.calculateAll(
                            provider.sheetLoading, provider.sheetGst);
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InputDecorator(
                      decoration: msmInputDeco("Basic (Auto)"),
                      child: Text(
                        item.basicRate > 0
                            ? "₹ ${item.basicRate.toStringAsFixed(2)}"
                            : "-",
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 3: Manual Total Qty toggle
              LayoutBuilder(builder: (context, constraints) {
                final narrow = constraints.maxWidth < 340;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Manual Total Qty?",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          Switch(
                            value: item.manualMode,
                            activeThumbColor: msmRed,
                            onChanged: (v) =>
                                setState(() => item.manualMode = v),
                          ),
                        ],
                      ),
                      if (item.manualMode)
                        TextField(
                          enabled: item.manualMode,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                          decoration: msmInputDeco("Manual Qty ($unit)"),
                          onChanged: (v) => setState(
                              () => item.manualQty = double.tryParse(v) ?? 0),
                        ),
                    ],
                  );
                }
                return Row(
                  children: [
                    const Text(
                      "Manual Total Qty?",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    Switch(
                      value: item.manualMode,
                      activeThumbColor: msmRed,
                      onChanged: (v) =>
                          setState(() => item.manualMode = v),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        enabled: item.manualMode,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                        decoration: msmInputDeco("Manual Qty ($unit)"),
                        onChanged: (v) => setState(
                            () => item.manualQty = double.tryParse(v) ?? 0),
                      ),
                    ),
                  ],
                );
              }),

              if (!item.manualMode) ...[
                const Divider(height: 20, color: Color(0xFFE2E8F0)),
                // Table Header
                Row(
                  children: [
                    const Expanded(
                      flex: 4,
                      child: Text(
                        "Size",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        "MT",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      flex: 2,
                      child: Text(
                        item.itemType == "Binding Wire"
                            ? "Bdls"
                            : item.itemType == "Nails"
                                ? "Bags"
                                : "Nos",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        "Total",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
                const SizedBox(height: 6),
                ...item.sizes.asMap().entries.map((e) {
                  int sIdx = e.key;
                  SaudaSize size = e.value;
                  return Padding(
                    key: ObjectKey(size),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: InkWell(
                            onTap: () => _showSizePicker(item, size),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      size.size.isEmpty
                                          ? "Select Size"
                                          : size.sizeDescriptionLabel(
                                              item.itemType),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: size.size.isEmpty
                                            ? textGrey
                                            : msmRed,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.edit_outlined,
                                      color: msmRed, size: 12),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 34),
                            child: TextField(
                              controller: size.mtCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600),
                              decoration: msmTableInputDeco(hint: "0.000"),
                              onChanged: (v) {
                                final provider =
                                    context.read<InventoryProvider>();
                                setState(() {
                                  size.total = double.tryParse(v) ?? 0;
                                  _recalcNosFromMT(item, size);
                                  item.calculateAll(provider.sheetLoading,
                                      provider.sheetGst);
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 34),
                            child: TextField(
                              controller: size.nosCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600),
                              decoration: msmTableInputDeco(hint: "0"),
                              onChanged: (v) {
                                final provider =
                                    context.read<InventoryProvider>();
                                setState(() {
                                  size.nos = double.tryParse(v) ?? 0;
                                  _recalcMTFromNos(item, size);
                                  item.calculateAll(provider.sheetLoading,
                                      provider.sheetGst);
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: Text(
                            size.total.toStringAsFixed(3),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () =>
                              setState(() => item.sizes.removeAt(sIdx)),
                          child: const Icon(Icons.remove_circle_outline,
                              color: msmRed, size: 16),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => item.sizes.add(SaudaSize())),
                    icon: const Icon(Icons.add_circle_outline,
                        size: 14, color: msmRed),
                    label: const Text(
                      "Add Size",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: msmRed,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showSizePicker(SaudaItem item, SaudaSize sizeObj) async {
    if (item.itemType == null) {
      MotionToast.show(context, "Please select an Item Type first",
          isError: true);
      return;
    }
    final v =
        await ResponsiveSizePicker.show(context, itemType: item.itemType!);
    if (!mounted) return;
    if (v != null) {
      final provider = context.read<InventoryProvider>();
      setState(() {
        sizeObj.size = v['label'];
        double w = double.tryParse(v['weight'].toString()) ?? 0;
        if (w <= 0) w = extractUnitWeight(sizeObj.size);
        sizeObj.weight = w;
        sizeObj.weightCtrl.text = sizeObj.weight.toString();
        if (sizeObj.total > 0) {
          _recalcNosFromMT(item, sizeObj);
        } else if (sizeObj.nos > 0) {
          _recalcMTFromNos(item, sizeObj);
        } else {
          _recalcNosFromMT(item, sizeObj);
        }
        item.calculateAll(provider.sheetLoading, provider.sheetGst);
      });
    }
  }
}

class SaudaItemPicker extends StatefulWidget {
  const SaudaItemPicker({super.key});
  @override
  State<SaudaItemPicker> createState() => _SaudaItemPickerState();
}

class _SaudaItemPickerState extends State<SaudaItemPicker> {
  String query = "";
  String sortBy = "Priority";
  final TextEditingController searchCtrl = TextEditingController();
  List<String> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    final all = context.read<InventoryProvider>().saudaItemTypes;
    _filteredItems = List.from(all);
    _applyFilter(query);
  }

  void _applyFilter(String q) {
    final all = context.read<InventoryProvider>().saudaItemTypes;
    var filtered = applyPrioritizedSearch(q, all, (t) => t);
    if (sortBy == "Priority") {
      filtered.sort((a, b) => SortingUtils.compareCategories(a, b));
    } else if (sortBy == "Name A-Z") {
      filtered.sort((a, b) => a.compareTo(b));
    } else if (sortBy == "Name Z-A") {
      filtered.sort((a, b) => b.compareTo(a));
    }
    setState(() {
      _filteredItems = filtered;
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(builder: (ctx, provider, child) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Select Product Item",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.sort_rounded, color: msmRed),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (c2) => Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: ["Priority", "Name A-Z", "Name Z-A"]
                                  .map(
                                    (o) => Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        dense: true,
                                        title: Text(
                                          o,
                                          style: TextStyle(
                                            fontWeight: sortBy == o
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: sortBy == o
                                                ? msmRed
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        onTap: () {
                                          setState(() => sortBy = o);
                                          _applyFilter(query);
                                          Navigator.pop(c2);
                                        },
                                      ),
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
                const SizedBox(height: 10),
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: msmInputDeco(
                    "Search item...",
                    prefix: const Icon(Icons.search_rounded, color: textGrey),
                    suffix: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              searchCtrl.clear();
                              setState(() => query = "");
                              _applyFilter("");
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() => query = v);
                    _applyFilter(v);
                  },
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _filteredItems.isEmpty
                      ? const Center(
                          child: Text(
                            "No item found",
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filteredItems.length,
                          separatorBuilder: (c, i) => const Divider(
                              height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (ctx2, i) {
                            final name = _filteredItems[i];
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Image.asset(
                                    _getItemIconPath(name),
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.category,
                                      color: msmRed,
                                      size: 16,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: Color(0xFF94A3B8),
                                ),
                                onTap: () => Navigator.pop(context, name),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class SaudaItem {
  Key? key;
  String? itemType;
  String? orderType;
  String? rateType;
  double rate = 0;
  double basicRate = 0;
  bool manualMode = false;
  double manualQty = 0;
  final TextEditingController rateCtrl = TextEditingController();
  List<SaudaSize> sizes = [SaudaSize()];
  SaudaItem({this.key});
  bool isPiecesItem() =>
      (itemType == "Bopp Tape" || itemType == "Cutting Wheels");
  double getTotalQty() {
    if (manualMode) return manualQty;
    double sum = 0;
    for (var s in sizes) {
      sum += s.total;
    }
    return sum;
  }

  void calculateAll(double sheetLoading, double sheetGst) {
    if (rate > 0 &&
        rateType == "Net" &&
        (orderType == "Bill" || orderType == "NC")) {
      double base = (rate / (1 + sheetGst)) - sheetLoading;
      if (orderType == "NC") base += 3000;
      basicRate = base;
    } else {
      basicRate = 0;
    }
  }

  void dispose() {
    rateCtrl.dispose();
    for (var s in sizes) {
      s.dispose();
    }
  }
}

class SaudaSize {
  String size = "";
  double weight = 0;
  double nos = 0;
  double total = 0;
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController nosCtrl = TextEditingController();
  final TextEditingController mtCtrl = TextEditingController();

  String sizeDescriptionLabel(String? itemType) {
    if (size.isEmpty) return "";
    return getFormattedSizeDisplay(
      formatSizeLabel(
          formatSizeDisplay(itemType ?? "", size), itemType ?? "", weight),
      weight,
    );
  }

  void dispose() {
    weightCtrl.dispose();
    nosCtrl.dispose();
    mtCtrl.dispose();
  }
}

String _getItemIconPath(String itemName) {
  String name = itemName.toLowerCase().trim();
  if (name.contains("pipe") && name.contains("hr")) return "assets/hr_pipe.png";
  if (name.contains("pipe")) return "assets/ms_pipe.png";
  if (name.contains("round")) return "assets/round_bar.png";
  if (name.contains("angle")) return "assets/angle.png";
  if (name.contains("channel")) return "assets/channel.png";
  if (name.contains("flat")) return "assets/flat.png";
  return "assets/msm_icon.jpg";
}
