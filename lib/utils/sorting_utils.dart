class SortingUtils {
  static const List<String> categoryPriority = [
    "MS Pipe",
    "ERW Pipe",
    "HR Pipe",
    "CR Pipe",
    "MS Angle",
    "MS Channel",
    "Binding Wire",
    "Nails",
    "SQR BAR",
    "Round Bar",
    "Flats",
    "MS Structure ISMC",
    "Heavy Structure ISMB",
    "Barbed Wire",
    "GATE Channel",
  ];

  /// Normalized versions of the priority list for fast lookup
  static final List<String> _normalizedPriority =
      categoryPriority.map((e) => normalizeCategoryName(e)).toList();

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

    final String normA = normalizeCategoryName(a);
    final String normB = normalizeCategoryName(b);
    if (normA == normB) return 0;

    // Check dynamic master order provider if available
    if (dynamicMasterOrderProvider != null) {
      final masterList = dynamicMasterOrderProvider!();
      final normMaster = masterList.map((e) => normalizeCategoryName(e)).toList();
      final idxA = normMaster.indexOf(normA);
      final idxB = normMaster.indexOf(normB);
      if (idxA != -1 && idxB != -1) {
        return idxA.compareTo(idxB);
      }
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
    }

    int indexA = _normalizedPriority.indexOf(normA);
    int indexB = _normalizedPriority.indexOf(normB);

    // If both are in the priority list, sort by their position in that list
    if (indexA != -1 && indexB != -1) {
      return indexA.compareTo(indexB);
    }
    // Priority items come first
    if (indexA != -1) return -1;
    if (indexB != -1) return 1;

    // Both are outside the priority list, sort alphabetically
    return normA.compareTo(normB);
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
