import 'formatters.dart' as formatters;
import '../constants/app_colors.dart';
import 'package:flutter/material.dart';

class SteelHelper {
  static double extractWeightKg(String? label, {String? category}) {
    if (label == null || label.isEmpty) return 0.0;

    try {
      // Clean label but keep dots and numbers
      String cleanLabel = label.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ').trim();

      // Match a numeric value at the end, optionally followed by "kg"
      final weightRegex =
          RegExp(r'(\d+[\.,]?\d*)\s*(kg)?$', caseSensitive: false);
      final match = weightRegex.firstMatch(cleanLabel);

      if (match != null) {
        String numStr = match.group(1)!.replaceAll(',', '.');
        double weight = double.tryParse(numStr) ?? 0.0;
        if (weight > 0) return weight;
      }
    } catch (_) {}

    final catLower = category?.toLowerCase().trim() ?? '';
    if (catLower.contains('binding wire') || catLower.contains('barbed wire')) {
      return 25.0; // Default 25 kg per bundle/roll
    }
    if (catLower.contains('nails')) {
      return 50.0; // Default 50 kg per bag
    }

    return 0.0;
  }

  static double calculateMT(num nos, String label) {
    double unitWeight = extractWeightKg(label);
    return (nos * unitWeight) / 1000.0;
  }

  static double getMTFromNos(num nos, String? label, {String? category}) {
    if (nos <= 0 || label == null) return 0.0;
    double kg = extractWeightKg(label, category: category);
    if (kg <= 0) return 0.0;
    return (nos * kg) / 1000.0;
  }

  static double getNosFromMT(double mt, String? label, {String? category}) {
    if (mt <= 0 || label == null) return 0.0;
    double kg = extractWeightKg(label, category: category);
    if (kg <= 0) return 0.0;
    return (mt * 1000.0) / kg;
  }

  /// Normalizes size text for robust comparison and deduplication.
  /// Handles lowercase, trimming, quotes, multiple spaces, invisible characters,
  /// and optional unit/format spacing (e.g., "10 mm" -> "10mm").
  static String normalizeSizeText(String s) {
    String res = s.toLowerCase().trim();
    // Remove invisible characters
    res = res.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    // Collapse multiple spaces to single
    res = res.replaceAll(RegExp(r'\s+'), ' ');
    // Collapsing spaces around units and common separators, supporting decimals
    res = res.replaceAll(
        RegExp(r'(\d+\.?\d*)\s+(mm|kg|mt|in|mtr|inch|")', caseSensitive: false),
        r'$1$2');
    res = res.replaceAll(RegExp(r'\s+x\s+', caseSensitive: false), 'x');
    return res.trim();
  }
}

// ✅ GLOBAL HELPERS FOR SORTING
double parseThickness(String label) {
  try {
    final parenMatch = RegExp(r'\((\d+\.?\d*)\s*m*m*\)').firstMatch(label);
    if (parenMatch != null) return double.tryParse(parenMatch.group(1)!) ?? 0.0;

    final xMatch = RegExp(r'x\s*(\d+\.?\d*)').firstMatch(label);
    if (xMatch != null) return double.tryParse(xMatch.group(1)!) ?? 0.0;

    final anyNum = RegExp(r'(\d+\.?\d*)').firstMatch(label);
    if (anyNum != null) return double.tryParse(anyNum.group(1)!) ?? 0.0;
  } catch (_) {}
  return 0.0;
}

double extractUnitWeight(String label) {
  return SteelHelper.extractWeightKg(label);
}

bool isWeightOnlyItem(String? category) {
  if (category == null) return false;
  final lc = category.toLowerCase().trim();
  return lc.contains("sq. bar") ||
      lc.contains("sqr bar") ||
      lc.contains("round bar") ||
      lc.contains("flat");
}

bool shouldShowNos(String? category, String? label) {
  if (label != null && label.toLowerCase().contains("kg")) return true;
  return !isWeightOnlyItem(category);
}

// ✅ GLOBAL SEARCH LOGIC
List<T> applyPrioritizedSearch<T>(
    String query, List<T> items, String Function(T) mapper) {
  if (query.isEmpty) return items;
  final q = query.toLowerCase().trim().replaceAll('X', 'x');

  final exact = <T>[];
  final starts = <T>[];
  final contains = <T>[];

  for (final item in items) {
    final val = mapper(item).toLowerCase().trim().replaceAll('X', 'x');
    if (val == q) {
      exact.add(item);
    } else if (val.startsWith(q)) {
      starts.add(item);
    } else if (val.contains(q)) {
      contains.add(item);
    }
  }

  int sortingAlgo(T a, T b) =>
      mapper(a).toLowerCase().compareTo(mapper(b).toLowerCase());
  exact.sort(sortingAlgo);
  starts.sort(sortingAlgo);
  contains.sort(sortingAlgo);

  return [...exact, ...starts, ...contains];
}

// ✅ UNIFIED INPUT DECORATIONS
InputDecoration msmInputDeco(String label,
    {String? hint, Widget? prefix, Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: inputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: borderLight)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: borderLight)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: msmRed, width: 2)),
    labelStyle: const TextStyle(color: textGrey, fontSize: 13),
    floatingLabelStyle:
        const TextStyle(color: msmRed, fontWeight: FontWeight.bold),
  );
}

InputDecoration msmTableInputDeco({String? hint, Color? fillColor}) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: fillColor ?? inputFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderLight)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderLight)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: msmRed, width: 1.5)),
  );
}
