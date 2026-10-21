typedef DeliveryOrderModel = DeliveryOrderDataModel;

class DeliveryOrderDataModel {
  final String documentTitle;
  final String poNo;
  final String poDate;
  final String dealerName;
  final String billingName;
  final String billingAddress;
  final String consigneeName;
  final String dispatchAddress;
  final String shippingAddress;
  final String orderDate;
  final String billType; // "BILL" | "NC"
  final dynamic ob;
  final dynamic freight;
  final double freightCharge;
  final String freightType; // 'PER_MT' or 'FIXED'
  final String lorryNo;
  final String note;
  final String signedBy;
  final String approvedBy;
  final List<DeliveryOrderItemModel> items;

  DeliveryOrderDataModel({
    this.documentTitle = 'SAUDA BOOK / DELIVERY ORDER',
    required this.poNo,
    required this.poDate,
    required this.dealerName,
    required this.billingName,
    required this.billingAddress,
    required this.consigneeName,
    required this.dispatchAddress,
    this.shippingAddress = '',
    required this.orderDate,
    required this.billType,
    required this.ob,
    required this.freight,
    this.freightCharge = 0.0,
    this.freightType = 'PER_MT',
    required this.lorryNo,
    required this.note,
    required this.signedBy,
    required this.approvedBy,
    required this.items,
  });

  double get totalEffectiveQty =>
      items.fold(0.0, (sum, item) => sum + item.totalQty);

  int get totalPiecesCount =>
      items.fold(0, (sum, item) => sum + item.totalPieces);

  double get grandTotalAmount =>
      items.fold(0.0, (sum, item) => sum + item.totalAmount);

  double get baseMaterialValue => grandTotalAmount;

  /// Freight calculation according to pricing model:
  /// - PER_MT: bookedTonnage * freightCharge
  /// - FIXED: freightCharge lump-sum
  double get calculatedFreight {
    if (freightCharge <= 0) return 0.0;
    if (freightType == 'FIXED') {
      return freightCharge;
    }
    return totalEffectiveQty * freightCharge;
  }

  double get grandTotalOrderValue => baseMaterialValue + calculatedFreight;

  double get effectiveLandedRate {
    if (totalEffectiveQty <= 0) return 0.0;
    return grandTotalOrderValue / totalEffectiveQty;
  }

