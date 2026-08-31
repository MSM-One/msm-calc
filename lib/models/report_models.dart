class StockMovementEntry {
  final String category;
  final String item;
  final List<StockSizeMovement> sizes;

  StockMovementEntry({
    required this.category,
    required this.item,
    required this.sizes,
  });

  double get closing => sizes.fold(0.0, (sum, s) => sum + s.closing);
  double get rawClosing => sizes.fold(0.0, (sum, s) => sum + s.closing);
  double get inQty => sizes.fold(0.0, (sum, s) => sum + s.inQty);
  double get outQty => sizes.fold(0.0, (sum, s) => sum + s.outQty);
  double get opening => sizes.fold(0.0, (sum, s) => sum + s.opening);

  // For backward compatibility
  String get itemName => item;
  String get size => sizes.isNotEmpty ? sizes.first.label : 'Standard';
}

class StockSizeMovement {
  final String label;
  double opening;
  double inQty;
  double outQty;
  double closing;

  StockSizeMovement({
    required this.label,
    required this.opening,
    required this.inQty,
    required this.outQty,
    required this.closing,
  });
}

class DeadStockEntry {
  final String category;
  final String itemName;
  final String size;
  final double currentQty;
  final int daysSinceLastMovement;
  final DateTime? lastMovementDate;

  DeadStockEntry({
    required this.category,
    required this.itemName,
    required this.size,
    required this.currentQty,
    required this.daysSinceLastMovement,
    this.lastMovementDate,
  });
}

class DailyMovementEntry {
  final String category;
  final String itemName;
  final String size;
  double openingQty;
  double inQty;
  double outQty;
  double closingQty;

  DailyMovementEntry({
    required this.category,
    required this.itemName,
    required this.size,
    this.openingQty = 0.0,
    required this.inQty,
    required this.outQty,
    this.closingQty = 0.0,
  });

  double get netQty => inQty - outQty;
}

class ConsolidatedStockEntry {
  final String item;
  final double yardQty;
  final double factoryQty;
  final List<StockSizeConsolidated> sizes;

  ConsolidatedStockEntry({
    required this.item,
    required this.yardQty,
    required this.factoryQty,
    required this.sizes,
  });

  double get totalQty => yardQty + factoryQty;

  // For backward compatibility
  String get itemName => item;
  double get totalMT => totalQty;
}

class StockSizeConsolidated {
  final String label;
  final double yard;
  final double factory;

  StockSizeConsolidated({
    required this.label,
    required this.yard,
    required this.factory,
  });

  double get total => yard + factory;
}

class MonthReportEntry {
  final String category;
  final String item;
  final double openingQty;
  final double inQty;
  final double outQty;

  MonthReportEntry({
    required this.category,
    required this.item,
    required this.openingQty,
    required this.inQty,
    required this.outQty,
  });

  double get closingQty => openingQty + inQty - outQty;
}

class LowStockEntry {
  final String category;
  final String itemName;
  final String size;
  final double currentStock;
  final double threshold;
  final String location;

  LowStockEntry({
    required this.category,
    required this.itemName,
    required this.size,
    required this.currentStock,
    required this.threshold,
    required this.location,
  });

  bool get isCritical => currentStock <= (threshold * 0.3);
}

class SalesDocumentModel {
  final String title; // Proforma Invoice or Quotation
  final String srNo;
  final String date;
  final String firmName;
  final String address;
  final String email;
  final String mobile;
  final String gstNo;
  final String subject;
  final List<SalesDocumentItem> items;
  final String terms;
  final String bankName;
  final String accNo;
  final String ifsc;
  final String branch;
  final double subtotal;
  final double freight;
  final double freightRatePerMt;
  final double gst;
  final double grandTotal;
  final String amountInWords;

  SalesDocumentModel({
    required this.title,
    required this.srNo,
    required this.date,
    required this.firmName,
    required this.address,
    required this.email,
    required this.mobile,
    required this.gstNo,
    required this.subject,
    required this.items,
    required this.terms,
    required this.bankName,
    required this.accNo,
    required this.ifsc,
    required this.branch,
    required this.subtotal,
    required this.freight,
    required this.freightRatePerMt,
    required this.gst,
    required this.grandTotal,
    required this.amountInWords,
  });

  double get totalQty => items.fold(0.0, (sum, item) => sum + item.qty);
  double get totalFreightAmount => totalQty * freightRatePerMt;
}

class SalesDocumentItem {
  final String description;
  final String size;
  final int nos;
  final double qty;
  final double rate;
  final double total;
  final double? unitWeight;

  SalesDocumentItem({
    required this.description,
    required this.size,
    required this.nos,
    required this.qty,
    required this.rate,
    required this.total,
    this.unitWeight,
  });
}
