import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/delivery_order_model.dart';
import '../services/delivery_order_print_service.dart';
import 'motion_toast.dart';

class DeliveryOrderPrintDialog extends StatefulWidget {
  final DeliveryOrderDataModel initialModel;

  const DeliveryOrderPrintDialog({
    super.key,
    required this.initialModel,
  });

  static Future<void> show(
    BuildContext context, {
    required DeliveryOrderDataModel model,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DeliveryOrderPrintDialog(initialModel: model),
    );
  }

  @override
  State<DeliveryOrderPrintDialog> createState() =>
      _DeliveryOrderPrintDialogState();
}

class _DeliveryOrderPrintDialogState extends State<DeliveryOrderPrintDialog> {
  late TextEditingController _orderDateCtrl;
  late TextEditingController _dealerNameCtrl;
  late TextEditingController _lorryNoCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _signedByCtrl;
  late TextEditingController _approvedByCtrl;
  late String _documentTitle;
  late String _billType;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    final m = widget.initialModel;
    _documentTitle = m.documentTitle.isNotEmpty
        ? m.documentTitle
        : 'SAUDA BOOK / DELIVERY ORDER';
    _orderDateCtrl = TextEditingController(text: m.orderDate);
    _dealerNameCtrl = TextEditingController(
        text: m.dealerName.isNotEmpty ? m.dealerName : m.billingName);
    _lorryNoCtrl = TextEditingController(text: m.lorryNo);
    _noteCtrl = TextEditingController(text: m.note);
    _signedByCtrl = TextEditingController(
        text: m.signedBy.isNotEmpty ? m.signedBy : 'Authorized Staff');
    _approvedByCtrl = TextEditingController(
        text: m.approvedBy.isNotEmpty
            ? m.approvedBy
            : 'For METAROLL STEEL MART');
    _billType = m.billType.isNotEmpty ? m.billType : 'BILL';
  }

  @override
  void dispose() {
    _orderDateCtrl.dispose();
    _dealerNameCtrl.dispose();
    _lorryNoCtrl.dispose();
    _noteCtrl.dispose();
    _signedByCtrl.dispose();
    _approvedByCtrl.dispose();
    super.dispose();
  }

  DeliveryOrderDataModel _buildCurrentModel() {
    return widget.initialModel.copyWith(
      documentTitle: _documentTitle,
      orderDate: _orderDateCtrl.text.trim(),
      dealerName: _dealerNameCtrl.text.trim(),
      billingName: _dealerNameCtrl.text.trim(),
      billType: _billType,
      lorryNo: _lorryNoCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      signedBy: _signedByCtrl.text.trim(),
      approvedBy: _approvedByCtrl.text.trim(),
    );
  }

  Future<void> _handlePrint() async {
    setState(() => _isProcessing = true);
    try {
      final model = _buildCurrentModel();
      await DeliveryOrderPrintService.printOrder(context, model);
    } catch (e) {
      if (mounted) {
        MotionToast.show(context, "Error printing document: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleShare() async {
    setState(() => _isProcessing = true);
    try {
      final model = _buildCurrentModel();
      await DeliveryOrderPrintService.shareOrderPdf(context, model);
    } catch (e) {
      if (mounted) {
        MotionToast.show(context, "Error sharing PDF: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.initialModel;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 750,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: msmRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.print_rounded, color: msmRed, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Delivery Order Print Preview",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                      ),
                      Text(
                        "${model.items.length} Item(s) • Total: ${model.totalEffectiveQty.toStringAsFixed(3)} MT",
                        style: const TextStyle(fontSize: 12, color: textGrey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: textGrey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            // Scrollable Form Fields
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Order Details
                    _buildSectionHeader("Order & Vehicle Info"),
                    const SizedBox(height: 12),
                    if (isMobile) ...[
                      _buildTextField(_dealerNameCtrl, "Firm Name"),
                      const SizedBox(height: 10),
                      _buildTextField(_orderDateCtrl, "Date (YYYY-MM-DD)"),
                      const SizedBox(height: 10),
                      _buildTextField(_lorryNoCtrl, "Vehicle No."),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: _buildTextField(_dealerNameCtrl, "Firm Name")),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(_orderDateCtrl, "Date")),
                          const SizedBox(width: 12),
                          Expanded(
                              child:
                                  _buildTextField(_lorryNoCtrl, "Vehicle No.")),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Document Title Selector
                    DropdownButtonFormField<String>(
                      initialValue: _documentTitle,
                      decoration: InputDecoration(
                        labelText: "Document Title",
                        labelStyle: const TextStyle(color: textGrey, fontSize: 13),
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: msmRed, width: 1.5),
                        ),
                      ),
                      dropdownColor: Colors.white,
                      items: const [
                        DropdownMenuItem(
                          value: 'SAUDA BOOK / DELIVERY ORDER',
                          child: Text(
                            'SAUDA BOOK / DELIVERY ORDER (Default)',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'DELIVERY ORDER',
                          child: Text(
                            'DELIVERY ORDER',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'SAUDA BOOK',
                          child: Text(
                            'SAUDA BOOK',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _documentTitle = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Bill Type Selector
                    Row(
                      children: [
                        const Text(
                          "Rate Type: ",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text("BILL"),
                          selected: _billType == "BILL",
                          selectedColor: msmRed,
                          labelStyle: TextStyle(
                            color:
                                _billType == "BILL" ? Colors.white : textDark,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (v) {
                            if (v) setState(() => _billType = "BILL");
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text("NC"),
                          selected: _billType == "NC",
                          selectedColor: msmRed,
                          labelStyle: TextStyle(
                            color: _billType == "NC" ? Colors.white : textDark,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (v) {
                            if (v) setState(() => _billType = "NC");
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Notes & Signatures
                    _buildSectionHeader("Remarks & Signatures"),
                    const SizedBox(height: 12),
                    _buildTextField(_noteCtrl, "Remarks / Notes", maxLines: 2),
                    const SizedBox(height: 12),
                    if (isMobile) ...[
                      _buildTextField(_signedByCtrl, "Prepared & Signed By"),
                      const SizedBox(height: 10),
                      _buildTextField(_approvedByCtrl, "Authorized Signatory"),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                              child: _buildTextField(
                                  _signedByCtrl, "Prepared & Signed By")),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(
                                  _approvedByCtrl, "Authorized Signatory")),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _handleShare,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text("Share PDF"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textDark,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _handlePrint,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print_rounded, size: 18),
                  label: const Text(
                    "Print",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: msmRed,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          color: msmRed,
          margin: const EdgeInsets.only(right: 6),
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: textGrey),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: msmRed, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}
