import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/report_models.dart';
import '../models/stock_role.dart';
import '../services/data_repository.dart';
import '../services/pdf_report_service.dart';
import '../utils/file_download_helper.dart' as download_helper;
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import '../utils/steel_helper.dart';
import '../widgets/motion_toast.dart';
import '../widgets/responsive_size_picker.dart';
import 'permission_denied_screen.dart';

/// Appends " kg" to a size label unless the product category is one of the
/// excluded bar/wire types (same rule as Stock Movement report).
String _appendKgSuffixSales(String productName, String sizeLabel) {
  const excluded = [
    'sqr bar',
    'round bar',
    'flats',
    'barbed wire',
    'gate channel',
  ];
  final lower = productName.toLowerCase();
  if (excluded.any((ex) => lower.contains(ex))) return sizeLabel;
  return getFormattedSizeDisplay(sizeLabel, null);
}

/// SalesDocumentCenterScreen
/// A dynamic Proforma Invoice (PI) and Quotation (QT) generator.
/// Features: Toggle PI/QT, Dynamic Sr No, Editable Product Table, GST Calc, Amount in Words.
class SalesDocumentCenterScreen extends StatefulWidget {
  const SalesDocumentCenterScreen({super.key});

  @override
  State<SalesDocumentCenterScreen> createState() =>
      _SalesDocumentCenterScreenState();
}

class _SalesDocumentCenterScreenState extends State<SalesDocumentCenterScreen> {
  // Theme Constants
  static const Color primaryRed = Color(0xFFD32F2F);
  static const Color slateBorder = Color(0xFFE2E8F0);
  static const Color slateDarkBorder = Color(0xFF334155);

  // Toggle State
  bool _isPI = true; // true = Proforma Invoice, false = Quotation
  bool _isPreparingPdf = false;

  // Header Controllers
  final TextEditingController _srNoController = TextEditingController();
  final TextEditingController _dateController =
      TextEditingController(text: DateFormat('dd-MM-yyyy').format(DateTime.now()));
  final TextEditingController _firmNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _gstNoController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();

  // Terms & Bank Details Controllers
  final TextEditingController _termsController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accNoController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _freightController = TextEditingController(text: "");

  // Table Data
  final List<SalesProductGroup> _items = [];

  // Settings for Quotation logic
  bool gstEnabled = true;
  bool ncDiscountEnabled = false;
  double globalFreight = 0;
  double globalOB = 0;
  double loading = 255;
  double ncDiscount = 3000;
  double gstRate = 0.18;

  // Sheet Data
  List<Map<String, dynamic>> _sheetItems = [];
  bool _isLoadingSheetData = true;
  static Map<String, List<Map<String, dynamic>>> sheetItemDataMap = {};

