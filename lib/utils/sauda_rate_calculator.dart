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
  double get netRatePerMT => netRate;
  final String breakdownString;
  final double subtotalBeforeGst;
  final double baseRate;
  final double sizeDiff;
  final double loadingCharges;
  final double ncDiscount;
  final double obCharge;
  final double freightChargePerMT;
  final double gstRate;
  final double gstAmountPerMT;

  const SaudaCalculationResult({
    required this.netRate,
    required this.breakdownString,
    this.subtotalBeforeGst = 0.0,
    this.baseRate = 0.0,
    this.sizeDiff = 0.0,
    this.loadingCharges = 0.0,
    this.ncDiscount = 0.0,
    this.obCharge = 0.0,
    this.freightChargePerMT = 0.0,
    this.gstRate = 0.18,
    this.gstAmountPerMT = 0.0,
  });
}

/// Dynamic calculator for Sauda rate breakdown strings and net rates
class SaudaRateCalculator {
  /// Computes the net rate and formula breakdown string dynamically based on live global charges.
  /// 
  /// Logic:
  /// - isBill: (orderType.toUpperCase() == 'BILL')
  /// - subtotalBeforeGst: baseRate + sizeDiff + loadingCharges + obCharge + freightChargePerMT (- ncDiscount if !isBill)
  /// - netRatePerMT: subtotalBeforeGst * (1 + gstRate)
  /// - breakdown:
  ///   Bill: "${baseRate.toInt()} + ${sizeDiff.toInt()} + ${loadingCharges.toInt()} + ${obCharge.toInt()} + ${freightChargePerMT.toInt()} + 18%"
  ///   NC:   "${baseRate.toInt()} + ${sizeDiff.toInt()} + ${loadingCharges.toInt()} - ${ncDiscount.toInt()} + ${obCharge.toInt()} + ${freightChargePerMT.toInt()} + 18%"
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
    final double gstRate = liveCharges.gstRate > 1.0
        ? liveCharges.gstRate / 100.0
        : (liveCharges.gstRate > 0 ? liveCharges.gstRate : 0.18);
    final double baseRate = saudaRate;
    final double sizeDiff = sd;
    final double loadingCharges = liveCharges.lcRate;
    final double obCharge = ob;
    final double freightChargePerMT = freight;
    final double ncDiscount = liveCharges.ncDiscount;

    // Check if item is exempt from NC discount
    final String cleanItem = (itemType ?? '').trim().toLowerCase();
    final bool isExempt = isPieces ||
        cleanItem == 'binding wire' ||
        cleanItem == 'nails' ||
        cleanItem == 'bopp tape' ||
        cleanItem == 'cutting wheels';

    final String cleanOrderType = billType.split('|').first.trim().toUpperCase();
    final bool isBill = (cleanOrderType == 'BILL');
    final bool shouldDeductNc = (!isBill && !isExempt);
    final double effectiveNcDiscount = shouldDeductNc ? ncDiscount : 0.0;

    // Calculation before GST:
    double subtotalBeforeGst = baseRate + sizeDiff + loadingCharges + obCharge + freightChargePerMT;
    if (shouldDeductNc) {
      subtotalBeforeGst -= effectiveNcDiscount; // Subtract NC Discount (e.g. -3000)
    }

    // Net Rate per MT (rounded or formatted to integer as per standard practice):
    final double netRatePerMT = subtotalBeforeGst * (1 + gstRate);
    final double gstAmountPerMT = subtotalBeforeGst * gstRate;

    final int gstPct = (gstRate * 100).round();

    // Dynamic Breakdown String:
    String breakdownText;
    if (isBill || !shouldDeductNc) {
      breakdownText =
          "${baseRate.toInt()} + ${sizeDiff.toInt()} + ${loadingCharges.toInt()} + ${obCharge.toInt()} + ${freightChargePerMT.toInt()} + $gstPct%";
    } else {
      breakdownText =
          "${baseRate.toInt()} + ${sizeDiff.toInt()} + ${loadingCharges.toInt()} - ${effectiveNcDiscount.toInt()} + ${obCharge.toInt()} + ${freightChargePerMT.toInt()} + $gstPct%";
    }

    return SaudaCalculationResult(
      netRate: netRatePerMT.roundToDouble(),
      breakdownString: breakdownText,
      subtotalBeforeGst: subtotalBeforeGst,
      baseRate: baseRate,
      sizeDiff: sizeDiff,
      loadingCharges: loadingCharges,
      ncDiscount: effectiveNcDiscount,
      obCharge: obCharge,
      freightChargePerMT: freightChargePerMT,
      gstRate: gstRate,
      gstAmountPerMT: gstAmountPerMT,
    );
  }
}
