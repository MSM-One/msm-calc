import 'package:flutter/material.dart';
import '../widgets/motion_toast.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pdf_report_service.dart';
import '../models/report_models.dart';
import '../services/sheet_service.dart';
import '../services/data_repository.dart';
import '../services/access_guard.dart';
import '../models/permission_model.dart';
import '../models/stock_role.dart';
import 'permission_denied_screen.dart';
import '../utils/file_download_helper.dart' as download_helper;
import '../utils/formatters.dart';
import '../utils/sorting_utils.dart';
import '../widgets/responsive_size_picker.dart';
import '../utils/steel_helper.dart';

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
  // Theme Configuration
  static const Color metarollRed = Color(0xFFE53935);
  static const Color glassWhite = Color(0xCCFFFFFF);
  static const double borderRadius = 24.0;

  // Toggle State
  bool _isPI = true; // true = Proforma Invoice, false = Quotation
  bool _isPreparingPdf = false;

  // Header Controllers
  final TextEditingController _srNoController = TextEditingController();
  final TextEditingController _dateController =
      TextEditingController(text: "19-05-2026");
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
  final TextEditingController _freightController =
      TextEditingController(text: "");

  // Table Data
  final List<SalesProductGroup> _items = [];

  // Settings for Quotation logic
  bool gstEnabled = true;
  bool ncDiscountEnabled = false;
  double globalFreight = 0;
  double globalOB = 0;
  double loading = 0;
  double ncDiscount = 3000; // overridden by nc_discount from global_charges
  double gstRate = 0.18;

  // Sheet Data
  List<Map<String, dynamic>> _sheetItems = [];
  bool _isLoadingSheetData = true;
  static Map<String, List<Map<String, dynamic>>> sheetItemDataMap = {};

  @override
  void initState() {
    super.initState();

    // Guard: Only admin can access.
    if (!UserSession.isUserAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const PermissionDeniedScreen(
                  screenName: "Sales Document Center")),
        );
      });
      return;
    }

    _updateSrNo();
    _updateSubject();
    _initDefaults();
    _loadSheetData();
  }

  Future<void> _loadSheetData() async {
    try {
      // ── Use DataRepository (Supabase-backed) instead of the deprecated SheetService.fetchData() stub
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
            // Dynamic NC Discount from global_charges.nc_discount
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: metarollRed),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Sales Document Center",
            style: TextStyle(fontWeight: FontWeight.bold, color: metarollRed)),
        backgroundColor: Colors.white,
        foregroundColor: metarollRed,
        elevation: 0,
        iconTheme: const IconThemeData(color: metarollRed),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                // 1. Toggle Switch
                _buildToggleSection(),
                const SizedBox(height: 32),

                // 2. Header Section (Glassmorphism)
                _buildGlassCard(
                  child: _buildHeaderForm(),
                ),
                const SizedBox(height: 32),

                // 3. Product Table Section
                _buildGlassCard(
                  child: _buildProductTable(),
                ),
                const SizedBox(height: 32),

                // 4. Calculations & Word Conversion
                _buildGlassCard(
                  child: _buildFooterSection(),
                ),
                const SizedBox(height: 32),

                // 5. Terms & Bank Details
                _buildGlassCard(
                  child: _buildTermsAndBankDetailsSection(),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isPreparingPdf ? () {} : _generateAndDownloadPdf,
        label: Text(
          _isPreparingPdf ? "Preparing PDF..." : "Generate PDF",
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
            : const Icon(Icons.picture_as_pdf, color: Colors.white),
        backgroundColor: _isPreparingPdf ? Colors.grey.shade600 : metarollRed,
      ),
    );
  }

  // --- PDF GENERATION LOGIC ---

  Future<void> _generateAndDownloadPdf() async {
    if (_isPreparingPdf) return;
    if (_firmNameController.text.isEmpty) {
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
      if (fileName.endsWith('_'))
        fileName = fileName.substring(0, fileName.length - 1);
      if (fileName.startsWith('_')) fileName = fileName.substring(1);

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

  Widget _buildToggleSection() {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToggleButton("Proforma Invoice", _isPI, () {
              setState(() {
                _isPI = true;
                _updateSrNo();
                _updateSubject();
              });
            }),
            _buildToggleButton("Quotation", !_isPI, () {
              setState(() {
                _isPI = false;
                _updateSrNo();
                _updateSubject();
              });
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? metarollRed : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: glassWhite,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              // 3D Effect
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                blurRadius: 0,
                offset: const Offset(-2, -2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildHeaderForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Document Information",
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: metarollRed)),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 700;
          return Column(
            children: [
              _buildRow(isDesktop, [
                _buildField("Sr No / Reference", _srNoController, Icons.tag),
                TextField(
                  controller: _dateController,
                  readOnly:
                      true, // Prevents raw keyboard popup to force pristine pattern selection
                  decoration: InputDecoration(
                    labelText: "Date",
                    prefixIcon: const Icon(Icons.calendar_today,
                        color: Color(0xFFB71C1C)), // MSM Brand Red
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onTap: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFFB71C1C), // MSM Header Red
                              onPrimary: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (pickedDate != null) {
                      // Formats date back to clean standard matching the document structure
                      String formattedDate =
                          "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
                      setState(() {
                        _dateController.text = formattedDate;
                      });
                    }
                  },
                ),
              ]),
              const SizedBox(height: 20),
              _buildField(
                  "Firm Name (To:)", _firmNameController, Icons.business,
                  prominent: true),
              const SizedBox(height: 20),
              _buildField("Address", _addressController, Icons.location_on,
                  maxLines: 3),
              const SizedBox(height: 20),
              _buildRow(isDesktop, [
                _buildField("Email Address", _emailController, Icons.email),
                _buildField(
                    "Mobile No", _mobileController, Icons.phone_android),
                _buildField("GSTIN", _gstNoController, Icons.receipt_long),
              ]),
              const SizedBox(height: 20),
              _buildField("Subject", _subjectController, Icons.subject),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildProductTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProductHeader(),
        const SizedBox(height: 16),
        ..._items.asMap().entries.map((e) => _buildItemCard(e.value, e.key)),
        const SizedBox(height: 24),
        _buildAddItemButton(),
      ],
    );
  }

  Widget _buildProductHeader() {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: metarollRed,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        const Text("Products & Items",
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
                letterSpacing: -0.5)),
        const Spacer(),
        if (_isLoadingSheetData)
          const SizedBox(
            height: 20,
            width: 20,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: metarollRed),
          ),
        Text("${_items.length} items added",
            style: const TextStyle(
                fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildItemCard(SalesProductGroup item, int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1)),
      child: ExpansionTile(
        initiallyExpanded: index == _items.length - 1,
        iconColor: metarollRed,
        collapsedIconColor: Colors.black45,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: BorderSide.none),
        collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        leading: Container(
            decoration: BoxDecoration(
                color: metarollRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(10),
            child: const Icon(Icons.inventory_2_outlined,
                color: metarollRed, size: 24)),
        title: Text(item.productName,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Colors.black87,
              letterSpacing: -0.3,
            )),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: metarollRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${item.totalQty.toStringAsFixed(3)} MT",
                  style: const TextStyle(
                      color: metarollRed,
                      fontWeight: FontWeight.w900,
                      fontSize: 10),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "₹ ${NumberFormat.currency(symbol: "", decimalDigits: 0, locale: "en_IN").format(item.totalAmount)}",
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Divider(color: Colors.grey.shade100, height: 24),
          Row(children: [
            Expanded(
                child: InkWell(
              onTap: () {
                _showSalesItemPicker(context, item);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Product Type',
                  labelStyle: const TextStyle(
                      color: Colors.black45,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: metarollRed, width: 1.5)),
                  suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: metarollRed),
                ),
                child: Text(
                  item.productName.isEmpty
                      ? "Select Product"
                      : item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            )),
            const SizedBox(width: 12),
            Container(
                decoration: BoxDecoration(
                    color: metarollRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: metarollRed, size: 24),
                    onPressed: () => setState(() => _items.removeAt(index))))
          ]),
          const SizedBox(height: 16),
          TextField(
              controller: item.basicRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                _recalcAllSizes(item);
                setState(() {});
              },
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: "Basic Rate (₹)",
                labelStyle: const TextStyle(
                  color: Colors.black45,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: metarollRed, width: 1.5),
                ),
                floatingLabelStyle: const TextStyle(
                    color: metarollRed, fontWeight: FontWeight.bold),
              )),
          const SizedBox(height: 24),
          if (item.sizes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Expanded(
                      flex: 3,
                      child: Text("Size",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Colors.black38,
                              letterSpacing: 0.5))),
                  const Expanded(
                      flex: 2,
                      child: Text("Rate",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Colors.black38,
                              letterSpacing: 0.5),
                          textAlign: TextAlign.center)),
                  if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
                      .contains(item.productName))
                    const Expanded(
                        flex: 2,
                        child: Text("Nos",
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                color: Colors.black38,
                                letterSpacing: 0.5),
                            textAlign: TextAlign.center)),
                  const Expanded(
                      flex: 2,
                      child: Text("Qty (MT)",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Colors.black38,
                              letterSpacing: 0.5),
                          textAlign: TextAlign.center)),
                  const Expanded(
                      flex: 3,
                      child: Text("Amt",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Colors.black38,
                              letterSpacing: 0.5),
                          textAlign: TextAlign.right)),
                  const SizedBox(width: 32)
                ]),
              ),
            ),
            ...item.sizes
                .asMap()
                .entries
                .map((entry) => _buildSizeRow(item, entry.key, entry.value)),
            const SizedBox(height: 16),
          ],
          _buildAddSizeButton(item),
        ],
      ),
    );
  }

  Widget _buildSizeRow(SalesProductGroup item, int sizeIndex, SalesSizeRow s) {
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
                        bottom:
                            BorderSide(color: Colors.grey.shade200, width: 1))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatSizeLabel(
                            _appendKgSuffixSales(item.productName, s.sizeLabel),
                            item.productName,
                            s.unitWeight),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: metarollRed,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.edit_note_rounded,
                        color: metarollRed.withOpacity(0.5), size: 14)
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(s.rate.toStringAsFixed(0),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                )),
          ),
          if (!['Sqr Bar', 'Round Bar', 'Flats', 'Barbed Wire']
              .contains(item.productName))
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: TextField(
                      controller: s.nosController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                      textAlign: TextAlign.center,
                      onChanged: (v) {
                        s.nos = int.tryParse(v) ?? 0;
                        _recalcQtyFromNos(s);
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: "0",
                        hintStyle: TextStyle(color: Colors.grey.shade300),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                    ),
                  ),
                  if (s.unitWeight <= 0)
                    const FittedBox(
                      child: Text(
                        "Master data weight missing",
                        style: TextStyle(
                            color: metarollRed,
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
                controller: s.qtyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
                textAlign: TextAlign.center,
                onChanged: (v) {
                  s.qty = double.tryParse(v) ?? 0;
                  _recalcNosFromQty(s);
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: "0.0",
                  hintStyle: TextStyle(color: Colors.grey.shade300),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  letterSpacing: -0.2,
                )),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => setState(() => item.sizes.removeAt(sizeIndex)),
            icon: Icon(Icons.remove_circle_outline_rounded,
                color: Colors.grey.shade400, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSizeButton(SalesProductGroup item) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: metarollRed.withOpacity(0.05),
        ),
        onPressed: () => _showAddSizeBottomSheet(item),
        icon: const Icon(Icons.add_circle_outline_rounded,
            color: metarollRed, size: 20),
        label: const Text("Add Size",
            style: TextStyle(
              color: metarollRed,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            )),
      ),
    );
  }

  Widget _buildAddItemButton() {
    return Align(
      alignment: Alignment.center,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _showAddItemBottomSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
          decoration: BoxDecoration(
            color: metarollRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: metarollRed.withOpacity(0.2), width: 1.5),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: metarollRed, size: 28),
              SizedBox(width: 10),
              Text("Add New Product",
                  style: TextStyle(
                      color: metarollRed,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.1)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddItemBottomSheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                        border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200))),
                    child: Row(children: [
                      Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: metarollRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.category_rounded,
                              color: metarollRed)),
                      const SizedBox(width: 12),
                      const Text("Select Product Type",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5)),
                      const Spacer(),
                      IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.white))
                    ])),
                Expanded(
                    child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sheetItemDataMap.keys.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          String cat = sheetItemDataMap.keys.elementAt(index);
                          return InkWell(
                              onTap: () {
                                setState(() {
                                  _items
                                      .add(SalesProductGroup(productName: cat));
                                });
                                Navigator.pop(context);
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Colors.grey.shade200),
                                      borderRadius: BorderRadius.circular(16)),
                                  child: Row(children: [
                                    const Icon(Icons.inventory_2_outlined,
                                        color: Colors.grey),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: Text(cat,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16))),
                                    const Icon(Icons.add_circle_outline_rounded,
                                        color: metarollRed)
                                  ])));
                        }))
              ]));
        });
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
    // We do NOT add GST in the rate per MT here because GST is applied at the invoice total level in SalesDocumentCenter.
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

  Widget _buildFooterSection() {
    return Column(
      children: [
        _buildSummaryRow("Subtotal", _subtotal),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    "Freight (per MT): Total QTY (${_totalQty.toStringAsFixed(3)} MT)",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
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
                      decoration: InputDecoration(
                        hintText: "0.00",
                        prefixText: "INR ",
                        prefixStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Colors.grey),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              NumberFormat.currency(symbol: "₹", locale: "en_IN")
                  .format(_totalFreightAmount),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSummaryRow("GST @ 18%", _gst),
        const SizedBox(height: 12),
        _buildSummaryRow("Grand Total", _grandTotal, isGrand: true),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: metarollRed.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: metarollRed.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Amount in Words:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: metarollRed)),
              const SizedBox(height: 8),
              Text(
                "INR ${AmountToWords.convert(_grandTotal).toUpperCase()} ONLY",
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsAndBankDetailsSection() {
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 700;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start, // Align to top for better alignment
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Terms & Conditions",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: metarollRed)),
                    const SizedBox(height: 24),
                    _buildField("Terms", _termsController, Icons.list_alt,
                        maxLines: 5),
                  ],
                ),
              ),
              if (isDesktop) const SizedBox(width: 40),
              if (isDesktop)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Bank Details",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: metarollRed)),
                      const SizedBox(height: 24),
                      _buildBankDetailsGrid(isDesktop),
                      _buildBillingDetailsSection(isDesktop),
                    ],
                  ),
                ),
            ],
          ),
          if (!isDesktop) ...[
            const SizedBox(height: 40),
            const Text("Bank Details",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: metarollRed)),
            const SizedBox(height: 24),
            _buildBankDetailsGrid(isDesktop),
            _buildBillingDetailsSection(isDesktop),
          ]
        ],
      );
    });
  }

  Widget _buildBillingDetailsSection(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text("Billing Details",
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: metarollRed)),
        const SizedBox(height: 24),
        _buildBillingRow(
            "Company",
            const Text("Metarolls Steel Mart Private Limited",
                style: TextStyle(fontWeight: FontWeight.bold))),
        _buildBillingRow(
            "Address",
            const Text(
                "Gut No. 48, Adjacent to MIDC, Phase II, Daregaon, Jalna - 431213")),
        _buildBillingRow("GSTIN / PAN",
            const Text("GSTIN/UIN: 27AARCM5928R1ZB | PAN: AARCM5928R")),
        _buildBillingRow("State / Code",
            const Text("State Name: Maharashtra | State Code: 27")),
        _buildBillingRow("CIN", const Text("U24109MH2023PTC415690")),
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
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBillingRow(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          const Text(" :  ",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _buildBankDetailsGrid(bool isDesktop) {
    return Column(
      children: [
        _buildField("Bank Name", _bankNameController, Icons.account_balance),
        const SizedBox(height: 16),
        _buildRow(isDesktop, [
          _buildField("Account No", _accNoController, Icons.numbers),
          _buildField("IFSC Code", _ifscController, Icons.code),
        ]),
        const SizedBox(height: 16),
        _buildField("Branch Name", _branchController, Icons.map),
      ],
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildField(
      String label, TextEditingController controller, IconData icon,
      {int maxLines = 1, bool prominent = false, bool readOnly = false}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: metarollRed),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: metarollRed)),
      ),
      style: TextStyle(
          fontSize: prominent ? 18 : 16,
          fontWeight: prominent ? FontWeight.bold : FontWeight.normal),
    );
  }

  Widget _buildTableCell(TextEditingController controller, String hint,
      {bool isNumeric = false, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextFormField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: isNumeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: isNumeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
            : [],
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildRow(bool isDesktop, List<Widget> children) {
    if (isDesktop) {
      return Row(
        children: children
            .expand((w) => [Expanded(child: w), const SizedBox(width: 16)])
            .toList()
          ..removeLast(),
      );
    }
    return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 16)]).toList()
              ..removeLast());
  }

  Widget _buildSummaryRow(String label, double amount, {bool isGrand = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: isGrand ? 22 : 16,
                fontWeight: isGrand ? FontWeight.w900 : FontWeight.bold)),
        Text(
          NumberFormat.currency(symbol: "₹", locale: "en_IN").format(amount),
          style: TextStyle(
            fontSize: isGrand ? 24 : 18,
            fontWeight: FontWeight.w900,
            color: isGrand ? metarollRed : Colors.black,
          ),
        ),
      ],
    );
  }

  void _showSalesItemPicker(BuildContext context, SalesProductGroup groupItem) {
    final List<String> allNames = sheetItemDataMap.keys.toList()
      ..sort((a, b) => SortingUtils.compareCategories(a, b));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        String query = "";
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = applyPrioritizedSearch(query, allNames, (n) => n);

            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8),
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
                        const Text("Select Item",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                        const Icon(Icons.sort, color: metarollRed),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Search item...",
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade200)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: metarollRed, width: 1.5)),
                      ),
                      onChanged: (val) => setSheetState(() => query = val),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(child: Text("No item found"))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                        color: metarollRed.withOpacity(0.05),
                                        shape: BoxShape.circle),
                                    child: Image.asset(
                                        'assets/images/icons/${name.toLowerCase().replaceAll(' ', '_')}.png',
                                        width: 24,
                                        height: 24,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.category,
                                                color: metarollRed, size: 20)),
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87)),
                                  trailing: const Icon(Icons.chevron_right,
                                      size: 16, color: Colors.grey),
                                  onTap: () {
                                    Navigator.pop(context, name);
                                  },
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
    if (n < 100)
      return "${_tens[n ~/ 10]}${n % 10 != 0 ? " ${_units[n % 10]}" : ""}";
    if (n < 1000)
      return "${_units[n ~/ 100]} Hundred${n % 100 != 0 ? " and ${_convertRecursive(n % 100)}" : ""}";
    if (n < 100000)
      return "${_convertRecursive(n ~/ 1000)} Thousand${n % 1000 != 0 ? " ${_convertRecursive(n % 1000)}" : ""}";
    if (n < 10000000)
      return "${_convertRecursive(n ~/ 100000)} Lakh${n % 100000 != 0 ? " ${_convertRecursive(n % 100000)}" : ""}";
    return "${_convertRecursive(n ~/ 10000000)} Crore${n % 10000000 != 0 ? " ${_convertRecursive(n % 10000000)}" : ""}";
  }
}
