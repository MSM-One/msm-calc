/// Category canonical resolution and exact matching utility.
/// Prevents size count corruption and ensures strict separation between
/// distinct steel product lines (e.g., MS Pipe vs HR Pipe vs ERW Pipe,
/// MS Channel vs Gate Channel vs ISMC, Sqr Bar vs Square Pipe).
library category_matcher;

/// Resolves a category string to its exact canonical identity.
String getCanonicalCategory(String? raw) {
  if (raw == null) return '';
  final s = raw.trim().toUpperCase();

  // 1. Differentiate Pipe sub-types explicitly:
  if (s == 'HR PIPE' || s.startsWith('HR PIPE')) return 'HR PIPE';
  if (s == 'CR PIPE' || s.startsWith('CR PIPE')) return 'CR PIPE';
  if (s == 'ERW PIPE' || s.startsWith('ERW PIPE')) return 'ERW PIPE';
  if (s == 'MS PIPE' || s == 'PIPE' || s == 'PIPES') return 'MS PIPE';

  // 2. Differentiate Channel sub-types explicitly:
  if (s.contains('GATE CHANNEL')) return 'GATE CHANNEL';
  if (s.contains('ISMC') || s.contains('MS STRUCTURE ISMC')) return 'MS STRUCTURE ISMC';
  if (s == 'MS CHANNEL' || s == 'CHANNEL') return 'MS CHANNEL';

  // 3. Differentiate Beams / Structures:
  if (s.contains('ISMB') || s.contains('HEAVY STRUCTURE')) return 'HEAVY STRUCTURE ISMB';

  // 4. Bars & Standard Structural Categories:
  if (s.contains('SQR') || s.contains('SQUARE')) return 'SQR BAR';
  if (s.contains('ROUND')) return 'ROUND BAR';
  if (s.contains('FLAT')) return 'FLATS';
  if (s == 'MS ANGLE' || s == 'ANGLE') return 'MS ANGLE';
  if (s.contains('BARBED')) return 'BARBED WIRE';
  if (s.contains('BINDING')) return 'BINDING WIRE';
  if (s.contains('NAIL')) return 'NAILS';

  return s;
}

/// Exact equality comparison for category sizes
bool isSizeInCategory(dynamic sizeItem, String targetCategory) {
  final target = getCanonicalCategory(targetCategory);
  if (target.isEmpty) return false;

  String? rawCat;
  if (sizeItem is Map) {
    rawCat = (sizeItem['material_name'] ??
              sizeItem['category'] ??
              sizeItem['materialName'] ??
              sizeItem['item_name'])?.toString();
  } else if (sizeItem != null) {
    try {
      rawCat = sizeItem.category?.toString() ??
               sizeItem.materialName?.toString() ??
               sizeItem.name?.toString();
    } catch (_) {
      rawCat = sizeItem.toString();
    }
  }
  final itemCat = getCanonicalCategory(rawCat);
  return target == itemCat;
}
