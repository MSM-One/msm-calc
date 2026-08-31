/// Represents live global pricing charges from `public.global_charges`
class GlobalCharges {
  final double gstRate; // e.g. 18.00 (%)
  final double lcRate; // e.g. 255.00 (Loading Charge ₹/MT)
  final double ncDiscount; // e.g. 3000.00 (NC Discount ₹/MT)

  const GlobalCharges({
    this.gstRate = 18.0,
    this.lcRate = 255.0,
    this.ncDiscount = 3000.0,
  });

  factory GlobalCharges.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return const GlobalCharges();
    
    // Handle both percentage ('18.0') and decimal ('0.18') formats gracefully
    double rawGst = (map['gst_rate'] as num?)?.toDouble() ??
        (map['gst_pct'] != null ? double.tryParse(map['gst_pct'].toString()) : null) ??
        18.0;
    if (rawGst < 1.0 && rawGst > 0) {
      rawGst = rawGst * 100.0;
    }

    final double rawLc = (map['lc_rate'] as num?)?.toDouble() ??
        (map['loading_charge'] != null
            ? double.tryParse(map['loading_charge'].toString())
            : null) ??
        255.0;

    final double rawNc = (map['nc_discount'] as num?)?.toDouble() ??
        (map['nc_discount'] != null
            ? double.tryParse(map['nc_discount'].toString())
            : null) ??
        3000.0;

    return GlobalCharges(
      gstRate: rawGst,
      lcRate: rawLc,
      ncDiscount: rawNc,
    );
  }

  Map<String, dynamic> toMap() => {
        'gst_rate': gstRate,
        'lc_rate': lcRate,
        'nc_discount': ncDiscount,
      };

  @override
  String toString() =>
      'GlobalCharges(gstRate: $gstRate%, lcRate: $lcRate, ncDiscount: $ncDiscount)';
}

/// Result of dynamic Sauda rate calculation
class SaudaCalculationResult {
  final double netRate;
  final String breakdownString;

  const SaudaCalculationResult({
    required this.netRate,
    required this.breakdownString,
  });
}

/// Dynamic calculator for Sauda rate breakdown strings and net rates
class SaudaRateCalculator {
  /// Computes the net rate and formula breakdown string dynamically based on live global charges.
  /// 
  /// Deduction rule:
  /// If billType contains 'NC' (case-insensitive) and item is NOT Binding Wire / Nails / Pieces item,
  /// apply `charges.ncDiscount`.
  /// 
  /// Formula:
  /// `(saudaRate + sd + charges.lcRate - deduction + freight + ob) * (1 + charges.gstRate / 100)`
  static SaudaCalculationResult calculate({
    required double saudaRate,
    double sd = 0.0,
    GlobalCharges? charges,
    String billType = 'BILL',
    String? itemType,
    double freight = 0.0,
    double ob = 0.0,
    bool isPieces = false,
  }) {
    final GlobalCharges liveCharges = charges ?? const GlobalCharges();

    // Check if item is exempt from NC discount
    final String cleanItem = (itemType ?? '').trim().toLowerCase();
    final bool isExempt = isPieces ||
        cleanItem == 'binding wire' ||
        cleanItem == 'nails' ||
        cleanItem == 'bopp tape' ||
        cleanItem == 'cutting wheels';

    final bool isNC = billType.toUpperCase().contains('NC');
    final double deduction = (isNC && !isExempt) ? liveCharges.ncDiscount : 0.0;

    final double base =
        saudaRate + sd + liveCharges.lcRate - deduction + freight + ob;
    final double netRate = base * (1.0 + (liveCharges.gstRate / 100.0));

    final String dedStr = deduction > 0 ? " - ${deduction.round()}" : "";
    final String obStr = ob > 0 ? " + ${ob.round()}(OB)" : "";
    final String freightStr = freight > 0 ? " + ${freight.round()}" : " + 0";
    final String lcStr = liveCharges.lcRate.round().toString();
    final String gstStr = "${liveCharges.gstRate.round()}%";

    // Breakdown string e.g.: 45700 + 8100 + 255 + 0 + 18% or 45700 + 8100 - 3000 + 255 + 0 + 18%
    final String breakdownString =
        "${saudaRate.round()} + ${sd.round()}$dedStr + $lcStr$freightStr$obStr + $gstStr";

    return SaudaCalculationResult(
      netRate: netRate.roundToDouble(),
      breakdownString: breakdownString,
    );
  }
}
