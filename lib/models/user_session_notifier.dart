import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stock_role.dart';
import 'permission_model.dart';
import 'user_model.dart';
import '../services/access_guard.dart';
import '../services/data_repository.dart';
import '../services/supabase_service.dart';

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

  bool get isSuperAdmin => UserSession.isSuperAdmin;

  bool get isAdmin =>
      role.name.trim().toUpperCase() == 'ADMIN' ||
      role.name.trim().toUpperCase() == 'SUPER_ADMIN' ||
      role == StockRole.ADMIN ||
      isSuperAdmin;

  /// Creates a snapshot from the current global UserSession static values.
  factory PermissionSnapshot.fromSession() {
    final user = DataRepository.currentUserNotifier.value;
    final bool isAdmin = (user != null && user.isAdmin) ||
        UserSession.isSuperAdmin ||
        UserSession.isUserAdmin ||
        UserSession.currentRole == StockRole.ADMIN ||
        UserSession.roleId.trim().toUpperCase() == 'ADMIN' ||
        UserSession.roleId.trim().toUpperCase() == 'SUPER_ADMIN';

    return PermissionSnapshot(
      allowedAccess: UserSession.allowedAccess,
      canStockIn: isAdmin || AccessGuard.can(Permissions.stockIn),
      canStockOut: isAdmin || AccessGuard.can(Permissions.stockOut),
      canStockTransfer: isAdmin || AccessGuard.can(Permissions.stockTransfer),
      canCheckRates: isAdmin || AccessGuard.can(Permissions.ratesView),
      canViewReports: isAdmin || AccessGuard.can(Permissions.reportsView),
      canVendorPurchase: isAdmin || AccessGuard.can(Permissions.vendorPurchase),
      canViewStockMovement: isAdmin || AccessGuard.can(Permissions.reportsMovement),
      canViewNonMoving: isAdmin || AccessGuard.can(Permissions.reportsNonMoving),
      canViewTodaySummary: isAdmin || AccessGuard.can(Permissions.reportsTodaySummary),
      canViewStockLedger: isAdmin || AccessGuard.can(Permissions.reportStockLedger),
      canViewLowStock: isAdmin || AccessGuard.can(Permissions.reportLowStock),
      canViewStockOverview: isAdmin || AccessGuard.can(Permissions.reportsOverview),
      role: isAdmin ? StockRole.ADMIN : UserSession.currentRole,
      // Field-level guards via new AccessGuard
      canViewInventoryQuantity:
          isAdmin || AccessGuard.can(Permissions.inventoryQuantityView),
      canViewInventoryMetrics:
          isAdmin || AccessGuard.can(Permissions.inventoryMetricsView),
      canViewTxnQuantity:
          isAdmin || AccessGuard.can(Permissions.transactionsQuantityView),

      // Screen Access via new granular slugs
      canAccessDashboard:
          isAdmin || AccessGuard.can(Permissions.screensDashboard),
      canAccessUsers: isAdmin || AccessGuard.can(Permissions.screensUsers),
      canAccessQuotation:
          isAdmin || AccessGuard.can(Permissions.screensQuotation),
      canAccessCalculator:
          isAdmin || AccessGuard.can(Permissions.screensCalculator),
      canAccessSaudaBooking:
          isAdmin || AccessGuard.can(Permissions.screensSaudaBooking),
      canAccessVendorPurchaseScreen: isAdmin || hasVendorPurchaseAccess(),
      canAccessStockInventory:
          isAdmin || AccessGuard.can(Permissions.screensStockInventory),
      canAccessReports: isAdmin || AccessGuard.can(Permissions.screensReports),
      canAccessInventoryDash:
          isAdmin || AccessGuard.can(Permissions.screensInventoryDash),
      canAccessCurrentStock:
          isAdmin || AccessGuard.can(Permissions.screensCurrentStock),
      canAccessTransactions:
          isAdmin || AccessGuard.can(Permissions.screensTransactions),
      canAccessStockDetail:
          isAdmin || AccessGuard.can(Permissions.screensStockDetail),
      canAccessItemDetail:
          isAdmin || AccessGuard.can(Permissions.screensItemDetail),
      canAccessTxnDetail:
          isAdmin || AccessGuard.can(Permissions.screensTxnDetail),
      canAccessSampleRate:
          isAdmin || AccessGuard.can(Permissions.screensSampleRate),
      canAccessSalesDocCenter:
          isAdmin || AccessGuard.can(Permissions.screensSalesDocCenter),
      canAccessMasterSize:
          isAdmin || AccessGuard.can(Permissions.screensMasterSize),
      canAccessStockSheet: isAdmin || AccessGuard.hasStockSheetAccess(),
      canDelete: isAdmin || AccessGuard.can(Permissions.usersDelete),
    );
  }

  bool canAccess(String requiredScreen) {
    if (isAdmin || role == StockRole.ADMIN) return true;
    // 'Vendor Purchase Only' always requires the explicit boolean permission,
    // regardless of whether the user has 'All Screens' chip selected.
    if (requiredScreen == 'Vendor Purchase Only') return canVendorPurchase;
    if (requiredScreen == 'Sample Rate Only') return canAccessSampleRate;
    if (requiredScreen == 'Stock Sheet Only') return canAccessStockSheet;
    if (allowedAccess == 'All Screens') return true;
    return allowedAccess.contains(requiredScreen);
  }

  bool get effectiveCanViewReports =>
      isAdmin || role == StockRole.ADMIN || canViewReports || canAccess('Reports Only');

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

