export 'format_helper.dart'
    show
        globalSizeWeightCache,
        updateGlobalSizeWeightCache,
        getFormattedSizeDisplay,
        lookupSizeWeight;
import 'package:intl/intl.dart';
import 'format_helper.dart';

// ✅ GLOBAL TIMEZONE & TIMESTAMP HELPERS
/// Robustly parses any Supabase or transaction timestamp into a local DateTime.
/// Supabase ISO-8601 strings (e.g., '2026-09-01 15:57:00+00' or '...Z') are converted
/// to the device/browser local timezone (IST +05:30) via `.toLocal()`.
DateTime parseSupabaseDateTime(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is DateTime) return raw.toLocal();
  final s = raw.toString().trim();
  if (s.isEmpty) return DateTime.now();

  // 1. Standard ISO-8601 string parsing (with +00, +05:30, Z, etc.)
  final parsed = DateTime.tryParse(s);
  if (parsed != null) {
    return parsed.toLocal();
  }

  // 2. Fallbacks for formatted date strings (DD/MM/YYYY HH:mm:ss, Google Sheets, etc.)
  try {
    return DateFormat('dd/MM/yyyy HH:mm:ss').parseStrict(s);
  } catch (_) {}

  try {
    return DateFormat('dd/MM/yyyy hh:mm a').parseStrict(s);
  } catch (_) {}

  try {
    return DateFormat('dd/MM/yyyy').parseStrict(s.split(' ')[0]);
  } catch (_) {}

  try {
    return DateFormat('yyyy-MM-dd').parseStrict(s.split(' ')[0]);
  } catch (_) {}

  return DateTime.now();
}

/// Formats a DateTime for compact table columns: 'dd/MM hh:mm a' (e.g., '01/09 09:27 PM')
String formatTransactionTime(DateTime dt) {
  return DateFormat('dd/MM hh:mm a').format(dt.toLocal());
}

/// Formats a DateTime for full document timestamps: 'dd/MM/yyyy hh:mm a' (e.g., '01/09/2026 09:27 PM')
String formatTransactionDateTime(DateTime dt) {
  return DateFormat('dd/MM/yyyy hh:mm a').format(dt.toLocal());
}

/// Formats a DateTime for date-only displays: 'dd/MM/yyyy' (e.g., '01/09/2026')
String formatTransactionDate(DateTime dt) {
  return DateFormat('dd/MM/yyyy').format(dt.toLocal());
}

// ✅ GLOBAL HELPER FOR SIZE DISPLAY
String formatSizeDisplay(String category, String label) {
  final specialCategories = [
    "Binding Wire",
    "Sq. Bar",
    "Sqr Bar",
    "Round Bar",
    "Flat",
    "Flats"
  ];

  String result = label.trim();

  // 1. Strip Category Name if it starts with it (case-insensitive)
  // e.g. "MS PIPE 1" 25x25" -> "1" 25x25"
  String catUpper = category.toUpperCase().trim();
  String resUpper = result.toUpperCase();
  if (resUpper.startsWith(catUpper)) {
    result = result.substring(catUpper.length).trim();
  }

  if (specialCategories.contains(category)) {
    return result
        .replaceAll(
            RegExp(r'\s*\(?\d*[\.,]?\d*\s*kg\)?$', caseSensitive: false), "")
        .trim();
  }

  // 2. Weight always shows one decimal place followed by kg (e.g., 6.0kg)
  final kgRegex = RegExp(r'(\d+[\.,]?\d*)\s*kg$', caseSensitive: false);
  final match = kgRegex.firstMatch(result);

  if (match != null) {
    String numPart = match.group(1)!.replaceAll(',', '.');
    double weight = double.tryParse(numPart) ?? 0.0;
    String formattedWeight = weight.toStringAsFixed(1);

    String core = result.substring(0, match.start).trim();
    // Ensure space before parenthesis if it exists in core
    core = core.replaceAllMapped(RegExp(r'(\S)\('), (m) => '${m[1]} (');

    result = "$core ${formattedWeight}kg";
  }

  return result.trim();
}

// ✅ GLOBAL HELPERS FOR CURRENCY
String formatIndianCurrency(num amount) {
  String s = amount.toStringAsFixed(0);
  if (s.length <= 3) return s;
  String result = s.substring(s.length - 3);
  s = s.substring(0, s.length - 3);
  while (s.length > 2) {
    result = '${s.substring(s.length - 2)},$result';
    s = s.substring(0, s.length - 2);
  }
  if (s.isNotEmpty) result = '$s,$result';
  return result;
}

String formatMT(double mt) {
  final val = mt < 0.0 ? 0.0 : mt;
  return val.toStringAsFixed(3);
}

String formatNos(double nos) => nos.toStringAsFixed(0);

String formatAngleSize(String sizeDesc, double weight) {
  // Strip any existing weight suffix (e.g. " 6.2kg", " 6.2 kg", " 6kg")
  String base = sizeDesc.trim();
  base = base
      .replaceAll(
          RegExp(r'\s*\(?\d*[\.,]?\d*\s*kg\)?$', caseSensitive: false), "")
      .trim();

  final formattedWeight =
      weight % 1 == 0 ? weight.toInt().toString() : weight.toStringAsFixed(1);
  return "${base.replaceAll(' ', '')} ${formattedWeight}kg";
}

// Helper for standardizing raw MS Angle size labels
String formatSizeLabel(String label, String materialName, double unitWeight) {
  final cleanMat = materialName.trim();
  if (cleanMat == 'MS Angle') {
    return formatAngleSize(label, unitWeight);
  }
  return label;
}

String formatSizeWithWeight(String sizeLabel, dynamic weight) {
  return getFormattedSizeDisplay(sizeLabel, weight);
}

String formatMaterialSize(String sizeLabel, dynamic weightKg) {
  if (sizeLabel.isEmpty) return '';

  // Clean extra parentheses around kg e.g. "18G (25kg)" -> "18G 25kg"
  String cleaned = sizeLabel.replaceAll('(', '').replaceAll(')', '').trim();

  // If weightKg is provided and not already in cleaned string, format nicely
  double parsedWeight = double.tryParse(weightKg?.toString() ?? '') ?? 0.0;

  if (parsedWeight > 0) {
    String weightStr = parsedWeight % 1 == 0
        ? '${parsedWeight.toInt()}kg'
        : '${parsedWeight}kg';

    // Strip existing '25kg' or '25 kg' from cleaned string before appending cleanly
    cleaned = cleaned
        .replaceAll(RegExp(r'\s*\d+(\.\d+)?\s*kg', caseSensitive: false), '')
        .trim();
    return '$cleaned $weightStr';
  }

  return cleaned;
}
