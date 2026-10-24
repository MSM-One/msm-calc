import 'package:flutter/material.dart';
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
import '../widgets/preview_order_dialog.dart';
import '../services/data_repository.dart';
import '../utils/sauda_rate_calculator.dart';

class SaudaBookingScreen extends StatefulWidget {
  const SaudaBookingScreen({super.key});

  @override
  State<SaudaBookingScreen> createState() => _SaudaBookingScreenState();
}

class _SaudaBookingScreenState extends State<SaudaBookingScreen> {
  final TextEditingController _dealerNameController = TextEditingController();
  final TextEditingController _billingNameController = TextEditingController();
  final TextEditingController _consigneeNameController = TextEditingController();

  TextEditingController get firmNameCtrl => _dealerNameController;
  TextEditingController get billingNameCtrl => _billingNameController;
  TextEditingController get consigneeNameCtrl => _consigneeNameController;

  final TextEditingController billingAddressCtrl = TextEditingController();
  final TextEditingController shippingAddressCtrl = TextEditingController();
  final TextEditingController vehicleCtrl = TextEditingController();
  final TextEditingController remarksCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController freightCtrl = TextEditingController();

  final FocusNode firmNameFocusNode = FocusNode();
  final FocusNode billingNameFocusNode = FocusNode();
  final FocusNode consigneeNameFocusNode = FocusNode();

  double freightCharge = 0.0;
  String freightType = 'PER_MT'; // 'PER_MT' or 'FIXED'

  bool _isBillingUntouched = true;
  bool _isConsigneeUntouched = true;
  bool _isBillingAddressAutoFilled = false;
  bool _isShippingAddressAutoFilled = false;

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
    DataRepository.loadCustomerAddresses();

