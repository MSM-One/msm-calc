final Map<String, double> globalSizeWeightCache = {};

String _normalizeCacheKey(String key) {
  return key
      .replaceAll('"', '')
      .replaceAll("'", "")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

void updateGlobalSizeWeightCache(String sizeLabel, double weight) {
  final clean = sizeLabel.trim();
  globalSizeWeightCache[clean] = weight;
  globalSizeWeightCache[_normalizeCacheKey(clean)] = weight;
}

double lookupSizeWeight(String sizeLabel) {
  final clean = sizeLabel.trim();
  if (globalSizeWeightCache.containsKey(clean)) {
    return globalSizeWeightCache[clean]!;
  }
  final normalized = _normalizeCacheKey(clean);
  if (globalSizeWeightCache.containsKey(normalized)) {
    return globalSizeWeightCache[normalized]!;
  }
  return 0.0;
}

String formatWeightNumber(double w) {
  if (w % 1 == 0) {
    return w.toInt().toString();
  }
  String str = w.toString();
  if (str.contains('.')) {
    str = str.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return str;
}

String resolveDynamicSizeTitle({
  required String rawLabel,
  required num? unitWeightKg,
}) {
  final String label = rawLabel.trim();
  if (label.isEmpty) return '';

  // If no weight exists or weight is zero/negative, return database label unmodified
  if (unitWeightKg == null || unitWeightKg <= 0) {
    return label;
  }

  // Format weight dynamically: 10.0 -> "10", 25.0 -> "25", 29.44 -> "29.44"
  final String weightStr = (unitWeightKg % 1 == 0)
      ? unitWeightKg.toInt().toString()
      : unitWeightKg.toString();

  // If label already contains "kg" (case-insensitive) OR already contains the exact weight digits, return as-is
  final String lowerLabel = label.toLowerCase();
  final bool hasKgSuffix = lowerLabel.contains('kg');
  final bool hasWeightDigits =
      RegExp(r'\b' + RegExp.escape(weightStr) + r'\b').hasMatch(label);

  if (hasKgSuffix || hasWeightDigits) {
    return label;
  }

  // Purely dynamic concatenation using the database-supplied weight value
  return '$label ${weightStr}kg';
}

String getFormattedSizeDisplay(String baseSize, dynamic weightValue) {
  String cleanLabel = baseSize.trim();
  if (cleanLabel.isEmpty) return '';

  // Clean duplicate repeated 'kg' suffixes if present in dirty data (e.g. '18G 25kg 25kg' -> '18G 25kg')
  cleanLabel = cleanLabel
      .replaceAllMapped(
          RegExp(r'(\b\d+[\.,]?\d*\s*kg\b)(?:\s+\1)+', caseSensitive: false),
          (m) => m[1]!)
      .replaceAll(
          RegExp(r'\)\s*\d+[\.,]?\d*\s*kg', caseSensitive: false), ')')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Resolve explicit unit_weight_kg
  num? weight;
  if (weightValue != null && weightValue.toString().trim().isNotEmpty) {
    if (weightValue is num) {
      weight = weightValue;
    } else {
      weight = num.tryParse(weightValue.toString().replaceAll(',', '.'));
    }
  }

  // Check if label contains an existing kg value (e.g. "18G 25kg" or "18G (25kg)")
  final kgRegex = RegExp(r'\(?\s*(\d+[\.,]?\d*)\s*kg\s*\)?', caseSensitive: false);
  final kgMatch = kgRegex.firstMatch(cleanLabel);

  if (weight != null && weight > 0) {
    if (kgMatch != null) {
      final double existingKg =
          double.tryParse(kgMatch.group(1)!.replaceAll(',', '.')) ?? 0.0;
      if ((existingKg - weight.toDouble()).abs() > 0.001) {
        // The label's embedded weight contradicts the row's explicit weight.
        // Strip the conflicting weight and re-format with the true weight.
        cleanLabel = cleanLabel
            .replaceAll(
                RegExp(
                    r'\(?\s*' +
                        RegExp.escape(kgMatch.group(1)!) +
                        r'\s*kg\s*\)?',
                    caseSensitive: false),
                '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      } else {
        // Label already has the matching weight
        return cleanLabel;
      }
    }
  } else {
    // If no explicit weight was provided, simply return the database label unmodified
    return cleanLabel;
  }

  return resolveDynamicSizeTitle(
    rawLabel: cleanLabel,
    unitWeightKg: weight,
  );
}