/// A singleton ValueNotifier and ChangeNotifier that emits a new [PermissionSnapshot]
/// whenever user permissions are refreshed from the backend, and manages live Realtime
/// updates from the Supabase `users` table.
class UserSessionNotifier extends ChangeNotifier {
  UserSessionNotifier._();

  static final UserSessionNotifier _singleton = UserSessionNotifier._();
  static UserSessionNotifier get notifier => _singleton;

  static final instance =
      ValueNotifier<PermissionSnapshot>(PermissionSnapshot.fromSession());

  static UserModel? _currentUser;
  static UserModel? get currentUser =>
      _currentUser ?? DataRepository.currentUserNotifier.value;

  static RealtimeChannel? _userChannel;

  /// Subscribes to Realtime updates on the `users` table for [userId].
  /// Matches on `id` column (or `email` if an email is provided).
  static void subscribeToUserUpdates(String userId) {
    if (userId.trim().isEmpty) return;

    // Clean up any existing channel before subscribing to a new one
    unsubscribeUserUpdates();

    final cleanId = userId.trim();
    final filterColumn = cleanId.contains('@') ? 'email' : 'id';
    final filterValue = cleanId.contains('@') ? cleanId.toLowerCase() : cleanId;

    debugPrint(
        '[UserSessionNotifier] Subscribing to realtime updates on users.$filterColumn = $filterValue');

    try {
      _userChannel = SupabaseService.client
          .channel('public:users:$cleanId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'users',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: filterColumn,
              value: filterValue,
            ),
            callback: (PostgresChangePayload payload) {
              debugPrint(
                  '[UserSessionNotifier] Realtime user update received: ${payload.newRecord}');
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                _handleUserRecordUpdate(newRecord);
              }
            },
          )
          .subscribe((status, [error]) {
        debugPrint(
            '[UserSessionNotifier] Realtime subscription status: $status ${error != null ? "(Error: $error)" : ""}');
      });
    } catch (e) {
      debugPrint(
          '[UserSessionNotifier] Error subscribing to realtime user channel: $e');
    }
  }

  static void _handleUserRecordUpdate(Map<String, dynamic> record) {
    try {
      final rawUser = UserModel.fromJson(record);
      final completeUser = DataRepository.backfillPermissions(rawUser);
      _currentUser = completeUser;
      DataRepository.currentUserNotifier.value = completeUser;

      // Update legacy UserSession identity & RBAC
      UserSession.userEmail = completeUser.email;
      UserSession.currentAppRole = completeUser.role;
      UserSession.currentRole = completeUser.isAdmin
          ? StockRole.ADMIN
          : (completeUser.role.isManager ? StockRole.MANAGER : StockRole.VIEWER);
      UserSession.roleId = completeUser.role.value;
      UserSession.applyPermissions(completeUser.permissions
          .map((k, v) => MapEntry(k, Permission(slug: k, isAllowed: v))));

      // Update SharedPreferences cache in background
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('currentUser', jsonEncode(completeUser.toJson()));
        prefs.setString('user_email', completeUser.email);
      });

      // Refresh snapshot and notify listeners
      refreshFromSession();
      _singleton.notifyListeners();
    } catch (e) {
      debugPrint(
          '[UserSessionNotifier] Error handling realtime user update: $e');
    }
  }

  /// Unsubscribes and cleans up the Realtime channel on logout.
  static Future<void> unsubscribeUserUpdates() async {
    if (_userChannel != null) {
      debugPrint(
          '[UserSessionNotifier] Unsubscribing from user realtime channel...');
      try {
        await SupabaseService.client.removeChannel(_userChannel!);
      } catch (e) {
        debugPrint(
            '[UserSessionNotifier] Error removing realtime channel: $e');
      }
      _userChannel = null;
    }
  }

  /// Call this after [DataRepository.syncCurrentUser()] completes or on realtime update.
  /// Returns true if the permissions actually changed (for nav guard logic).
  static bool refreshFromSession() {
    final newSnapshot = PermissionSnapshot.fromSession();

    // Verbatim Requirement: Log permission state
    debugPrint(
        "[MOBILE PERMISSION STATE] ${newSnapshot.role.name} ${UserSession.customPermissions.keys.toList()}");

    if (newSnapshot != instance.value) {
      instance.value = newSnapshot;
      _singleton.notifyListeners();
      return true; // permissions changed
    }
    return false;
  }
}
