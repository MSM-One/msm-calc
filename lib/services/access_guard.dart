import 'package:flutter/foundation.dart';
import '../models/permission_model.dart';
import '../models/stock_role.dart';
import '../models/user_model.dart';
import '../services/data_repository.dart';
import '../core/app_permissions.dart';

/// Helper check for Vendor Purchase module access across all permission aliases.
bool hasVendorPurchaseAccess([UserModel? user]) {
  final u = user ?? DataRepository.currentUserNotifier.value;
  if (u != null) {
    if (u.isAdmin || UserSession.currentRole == StockRole.ADMIN) return true;
    return u.permissions['log_vendor_purchase'] == true ||
        u.permissions['vendor_purchase_log'] == true ||
        u.permissions['vendor_purchase'] == true ||
        u.permissions['can_add_vendor_purchase'] == true ||
        u.permissions[AppPermissions.vendorPurchase] == true ||
        u.permissions[AppPermissions.screensVendorPurchase] == true;
  }
  if (UserSession.currentRole == StockRole.ADMIN) return true;
  return AccessGuard.can(AppPermissions.vendorPurchase) ||
      AccessGuard.can(AppPermissions.screensVendorPurchase) ||
      AccessGuard.can('log_vendor_purchase') ||
      AccessGuard.can('vendor_purchase_log') ||
      AccessGuard.can('vendor_purchase');
}

/// Centralised access enforcement engine.
class AccessGuard {
  AccessGuard._();

  /// Unified Vendor Purchase permission check
  static bool hasVendorPurchaseAccess([UserModel? user]) =>
      hasVendorPurchaseAccess(user);

  /// Returns `true` if the current user is allowed to perform [slug].
  static bool can(String slug, {String? location}) {
    final user = DataRepository.currentUserNotifier.value;

    // ── 1. UserModel present — it is the single source of truth ──────────────
    if (user != null) {
      // Admins bypass all checks
      if (user.isAdmin) return true;

      // Enforce module hierarchy (parent must be ON for children to work)
      if (slug.startsWith('inventory.') &&
          slug != Permissions.inventoryScreen) {
        if (user.permissions[Permissions.inventoryScreen] != true) {
          debugPrint("[AccessGuard] denied (parent off): $slug");
          return false;
        }
      }
      if (slug.startsWith('reports.') && slug != Permissions.reportsScreen) {
        if (user.permissions[Permissions.reportsScreen] != true) {
          debugPrint("[AccessGuard] denied (parent off): $slug");
          return false;
        }
      }

      // Read directly from the saved permissions map.
      // If the key is absent, deny (never fall through to legacy for UserModel users).
      final allowed = user.permissions[slug] ?? false;
      if (!allowed) {
        debugPrint(
            "[AccessGuard] denied ($slug absent/false in user.permissions)");
        return false;
      }

      // Optional location-scope check
      if (location != null &&
          user.branchLocation != null &&
          user.branchLocation!.isNotEmpty) {
        return user.branchLocation!.toLowerCase() == location.toLowerCase();
      }
      return true;
    }

    // ── 2. No UserModel — fall back to legacy UserSession ────────────────────
    if (UserSession.currentRole == StockRole.ADMIN) return true;

    if (slug.startsWith('inventory.') && slug != Permissions.inventoryScreen) {
      if (!can(Permissions.inventoryScreen)) return false;
    }
    if (slug.startsWith('reports.') && slug != Permissions.reportsScreen) {
      if (!can(Permissions.reportsScreen)) return false;
    }

    final effective = PermissionRegistry.resolve(
      roleId: UserSession.roleId,
      customPermissions: UserSession.customPermissions,
    );

    final perm = effective[slug];
    if (perm == null || !perm.isAllowed) {
      debugPrint("[MOBILE HIDE CHECK] $slug false");
      return false;
    }

    if (perm.scope == PermissionScope.location) {
      if (location == null) return true;
      final assigned = UserSession.assignedLocation?.toLowerCase();
      if (assigned == null || assigned.isEmpty) return false;
      return assigned == location.toLowerCase();
    }

    // Verbatim Requirement: Log visibility checks
    debugPrint("[MOBILE HIDE CHECK] $slug true");
    return true;
  }

  /// Convenience: returns `true` if the user is NOT allowed.
  static bool cannot(String slug, {String? location}) =>
      !can(slug, location: location);

  /// Use in [initState] of guarded screens to check and return
  /// whether the current route should be blocked.
  /// Returns `true` if access is allowed, `false` if not.
  static bool canNavigate(String slug) => can(slug);

  /// Checks a parent permission. If the parent is denied,
  /// a child permission must also be treated as denied.
  static bool canWithParent(String slug, String parentSlug) {
    if (!can(parentSlug)) return false;
    return can(slug);
  }
}
