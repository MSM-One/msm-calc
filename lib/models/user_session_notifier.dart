import 'package:flutter/foundation.dart';
import 'stock_role.dart';
import 'permission_model.dart';
import '../services/access_guard.dart';

/// A lightweight snapshot of the current user's permissions.
/// Used to drive reactive UI rebuilds without a state management package.
class PermissionSnapshot {
  final String allowedAccess;
  final bool canStockIn;
  final bool canStockOut;
  final bool canStockTransfer;
  final bool canCheckRates;
  final bool canViewReports;
  final bool canVendorPurchase;
  final bool canViewStockMovement;
  final bool canViewNonMoving;
  final bool canViewTodaySummary;
  final bool canViewStockLedger;
  final bool canViewLowStock;
  final bool canViewStockOverview;
  final StockRole role;
  // ── Field-level data guards ────────────────────────────────────────────────────
  final bool canViewInventoryQuantity;
  final bool canViewInventoryMetrics;
  final bool canViewTxnQuantity;

  // ── Screen Access Flags ────────────────────────────────────────────────────────
  final bool canAccessDashboard;
  final bool canAccessUsers;
  final bool canAccessQuotation;
  final bool canAccessCalculator;
  final bool canAccessSaudaBooking;
  final bool canAccessVendorPurchaseScreen;
  final bool canAccessStockInventory;
  final bool canAccessReports;
  final bool canAccessInventoryDash;
  final bool canAccessCurrentStock;
  final bool canAccessTransactions;
  final bool canAccessStockDetail;
  final bool canAccessItemDetail;
  final bool canAccessTxnDetail;
  final bool canAccessSampleRate;
  final bool canAccessSalesDocCenter;
  final bool canAccessMasterSize;
  final bool canAccessStockSheet;
  final bool canDelete;

  const PermissionSnapshot({
    required this.allowedAccess,
    required this.canStockIn,
    required this.canStockOut,
    required this.canStockTransfer,
    required this.canCheckRates,
    required this.canViewReports,
    required this.canVendorPurchase,
    required this.canViewStockMovement,
    required this.canViewNonMoving,
    required this.canViewTodaySummary,
    this.canViewStockLedger = false,
    this.canViewLowStock = false,
    required this.canViewStockOverview,
    required this.role,
    this.canViewInventoryQuantity = false,
    this.canViewInventoryMetrics = false,
    this.canViewTxnQuantity = false,
    this.canAccessDashboard = true,
    this.canAccessUsers = false,
    this.canAccessQuotation = false,
    this.canAccessCalculator = false,
    this.canAccessSaudaBooking = false,
    this.canAccessVendorPurchaseScreen = false,
    this.canAccessStockInventory = false,
    this.canAccessReports = false,
    this.canAccessInventoryDash = false,
    this.canAccessCurrentStock = false,
    this.canAccessTransactions = false,
    this.canAccessStockDetail = false,
    this.canAccessItemDetail = false,
    this.canAccessTxnDetail = false,
    this.canAccessSampleRate = false,
    this.canAccessSalesDocCenter = false,
    this.canAccessMasterSize = false,
    this.canAccessStockSheet = false,
    this.canDelete = false,
  });

  /// Creates a snapshot from the current global UserSession static values.
  factory PermissionSnapshot.fromSession() {
    return PermissionSnapshot(
      allowedAccess: UserSession.allowedAccess,
      canStockIn: AccessGuard.can(Permissions.stockIn),
      canStockOut: AccessGuard.can(Permissions.stockOut),
      canStockTransfer: AccessGuard.can(Permissions.stockTransfer),
      canCheckRates: AccessGuard.can(Permissions.ratesView),
      canViewReports: AccessGuard.can(Permissions.reportsView),
      canVendorPurchase: AccessGuard.can(Permissions.vendorPurchase),
      canViewStockMovement: AccessGuard.can(Permissions.reportsMovement),
      canViewNonMoving: AccessGuard.can(Permissions.reportsNonMoving),
      canViewTodaySummary: AccessGuard.can(Permissions.reportsTodaySummary),
      canViewStockLedger: AccessGuard.can(Permissions.reportStockLedger),
      canViewLowStock: AccessGuard.can(Permissions.reportLowStock),
      canViewStockOverview: AccessGuard.can(Permissions.reportsOverview),
      role: UserSession.currentRole,
      // Field-level guards via new AccessGuard
      canViewInventoryQuantity:
          AccessGuard.can(Permissions.inventoryQuantityView),
      canViewInventoryMetrics:
          AccessGuard.can(Permissions.inventoryMetricsView),
      canViewTxnQuantity: AccessGuard.can(Permissions.transactionsQuantityView),

      // Screen Access via new granular slugs
      canAccessDashboard: AccessGuard.can(Permissions.screensDashboard),
      canAccessUsers: AccessGuard.can(Permissions.screensUsers),
      canAccessQuotation: AccessGuard.can(Permissions.screensQuotation),
      canAccessCalculator: AccessGuard.can(Permissions.screensCalculator),
      canAccessSaudaBooking: AccessGuard.can(Permissions.screensSaudaBooking),
      canAccessVendorPurchaseScreen: hasVendorPurchaseAccess(),
      canAccessStockInventory:
          AccessGuard.can(Permissions.screensStockInventory),
      canAccessReports: AccessGuard.can(Permissions.screensReports),
      canAccessInventoryDash: AccessGuard.can(Permissions.screensInventoryDash),
      canAccessCurrentStock: AccessGuard.can(Permissions.screensCurrentStock),
      canAccessTransactions: AccessGuard.can(Permissions.screensTransactions),
      canAccessStockDetail: AccessGuard.can(Permissions.screensStockDetail),
      canAccessItemDetail: AccessGuard.can(Permissions.screensItemDetail),
      canAccessTxnDetail: AccessGuard.can(Permissions.screensTxnDetail),
      canAccessSampleRate: AccessGuard.can(Permissions.screensSampleRate),
      canAccessSalesDocCenter:
          AccessGuard.can(Permissions.screensSalesDocCenter),
      canAccessMasterSize: AccessGuard.can(Permissions.screensMasterSize),
      canAccessStockSheet: AccessGuard.can(Permissions.screensStockSheet) ||
          AccessGuard.can(Permissions.canAccessStockSheet),
      canDelete: AccessGuard.can(Permissions.usersDelete),
    );
  }

