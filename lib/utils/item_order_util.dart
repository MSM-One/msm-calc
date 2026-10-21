/// Canonical global category sequence utility for MSM ERP.
/// Ensures consistent sorting across Mobile, Web, Database Views, and PDF Exports.
class ItemOrderUtil {
  /// Canonical sort order requested by ERP specifications
  static const List<String> canonicalSequence = [
    "MS Pipe",
    "MS Angle",
    "MS Channel",
    "Binding Wire",
    "Nails",
    "Sqr Bar",
    "Round Bar",
    "Flats",
    "HR Pipe",
    "MS Structure ISMC",
    "Heavy Structure ISMB",
    "Barbed Wire",
    "GATE Channel",
    "ERW Pipe",
  ];

  static final Map<String, int> _orderMap = {
    for (int i = 0; i < canonicalSequence.length; i++)
      _normalize(canonicalSequence[i]): i,
    // Standard Aliases
    'pipe': 0,
    'ms pipe': 0,
    'ms pipes': 0,
    'angle': 1,
    'ms angle': 1,
    'ms angles': 1,
    'channel': 2,
    'ms channel': 2,
    'ms channels': 2,
    'binding wire': 3,
    'binding wires': 3,
    'nails': 4,
    'nail': 4,
    'sqr bar': 5,
    'sqr bars': 5,
    'square bar': 5,
    'square bars': 5,
    'sq bar': 5,
    'round bar': 6,
    'round bars': 6,
    'rd bar': 6,
    'flat': 7,
    'flats': 7,
    'ms flat': 7,
    'ms flats': 7,
    'hr pipe': 8,
    'hr pipes': 8,
    'ismc': 9,
    'ms structure ismc': 9,
    'structure ismc': 9,
    'ismb': 10,
    'heavy structure ismb': 10,
    'structure ismb': 10,
    'barbed wire': 11,
    'barbed wires': 11,
    'gate channel': 12,
    'gate channels': 12,
    'erw pipe': 13,
    'erw pipes': 13,
  };

  static String _normalize(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Returns the 0-indexed canonical sort rank (or 999 for unknown items).
  static int getOrder(String? itemName) {
    if (itemName == null || itemName.trim().isEmpty) return 999;
    final norm = _normalize(itemName);
    if (_orderMap.containsKey(norm)) {
      return _orderMap[norm]!;
    }
    // Partial substring fallback
    for (final entry in _orderMap.entries) {
      if (norm == entry.key || norm.contains(entry.key)) {
        return entry.value;
      }
    }
    return 999;
  }

  /// Compares two category / item names based on the canonical sequence.
  /// Falls back to alphabetical comparison for items outside the canonical list.
  static int compare(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final int orderA = getOrder(a);
    final int orderB = getOrder(b);

    if (orderA != orderB) {
      return orderA.compareTo(orderB);
    }

    return _normalize(a).compareTo(_normalize(b));
  }
}
