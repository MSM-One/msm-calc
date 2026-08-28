import 'package:intl/intl.dart';
import '../services/data_repository.dart';

String detectCategory(String itemName) {
  final trimmed = itemName.trim();
  if (trimmed.isEmpty || trimmed.toUpperCase() == 'UNKNOWN') {
    return "General";
  }

  // 1. Dynamic matching against DataRepository master material lookup
  for (final matName in DataRepository.materialIdToNameMap.values) {
    if (matName.trim().toUpperCase() == trimmed.toUpperCase()) {
      return matName.trim();
    }
  }

  // 2. Specific pipe and shape heuristics
  final name = trimmed.toUpperCase();
  if (name.contains("ERW PIPE")) return "ERW Pipe";
  if (name.contains("HR PIPE")) return "HR Pipe";
  if (name.contains("CR PIPE")) return "CR Pipe";
  if (name.contains("PIPE")) return "MS Pipe";
  if (name.contains("ANGLE")) return "MS Angle";
  if (name.contains("GATE")) return "GATE Channel";
  if (name.contains("CHANNEL")) return "MS Channel";
  if (name.contains("FLAT")) return "Flats";
  if (name.contains("SQUARE") || name.contains("SQR")) return "Sqr Bar";
  if (name.contains("ROUND")) return "Round Bar";
  if (name.contains("NAIL")) return "Nails";
  if (name.contains("BINDING")) return "Binding Wire";
  if (name.contains("BARBED")) return "Barbed Wire";
  if (name.contains("WIRE")) return "Wire";
  if (name.contains("ISMC")) return "MS Structure ISMC";
  if (name.contains("ISMB")) return "Heavy Structure ISMB";
  return trimmed;
}

class ItemVariant {
  final String itemName;
  final String category;
  final String size;
  double openingStockMT;
  double _currentStockMT;
  double reservedStockMT;
  double minStock;
  double price;
  final String location; // 'YARD' or 'FACTORY' or 'ALL'
  String stockStatus;

  double yardTotal;
  double factoryTotal;

  ItemVariant({
    required this.itemName,
    required String category,
    required this.size,
    this.openingStockMT = 0,
    required double currentStockMT,
    this.reservedStockMT = 0,
    this.minStock = 5.0,
    this.price = 0,
    required this.location,
    this.stockStatus = 'In Stock',
    this.yardTotal = 0.0,
    this.factoryTotal = 0.0,
  })  : this.category = (category.trim().isNotEmpty
            ? category.trim()
            : (itemName.trim().isNotEmpty
                ? detectCategory(itemName)
                : 'General')),
        _currentStockMT = currentStockMT;

  double get currentStockMT => _currentStockMT;
  set currentStockMT(double val) => _currentStockMT = val;

  double get availableStockMT {
    final diff = currentStockMT - reservedStockMT;
    return diff < 0 ? 0.0 : diff;
  }

  String get id => '$category-$itemName-$size-$location';

  String get sizeLabel => size;
  double get netStockMt => currentStockMT;

  factory ItemVariant.fromSupabaseStockMap(Map<String, dynamic> map) {
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    final itemName = map['item_name']?.toString() ?? '';
    final rawCat = map['category']?.toString() ?? '';

    return ItemVariant(
      itemName: itemName,
      category: rawCat.isNotEmpty ? rawCat : itemName,
      size: map['size_label']?.toString() ?? '',
      currentStockMT: parseDouble(map['net_stock_mt']),
      yardTotal: parseDouble(map['yard_total']),
      factoryTotal: parseDouble(map['factory_total']),
      location: map['location']?.toString() ?? 'ALL',
    );
  }
}

class SampleRateSize {
  final String label;
  final num sd;
  final num weight;
  final bool isMissing;
  SampleRateSize(this.label, this.sd, this.weight, {this.isMissing = false});
}

class StockUtils {
  static String normalizeLocation(String loc) {
    String n = loc.toUpperCase().trim();
    if (n.contains('PLANT') || n.contains('FACTORY')) return 'FACTORY';
    if (n.contains('YARD') || n.contains('WH') || n.contains('WAREHOUSE')) {
      return 'YARD';
    }
    return n;
  }
}

class LocationStockGroup {
  final String location;
  final Map<String, Map<String, double>> items; // ItemName -> Size -> Qty

  LocationStockGroup({required this.location, required this.items});

  double get totalMT {
    double total = 0;
    items.forEach((itemName, sizes) {
      sizes.forEach((size, qty) {
        total += qty;
      });
    });
    return total;
  }
}

