import 'item_order_util.dart';

class SortingUtils {
  static const List<String> categoryPriority = ItemOrderUtil.canonicalSequence;

  /// Normalizes a category name: trim, lowercase, and collapse multiple spaces.
  static String normalizeCategoryName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Optional dynamic provider for master materials order (e.g. from Supabase materials table)
  static List<String> Function()? dynamicMasterOrderProvider;

  /// Compares two categories based on dynamic master materials order and the global priority list.
  /// Dynamic master items come first in master table order, followed by priority list, then alphabetical.
  static int compareCategories(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    return ItemOrderUtil.compare(a, b);
  }

  static List<double> extractNumericalComponents(String sizeStr) {
    final regExp = RegExp(r'\d+(?:\.\d+)?');
    final matches = regExp.allMatches(sizeStr);
    return matches.map((m) => double.tryParse(m.group(0)!) ?? 0.0).toList();
  }

  static int compareSizes(String a, String b) {
    final List<double> numsA = extractNumericalComponents(a);
    final List<double> numsB = extractNumericalComponents(b);

    final int minLen =
        numsA.length < numsB.length ? numsA.length : numsB.length;
    for (int i = 0; i < minLen; i++) {
      final int cmp = numsA[i].compareTo(numsB[i]);
      if (cmp != 0) return cmp;
    }

    if (numsA.length != numsB.length) {
      return numsA.length.compareTo(numsB.length);
    }

    // Alphabetical fallback comparison to maintain stable indexing
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
}