  Map<String, dynamic> toJson() => {
        'documentTitle': documentTitle,
        'poNo': poNo,
        'poDate': poDate,
        'dealerName': dealerName,
        'billingName': billingName,
        'billingAddress': billingAddress,
        'consigneeName': consigneeName,
        'dispatchAddress': dispatchAddress,
        'shippingAddress':
            shippingAddress.isNotEmpty ? shippingAddress : dispatchAddress,
        'orderDate': orderDate,
        'billType': billType,
        'ob': ob,
        'freight': freight,
        'freightCharge': freightCharge,
        'freight_charge': freightCharge,
        'freightType': freightType,
        'freight_type': freightType,
        'lorryNo': lorryNo,
        'note': note,
        'signedBy': signedBy,
        'approvedBy': approvedBy,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory DeliveryOrderDataModel.fromJson(Map<String, dynamic> json) {
    final sAddr = json['shippingAddress']?.toString() ??
        json['dispatchAddress']?.toString() ??
        '';
    final double fCharge = (json['freightCharge'] as num?)?.toDouble() ??
        (json['freight_charge'] as num?)?.toDouble() ??
        double.tryParse(json['freight']?.toString() ?? '') ??
        0.0;
    final String fType = json['freightType']?.toString() ??
        json['freight_type']?.toString() ??
        'PER_MT';

    return DeliveryOrderDataModel(
      documentTitle: json['documentTitle']?.toString() ??
          'SAUDA BOOK / DELIVERY ORDER',
      poNo: json['poNo']?.toString() ?? '',
      poDate: json['poDate']?.toString() ?? '',
      dealerName: json['dealerName']?.toString() ?? '',
      billingName: json['billingName']?.toString() ?? '',
      billingAddress: json['billingAddress']?.toString() ?? '',
      consigneeName: json['consigneeName']?.toString() ?? '',
      dispatchAddress: json['dispatchAddress']?.toString() ?? sAddr,
      shippingAddress: sAddr,
      orderDate: json['orderDate']?.toString() ?? '',
      billType: json['billType']?.toString() ?? 'BILL',
      ob: json['ob'] ?? '',
      freight: json['freight'] ?? (fCharge > 0 ? fCharge : ''),
      freightCharge: fCharge,
      freightType: fType,
      lorryNo: json['lorryNo']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      signedBy: json['signedBy']?.toString() ?? '',
      approvedBy: json['approvedBy']?.toString() ?? '',
      items: (json['items'] as List? ?? [])
          .map((i) =>
              DeliveryOrderItemModel.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
    );
  }

  DeliveryOrderDataModel copyWith({
    String? documentTitle,
    String? poNo,
    String? poDate,
    String? dealerName,
    String? billingName,
    String? billingAddress,
    String? consigneeName,
    String? dispatchAddress,
    String? shippingAddress,
    String? orderDate,
    String? billType,
    dynamic ob,
    dynamic freight,
    double? freightCharge,
    String? freightType,
    String? lorryNo,
    String? note,
    String? signedBy,
    String? approvedBy,
    List<DeliveryOrderItemModel>? items,
  }) {
    return DeliveryOrderDataModel(
      documentTitle: documentTitle ?? this.documentTitle,
      poNo: poNo ?? this.poNo,
      poDate: poDate ?? this.poDate,
      dealerName: dealerName ?? this.dealerName,
      billingName: billingName ?? this.billingName,
      billingAddress: billingAddress ?? this.billingAddress,
      consigneeName: consigneeName ?? this.consigneeName,
      dispatchAddress: dispatchAddress ?? this.dispatchAddress,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      orderDate: orderDate ?? this.orderDate,
      billType: billType ?? this.billType,
      ob: ob ?? this.ob,
      freight: freight ?? this.freight,
      freightCharge: freightCharge ?? this.freightCharge,
      freightType: freightType ?? this.freightType,
      lorryNo: lorryNo ?? this.lorryNo,
      note: note ?? this.note,
      signedBy: signedBy ?? this.signedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      items: items ?? this.items,
    );
  }
}

class DeliveryOrderItemModel {
  final String item;
  final dynamic saudaRate;
  final String rateType;
  final dynamic balanceQty;
  final double freightCharge;
  final String freightType; // 'PER_MT' or 'FIXED'
  final List<DeliveryOrderSizeModel> sizes;

  DeliveryOrderItemModel({
    required this.item,
    required this.saudaRate,
    this.rateType = '',
    required this.balanceQty,
    this.freightCharge = 0.0,
    this.freightType = 'PER_MT',
    required this.sizes,
  });

  double get totalQty => sizes.fold(0.0, (sum, s) => sum + s.qty);
  int get totalPieces => sizes.fold(0, (sum, s) => sum + (s.nos?.toInt() ?? 0));
  double get totalAmount => sizes.fold(0.0, (sum, s) => sum + s.amount);

  double get calculatedFreight {
    if (freightCharge <= 0) return 0.0;
    if (freightType == 'FIXED') return freightCharge;
    return totalQty * freightCharge;
  }

  Map<String, dynamic> toJson() => {
        'item': item,
        'saudaRate': saudaRate,
        'rateType': rateType,
        'balanceQty': balanceQty,
        'freightCharge': freightCharge,
        'freight_charge': freightCharge,
        'freightType': freightType,
        'freight_type': freightType,
        'sizes': sizes.map((s) => s.toJson()).toList(),
      };

  factory DeliveryOrderItemModel.fromJson(Map<String, dynamic> json) {
    final double fCharge = (json['freightCharge'] as num?)?.toDouble() ??
        (json['freight_charge'] as num?)?.toDouble() ??
        0.0;
    final String fType = json['freightType']?.toString() ??
        json['freight_type']?.toString() ??
        'PER_MT';

    return DeliveryOrderItemModel(
      item: json['item']?.toString() ?? '',
      saudaRate: json['saudaRate'] ?? '',
      rateType: json['rateType']?.toString() ?? '',
      balanceQty: json['balanceQty'] ?? '',
      freightCharge: fCharge,
      freightType: fType,
      sizes: (json['sizes'] as List? ?? [])
          .map((s) =>
              DeliveryOrderSizeModel.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
    );
  }
}

class DeliveryOrderSizeModel {
  final String size;
  final double qty;
  final double rate;
  final String bd; // Calculation breakdown string e.g. "50 x 24.50 kg = 1.225 MT"
  final double? nos;
  final double? unitWeight;

  DeliveryOrderSizeModel({
    required this.size,
    required this.qty,
    required this.rate,
    required this.bd,
    this.nos,
    this.unitWeight,
  });

  double get amount => rate > 0 ? (qty * rate) : 0.0;

  Map<String, dynamic> toJson() => {
        'size': size,
        'qty': qty,
        'rate': rate,
        'bd': bd,
        if (nos != null) 'nos': nos,
        if (unitWeight != null) 'unitWeight': unitWeight,
      };

  factory DeliveryOrderSizeModel.fromJson(Map<String, dynamic> json) {
    return DeliveryOrderSizeModel(
      size: json['size']?.toString() ?? '',
      qty: double.tryParse(json['qty']?.toString() ?? '0') ?? 0.0,
      rate: double.tryParse(json['rate']?.toString() ?? '0') ?? 0.0,
      bd: json['bd']?.toString() ?? '',
      nos: json['nos'] != null
          ? double.tryParse(json['nos'].toString())
          : null,
      unitWeight: json['unitWeight'] != null
          ? double.tryParse(json['unitWeight'].toString())
          : null,
    );
  }
}