class ItemGroup {
  final String itemName;
  final String category;
  final String? location;
  final List<ItemVariant> variants = [];

  ItemGroup(this.itemName, this.category, {this.location});

  double get totalMT => variants.fold(0.0, (sum, v) => sum + v.currentStockMT);
  bool get hasLowStock => variants.any((v) => v.currentStockMT <= v.minStock);
}

class StockTransaction {
  final String txnId;
  final DateTime dateTime;
  final String itemName;
  final String size;
  final String type; // 'IN', 'OUT', 'TRANSFER', 'ADJUSTMENT', 'RETURN'
  final double qtyMT;
  final double? basicRate; // For linking with Sauda
  final String location; // Source location or primary location
  final String? toLocation; // Destination for Transfers
  final String? reason; // For Adjustments
  final String? note;
  final String? invoiceNo;
  final String? lorryNo;
  final String? transportCo;
  final String? driverName;
  final String? driverPhone;
  final String? partyName;
  final String? contactNo;
  final String? batchId;
  final String? region; // NEW: Region field
  final double? handMT;
  final double? craneMT;
  final String? user;
  bool isReversed;
  final String? _category;

  // Helpers for reports alignment
  String get category => (_category != null &&
          _category!.trim().isNotEmpty &&
          _category != 'General')
      ? _category!.trim()
      : (itemName.trim().isNotEmpty && itemName != 'Unknown'
          ? detectCategory(itemName)
          : 'General');
  String get sizeLabel => size;
  DateTime get date => dateTime;
  double get qty => qtyMT;

  StockTransaction({
    required this.txnId,
    required this.dateTime,
    required this.itemName,
    required this.size,
    required this.type,
    required this.qtyMT,
    this.basicRate,
    required this.location,
    this.toLocation,
    this.reason,
    this.note,
    this.invoiceNo,
    this.lorryNo,
    this.transportCo,
    this.driverName,
    this.driverPhone,
    this.partyName,
    this.contactNo,
    this.batchId,
    this.region,
    this.handMT,
    this.craneMT,
    this.user,
    this.isReversed = false,
    String? category,
  }) : _category = category;

  Map<String, dynamic> toJson() => {
        'txnId': txnId,
        'itemName': itemName,
        'size': size,
        'type': type,
        'qtyMT': qtyMT,
        'basicRate': basicRate,
        'location': location,
        'toLocation': toLocation,
        'reason': reason,
        'note': note,
        'invoiceNo': invoiceNo,
        'lorryNo': lorryNo,
        'transportCo': transportCo,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'dateTime': dateTime.toIso8601String(),
        'partyName': partyName,
        'contactNo': contactNo,
        'batchId': batchId,
        'region': region,
        'handMT': handMT,
        'craneMT': craneMT,
        'user': user,
        'isReversed': isReversed,
      };

