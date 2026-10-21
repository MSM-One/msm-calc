import 'permission_model.dart';
import '../services/app_config_service.dart';

/// AppRole matches the database check constraints ('admin', 'manager', 'staff').
enum AppRole {
  admin('admin', 'Admin', '👑 Admin'),
  manager('manager', 'Manager', '👔 Manager'),
  staff('staff', 'Staff', '👤 Staff');

  final String value;
  final String label;
  final String displayWithIcon;

  const AppRole(this.value, this.label, this.displayWithIcon);

  bool get isAdmin => this == AppRole.admin;
  bool get isManager => this == AppRole.manager;
  bool get isStaff => this == AppRole.staff;

  String get icon {
    switch (this) {
      case AppRole.admin:
        return '👑';
      case AppRole.manager:
        return '👔';
      case AppRole.staff:
        return '👤';
    }
  }

  /// Safe parsing method with fallback to staff.
  static AppRole fromString(String? val) {
    if (val == null || val.trim().isEmpty) return AppRole.staff;
    final clean = val.toLowerCase().trim();
    for (final role in AppRole.values) {
      if (role.value == clean || role.name == clean) return role;
    }
    if (clean == 'super_admin' || clean == 'superadmin') return AppRole.admin;
    if (clean == 'operator' || clean == 'viewer' || clean == 'unknown') {
      return AppRole.staff;
    }
    return AppRole.staff;
  }
}

typedef UserRole = AppRole;

enum StockRole { VIEWER, OPERATOR, MANAGER, ADMIN }

class UserSession {
  UserSession._();

  // ── Identity ────────────────────────────────────────────────────────────────
  static StockRole currentRole = StockRole.VIEWER;
  static AppRole currentAppRole = AppRole.staff;
  static String? userEmail;
  static String allowedAccess = 'All Screens';

  // ── RBAC: Permission map ───────────────────────────────────────────────────
  /// The user's role ID: 'admin', 'manager', or 'staff'.
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
    if (isUserAdmin) return true;
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

  /// Dynamic Super Admin email from AppConfigService.
  static String get superAdminEmail => AppConfigService.superAdminEmail;
  static set superAdminEmail(String val) {
    AppConfigService.superAdminEmailNotifier.value = val;
  }

  // ── Legacy action checks (kept for backward compat) ────────────────────────
  static bool canPerform(String action) {
    if (isSuperAdmin) return true;
    if (isUserAdmin) return true;
    if (currentRole == StockRole.MANAGER || currentAppRole.isManager) {
      if (action == 'WIPE_DATA') return false;
      return true;
    }
    if (currentRole == StockRole.OPERATOR) {
      return ['IN', 'OUT', 'TRANSFER', 'RETURN'].contains(action);
    }
    return false;
  }

  /// True only for the active Super Admin account dynamically via AppConfigService.
  static bool get isSuperAdmin => AppConfigService.isSuperAdmin(userEmail);

  static bool get isUserAdmin {
    if (isSuperAdmin) return true;
    return currentRole == StockRole.ADMIN || currentAppRole.isAdmin;
  }
}