  @override
  void initState() {
    super.initState();

    // Guard: Check admin permissions
    if (!UserSession.isUserAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const PermissionDeniedScreen(
              screenName: "Sales Document Center",
            ),
          ),
        );
      });
      return;
    }

    _updateSrNo();
    _updateSubject();
    _initDefaults();
    _loadSheetData();
  }

  @override
  void dispose() {
    _srNoController.dispose();
    _dateController.dispose();
    _firmNameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _gstNoController.dispose();
    _subjectController.dispose();
    _termsController.dispose();
    _bankNameController.dispose();
    _accNoController.dispose();
    _ifscController.dispose();
    _branchController.dispose();
    _freightController.dispose();
    for (final item in _items) {
      item.basicRateController.dispose();
      for (final s in item.sizes) {
        s.nosController.dispose();
        s.qtyController.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadSheetData() async {
    try {
      final data = await DataRepository.getSheetDataAsync(null);
      if (mounted) {
        setState(() {
          if (data['meta'] != null) {
            final meta = data['meta'];
            final double rawGst =
                double.tryParse(meta['gst_rate']?.toString() ?? '0.18') ?? 0.18;
            gstRate = rawGst > 1.0 ? rawGst / 100.0 : rawGst;
            loading =
                double.tryParse(meta['loading_charge']?.toString() ?? '255') ??
                    255;
            ncDiscount =
                double.tryParse(meta['nc_discount']?.toString() ?? '3000') ??
                    3000;
            debugPrint(
                '[SalesDocCenter] Loaded: GST=${(gstRate * 100).toStringAsFixed(2)}% LC=₹$loading NC=₹$ncDiscount');
          }
          _sheetItems = List<Map<String, dynamic>>.from(data['items'] ?? []);
          final Map<String, List<Map<String, dynamic>>> tempMap = {};
          for (final item in _sheetItems) {
            final name = item['name'] as String;
            final sizes = List<Map<String, dynamic>>.from(item['sizes'] ?? []);
            tempMap[name] = sizes;
          }
          final sortedKeys = tempMap.keys.toList()
            ..sort(SortingUtils.compareCategories);
          final Map<String, List<Map<String, dynamic>>> sortedMap = {};
          for (final key in sortedKeys) {
            sortedMap[key] = tempMap[key]!;
          }
          sheetItemDataMap = sortedMap;
          _isLoadingSheetData = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading sheet data: $e");
      if (mounted) {
        setState(() => _isLoadingSheetData = false);
      }
    }
  }

  void _initDefaults() {
    _termsController.text = "1. Rates: FOR\n"
        "2. Payment Terms: 100% Advance\n"
        "3. Unloading: At your end/cost\n"
        "4. Weight Tolerance: +0.5% allowed without deduction\n"
        "5. Delivery: FOR within 4-6 days\n"
        "6. Transport: Inclusive";
    _bankNameController.text = "ICICI BANK LTD";
    _accNoController.text = "777705854699";
    _ifscController.text = "ICIC0006469";
    _branchController.text = "JALNA";
  }

  void _updateSrNo() {
    setState(() {
      _srNoController.text = _isPI ? "MSMPL/26-27/PI/05" : "MSMPL/26-27/QT/05";
    });
  }

  void _updateSubject() {
    setState(() {
      _subjectController.text = _isPI
          ? "Proforma Invoice for the supply of structural items."
          : "Quotation for the supply of structural items.";
    });
  }

  // Calculations
  double get _subtotal =>
      _items.fold(0, (sum, group) => sum + group.totalAmount);
  double get _totalQty =>
      _items.fold(0.0, (sum, group) => sum + group.totalQty);
  double get _freightRatePerMt =>
      double.tryParse(_freightController.text) ?? 0.0;
  double get _totalFreightAmount => _totalQty * _freightRatePerMt;
  double get _taxableAmount => _subtotal + _totalFreightAmount;
  double get _gst => _taxableAmount * 0.18;
  double get _grandTotal => _taxableAmount + _gst;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
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
          "Sales Document Center",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? slateDarkBorder : slateBorder,
            height: 1,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Document Mode Switcher
                _buildToggleSection(isDark),
                const SizedBox(height: 20),

                // 2. Document & Customer Information Card
                _buildEnterpriseCard(
                  isDark: isDark,
                  child: _buildHeaderForm(isDark),
                ),
                const SizedBox(height: 20),

                // 3. Products & Line Items Table Card
                _buildEnterpriseCard(
                  isDark: isDark,
                  child: _buildProductTable(isDark),
                ),
                const SizedBox(height: 20),

                // 4. Financial Summary Card
                _buildEnterpriseCard(
                  isDark: isDark,
                  child: _buildFooterSection(isDark),
                ),
                const SizedBox(height: 20),

                // 5. Terms & Bank Details Card
                _buildEnterpriseCard(
                  isDark: isDark,
                  child: _buildTermsAndBankDetailsSection(isDark),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isPreparingPdf ? () {} : _generateAndDownloadPdf,
        label: Text(
          _isPreparingPdf ? "Preparing PDF..." : "Generate PDF",
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        icon: _isPreparingPdf
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
        backgroundColor: _isPreparingPdf ? Colors.grey.shade600 : primaryRed,
        elevation: 4,
      ),
    );
  }

  // --- PDF GENERATION LOGIC ---

  Future<void> _generateAndDownloadPdf() async {
    if (_isPreparingPdf) return;
    if (_firmNameController.text.trim().isEmpty) {
      MotionToast.show(context, "Please enter Firm Name", isError: true);
      return;
    }

    try {
      setState(() {
        _isPreparingPdf = true;
      });

      MotionToast.show(context, "Preparing PDF Document...");

      // 1. Prepare items
      final List<SalesDocumentItem> documentItems = [];
      for (var group in _items) {
        for (var size in group.sizes) {
          documentItems.add(SalesDocumentItem(
            description: group.productName,
            size: size.sizeLabel,
            nos: size.nos,
            qty: size.qty,
            rate: size.rate,
            total: size.amount,
            unitWeight: size.unitWeight,
          ));
        }
      }

      // 2. Build model
      final model = SalesDocumentModel(
        title: _isPI ? "Proforma Invoice" : "Quotation",
        srNo: _srNoController.text,
        date: _dateController.text,
        firmName: _firmNameController.text,
        address: _addressController.text,
        email: _emailController.text,
        mobile: _mobileController.text,
        gstNo: _gstNoController.text,
        subject: _subjectController.text,
        items: documentItems,
        terms: _termsController.text,
        bankName: _bankNameController.text,
        accNo: _accNoController.text,
        ifsc: _ifscController.text,
        branch: _branchController.text,
        subtotal: _subtotal,
        freight: _totalFreightAmount,
        freightRatePerMt: _freightRatePerMt,
        gst: _gst,
        grandTotal: _grandTotal,
        amountInWords:
            "INR ${AmountToWords.convert(_grandTotal).toUpperCase()} ONLY",
      );

      // 3. Generate PDF (High Fidelity Replica)
      final pdfBytes = await PdfReportService.generateProformaInvoiceReplicaPdf(
          model: model);

      // 4. Show Print/Save Dialog
      String sanitizedFirmName = _firmNameController.text
          .replaceAll(RegExp(r'[^a-zA-Z0-9_ ]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      if (sanitizedFirmName.isEmpty) sanitizedFirmName = "Document";

      String docType = _isPI ? "Proforma_Invoice" : "Quotation";
      String safeSrNo =
          _srNoController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      String fileName = "${sanitizedFirmName}_${docType}_$safeSrNo"
          .replaceAll(RegExp(r'_+'), '_');
      if (fileName.endsWith('_')) {
        fileName = fileName.substring(0, fileName.length - 1);
      }
      if (fileName.startsWith('_')) {
        fileName = fileName.substring(1);
      }

      fileName += ".pdf";

      download_helper.setDocumentTitle(fileName);
      SystemChrome.setApplicationSwitcherDescription(
          ApplicationSwitcherDescription(
        label: fileName,
        primaryColor: 0,
      ));

      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: fileName,
      );

      // Delay resetting the title to ensure Chrome's Save As dialog captures it
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          download_helper.setDocumentTitle("Metaroll Steel Mart");
          SystemChrome.setApplicationSwitcherDescription(
              const ApplicationSwitcherDescription(
            label: "Metaroll Steel Mart",
            primaryColor: 0,
          ));
        }
      });
    } catch (e) {
      debugPrint("PDF Generation Error: $e");
      if (mounted) {
        MotionToast.show(context, "Error generating PDF: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingPdf = false;
        });
      }
    }
  }

  // --- UI BUILDERS ---

  Widget _buildToggleSection(bool isDark) {
    return Center(
      child: Material(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? slateDarkBorder : slateBorder,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _buildToggleButton("Proforma Invoice", _isPI, () {
                  setState(() {
                    _isPI = true;
                    _updateSrNo();
                    _updateSubject();
                  });
                }),
              ),
              Flexible(
                child: _buildToggleButton("Quotation", !_isPI, () {
                  setState(() {
                    _isPI = false;
                    _updateSrNo();
                    _updateSubject();
                  });
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? primaryRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryRed.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildEnterpriseCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? slateDarkBorder : slateBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primaryRed,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _buildHeaderForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Document Information"),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 700;
          return Column(
            children: [
              _buildRow(isDesktop, [
                _buildField(
                  "Sr No / Reference",
                  _srNoController,
                  Icons.tag_rounded,
                  isDark: isDark,
                ),
                _buildDatePickerField(isDark),
              ]),
              const SizedBox(height: 14),
              _buildField(
                "Firm Name (To:)",
                _firmNameController,
                Icons.business_rounded,
                isDark: isDark,
                prominent: true,
              ),
              const SizedBox(height: 14),
              _buildField(
                "Address",
                _addressController,
                Icons.location_on_outlined,
                isDark: isDark,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              _buildRow(isDesktop, [
                _buildField(
                  "Email Address",
                  _emailController,
                  Icons.email_outlined,
                  isDark: isDark,
                ),
                _buildField(
                  "Mobile No",
                  _mobileController,
                  Icons.phone_android_rounded,
                  isDark: isDark,
                ),
                _buildField(
                  "GSTIN",
                  _gstNoController,
                  Icons.receipt_long_outlined,
                  isDark: isDark,
                ),
              ]),
              const SizedBox(height: 14),
              _buildField(
                "Subject",
                _subjectController,
                Icons.subject_rounded,
                isDark: isDark,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildDatePickerField(bool isDark) {
    return TextFormField(
      controller: _dateController,
      readOnly: true,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        labelText: "Date",
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(Icons.calendar_today_rounded,
            color: primaryRed, size: 16),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryRed, width: 1.5),
        ),
      ),
      onTap: () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
        DateTime initial = now;
        try {
          if (_dateController.text.isNotEmpty) {
            initial = DateFormat('dd-MM-yyyy').parse(_dateController.text);
          }
        } catch (_) {}

        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: initial.isAfter(today) ? now : initial,
          firstDate: DateTime(2020),
          lastDate: today,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: primaryRed,
                  onPrimary: Colors.white,
                  onSurface: Color(0xFF1E293B),
                ),
              ),
              child: child!,
            );
          },
        );
        if (pickedDate != null) {
          String formattedDate =
              "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
          setState(() {
            _dateController.text = formattedDate;
          });
        }
      },
    );
  }

  Widget _buildProductTable(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          "Products & Items",
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoadingSheetData)
                const Padding(
                  padding: EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryRed,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${_items.length} items added",
                  style: const TextStyle(
                    fontSize: 11,
                    color: primaryRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? slateDarkBorder : slateBorder,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 36,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 8),
                Text(
                  "No items added yet. Click 'Add New Product' below.",
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          ..._items.asMap().entries.map((e) => _buildItemCard(e.value, e.key, isDark)),
        const SizedBox(height: 16),
        _buildAddItemButton(isDark),
      ],
    );
  }

  Widget _buildItemCard(SalesProductGroup item, int index, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? slateDarkBorder : slateBorder,
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: index == _items.length - 1,
          iconColor: primaryRed,
          collapsedIconColor: isDark ? Colors.white70 : const Color(0xFF64748B),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            decoration: BoxDecoration(
              color: primaryRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(7),
            child: const Icon(Icons.inventory_2_outlined,
                color: primaryRed, size: 18),
          ),
          title: Text(
            item.productName.isEmpty ? "Select Product" : item.productName,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "${item.totalQty.toStringAsFixed(3)} MT",
                    style: const TextStyle(
                      color: primaryRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "₹ ${NumberFormat.currency(symbol: "", decimalDigits: 0, locale: "en_IN").format(item.totalAmount)}",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            Divider(color: isDark ? slateDarkBorder : slateBorder, height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _showSalesItemPicker(context, item),
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Product Type',
                        labelStyle: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                          ),
                        ),
                        suffixIcon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: primaryRed,
                          size: 20,
                        ),
                      ),
                      child: Text(
                        item.productName.isEmpty
                            ? "Select Product"
                            : item.productName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: primaryRed, size: 20),
                  tooltip: "Remove Product",
                  style: IconButton.styleFrom(
                    backgroundColor: primaryRed.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => setState(() => _items.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: item.basicRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                _recalcAllSizes(item);
                setState(() {});
              },
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: "Basic Rate (₹/MT)",
                labelStyle: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                prefixText: "₹ ",
                prefixStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: primaryRed,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: primaryRed, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (item.sizes.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 3,
                      child: Text(
                        "SIZE",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        "RATE (₹)",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
                        .contains(item.productName))
                      const Expanded(
                        flex: 2,
                        child: Text(
                          "NOS",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                            color: Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        "QTY (MT)",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Expanded(
                      flex: 3,
                      child: Text(
                        "AMOUNT",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 28),
                  ],
                ),
              ),
              ...item.sizes
                  .asMap()
                  .entries
                  .map((entry) => _buildSizeRow(item, entry.key, entry.value, isDark)),
              const SizedBox(height: 10),
            ],
            _buildAddSizeButton(item, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeRow(
      SalesProductGroup item, int sizeIndex, SalesSizeRow s, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => _showAddSizeBottomSheet(item, existingSize: s),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? slateDarkBorder : slateBorder,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatSizeLabel(
                            _appendKgSuffixSales(item.productName, s.sizeLabel),
                            item.productName,
                            s.unitWeight),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: primaryRed,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.edit_note_rounded,
                      color: primaryRed.withValues(alpha: 0.6),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              s.rate.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
              .contains(item.productName))
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: s.nosController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    s.nos = int.tryParse(v) ?? 0;
                    _recalcQtyFromNos(s);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: "0",
                    hintStyle: TextStyle(
                      color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                      borderSide: BorderSide(color: primaryRed, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: s.qtyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
                onChanged: (v) {
                  s.qty = double.tryParse(v) ?? 0;
                  _recalcNosFromQty(s);
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: "0.0",
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide(color: primaryRed, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              NumberFormat.currency(
                      symbol: "₹", decimalDigits: 0, locale: "en_IN")
                  .format(s.amount),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => setState(() => item.sizes.removeAt(sizeIndex)),
            icon: Icon(
              Icons.remove_circle_outline_rounded,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              size: 18,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Delete size",
          ),
        ],
      ),
    );
  }

  Widget _buildAddSizeButton(SalesProductGroup item, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          backgroundColor: primaryRed.withValues(alpha: 0.08),
        ),
        onPressed: () => _showAddSizeBottomSheet(item),
        icon: const Icon(Icons.add_circle_outline_rounded,
            color: primaryRed, size: 16),
        label: const Text(
          "Add Size",
          style: TextStyle(
            color: primaryRed,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildAddItemButton(bool isDark) {
    return Align(
      alignment: Alignment.center,
      child: OutlinedButton.icon(
        onPressed: _showAddItemBottomSheet,
        icon: const Icon(Icons.add_circle_outline_rounded,
            color: primaryRed, size: 18),
        label: const Text(
          "Add New Product",
          style: TextStyle(
            color: primaryRed,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          side: const BorderSide(color: primaryRed, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          backgroundColor: primaryRed.withValues(alpha: 0.04),
        ),
      ),
    );
  }

  void _showAddItemBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? slateDarkBorder : slateBorder,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.category_rounded,
                          color: primaryRed, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Select Product Type",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sheetItemDataMap.keys.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    String cat = sheetItemDataMap.keys.elementAt(index);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _items.add(SalesProductGroup(productName: cat));
                        });
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark ? slateDarkBorder : slateBorder,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                                color: primaryRed, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const Icon(Icons.add_circle_outline_rounded,
                                color: primaryRed, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddSizeBottomSheet(SalesProductGroup item,
      {SalesSizeRow? existingSize}) async {
    List<Map<String, dynamic>> sizes = sheetItemDataMap[item.productName] ?? [];
    if (sizes.isEmpty) return;

    final result = await ResponsiveSizePicker.show(
      context,
      itemType: item.productName,
      customSizes: sizes
          .map((s) => {
                'label': s['label']?.toString() ?? '',
                'weight':
                    double.tryParse(s['weight']?.toString() ?? '0') ?? 0.0,
                'sd': double.tryParse(s['sd']?.toString() ?? '0') ?? 0.0,
              })
          .toList(),
    );

    if (result != null && mounted) {
      final label = result['label'] as String;
      final sd = (result['sd'] as num).toDouble();
      final weight = (result['weight'] as num).toDouble();

      setState(() {
        if (existingSize != null) {
          existingSize.sizeLabel = label;
          existingSize.sd = sd;
          existingSize.unitWeight = weight;
          _recalcAllSizes(item);
        } else {
          final newSize = SalesSizeRow(
            sizeLabel: label,
            sd: sd,
            unitWeight: weight,
          );
          item.sizes.add(newSize);
          _recalcAllSizes(item);
        }
      });
    }
  }

  double netRate(SalesProductGroup item, SalesSizeRow size) {
    double gross =
        item.basicRate + size.sd + globalFreight + globalOB + loading;
    double finalVal = gross;
    if (ncDiscountEnabled) {
      finalVal -= ncDiscount;
    }
    return finalVal;
  }

  void _recalcAllSizes(SalesProductGroup item) {
    for (var s in item.sizes) {
      s.rate = netRate(item, s);
    }
  }

  void _recalcQtyFromNos(SalesSizeRow s) {
    if (s.unitWeight > 0) {
      s.qty = (s.nos * s.unitWeight) / 1000;
      s.qtyController.text = s.qty.toStringAsFixed(3);
    }
  }

  void _recalcNosFromQty(SalesSizeRow s) {
    if (s.unitWeight > 0) {
      s.nos = ((s.qty * 1000) / s.unitWeight).round();
      s.nosController.text = s.nos.toString();
    }
  }

  Widget _buildFooterSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Financial Summary"),
        const SizedBox(height: 16),
        _buildSummaryRow("Subtotal", _subtotal, isDark: isDark),
        Divider(
          color: isDark ? slateDarkBorder : slateBorder,
          height: 24,
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  "Freight (per MT) [${_totalQty.toStringAsFixed(3)} MT]:",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
                SizedBox(
                  width: 95,
                  child: TextFormField(
                    controller: _freightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                    ],
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: "0.00",
                      prefixText: "₹ ",
                      prefixStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: primaryRed,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        borderSide: BorderSide(color: primaryRed, width: 1.2),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            Text(
              NumberFormat.currency(symbol: "₹", locale: "en_IN")
                  .format(_totalFreightAmount),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSummaryRow("GST @ 18%", _gst, isDark: isDark),
        const SizedBox(height: 12),
        _buildSummaryRow("Grand Total", _grandTotal,
            isGrand: true, isDark: isDark),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: primaryRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: primaryRed.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Amount in Words:",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: primaryRed,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "INR ${AmountToWords.convert(_grandTotal).toUpperCase()} ONLY",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsAndBankDetailsSection(bool isDark) {
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 700;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Terms & Bank Details"),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Terms & Conditions",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      "Terms",
                      _termsController,
                      Icons.list_alt_rounded,
                      isDark: isDark,
                      maxLines: 5,
                    ),
                  ],
                ),
              ),
              if (isDesktop) const SizedBox(width: 24),
              if (isDesktop)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Bank Details",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildBankDetailsGrid(isDesktop, isDark),
                      _buildBillingDetailsSection(isDesktop, isDark),
                    ],
                  ),
                ),
            ],
          ),
          if (!isDesktop) ...[
            const SizedBox(height: 24),
            Text(
              "Bank Details",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            _buildBankDetailsGrid(isDesktop, isDark),
            _buildBillingDetailsSection(isDesktop, isDark),
          ]
        ],
      );
    });
  }

  Widget _buildBillingDetailsSection(bool isDesktop, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          "Billing Details",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        _buildBillingRow(
          "Company",
          Text("Metarolls Steel Mart Private Limited",
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isDark ? Colors.white : const Color(0xFF0F172A))),
        ),
        _buildBillingRow(
          "Address",
          Text(
            "Gut No. 48, Adjacent to MIDC, Phase II, Daregaon, Jalna - 431213",
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ),
        _buildBillingRow(
          "GSTIN / PAN",
          Text(
            "GSTIN/UIN: 27AARCM5928R1ZB | PAN: AARCM5928R",
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ),
        _buildBillingRow(
          "State / Code",
          Text(
            "State Name: Maharashtra | State Code: 27",
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ),
        _buildBillingRow(
          "CIN",
          Text(
            "U24109MH2023PTC415690",
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
        ),
        _buildBillingRow(
          "Email",
          InkWell(
            onTap: () async {
              final Uri emailLaunchUri = Uri(
                scheme: 'mailto',
                path: 'metarollssteelmart@metarolls.com',
              );
              if (await canLaunchUrl(emailLaunchUri)) {
                await launchUrl(emailLaunchUri);
              }
            },
            child: const Text(
              "metarollssteelmart@metarolls.com",
              style: TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBillingRow(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          const Text(" :  ",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                color: Color(0xFF64748B),
              )),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _buildBankDetailsGrid(bool isDesktop, bool isDark) {
    return Column(
      children: [
        _buildField("Bank Name", _bankNameController, Icons.account_balance_rounded,
            isDark: isDark),
        const SizedBox(height: 12),
        _buildRow(isDesktop, [
          _buildField("Account No", _accNoController, Icons.numbers_rounded,
              isDark: isDark),
          _buildField("IFSC Code", _ifscController, Icons.code_rounded,
              isDark: isDark),
        ]),
        const SizedBox(height: 12),
        _buildField("Branch Name", _branchController, Icons.map_rounded,
            isDark: isDark),
      ],
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    bool prominent = false,
    bool readOnly = false,
    required bool isDark,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      style: TextStyle(
        fontSize: prominent ? 14.5 : 13,
        fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: primaryRed, size: 16),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? slateDarkBorder : const Color(0xFFCBD5E1),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: primaryRed, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildRow(bool isDesktop, List<Widget> children) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children
            .expand((w) => [Expanded(child: w), const SizedBox(width: 14)])
            .toList()
          ..removeLast(),
      );
    }
    return Column(
      children: children
          .expand((w) => [w, const SizedBox(height: 12)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _buildSummaryRow(String label, double amount,
      {bool isGrand = false, required bool isDark}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isGrand ? 16 : 13,
            fontWeight: isGrand ? FontWeight.w800 : FontWeight.w600,
            color: isGrand
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark ? Colors.white70 : const Color(0xFF475569)),
          ),
        ),
        Text(
          NumberFormat.currency(symbol: "₹", locale: "en_IN").format(amount),
          style: TextStyle(
            fontSize: isGrand ? 18 : 14,
            fontWeight: FontWeight.w800,
            color: isGrand ? primaryRed : (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  void _showSalesItemPicker(BuildContext context, SalesProductGroup groupItem) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> allNames = sheetItemDataMap.keys.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = "";
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = applyPrioritizedSearch(query, allNames, (n) => n);

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 16,
                  left: 16,
                  right: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Select Item",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: "Search item...",
                        hintStyle: TextStyle(
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: primaryRed, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? slateDarkBorder : slateBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? slateDarkBorder : slateBorder,
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: primaryRed, width: 1.5),
                        ),
                      ),
                      onChanged: (val) => setSheetState(() => query = val),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                "No item found",
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) => Divider(
                                height: 1,
                                color: isDark ? slateDarkBorder : slateBorder,
                              ),
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  leading: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: primaryRed.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Image.asset(
                                      'assets/images/icons/${name.toLowerCase().replaceAll(' ', '_')}.png',
                                      width: 20,
                                      height: 20,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.category_rounded,
                                              color: primaryRed, size: 18),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context, name);
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((selectedName) {
      if (selectedName != null && selectedName is String && mounted) {
        setState(() {
          groupItem.productName = selectedName;
          groupItem.sizes.clear();
        });
      }
    });
  }
}

/// Data Model for Sales Product Groups
class SalesProductGroup {
  String productName;
  final TextEditingController basicRateController = TextEditingController();
  List<SalesSizeRow> sizes = [];

  SalesProductGroup({required this.productName, List<SalesSizeRow>? sizes})
      : sizes = sizes ?? [];

  double get basicRate => double.tryParse(basicRateController.text) ?? 0.0;

  double get totalQty => sizes.fold(0.0, (sum, s) => sum + s.qty);
  double get totalAmount => sizes.fold(0.0, (sum, s) => sum + s.amount);
}

class SalesSizeRow {
  String sizeLabel;
  double sd;
  double unitWeight;
  int nos;
  double qty;
  double rate;

  final TextEditingController nosController;
  final TextEditingController qtyController;

  SalesSizeRow({
    required this.sizeLabel,
    required this.sd,
    this.unitWeight = 0,
    this.nos = 0,
    this.qty = 0,
    this.rate = 0,
  })  : nosController =
            TextEditingController(text: nos == 0 ? '' : nos.toString()),
        qtyController =
            TextEditingController(text: qty == 0 ? '' : qty.toString());

  // Precision lock: round at the presentation layer
  double get amount => (rate * qty).roundToDouble();
}

/// Utility for converting Amount to Words
class AmountToWords {
  static const _units = [
    "",
    "One",
    "Two",
    "Three",
    "Four",
    "Five",
    "Six",
    "Seven",
    "Eight",
    "Nine"
  ];
  static const _teens = [
    "Ten",
    "Eleven",
    "Twelve",
    "Thirteen",
    "Fourteen",
    "Fifteen",
    "Sixteen",
    "Seventeen",
    "Eighteen",
    "Nineteen"
  ];
  static const _tens = [
    "",
    "",
    "Twenty",
    "Thirty",
    "Forty",
    "Fifty",
    "Sixty",
    "Seventy",
    "Eighty",
    "Ninety"
  ];

  static String convert(double amount) {
    if (amount == 0) return "Zero";

    int total = (amount * 100).round();
    int rupees = total ~/ 100;
    int paisa = total % 100;

    String result = _convertRecursive(rupees);

    if (paisa > 0) {
      result += " and ${_convertRecursive(paisa)} Paisa";
    }

    return result.trim();
  }

  static String _convertRecursive(int n) {
    if (n < 0) return "Minus ${_convertRecursive(-n)}";
    if (n < 10) return _units[n];
    if (n < 20) return _teens[n - 10];
    if (n < 100) {
      return "${_tens[n ~/ 10]}${n % 10 != 0 ? " ${_units[n % 10]}" : ""}";
    }
    if (n < 1000) {
      return "${_units[n ~/ 100]} Hundred${n % 100 != 0 ? " and ${_convertRecursive(n % 100)}" : ""}";
    }
    if (n < 100000) {
      return "${_convertRecursive(n ~/ 1000)} Thousand${n % 1000 != 0 ? " ${_convertRecursive(n % 1000)}" : ""}";
    }
    if (n < 10000000) {
      return "${_convertRecursive(n ~/ 100000)} Lakh${n % 100000 != 0 ? " ${_convertRecursive(n % 100000)}" : ""}";
    }
    return "${_convertRecursive(n ~/ 10000000)} Crore${n % 10000000 != 0 ? " ${_convertRecursive(n % 10000000)}" : ""}";
  }
}