  /// Safely converts any dynamic value to double, avoiding cast exceptions
  /// when Supabase returns unexpected types (bool, null, etc.).
  static double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  factory StockTransaction.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d, String txnId) {
      // 1. Fast path: txnId contains a Unix ms timestamp (app-generated entries)
      try {
        final firstPart = txnId.split('_')[0];
        if (firstPart.length >= 13) {
          final ms = int.tryParse(firstPart.substring(0, 13));
          if (ms != null && ms > 1600000000000 && ms < 2000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(ms);
          }
        }
      } catch (_) {}

      // 2. Field value parsing
      if (d == null) return DateTime.now();
      final s = d.toString().trim();
      if (s.isEmpty) return DateTime.now();

      // 2a. Explicit DD/MM/YYYY HH:mm:ss (Google Sheets format) — highest priority
      try {
        return DateFormat('dd/MM/yyyy HH:mm:ss').parseStrict(s);
      } catch (_) {}

      // 2b. DD/MM/YYYY without time component
      try {
        return DateFormat('dd/MM/yyyy').parseStrict(s.split(' ')[0]);
      } catch (_) {}

      // 2c. ISO 8601 fallback (app-synced entries stored as ISO)
      // Do NOT call .toLocal() — it shifts late-night UTC dates forward by +5:30
      final iso = DateTime.tryParse(s);
      if (iso != null) return iso;

      // 2d. Last resort: return now so row isn't silently discarded
      return DateTime.now();
    }

    // Stable ID for manual entries: If no ID exists, create one from content
    final itemName = (json['itemName'] ??
                json['Item Name'] ??
                json['ITEM NAME'] ??
                json['Item'])
            ?.toString() ??
        "Unknown";
    final size = (json['size'] ?? json['Size'] ?? json['Spec'] ?? json['SIZE'])
            ?.toString() ??
        "Standard";
    final qty = (json['qtyMT'] ??
            json['Qty (MT)'] ??
            json['QTY (MT)'] ??
            json['qty'] ??
            json['Qty'] ??
            json['QTY'] ??
            0.0)
        .toString();
    final dateStr = (json['dateTime'] ??
                json['date'] ??
                json['Date'] ??
                json['Timestamp'] ??
                json['DateTime'])
            ?.toString() ??
        "";

    final id = (json['txnId'] ??
                json['TXN ID'] ??
                json['TXNID'] ??
                json['ID'] ??
                json['Transaction ID'])
            ?.toString() ??
        "MANUAL_${itemName}_${size}_${qty}_${dateStr.replaceAll(RegExp(r'[^0-9]'), '')}";

    return StockTransaction(
      txnId: id,
      dateTime: parseDate(
          json['dateTime'] ??
              json['date'] ??
              json['Date'] ??
              json['Timestamp'] ??
              json['DateTime'],
          id),
      itemName: (json['itemName'] ??
                  json['Item Name'] ??
                  json['ITEM NAME'] ??
                  json['Item'])
              ?.toString() ??
          "Unknown",
      size: (json['size'] ?? json['Size'] ?? json['Spec'] ?? json['SIZE'])
              ?.toString() ??
          "Standard",
      type: (json['type'] ?? json['Type'] ?? json['TYPE'])?.toString() ?? "IN",
      qtyMT: _safeDouble(json['qtyMT'] ??
          json['Qty (MT)'] ??
          json['QTY (MT)'] ??
          json['qty'] ??
          json['Qty'] ??
          json['QTY']),
      basicRate:
          _safeDouble(json['basicRate'] ?? json['Rate'] ?? json['BASIC RATE']),
      location: (json['location'] ?? json['Location'] ?? json['LOCATION'])
              ?.toString() ??
          'YARD',
      toLocation:
          (json['toLocation'] ?? json['To Location'] ?? json['TO LOCATION'])
              ?.toString(),
      reason: (json['reason'] ?? json['Reason'] ?? json['REASON'])?.toString(),
      note: (json['note'] ?? json['Note'] ?? json['Remark'] ?? json['NOTE'])
          ?.toString(),
      invoiceNo: (json['invoiceNo'] ??
              json['Invoice No'] ??
              json['INVOICE NO'] ??
              json['billNo'] ??
              json['Bill No'])
          ?.toString(),
      lorryNo:
          (json['lorryNo'] ?? json['Lorry No'] ?? json['LORRY NO'])?.toString(),
      transportCo:
          (json['transportCo'] ?? json['Transport'] ?? json['TRANSPORT'])
              ?.toString(),
      driverName: (json['driverName'] ?? json['Driver Name'] ?? json['DRIVER'])
          ?.toString(),
      driverPhone:
          (json['driverPhone'] ?? json['Driver Phone'] ?? json['PHONE'])
              ?.toString(),
      partyName: (json['partyName'] ??
              json['Party Name'] ??
              json['Party'] ??
              json['PARTY'])
          ?.toString(),
      contactNo: (json['contactNo'] ?? json['Contact No'])?.toString(),
      batchId:
          (json['batchId'] ?? json['Batch ID'] ?? json['Batch'])?.toString(),
      region: (json['region'] ??
              json['Region'] ??
              json['Purchase Region'] ??
              json['REGION'])
          ?.toString(),
      handMT: json['handMT'] == null ? null : _safeDouble(json['handMT']),
      craneMT: json['craneMT'] == null ? null : _safeDouble(json['craneMT']),
      user: (json['user'] ?? json['User'] ?? json['USER'])?.toString(),
      isReversed: (json['isReversed'] ?? json['Reversed'] ?? json['REVERSED'])
              ?.toString()
              .toLowerCase() ==
          'true',
      category: (json['category'] ??
              json['Category'] ??
              json['category_name'] ??
              json['itemName'] ??
              json['Item Name'])
          ?.toString(),
    );
  }
}

class MaterialModel {
  final int id;
  final String itemName;

  MaterialModel({required this.id, required this.itemName});

  factory MaterialModel.fromSupabaseMap(Map<String, dynamic> map) {
    return MaterialModel(
      id: map['id'] is int
          ? map['id'] as int
          : int.tryParse(map['id']?.toString() ?? '') ?? 0,
      itemName: map['item_name']?.toString() ?? '',
    );
  }
}
