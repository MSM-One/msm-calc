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

String getFormattedSizeDisplay(String baseSize, dynamic weightValue) {
  dynamic targetWeight = weightValue;
  if (targetWeight == null ||
      targetWeight.toString().trim().isEmpty ||
      targetWeight.toString() == '0') {
    final cleanLabel = baseSize.trim();
    final cachedWeight = lookupSizeWeight(cleanLabel);
    if (cachedWeight > 0) {
      targetWeight = cachedWeight;
    } else {
      final match = RegExp(r'(\d+[\.,]?\d*)\s*(kg)?$', caseSensitive: false)
          .firstMatch(baseSize);
      if (match != null) {
        targetWeight = double.tryParse(match.group(1)!.replaceAll(',', '.'));
      }
    }
  }

  if (targetWeight == null || targetWeight.toString().trim().isEmpty)
    return baseSize;
  final parsedWeight = double.tryParse(targetWeight.toString());
  if (parsedWeight == null || parsedWeight == 0) return baseSize;
  final cleanWeightText = parsedWeight % 1 == 0
      ? parsedWeight.toInt().toString()
      : parsedWeight.toStringAsFixed(1);

  final cleanBase = baseSize
      .replaceAll(RegExp(r'\s*\(\d+(\.\d+)?\s*kg\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\d+(\.\d+)?\s*kg', caseSensitive: false), '')
      .trim();

  return "$cleanBase ${cleanWeightText}kg";
}
