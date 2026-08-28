import 'permission_model.dart';

enum StockRole { VIEWER, OPERATOR, MANAGER, ADMIN }

class UserSession {
  UserSession._();

  // ── Identity ────────────────────────────────────────────────────────────────
  static StockRole currentRole = StockRole.VIEWER;
  static String? userEmail;
  static String allowedAccess = 'All Screens';

  // ── RBAC: New permission map (replaces old booleans) ───────────────────────
  /// The user's role ID: 'admin' or 'staff'.
  static String roleId = 'staff';

  /// Optional single location this Staff user is restricted to.
  static String? assignedLocation;

  /// User-level custom permission overrides.
  /// Merged with [PermissionRegistry] defaults by [AccessGuard].
  static Map<String, Permission> customPermissions = {};

  // ── Legacy booleans (DEPRECATED: Use AccessGuard.can(slug) instead) ───────
  @deprecated
  static bool canCheckRates = false;
  @deprecated
  static bool canViewReports = false;
  @deprecated
  static bool canStockIn = false;
  @deprecated
  static bool canStockOut = false;
  @deprecated
  static bool canStockTransfer = false;
  @deprecated
  static bool canVendorPurchase = false;
  @deprecated
  static bool canViewStockMovement = false;
  @deprecated
  static bool canViewNonMoving = false;
  @deprecated
  static bool canViewTodaySummary = false;
  @deprecated
  static bool canViewStockOverview = false;

  /// Rebuilds legacy booleans from the [customPermissions] map so existing
  /// callers don't need to be updated all at once.
  static void _syncLegacyBooleans() {
    canViewReports = _perm(Permissions.reportsView);
    canCheckRates = _perm(Permissions.ratesView);
    canStockIn = _perm(Permissions.stockIn);
    canStockOut = _perm(Permissions.stockOut);
    canStockTransfer = _perm(Permissions.stockTransfer);
    canVendorPurchase = _perm(Permissions.vendorPurchase);
    canViewStockMovement = _perm(Permissions.reportsMovement);
    canViewNonMoving = _perm(Permissions.reportsNonMoving);
    canViewTodaySummary = _perm(Permissions.reportsTodaySummary);
    canViewStockOverview = _perm(Permissions.reportsOverview);
  }

  static bool _perm(String slug) {
    if (currentRole == StockRole.ADMIN) return true;
    final resolved = PermissionRegistry.resolve(
      roleId: roleId,
      customPermissions: customPermissions,
    );
    return resolved[slug]?.isAllowed ?? false;
  }

  /// Apply a full set of custom permissions and immediately sync legacy booleans.
  static void applyPermissions(Map<String, Permission> perms) {
    customPermissions = perms;
    _syncLegacyBooleans();
  }

  // ── Legacy action checks (kept for backward compat) ────────────────────────
  static bool canPerform(String action) {
    if (userEmail == 'j2833945@gmail.com') return true;
    if (currentRole == StockRole.ADMIN) return true;
    if (currentRole == StockRole.MANAGER) {
      if (action == 'WIPE_DATA') return false;
      return true;
    }
    if (currentRole == StockRole.OPERATOR) {
      return ['IN', 'OUT', 'TRANSFER', 'RETURN'].contains(action);
    }
    return false;
  }

  static bool get isUserAdmin {
    if (userEmail?.toLowerCase().trim() == 'j2833945@gmail.com') return true;
    return currentRole == StockRole.ADMIN;
  }
}
