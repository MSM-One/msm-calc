import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/global_view_wrapper.dart';
import '../constants/app_colors.dart';
import '../utils/steel_helper.dart';
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../widgets/responsive_size_picker.dart';
import '../widgets/motion_toast.dart';
import '../models/delivery_order_model.dart';
import '../services/delivery_order_print_service.dart';
import '../widgets/delivery_order_dialog.dart';

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
    // Pre-fetch inventory data for modals
    final provider = context.read<InventoryProvider>();
    provider.loadSaudaData();

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
    if (vehicleCtrl.text.isNotEmpty)
      msg.writeln("Vehicle No.: ${vehicleCtrl.text.toUpperCase()}");
    msg.writeln("*Total Qty (MT): $effQty MT*");
    msg.writeln("");

    for (int i = 0; i < items.length; i++) {
      var item = items[i];
      if (item.itemType == null ||
          (item.getTotalQty() == 0 && !item.manualMode)) continue;
      String unit = item.isPiecesItem() ? "Pcs" : "MT";
      String totalQtyStr =
          item.getTotalQty().toStringAsFixed(item.isPiecesItem() ? 0 : 3);
      msg.writeln("*Item #${i + 1}: ${item.itemType}*");
      msg.writeln("Order Type: *${item.orderType ?? '-'}*");
      if (item.rateType != null) msg.writeln("Rate Type: ${item.rateType}");
      if (item.rate > 0) msg.writeln("Rate: ${item.rate.toStringAsFixed(0)}");
      if (item.basicRate > 0)
        msg.writeln("Basic Rate (Auto): ${item.basicRate.toStringAsFixed(2)}");
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
    final String safeLorry = vehicleCtrl.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final String autoPoNo = "DO-${DateFormat('yyyyMMdd').format(bookingDate)}-${safeLorry.isNotEmpty ? safeLorry : '01'}";

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
            weight = SteelHelper.extractWeightKg(s.size, category: item.itemType);
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
            bdStr = "${nos.toStringAsFixed(0)} $nosUnit x ${weight.toStringAsFixed(2)} kg = ${qty.toStringAsFixed(3)} MT";
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
            saudaRate: item.rate > 0 ? item.rate : (item.basicRate > 0 ? item.basicRate : "-"),
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
      approvedBy: "For METAROLL STEEL MART",
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
                            const Text("Preview",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: textDark)),
                            Switch(
                                value: showDetails,
                                activeThumbColor: msmRed,
                                onChanged: (val) {
                                  setDialogState(() => showDetails = val);
                                })
                          ]),
                      const Text("Toggle switch to show/hide details",
                          style: TextStyle(color: textGrey, fontSize: 12)),
                      const Divider(),
                      Expanded(
                          child: SingleChildScrollView(
                              child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: bgLight,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text(message,
                                      style: const TextStyle(
                                          fontSize: 13, color: textDark))))),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: textDark,
                                    side: const BorderSide(color: Colors.grey),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(30))),
                                icon: const Icon(Icons.copy, size: 18),
                                label: const Text("Copy",
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
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
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(30)),
                                    elevation: 0),
                                icon: const Icon(Icons.share, size: 18),
                                label: const Text("Share",
                                    style: TextStyle(
                                        fontSize: 14,
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
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(30)),
                                    elevation: 0),
                                icon: const Icon(Icons.print_rounded, size: 18),
                                label: const Text("Print",
                                    style: TextStyle(
                                        fontSize: 14,
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
                                      color: Colors.black54, fontSize: 14))))
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
                title: const Text("Reset Form?"),
                content: const Text("This will clear all items."),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel")),
                  TextButton(
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
                      child: const Text("Reset",
                          style: TextStyle(color: Colors.red)))
                ]));
  }

  @override
  Widget build(BuildContext context) {
    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: msmBg,
        extendBodyBehindAppBar: true,
        appBar: _buildModernAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth > 700;
            bool isMobile = constraints.maxWidth < 600;
            return SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding:
                          EdgeInsets.fromLTRB(24, isMobile ? 32 : 90, 24, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionCard(
                                  title: "Basic Details",
                                  child: _buildBasicDetailsFields(isMobile)),
                              const SizedBox(
                                  height: 20), // Consistent vertical spacing
                              _buildSectionTitle("Items & Rates"),
                              const SizedBox(
                                  height: 4), // Reduced gap above cards
                              ...items.asMap().entries.map(
                                  (e) => _buildSaudaItemCard(e.value, e.key)),
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 12),
                                child: _buildAddItemButton(),
                              ),
                              const SizedBox(height: 8),
                              _buildSectionCard(
                                  title: "Other Details",
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildDocumentTitleSelector(),
                                      const SizedBox(height: 12),
                                      TextField(
                                          controller: remarksCtrl,
                                          maxLines: 3,
                                          decoration: msmInputDeco("Remarks"),
                                          onChanged: (_) => _saveData()),
                                    ],
                                  )),
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
        bottomNavigationBar: MediaQuery.of(context).size.width <= 900
            ? _buildMobileFooter()
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: msmRed.withValues(alpha: 0.85),
            elevation: 0,
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context)),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Sauda Booking",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: -0.5)),
                Opacity(
                  opacity: 0.8,
                  child: Text("Metaroll Premium Edition • 2026",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            actions: [
              IconButton(
                  icon: const Icon(Icons.print_rounded, color: Colors.white),
                  tooltip: "Print Delivery Order",
                  onPressed: _showDeliveryOrderPrintDialog),
              IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _resetForm),
              const SizedBox(width: 8)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
                color: msmRed.withValues(alpha: 0.03),
                border: Border(
                    bottom:
                        BorderSide(color: Colors.red.withValues(alpha: 0.1)))),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18, color: msmRed),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textDark,
                      fontSize: 15))
            ])),
        Padding(padding: const EdgeInsets.all(20), child: child),
      ]),
    );
  }

  Widget _buildBasicDetailsFields(bool isMobile) {
    return Column(children: [
      if (isMobile) ...[
        InkWell(
          onTap: () => _pickDate(),
          child: InputDecorator(
              decoration: msmInputDeco("Booking Date",
                  prefix: const Icon(Icons.calendar_month,
                      size: 20, color: msmRed)),
              child: Text(_dateCtrl.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14))),
        ),
        const SizedBox(height: 16),
        TextField(
            controller: vehicleCtrl,
            decoration: msmInputDeco("Vehicle No."),
            onChanged: (_) => _saveData()),
      ] else
        Row(children: [
          Expanded(
              child: InkWell(
            onTap: () => _pickDate(),
            child: InputDecorator(
                decoration: msmInputDeco("Booking Date",
                    prefix: const Icon(Icons.calendar_month,
                        size: 20, color: msmRed)),
                child: Text(_dateCtrl.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14))),
          )),
          const SizedBox(width: 16),
          Expanded(
              child: TextField(
                  controller: vehicleCtrl,
                  decoration: msmInputDeco("Vehicle No."),
                  onChanged: (_) => _saveData())),
        ]),
      const SizedBox(height: 16),
      TextField(
          controller: firmNameCtrl,
          decoration: msmInputDeco("Firm Name",
              prefix: const Icon(Icons.business_outlined,
                  size: 20, color: textGrey)),
          onChanged: (_) => _saveData()),
    ]);
  }

  void _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: bookingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: msmRed,
              onPrimary: Colors.white,
              onSurface: textDark,
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
      width: 400,
      height: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 100, 24, 24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 30,
                offset: const Offset(-10, 0))
          ]),
      child: Column(children: [
        _buildSidebarHeader(totalQty),
        Expanded(child: _buildSidebarItemList()),
        _buildSidebarFooter(),
      ]),
    );
  }

  Widget _buildSidebarHeader(double totalQty) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [msmRed, msmRed.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Booking Summary",
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Total Quantity",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text("${totalQty.toStringAsFixed(3)} MT",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900))
        ]),
      ]),
    );
  }

  Widget _buildSidebarItemList() {
    final activeItems = items.where((i) => i.itemType != null).toList();
    if (activeItems.isEmpty)
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[200]),
        const SizedBox(height: 16),
        const Text("No items added yet", style: TextStyle(color: textGrey))
      ]));
    return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: activeItems.length,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (context, index) {
          final item = activeItems[index];
          return Row(children: [
            CircleAvatar(
                backgroundColor: msmRed.withValues(alpha: 0.05),
                child: Image.asset(_getItemIconPath(item.itemType!),
                    width: 20,
                    errorBuilder: (ctx, err, st) =>
                        const Icon(Icons.category, color: msmRed, size: 14))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.itemType!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text("${item.orderType ?? '-'} | ${item.rateType ?? '-'}",
                      style: const TextStyle(color: textGrey, fontSize: 12))
                ])),
            Text(
                "${item.getTotalQty().toStringAsFixed(3)} ${item.isPiecesItem() ? 'Pcs' : 'MT'}",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, color: msmRed))
          ]);
        });
  }

  Widget _buildSidebarFooter() {
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24))),
        child: Column(
          children: [
            ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: msmRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 3,
                    shadowColor: msmRed.withValues(alpha: 0.3)),
                icon: const Icon(Icons.print_rounded, size: 20),
                label: const Text("Print Delivery Order",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: _showDeliveryOrderPrintDialog),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: textDark,
                    side: BorderSide(color: Colors.grey.shade300),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text("Share Order Text",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                onPressed: () => _showPreviewDialog(true)),
          ],
        ));
  }

  Widget _buildMobileFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -6),
            spreadRadius: 0,
          )
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: msmRed.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text("Total Qty",
                  style: TextStyle(fontSize: 9, color: textGrey)),
              Text("${getTotalEffectiveQty().toStringAsFixed(3)} MT",
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: msmRed))
            ])),
        const SizedBox(width: 8),
        Expanded(
            child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: textDark,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.share_rounded, size: 16),
                onPressed: () => _showPreviewDialog(true),
                label: const Text("Share",
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),
        const SizedBox(width: 8),
        Expanded(
            flex: 2,
            child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: msmRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.print_rounded, size: 18),
                onPressed: _showDeliveryOrderPrintDialog,
                label: const Text("Print Order",
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))),
      ]),
    );
  }

  Widget _buildDocumentTitleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Document Title for Print",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: textDark,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _documentTitle,
          decoration: msmInputDeco("Print Title"),
          dropdownColor: Colors.white,
          items: const [
            DropdownMenuItem(
              value: 'SAUDA BOOK / DELIVERY ORDER',
              child: Text(
                'SAUDA BOOK / DELIVERY ORDER (Default)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            DropdownMenuItem(
              value: 'DELIVERY ORDER',
              child: Text(
                'DELIVERY ORDER',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            DropdownMenuItem(
              value: 'SAUDA BOOK',
              child: Text(
                'SAUDA BOOK',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
    return Padding(
      padding: EdgeInsets.zero,
      child: OutlinedButton.icon(
        onPressed: addItem,
        icon: const Icon(Icons.add_circle_outline, size: 20, color: msmRed),
        label: const Text("+ Add Item",
            style: TextStyle(
                color: msmRed, fontWeight: FontWeight.bold, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(color: msmRed.withValues(alpha: 0.3), width: 1.5),
          backgroundColor: msmRed.withValues(alpha: 0.04),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
              width: 4,
              height: 16,
              color: msmRed,
              margin: const EdgeInsets.only(right: 8)),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: textDark, fontSize: 16))
        ]));
  }

  Widget _buildSaudaItemCard(SaudaItem item, int index) {
    String unit = item.isPiecesItem() ? 'Pcs' : 'MT';
    String totalStr = item.getTotalQty().toStringAsFixed(3);
    String titleText = item.itemType ?? "Tap to select product";
    String subtitleText =
        item.itemType != null ? "$totalStr $unit" : "Order details not set";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ]),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: index == items.length - 1,
          leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: msmRed.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10)),
              child: Image.asset(_getItemIconPath(item.itemType ?? ""),
                  width: 24,
                  height: 24,
                  errorBuilder: (ctx, err, st) =>
                      const Icon(Icons.category, color: msmRed, size: 20))),
          title: Text(titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: textDark)),
          subtitle: Text(subtitleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: item.itemType != null ? Colors.green : textGrey,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (index > 0)
              IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: msmRed, size: 20),
                  onPressed: () => removeItem(index)),
            const Icon(Icons.expand_more, color: textGrey)
          ]),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            InkWell(
              onTap: () {
                showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      final bottomInset =
                          MediaQuery.of(context).viewInsets.bottom;
                      return Padding(
                        padding: EdgeInsets.only(bottom: bottomInset),
                        child: const SaudaItemPicker(),
                      );
                    }).then((v) {
                  if (v != null) {
                    if (!mounted) return;
                    final provider = context.read<InventoryProvider>();
                    setState(() {
                      item.itemType = v;
                      item.calculateAll(
                          provider.sheetLoading, provider.sheetGst);
                    });
                  }
                });
              },
              child: InputDecorator(
                  decoration: msmInputDeco("Select Item"),
                  child: Text(item.itemType ?? "Tap to select",
                      style: TextStyle(
                          fontSize: 14,
                          color: item.itemType == null ? textGrey : textDark))),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DropdownButtonFormField<String>(
                      initialValue: item.orderType,
                      decoration: msmInputDeco("Type"),
                      items: ["Bill", "NC"]
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) {
                        final provider = context.read<InventoryProvider>();
                        setState(() {
                          item.orderType = v;
                          item.calculateAll(
                              provider.sheetLoading, provider.sheetGst);
                        });
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: DropdownButtonFormField<String>(
                      initialValue: item.rateType,
                      decoration: msmInputDeco("Rate Type"),
                      items: ["Basic", "Net"]
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) {
                        final provider = context.read<InventoryProvider>();
                        setState(() {
                          item.rateType = v;
                          item.calculateAll(
                              provider.sheetLoading, provider.sheetGst);
                        });
                      }))
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: item.rateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: msmInputDeco("Rate"),
                      onChanged: (v) {
                        final provider = context.read<InventoryProvider>();
                        item.rate = double.tryParse(v) ?? 0;
                        item.calculateAll(
                            provider.sheetLoading, provider.sheetGst);
                        setState(() {});
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: TextEditingController(
                          text: item.basicRate > 0
                              ? item.basicRate.toStringAsFixed(2)
                              : ""),
                      readOnly: true,
                      decoration: msmInputDeco("Basic (Auto)")))
            ]),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 340;
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text("Manual Total Qty?",
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      Switch(
                          value: item.manualMode,
                          activeThumbColor: msmRed,
                          onChanged: (v) =>
                              setState(() => item.manualMode = v)),
                    ]),
                    if (item.manualMode)
                      TextField(
                          enabled: item.manualMode,
                          keyboardType: TextInputType.number,
                          decoration: msmInputDeco("Manual Qty"),
                          onChanged: (v) => setState(
                              () => item.manualQty = double.tryParse(v) ?? 0)),
                  ],
                );
              }
              return Row(children: [
                const Text("Manual Total Qty?",
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                Switch(
                    value: item.manualMode,
                    activeThumbColor: msmRed,
                    onChanged: (v) => setState(() => item.manualMode = v)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        enabled: item.manualMode,
                        keyboardType: TextInputType.number,
                        decoration: msmInputDeco("Manual Qty"),
                        onChanged: (v) => setState(
                            () => item.manualQty = double.tryParse(v) ?? 0)))
              ]);
            }),
            if (!item.manualMode) ...[
              const Divider(height: 32),
              const Row(children: [
                Expanded(
                    flex: 4,
                    child: Text("Size",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textGrey))),
                Expanded(
                    flex: 2,
                    child: Text("MT",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textGrey),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text("Nos",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textGrey),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text("Total",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textGrey),
                        textAlign: TextAlign.right)),
                SizedBox(width: 24)
              ]),
              const SizedBox(height: 8),
              ...item.sizes.asMap().entries.map((e) {
                int sIdx = e.key;
                SaudaSize size = e.value;
                return Padding(
                    key: ObjectKey(size),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                          flex: 4,
                          child: InkWell(
                              onTap: () => _showSizePicker(item, size),
                              child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: const BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(
                                              color: borderLight, width: 0.5))),
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
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: size.size.isEmpty
                                                        ? textGrey
                                                        : msmRed),
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        const Icon(Icons.edit,
                                            color: msmRed, size: 14)
                                      ])))),
                      const SizedBox(width: 4),
                      Expanded(
                          flex: 2,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40),
                              child: TextField(
                                  controller: size.mtCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: msmTableInputDeco(hint: "0"),
                                  onChanged: (v) {
                                    final provider =
                                        context.read<InventoryProvider>();
                                    setState(() {
                                      size.total = double.tryParse(v) ?? 0;
                                      _recalcNosFromMT(item, size);
                                      item.calculateAll(provider.sheetLoading,
                                          provider.sheetGst);
                                    });
                                  }))),
                      const SizedBox(width: 4),
                      Expanded(
                          flex: 2,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40),
                              child: TextField(
                                  controller: size.nosCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
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
                                  }))),
                      Expanded(
                          flex: 2,
                          child: Text(size.total.toStringAsFixed(3),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textDark))),
                      const SizedBox(width: 4),
                      GestureDetector(
                          onTap: () =>
                              setState(() => item.sizes.removeAt(sIdx)),
                          child: const Icon(Icons.remove_circle,
                              color: msmRed, size: 20))
                    ]));
              }),
              const SizedBox(height: 8),
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: () =>
                          setState(() => item.sizes.add(SaudaSize())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("Add Size",
                          style: TextStyle(fontWeight: FontWeight.bold)))),
            ],
          ],
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
        } else if (sizeObj.nos > 0)
          _recalcMTFromNos(item, sizeObj);
        else
          _recalcNosFromMT(item, sizeObj);
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 24, left: 16, right: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Select Item",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textDark)),
                IconButton(
                    icon: const Icon(Icons.sort, color: msmRed),
                    onPressed: () {
                      showModalBottomSheet(
                          context: context,
                          builder: (c2) => Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: ["Priority", "Name A-Z", "Name Z-A"]
                                      .map((o) => ListTile(
                                          title: Text(o,
                                              style: TextStyle(
                                                  fontWeight: sortBy == o
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: sortBy == o
                                                      ? msmRed
                                                      : textDark)),
                                          onTap: () {
                                            setState(() => sortBy = o);
                                            _applyFilter(query);
                                            Navigator.pop(c2);
                                          }))
                                      .toList())));
                    })
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: msmInputDeco("Search item...",
                      prefix: const Icon(Icons.search, color: textGrey),
                      suffix: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                searchCtrl.clear();
                                setState(() => query = "");
                                _applyFilter("");
                              })
                          : null),
                  onChanged: (v) {
                    setState(() => query = v);
                    _applyFilter(v);
                  },
                  onSubmitted: (_) => FocusScope.of(context).unfocus()),
              const SizedBox(height: 16),
              Expanded(
                  child: _filteredItems.isEmpty
                      ? const Center(child: Text("No item found"))
                      : ListView.separated(
                          itemCount: _filteredItems.length,
                          separatorBuilder: (c, i) => const Divider(),
                          itemBuilder: (ctx2, i) {
                            final name = _filteredItems[i];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: msmRed.withValues(alpha: 0.05),
                                    shape: BoxShape.circle),
                                child: Image.asset(_getItemIconPath(name),
                                    width: 24,
                                    height: 24,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.category,
                                        color: msmRed,
                                        size: 20)),
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textDark)),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 16, color: textGrey),
                              onTap: () => Navigator.pop(context, name),
                            );
                          })),
              const SizedBox(height: 16),
            ]),
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