  bool canAccess(String requiredScreen) {
    if (role == StockRole.ADMIN) return true;
    // 'Vendor Purchase Only' always requires the explicit boolean permission,
    // regardless of whether the user has 'All Screens' chip selected.
    if (requiredScreen == 'Vendor Purchase Only') return canVendorPurchase;
    if (requiredScreen == 'Sample Rate Only') return canAccessSampleRate;
    if (allowedAccess == 'All Screens') return true;
    return allowedAccess.contains(requiredScreen);
  }

  bool get effectiveCanViewReports =>
      role == StockRole.ADMIN || canViewReports || canAccess('Reports Only');

  @override
  bool operator ==(Object other) =>
      other is PermissionSnapshot &&
      other.allowedAccess == allowedAccess &&
      other.canStockIn == canStockIn &&
      other.canStockOut == canStockOut &&
      other.canStockTransfer == canStockTransfer &&
      other.canCheckRates == canCheckRates &&
      other.canViewReports == canViewReports &&
      other.canVendorPurchase == canVendorPurchase &&
      other.canViewStockMovement == canViewStockMovement &&
      other.canViewNonMoving == canViewNonMoving &&
      other.canViewTodaySummary == canViewTodaySummary &&
      other.canViewStockOverview == canViewStockOverview &&
      other.canViewInventoryQuantity == canViewInventoryQuantity &&
      other.canViewInventoryMetrics == canViewInventoryMetrics &&
      other.canViewTxnQuantity == canViewTxnQuantity &&
      other.canAccessDashboard == canAccessDashboard &&
      other.canAccessUsers == canAccessUsers &&
      other.canAccessQuotation == canAccessQuotation &&
      other.canAccessCalculator == canAccessCalculator &&
      other.canAccessSaudaBooking == canAccessSaudaBooking &&
      other.canAccessVendorPurchaseScreen == canAccessVendorPurchaseScreen &&
      other.canAccessStockInventory == canAccessStockInventory &&
      other.canAccessReports == canAccessReports &&
      other.canAccessInventoryDash == canAccessInventoryDash &&
      other.canAccessCurrentStock == canAccessCurrentStock &&
      other.canAccessTransactions == canAccessTransactions &&
      other.canAccessStockDetail == canAccessStockDetail &&
      other.canAccessItemDetail == canAccessItemDetail &&
      other.canAccessTxnDetail == canAccessTxnDetail &&
      other.canAccessSampleRate == canAccessSampleRate &&
      other.canAccessSalesDocCenter == canAccessSalesDocCenter &&
      other.canAccessMasterSize == canAccessMasterSize &&
      other.canAccessStockSheet == canAccessStockSheet &&
      other.canDelete == canDelete &&
      other.role == role;

  @override
  int get hashCode => Object.hashAll([
        allowedAccess,
        canStockIn,
        canStockOut,
        canStockTransfer,
        canCheckRates,
        canViewReports,
        canVendorPurchase,
        canViewStockMovement,
        canViewNonMoving,
        canViewTodaySummary,
        canViewStockOverview,
        canViewInventoryQuantity,
        canViewInventoryMetrics,
        canViewTxnQuantity,
        canAccessDashboard,
        canAccessUsers,
        canAccessQuotation,
        canAccessCalculator,
        canAccessSaudaBooking,
        canAccessVendorPurchaseScreen,
        canAccessStockInventory,
        canAccessReports,
        canAccessInventoryDash,
        canAccessCurrentStock,
        canAccessTransactions,
        canAccessStockDetail,
        canAccessItemDetail,
        canAccessTxnDetail,
        canAccessSampleRate,
        canAccessSalesDocCenter,
        canAccessMasterSize,
        canAccessStockSheet,
        canDelete,
        role
      ]);
}

/// A singleton ValueNotifier that emits a new [PermissionSnapshot] whenever
/// user permissions are refreshed from the backend.
class UserSessionNotifier {
  UserSessionNotifier._();
  static final instance =
      ValueNotifier<PermissionSnapshot>(PermissionSnapshot.fromSession());

  /// Call this after [DataRepository.syncCurrentUser()] completes.
  /// Returns true if the permissions actually changed (for nav guard logic).
  static bool refreshFromSession() {
    final newSnapshot = PermissionSnapshot.fromSession();

    // Verbatim Requirement: Log permission state
    debugPrint(
        "[MOBILE PERMISSION STATE] ${newSnapshot.role.name} ${UserSession.customPermissions.keys.toList()}");

    if (newSnapshot != instance.value) {
      instance.value = newSnapshot;
      return true; // permissions changed
    }
    return false;
  }
}