    _dateCtrl.text = DateFormat('dd MMM yyyy').format(bookingDate);
    if (items.isEmpty) addItem();
  }

  @override
  void dispose() {
    firmNameFocusNode.dispose();
    billingNameFocusNode.dispose();
    consigneeNameFocusNode.dispose();
    firmNameCtrl.dispose();
    billingNameCtrl.dispose();
    billingAddressCtrl.dispose();
    consigneeNameCtrl.dispose();
    shippingAddressCtrl.dispose();
    vehicleCtrl.dispose();
    remarksCtrl.dispose();
    _dateCtrl.dispose();
    freightCtrl.dispose();
    for (var item in items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedFirm = (prefs.getString('sauda_firm') ?? "").trim();
      final savedBilling =
          (prefs.getString('sauda_billing_name') ?? "").trim();
      final savedConsignee =
          (prefs.getString('sauda_consignee_name') ?? "").trim();

      final storedDisplayName =
          prefs.getString('user_display_name')?.trim().toLowerCase();
      final userEmail = prefs.getString('user_email')?.trim().toLowerCase();
      final currentUserEmail =
          DataRepository.currentUserNotifier.value?.email.trim().toLowerCase();

      // 1. Remove default prefill of logged-in user name ("Vivek salve")
      bool isUserMatch(String val) {
        final lower = val.toLowerCase();
        if (lower == 'vivek salve' || lower == 'vivek') return true;
        if (storedDisplayName != null &&
            storedDisplayName.isNotEmpty &&
            lower == storedDisplayName) {
          return true;
        }
        if (userEmail != null &&
            userEmail.isNotEmpty &&
            (lower == userEmail || lower == userEmail.split('@').first)) {
          return true;
        }
        if (currentUserEmail != null &&
            currentUserEmail.isNotEmpty &&
            (lower == currentUserEmail ||
                lower == currentUserEmail.split('@').first)) {
          return true;
        }
        return false;
      }

      final cleanFirm = isUserMatch(savedFirm) ? "" : savedFirm;
      final cleanBilling = isUserMatch(savedBilling) ? "" : savedBilling;
      final cleanConsignee = isUserMatch(savedConsignee) ? "" : savedConsignee;

      _dealerNameController.text = cleanFirm;
      billingAddressCtrl.text = prefs.getString('sauda_billing_address') ?? "";
      shippingAddressCtrl.text =
          prefs.getString('sauda_shipping_address') ?? "";
      vehicleCtrl.text = prefs.getString('sauda_vehicle') ?? "";
      remarksCtrl.text = prefs.getString('sauda_remarks') ?? "";
      _documentTitle = prefs.getString('sauda_document_title') ??
          'SAUDA BOOK / DELIVERY ORDER';
      freightCharge = prefs.getDouble('sauda_freight_charge') ?? 0.0;
      freightType = prefs.getString('sauda_freight_type') ?? 'PER_MT';

      // 2. Initialize smart auto-sync status
      _isBillingUntouched = cleanBilling.isEmpty ||
          (cleanFirm.isNotEmpty &&
              cleanBilling.toLowerCase() == cleanFirm.toLowerCase());
      _isConsigneeUntouched = cleanConsignee.isEmpty ||
          (cleanFirm.isNotEmpty &&
              cleanConsignee.toLowerCase() == cleanFirm.toLowerCase());

      if (_isBillingUntouched) {
        _billingNameController.text = cleanFirm;
      } else {
        _billingNameController.text = cleanBilling;
      }

      if (_isConsigneeUntouched) {
        _consigneeNameController.text = cleanFirm;
      } else {
        _consigneeNameController.text = cleanConsignee;
      }

      if (freightCharge > 0) {
        freightCtrl.text = (freightCharge % 1 == 0)
            ? freightCharge.toInt().toString()
            : freightCharge.toString();
        for (var it in items) {
          it.freightCharge = freightCharge;
          it.freightType = freightType;
          it.freightCtrl.text = freightCtrl.text;
        }
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sauda_firm', firmNameCtrl.text);
    await prefs.setString('sauda_billing_name', billingNameCtrl.text);
    await prefs.setString('sauda_billing_address', billingAddressCtrl.text);
    await prefs.setString('sauda_consignee_name', consigneeNameCtrl.text);
    await prefs.setString(
        'sauda_shipping_address', shippingAddressCtrl.text);
    await prefs.setString('sauda_vehicle', vehicleCtrl.text);
    await prefs.setString('sauda_remarks', remarksCtrl.text);
    await prefs.setString('sauda_document_title', _documentTitle);
    await prefs.setDouble('sauda_freight_charge', freightCharge);
    await prefs.setString('sauda_freight_type', freightType);
    if (firmNameCtrl.text.trim().isNotEmpty) {
      final addr = shippingAddressCtrl.text.trim().isNotEmpty
          ? shippingAddressCtrl.text.trim()
          : billingAddressCtrl.text.trim();
      if (addr.isNotEmpty) {
        DataRepository.saveCustomerAddress(
            firmNameCtrl.text.trim(), addr);
      }
    }
  }

  void addItem() {
    setState(() {
      final newItem = SaudaItem(key: UniqueKey());
      newItem.freightCharge = freightCharge;
      newItem.freightType = freightType;
      if (freightCharge > 0) {
        newItem.freightCtrl.text = (freightCharge % 1 == 0)
            ? freightCharge.toInt().toString()
            : freightCharge.toString();
      }
      items.add(newItem);
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

  double getTotalFreight() {
    double itemFreightSum =
        items.fold(0.0, (sum, i) => sum + i.calculateFreight());
    if (itemFreightSum > 0) return itemFreightSum;
    if (freightCharge > 0) {
      if (freightType == 'FIXED') return freightCharge;
      return getTotalEffectiveQty() * freightCharge;
    }
    return 0.0;
  }

  double getBaseMaterialValue() {
    return items.fold(0.0, (sum, i) => sum + i.getBaseMaterialValue());
  }

  Map<String, double> calculateBookingSummary() {
    final liveCharges = DataRepository.instance.globalCharges;
    final double gstRate = liveCharges.gstRate > 1.0
        ? liveCharges.gstRate / 100.0
        : (liveCharges.gstRate > 0 ? liveCharges.gstRate : 0.18);

    double totalTonnage = 0.0;
    double totalBaseAndSdValue = 0.0;
    double totalLoadingCharges = 0.0;
    double totalNcDiscount = 0.0;
    double totalFreightCharges = 0.0;
    double totalSubtotalBeforeGst = 0.0;
    double totalOrderValue = 0.0;

    final double globalFreightCharge = freightCharge;
    final String globalFreightType = freightType;

    for (var item in items) {
      final double baseRate = item.rate > 0 ? item.rate : item.basicRate;

      final double itemFreightCharge =
          item.freightCharge > 0 ? item.freightCharge : globalFreightCharge;
      final String itemFreightType =
          item.freightCharge > 0 ? item.freightType : globalFreightType;

      if (item.manualMode) {
        final double qty = item.manualQty;
        if (qty > 0 && baseRate > 0) {
          totalTonnage += qty;
          const double sd = 0.0;
          final double fPerMt = itemFreightType == 'PER_MT'
              ? itemFreightCharge
              : (qty > 0 ? itemFreightCharge / qty : 0.0);

          final calc = SaudaRateCalculator.calculate(
            saudaRate: baseRate,
            sd: sd,
            charges: liveCharges,
            billType: item.orderType ?? 'BILL',
            itemType: item.itemType,
            freight: fPerMt,
            ob: 0.0,
            isPieces: item.isPiecesItem(),
          );

          totalBaseAndSdValue += (calc.baseRate + calc.sizeDiff) * qty;
          totalLoadingCharges += calc.loadingCharges * qty;
          totalNcDiscount += calc.ncDiscount * qty;
          totalFreightCharges += calc.freightChargePerMT * qty;
          totalSubtotalBeforeGst += calc.subtotalBeforeGst * qty;
          totalOrderValue += (calc.netRate * qty);
        }
      } else {
        for (var s in item.sizes) {
          final double qty = s.total;
          if (qty > 0 && baseRate > 0) {
            totalTonnage += qty;
            final double sd = DataRepository.getSizeSD(item.itemType, s.size);
            final double itemTotalQty = item.getTotalQty();
            final double fPerMt = itemFreightType == 'PER_MT'
                ? itemFreightCharge
                : (itemTotalQty > 0 ? itemFreightCharge / itemTotalQty : 0.0);

            final calc = SaudaRateCalculator.calculate(
              saudaRate: baseRate,
              sd: sd,
              charges: liveCharges,
              billType: item.orderType ?? 'BILL',
              itemType: item.itemType,
              freight: fPerMt,
              ob: 0.0,
              isPieces: item.isPiecesItem(),
            );

            totalBaseAndSdValue += (calc.baseRate + calc.sizeDiff) * qty;
            totalLoadingCharges += calc.loadingCharges * qty;
            totalNcDiscount += calc.ncDiscount * qty;
            totalFreightCharges += calc.freightChargePerMT * qty;
            totalSubtotalBeforeGst += calc.subtotalBeforeGst * qty;
            totalOrderValue += (calc.netRate * qty);
          }
        }
      }
    }

    final double totalGst = totalSubtotalBeforeGst * gstRate;
    final double effectiveNetRate =
        totalTonnage > 0 ? (totalOrderValue / totalTonnage) : 0.0;

    return {
      'tonnage': totalTonnage,
      'baseAndSd': totalBaseAndSdValue,
      'loading': totalLoadingCharges,
      'ncDiscount': totalNcDiscount,
      'freight': totalFreightCharges,
      'subtotal': totalSubtotalBeforeGst,
      'gst': totalGst,
      'totalOrderValue': totalOrderValue,
      'effectiveNetRate': effectiveNetRate,
    };
  }

  double getTotalOrderValue() {
    final summary = calculateBookingSummary();
    if (summary['totalOrderValue']! > 0) {
      return summary['totalOrderValue']!;
    }
    final base = getBaseMaterialValue();
    final freight = getTotalFreight();
    final provider = context.read<InventoryProvider>();
    final gstRate = provider.sheetGst;
    bool hasBill = items.any((i) => i.orderType == 'Bill');
    if (hasBill && base > 0) {
      return (base + freight) * (1 + gstRate);
    }
    return base + freight;
  }

  String _generateSaudaMessage(bool includeDetails) {
    String dateStr = DateFormat('dd/MM/yyyy').format(bookingDate);
    String effQty = getTotalEffectiveQty().toStringAsFixed(3);
    StringBuffer msg = StringBuffer();
    msg.writeln("*Sauda Booking*");
    msg.writeln("Date: $dateStr");
    msg.writeln("*Firm: ${firmNameCtrl.text.trim()}*");
    if (billingNameCtrl.text.trim().isNotEmpty &&
        billingNameCtrl.text.trim() != firmNameCtrl.text.trim()) {
      msg.writeln("Billing Name: ${billingNameCtrl.text.trim()}");
    }
    if (billingAddressCtrl.text.trim().isNotEmpty) {
      msg.writeln("Billing Address: ${billingAddressCtrl.text.trim()}");
    }
    if (consigneeNameCtrl.text.trim().isNotEmpty &&
        consigneeNameCtrl.text.trim() != firmNameCtrl.text.trim()) {
      msg.writeln("Consignee Name: ${consigneeNameCtrl.text.trim()}");
    }
    if (shippingAddressCtrl.text.trim().isNotEmpty) {
      msg.writeln("Delivery Address: ${shippingAddressCtrl.text.trim()}");
    }
    if (vehicleCtrl.text.trim().isNotEmpty) {
      msg.writeln("Vehicle No.: ${vehicleCtrl.text.trim().toUpperCase()}");
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
      if (item.freightCharge > 0) {
        if (item.freightType == 'PER_MT') {
          msg.writeln("Freight: ₹${item.freightCharge.toStringAsFixed(0)}/MT");
        } else {
          msg.writeln("Freight: ₹${formatIndianCurrency(item.freightCharge)} (Fixed)");
        }
        if (item.getEffectiveLandedRate() > 0) {
          msg.writeln("Landed Net Rate: ₹${formatIndianCurrency(item.getEffectiveLandedRate())}/MT");
        }
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

    final double totalFreight = getTotalFreight();
    final double effectiveFreightCharge = freightCharge > 0
        ? freightCharge
        : (items.isNotEmpty ? items.first.freightCharge : 0.0);
    final String effectiveFreightType = freightCharge > 0
        ? freightType
        : (items.isNotEmpty ? items.first.freightType : 'PER_MT');

    if (totalFreight > 0) {
      if (effectiveFreightType == 'PER_MT') {
        msg.writeln("🚚 Freight: ₹${effectiveFreightCharge.toStringAsFixed(0)}/MT (Total: ₹${formatIndianCurrency(totalFreight)})");
      } else {
        msg.writeln("🚚 Freight: ₹${formatIndianCurrency(totalFreight)} (Fixed)");
      }
    } else {
      msg.writeln("🚚 Freight: To-Pay (Extra)");
    }

    final double baseVal = getBaseMaterialValue();
    if (baseVal > 0) {
      msg.writeln("Base Material Value: ₹${formatIndianCurrency(baseVal)}");
      msg.writeln("*Total Order Value: ₹${formatIndianCurrency(getTotalOrderValue())}*");
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
              size: s.size.isNotEmpty
                  ? s.size
                  : s.sizeDescriptionLabel(item.itemType),
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
            freightCharge: item.freightCharge,
            freightType: item.freightType,
            sizes: sizeModels,
          ),
        );
      }
    }

    final dealer = firmNameCtrl.text.trim();
    final bName = billingNameCtrl.text.trim().isNotEmpty
        ? billingNameCtrl.text.trim()
        : dealer;
    final bAddr = billingAddressCtrl.text.trim();
    final cName = consigneeNameCtrl.text.trim().isNotEmpty
        ? consigneeNameCtrl.text.trim()
        : dealer;
    final sAddr = shippingAddressCtrl.text.trim().isNotEmpty
        ? shippingAddressCtrl.text.trim()
        : (bAddr.isNotEmpty ? bAddr : '');

    final double totalOrderFreight = getTotalFreight();
    final double effectiveFreightCharge = freightCharge > 0
        ? freightCharge
        : (items.isNotEmpty ? items.first.freightCharge : 0.0);
    final String effectiveFreightType = freightCharge > 0
        ? freightType
        : (items.isNotEmpty ? items.first.freightType : 'PER_MT');
    final String freightSummaryStr = totalOrderFreight > 0
        ? (effectiveFreightType == 'PER_MT'
            ? "₹${effectiveFreightCharge.toStringAsFixed(0)}/MT"
            : "₹${formatIndianCurrency(totalOrderFreight)} Fixed")
        : "To Pay";

    return DeliveryOrderDataModel(
      documentTitle: _documentTitle,
      poNo: autoPoNo,
      poDate: dateStr,
      dealerName: dealer,
      billingName: bName,
      billingAddress: bAddr,
      consigneeName: cName,
      dispatchAddress: sAddr,
      shippingAddress: sAddr,
      orderDate: dateStr,
      billType: detectedBillType,
      ob: "",
      freight: freightSummaryStr,
      freightCharge: effectiveFreightCharge,
      freightType: effectiveFreightType,
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
    if (firmNameCtrl.text.trim().isEmpty) {
      MotionToast.show(context, "Please enter Firm Name", isError: true);
      return;
    }
    _saveData();
    final activeItemsCount = items
        .where((i) => i.itemType != null && (i.getTotalQty() > 0 || i.manualMode))
        .length;
    final totalQtyStr = "${getTotalEffectiveQty().toStringAsFixed(3)} MT";

    PreviewOrderDialog.show(
      context,
      messageBuilder: (showDetails) => _generateSaudaMessage(showDetails),
      onPrint: _showDeliveryOrderPrintDialog,
      firmName: firmNameCtrl.text.trim(),
      totalQty: totalQtyStr,
      itemCount: activeItemsCount,
      initialShowDetails: forDetails,
    );
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
                          _dealerNameController.clear();
                          _billingNameController.clear();
                          billingAddressCtrl.clear();
                          _consigneeNameController.clear();
                          shippingAddressCtrl.clear();
                          _isBillingUntouched = true;
                          _isBillingAddressAutoFilled = false;
                          _isConsigneeUntouched = true;
                          _isShippingAddressAutoFilled = false;
                          vehicleCtrl.clear();
                          remarksCtrl.clear();
                          freightCharge = 0.0;
                          freightType = 'PER_MT';
                          freightCtrl.clear();
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
        ] else ...[
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
        ],
        const SizedBox(height: 10),
        _buildFirmNameField(),
        const SizedBox(height: 12),
        _buildPartyDetailsGrid(isMobile),
        const SizedBox(height: 12),
        _buildFreightFieldRow(),
      ],
    );
  }

  void _onFirmChanged(String dealerName) {
    if (_isBillingUntouched) {
      _billingNameController.text = dealerName;
    }
    if (_isConsigneeUntouched) {
      _consigneeNameController.text = dealerName;
    }

    final trimmed = dealerName.trim();
    if (trimmed.isNotEmpty) {
      final defaultAddr = DataRepository.getCustomerAddress(trimmed);
      if (defaultAddr != null && defaultAddr.trim().isNotEmpty) {
        final cleanAddr = defaultAddr.trim();
        if (billingAddressCtrl.text.trim().isEmpty || _isBillingAddressAutoFilled) {
          billingAddressCtrl.text = cleanAddr;
          _isBillingAddressAutoFilled = true;
        }
        if (shippingAddressCtrl.text.trim().isEmpty || _isShippingAddressAutoFilled) {
          shippingAddressCtrl.text = cleanAddr;
          _isShippingAddressAutoFilled = true;
        }
      }
    }
    setState(() {});
    _saveData();
  }

  Widget _buildPartyDetailsGrid(bool isMobile) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBillingNameField(),
          const SizedBox(height: 10),
          _buildBillingAddressField(),
          const SizedBox(height: 10),
          _buildConsigneeNameField(),
          const SizedBox(height: 10),
          _buildShippingAddressField(),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBillingNameField(),
                const SizedBox(height: 10),
                _buildBillingAddressField(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConsigneeNameField(),
                const SizedBox(height: 10),
                _buildShippingAddressField(),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildBillingNameField() {
    final bool isOverridden = !_isBillingUntouched &&
        _billingNameController.text.trim() != _dealerNameController.text.trim();

    return TextField(
      controller: _billingNameController,
      focusNode: billingNameFocusNode,
      decoration: msmInputDeco(
        "Billing Name",
        prefix: const Icon(Icons.badge_outlined,
            size: 16, color: Color(0xFF64748B)),
        hint: "Enter billing name (defaults to Dealer)",
      ).copyWith(
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOverridden)
              IconButton(
                icon: const Icon(Icons.sync,
                    size: 18, color: Color(0xFF0284C7)),
                tooltip: "Re-sync to Dealer Name",
                onPressed: () {
                  setState(() {
                    _billingNameController.text = _dealerNameController.text;
                    _isBillingUntouched = true;
                  });
                  _saveData();
                },
              ),
            if (_billingNameController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_rounded,
                    size: 16, color: textGrey),
                tooltip: "Clear billing name",
                onPressed: () {
                  setState(() {
                    _billingNameController.clear();
                    _isBillingUntouched = false;
                  });
                  _saveData();
                },
              ),
          ],
        ),
      ),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
      onChanged: (val) {
        _isBillingUntouched = false;
        _saveData();
        setState(() {});
      },
    );
  }

  Widget _buildBillingAddressField() {
    return TextField(
      controller: billingAddressCtrl,
      minLines: 1,
      maxLines: 3,
      decoration: msmInputDeco(
        "Billing Address",
        prefix: const Icon(Icons.location_city_outlined,
            size: 16, color: Color(0xFF64748B)),
        hint: "Enter billing address (optional)",
      ).copyWith(
        suffixIcon: billingAddressCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded,
                    size: 16, color: textGrey),
                tooltip: "Clear billing address",
                onPressed: () {
                  setState(() {
                    billingAddressCtrl.clear();
                    _isBillingAddressAutoFilled = false;
                  });
                  _saveData();
                },
              )
            : null,
      ),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF0F172A),
      ),
      onChanged: (val) {
        _isBillingAddressAutoFilled = false;
        _saveData();
      },
    );
  }

  Widget _buildConsigneeNameField() {
    final bool isOverridden = !_isConsigneeUntouched &&
        _consigneeNameController.text.trim() != _dealerNameController.text.trim();

    return TextField(
      controller: _consigneeNameController,
      focusNode: consigneeNameFocusNode,
      decoration: msmInputDeco(
        "Consignee Name",
        prefix: const Icon(Icons.person_pin_outlined,
            size: 16, color: Color(0xFF64748B)),
        hint: "Enter consignee name (defaults to Dealer)",
      ).copyWith(
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOverridden)
              IconButton(
                icon: const Icon(Icons.sync,
                    size: 18, color: Color(0xFF0284C7)),
                tooltip: "Re-sync to Dealer Name",
                onPressed: () {
                  setState(() {
                    _consigneeNameController.text = _dealerNameController.text;
                    _isConsigneeUntouched = true;
                  });
                  _saveData();
                },
              ),
            if (_consigneeNameController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_rounded,
                    size: 16, color: textGrey),
                tooltip: "Clear consignee name",
                onPressed: () {
                  setState(() {
                    _consigneeNameController.clear();
                    _isConsigneeUntouched = false;
                  });
                  _saveData();
                },
              ),
          ],
        ),
      ),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
      onChanged: (val) {
        _isConsigneeUntouched = false;
        _saveData();
        setState(() {});
      },
    );
  }

  Widget _buildFirmNameField() {
    final knownFirms = DataRepository.customerAddressCache.keys
        .where((k) => k.trim().isNotEmpty)
        .toList();

    return RawAutocomplete<String>(
      textEditingController: _dealerNameController,
      focusNode: firmNameFocusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim();
        if (query.isEmpty) {
          return knownFirms;
        }
        return knownFirms
            .where((f) => f.toLowerCase().contains(query.toLowerCase()))
            .toList();
      },
      onSelected: (String selection) {
        firmNameCtrl.text = selection;
        _onFirmChanged(selection);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: msmInputDeco(
            "Dealer / Firm Name",
            prefix: const Icon(Icons.business_outlined,
                size: 16, color: Color(0xFF64748B)),
            hint: "Enter client firm name",
          ).copyWith(
            suffixIcon: textEditingController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded,
                        size: 16, color: textGrey),
                    onPressed: () {
                      textEditingController.clear();
                      _onFirmChanged('');
                    },
                  )
                : null,
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          onChanged: (val) => _onFirmChanged(val),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 380),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);
                  final addr = DataRepository.getCustomerAddress(option);
                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: const Icon(Icons.business_rounded,
                        size: 16, color: msmRed),
                    title: Text(
                      option,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    subtitle: addr != null && addr.isNotEmpty
                        ? Text(
                            addr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF64748B)),
                          )
                        : null,
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShippingAddressField() {
    return TextField(
      controller: shippingAddressCtrl,
      minLines: 1,
      maxLines: 3,
      decoration: msmInputDeco(
        "Shipping / Delivery Address",
        prefix: const Icon(Icons.local_shipping_outlined,
            size: 16, color: Color(0xFF64748B)),
        hint: "Enter destination / shipping address (optional)",
      ).copyWith(
        suffixIcon: shippingAddressCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded,
                    size: 16, color: textGrey),
                tooltip: "Clear address",
                onPressed: () {
                  setState(() {
                    shippingAddressCtrl.clear();
                    _isShippingAddressAutoFilled = false;
                  });
                  _saveData();
                },
              )
            : null,
      ),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF0F172A),
      ),
      onChanged: (val) {
        _isShippingAddressAutoFilled = false;
        _saveData();
        if (firmNameCtrl.text.trim().isNotEmpty && val.trim().isNotEmpty) {
          DataRepository.saveCustomerAddress(
              firmNameCtrl.text.trim(), val.trim());
        }
      },
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
    final double totalQty = getTotalEffectiveQty();
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

  Widget _buildSummaryLine({
    required String label,
    required String value,
    bool isBold = false,
    double fontSize = 12.5,
    Color valueColor = const Color(0xFF0F172A),
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: const Color(0xFF475569),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarFooter() {
    final summary = calculateBookingSummary();
    final double totalBookedTonnage = summary['tonnage']! > 0
        ? summary['tonnage']!
        : getTotalEffectiveQty();
    final double baseAndSd = summary['baseAndSd']!;
    final double loading = summary['loading']!;
    final double ncDiscount = summary['ncDiscount']!;
    final double totalFreight = summary['freight']! > 0
        ? summary['freight']!
        : getTotalFreight();
    final double gstAmount = summary['gst']!;
    final double effectiveNetRate = summary['effectiveNetRate'] ?? 0.0;
    final double totalOrder = totalBookedTonnage > 0 && effectiveNetRate > 0
        ? (effectiveNetRate * totalBookedTonnage)
        : (summary['totalOrderValue']! > 0
            ? summary['totalOrderValue']!
            : getTotalOrderValue());
    final bool hasNc = items.any((i) => i.orderType?.trim().toUpperCase() == 'NC');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          // Order summary card showing Base Material + Size Diff, Loading, NC Discount, Freight, GST, and Total Order Value
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSummaryLine(
                  label: "Total Booked Tonnage",
                  value: "${totalBookedTonnage.toStringAsFixed(3)} MT",
                  isBold: true,
                  valueColor: const Color(0xFF0F172A),
                ),
                const SizedBox(height: 6),
                _buildSummaryLine(
                  label: "Base Material + Size Diff",
                  value: baseAndSd > 0
                      ? "₹ ${formatIndianCurrency(baseAndSd)}"
                      : "₹ 0.00",
                  valueColor: const Color(0xFF475569),
                ),
                const SizedBox(height: 6),
                _buildSummaryLine(
                  label: "Loading Charges",
                  value: loading > 0
                      ? "₹ ${formatIndianCurrency(loading)}"
                      : "₹ 0.00",
                  valueColor: const Color(0xFF475569),
                ),
                if (hasNc) ...[
                  const SizedBox(height: 6),
                  _buildSummaryLine(
                    label: "NC Discount",
                    value: ncDiscount > 0
                        ? "-₹ ${formatIndianCurrency(ncDiscount)}"
                        : "-₹ 0.00",
                    isBold: true,
                    valueColor: msmRed,
                  ),
                ],
                const SizedBox(height: 6),
                _buildSummaryLine(
                  label: "Freight",
                  value: totalFreight > 0
                      ? "₹ ${formatIndianCurrency(totalFreight)}"
                      : "₹ 0 (To-Pay)",
                  isBold: totalFreight > 0,
                  valueColor: totalFreight > 0
                      ? msmRed
                      : const Color(0xFF64748B),
                ),
                const SizedBox(height: 6),
                _buildSummaryLine(
                  label: "GST (18%)",
                  value: gstAmount > 0
                      ? "₹ ${formatIndianCurrency(gstAmount)}"
                      : "₹ 0.00",
                  valueColor: const Color(0xFF64748B),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                ),
                _buildSummaryLine(
                  label: "Total Order Value",
                  value: totalOrder > 0
                      ? "₹ ${formatIndianCurrency(totalOrder)}"
                      : "₹ 0.00",
                  isBold: true,
                  fontSize: 13.5,
                  valueColor: const Color(0xFF059669),
                ),
                if (effectiveNetRate > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Center(
                      child: Text(
                        "Effective Landed Net Rate: ₹${effectiveNetRate.round()}/MT",
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                  ),
                ],
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

  void _showMobileSummarySheet() {
    final summary = calculateBookingSummary();
    final double totalBookedTonnage = summary['tonnage']! > 0
        ? summary['tonnage']!
        : getTotalEffectiveQty();
    final double baseAndSd = summary['baseAndSd']!;
    final double loading = summary['loading']!;
    final double ncDiscount = summary['ncDiscount']!;
    final double totalFreight = summary['freight']! > 0
        ? summary['freight']!
        : getTotalFreight();
    final double gstAmount = summary['gst']!;
    final double totalOrder = summary['totalOrderValue']! > 0
        ? summary['totalOrderValue']!
        : getTotalOrderValue();
    final double effectiveNetRate = summary['effectiveNetRate'] ?? 0.0;
    final bool hasNc = items.any((i) => i.orderType == 'NC');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Booking Summary",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  "${totalBookedTonnage.toStringAsFixed(3)} MT",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: msmRed,
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: Color(0xFFE2E8F0)),
            _buildSummaryLine(
              label: "Base Material + Size Diff",
              value: baseAndSd > 0
                  ? "₹ ${formatIndianCurrency(baseAndSd)}"
                  : "₹ 0.00",
              valueColor: const Color(0xFF475569),
            ),
            const SizedBox(height: 6),
            _buildSummaryLine(
              label: "Loading Charges",
              value: loading > 0
                  ? "₹ ${formatIndianCurrency(loading)}"
                  : "₹ 0.00",
              valueColor: const Color(0xFF475569),
            ),
            if (hasNc) ...[
              const SizedBox(height: 6),
              _buildSummaryLine(
                label: "NC Discount",
                value: ncDiscount > 0
                    ? "-₹ ${formatIndianCurrency(ncDiscount)}"
                    : "-₹ 0.00",
                isBold: true,
                valueColor: msmRed,
              ),
            ],
            const SizedBox(height: 6),
            _buildSummaryLine(
              label: "Freight",
              value: totalFreight > 0
                  ? "₹ ${formatIndianCurrency(totalFreight)}"
                  : "₹ 0 (To-Pay)",
              isBold: totalFreight > 0,
              valueColor: totalFreight > 0 ? msmRed : const Color(0xFF64748B),
            ),
            const SizedBox(height: 6),
            _buildSummaryLine(
              label: "GST (18%)",
              value: gstAmount > 0
                  ? "₹ ${formatIndianCurrency(gstAmount)}"
                  : "₹ 0.00",
              valueColor: const Color(0xFF64748B),
            ),
            const Divider(height: 16, color: Color(0xFFE2E8F0)),
            _buildSummaryLine(
              label: "Total Order Value",
              value: totalOrder > 0
                  ? "₹ ${formatIndianCurrency(totalOrder)}"
                  : "₹ 0.00",
              isBold: true,
              valueColor: const Color(0xFF059669),
            ),
            if (effectiveNetRate > 0) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  "Effective Landed Net Rate: ₹${effectiveNetRate.round()}/MT",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF065F46),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileFooter() {
    final summary = calculateBookingSummary();
    final double totalQty = summary['tonnage']! > 0
        ? summary['tonnage']!
        : getTotalEffectiveQty();
    final double totalFreight = summary['freight']! > 0
        ? summary['freight']!
        : getTotalFreight();
    final double totalOrder = summary['totalOrderValue']! > 0
        ? summary['totalOrderValue']!
        : getTotalOrderValue();
    final double effectiveNetRate = summary['effectiveNetRate'] ?? 0.0;
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
          // Sleek Tonnage & Valuation Summary Strip
          InkWell(
            onTap: _showMobileSummarySheet,
            borderRadius: BorderRadius.circular(8),
            child: Container(
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${totalQty.toStringAsFixed(3)} MT",
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: msmRed,
                      ),
                    ),
                    Text(
                      totalFreight > 0
                          ? "Freight: ₹${formatIndianCurrency(totalFreight)}"
                          : "Freight: To-Pay",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                if (effectiveNetRate > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "₹${effectiveNetRate.round()}/MT",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        const Text(
                          "Net Rate",
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      totalOrder > 0
                          ? "₹ ${formatIndianCurrency(totalOrder)}"
                          : "₹ 0.00",
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF059669),
                      ),
                    ),
                    const Text(
                      "Total Order Value",
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
        final rawLabel = (v['size_label'] ?? v['label'] ?? '').toString();
        final rawWeight = v['unit_weight_kg'] ?? v['weight'];
        double w = (rawWeight as num?)?.toDouble() ??
            double.tryParse(rawWeight?.toString() ?? '') ??
            0;
        sizeObj.size = getFormattedSizeDisplay(rawLabel, w > 0 ? w : null);
        final rawId = v['id'];
        sizeObj.sizeId = rawId != null ? int.tryParse(rawId.toString()) : null;
        if (w <= 0) w = lookupSizeWeight(sizeObj.size);
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

  Widget _buildFreightFieldRow() {
    final hasFreight = freightCharge > 0;
    final isPerMt = freightType == 'PER_MT';

    final summary = calculateBookingSummary();
    final double effectiveNetRate = summary['effectiveNetRate'] ?? 0.0;
    final double firstItemNetRate = items.isNotEmpty
        ? items.first
            .getNetRatePerMT(charges: DataRepository.instance.globalCharges)
        : 0.0;
    final double displayNetRate =
        effectiveNetRate > 0 ? effectiveNetRate : firstItemNetRate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasFreight
              ? msmRed.withValues(alpha: 0.25)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined,
                  size: 16, color: msmRed),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  "Freight",
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasFreight) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: msmRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPerMt
                        ? "₹${formatIndianCurrency(freightCharge)} / MT"
                        : "Fixed: ₹${formatIndianCurrency(freightCharge)}",
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: msmRed,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;
              final freightInput = TextField(
                controller: freightCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
                decoration: msmInputDeco(
                  isPerMt
                      ? "Freight Charge (₹ / MT)"
                      : "Freight (₹)",
                  hint: "e.g. 850 or 0",
                  prefix: const Icon(Icons.currency_rupee,
                      size: 14, color: Color(0xFF64748B)),
                ),
                onChanged: (v) {
                  final charge = double.tryParse(v) ?? 0.0;
                  freightCharge = charge;
                  for (var it in items) {
                    it.freightCharge = charge;
                    it.freightType = freightType;
                    it.freightCtrl.text = v;
                  }
                  _saveData();
                  setState(() {});
                },
              );

              final freightDropdown = DropdownButtonFormField<String>(
                initialValue: freightType,
                decoration: msmInputDeco("Freight Type"),
                items: const [
                  DropdownMenuItem(
                    value: 'PER_MT',
                    child: Text("Per MT (₹/MT)",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  DropdownMenuItem(
                    value: 'FIXED',
                    child: Text("Lump Sum (₹)",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      freightType = v;
                      for (var it in items) {
                        it.freightType = v;
                      }
                      _saveData();
                    });
                  }
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    freightInput,
                    const SizedBox(height: 8),
                    freightDropdown,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: freightInput),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: freightDropdown),
                ],
              );
            },
          ),
          if (displayNetRate > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 13, color: Color(0xFF059669)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      "Effective Landed Net Rate: ₹${displayNetRate.round()}/MT",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF065F46),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
  double freightCharge = 0.0;
  String freightType = 'PER_MT'; // 'PER_MT' or 'FIXED'
  bool manualMode = false;
  double manualQty = 0;
  final TextEditingController rateCtrl = TextEditingController();
  final TextEditingController freightCtrl = TextEditingController();
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

  double calculateFreight() {
    if (freightCharge <= 0) return 0.0;
    if (freightType == 'FIXED') return freightCharge;
    return getTotalQty() * freightCharge;
  }

  double getBaseMaterialValue() {
    double q = getTotalQty();
    double r = rate > 0 ? rate : basicRate;
    return q * r;
  }

  double getEffectiveLandedRate() {
    return getNetRatePerMT();
  }

  double getNetRatePerMT({GlobalCharges? charges, double ob = 0.0}) {
    final double baseRate = rate > 0 ? rate : basicRate;
    if (baseRate <= 0) return 0.0;
    double sd = 0.0;
    for (var s in sizes) {
      if (s.size.isNotEmpty) {
        final currentSd = DataRepository.getSizeSD(itemType, s.size);
        if (currentSd != 0) {
          sd = currentSd;
          break;
        }
      }
    }
    double fPerMt = 0.0;
    if (freightCharge > 0) {
      if (freightType == 'PER_MT') {
        fPerMt = freightCharge;
      } else {
        double q = getTotalQty();
        fPerMt = q > 0 ? (freightCharge / q) : freightCharge;
      }
    }
    final calcResult = SaudaRateCalculator.calculate(
      saudaRate: baseRate,
      sd: sd,
      charges: charges ?? DataRepository.instance.globalCharges,
      billType: orderType ?? 'BILL',
      itemType: itemType,
      freight: fPerMt,
      ob: ob,
      isPieces: isPiecesItem(),
    );
    return calcResult.netRate;
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
    freightCtrl.dispose();
    for (var s in sizes) {
      s.dispose();
    }
  }
}

class SaudaSize {
  String size = "";
  int? sizeId;
  double weight = 0;
  double nos = 0;
  double total = 0;
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController nosCtrl = TextEditingController();
  final TextEditingController mtCtrl = TextEditingController();

  String sizeDescriptionLabel(String? itemType) {
    if (size.isEmpty) return "";
    return getFormattedSizeDisplay(size, weight > 0 ? weight : null);
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
