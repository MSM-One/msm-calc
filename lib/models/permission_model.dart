import 'package:flutter/foundation.dart';
import '../core/app_permissions.dart';

typedef Permissions = AppPermissions;

/// Defines the scope of a permission.
enum PermissionScope {
  /// Access to all data regardless of location.
  all,

  /// Access limited to data matching the user's assigned location.
  location,

  /// Access limited to data created by the user.
  own,
}

/// A single permission entry with a slug, scope, and allowed flag.
@immutable
class Permission {
  final String slug;
  final PermissionScope scope;
  final bool isAllowed;

  const Permission({
    required this.slug,
    required this.isAllowed,
    this.scope = PermissionScope.all,
  });

  Permission copyWith({bool? isAllowed, PermissionScope? scope}) {
    return Permission(
      slug: slug,
      isAllowed: isAllowed ?? this.isAllowed,
      scope: scope ?? this.scope,
    );
  }

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'scope': scope.name,
        'isAllowed': isAllowed,
      };

  factory Permission.fromJson(Map<String, dynamic> json) {
    return Permission(
      slug: json['slug'] as String,
      isAllowed: json['isAllowed'] == true || json['isAllowed'] == 'true',
      scope: PermissionScope.values.firstWhere(
        (s) => s.name == (json['scope'] ?? 'all'),
        orElse: () => PermissionScope.all,
      ),
    );
  }

  @override
  String toString() =>
      'Permission($slug, allowed=$isAllowed, scope=${scope.name})';
}

/// Holds the default permission sets for each role.
/// Any permission NOT listed defaults to denied.
class PermissionRegistry {
  PermissionRegistry._();

  static Map<String, Permission> get adminDefaults {
    // Admins get everything — enforced by AccessGuard, not by this map.
    // This map is only needed for the PermissionManagerScreen UI to render.
    return {
      for (final slug in _allSlugs)
        slug: Permission(slug: slug, isAllowed: true),
    };
  }

  static Map<String, Permission> get staffDefaults => {
        Permissions.inventoryScreen: const Permission(
            slug: Permissions.inventoryScreen, isAllowed: true),
        Permissions.stockIn:
            const Permission(slug: Permissions.stockIn, isAllowed: false),
        Permissions.stockOut:
            const Permission(slug: Permissions.stockOut, isAllowed: false),
        Permissions.stockTransfer:
            const Permission(slug: Permissions.stockTransfer, isAllowed: false),
        Permissions.vendorPurchase: const Permission(
            slug: Permissions.vendorPurchase, isAllowed: false),
        // Field-level data protection — OFF by default for Staff
        Permissions.inventoryQuantityView: const Permission(
            slug: Permissions.inventoryQuantityView, isAllowed: false),
        Permissions.inventoryMetricsView: const Permission(
            slug: Permissions.inventoryMetricsView, isAllowed: false),
        Permissions.transactionsQuantityView: const Permission(
            slug: Permissions.transactionsQuantityView, isAllowed: false),
        Permissions.reportsScreen:
            const Permission(slug: Permissions.reportsScreen, isAllowed: false),
        Permissions.reportsMovement: const Permission(
            slug: Permissions.reportsMovement, isAllowed: false),
        Permissions.reportsNonMoving: const Permission(
            slug: Permissions.reportsNonMoving, isAllowed: false),
        Permissions.reportsTodaySummary: const Permission(
            slug: Permissions.reportsTodaySummary, isAllowed: false),
        Permissions.reportStockLedger: const Permission(
            slug: Permissions.reportStockLedger, isAllowed: false),
        Permissions.reportLowStock: const Permission(
            slug: Permissions.reportLowStock, isAllowed: false),
        Permissions.reportsOverview: const Permission(
            slug: Permissions.reportsOverview, isAllowed: false),
        Permissions.reportsExport:
            const Permission(slug: Permissions.reportsExport, isAllowed: false),
        Permissions.ratesView:
            const Permission(slug: Permissions.ratesView, isAllowed: false),
        Permissions.saudaView:
            const Permission(slug: Permissions.saudaView, isAllowed: false),
        Permissions.saudaCreate:
            const Permission(slug: Permissions.saudaCreate, isAllowed: false),
        Permissions.usersView:
            const Permission(slug: Permissions.usersView, isAllowed: false),
        Permissions.usersManage:
            const Permission(slug: Permissions.usersManage, isAllowed: false),
        Permissions.usersDelete:
            const Permission(slug: Permissions.usersDelete, isAllowed: false),
        Permissions.dashboardView:
            const Permission(slug: Permissions.dashboardView, isAllowed: true),

        // Screen-level access — restrictive by default for Staff
        Permissions.screensDashboard: const Permission(
            slug: Permissions.screensDashboard, isAllowed: true),
        Permissions.screensUsers:
            const Permission(slug: Permissions.screensUsers, isAllowed: false),
        Permissions.screensQuotation: const Permission(
            slug: Permissions.screensQuotation, isAllowed: false),
        Permissions.screensCalculator: const Permission(
            slug: Permissions.screensCalculator, isAllowed: false),
        Permissions.screensSaudaBooking: const Permission(
            slug: Permissions.screensSaudaBooking, isAllowed: false),
        Permissions.screensVendorPurchase: const Permission(
            slug: Permissions.screensVendorPurchase, isAllowed: false),
        Permissions.screensSampleRate: const Permission(
            slug: Permissions.screensSampleRate, isAllowed: false),
        Permissions.screensSalesDocCenter: const Permission(
            slug: Permissions.screensSalesDocCenter, isAllowed: false),
        Permissions.screensMasterSize: const Permission(
            slug: Permissions.screensMasterSize, isAllowed: false),
        Permissions.screensStockSheet: const Permission(
            slug: Permissions.screensStockSheet, isAllowed: false),
        Permissions.canAccessStockSheet: const Permission(
            slug: Permissions.canAccessStockSheet, isAllowed: false),
        Permissions.screensInventoryDash: const Permission(
            slug: Permissions.screensInventoryDash, isAllowed: false),
        Permissions.screensCurrentStock: const Permission(
            slug: Permissions.screensCurrentStock, isAllowed: false),
        Permissions.screensTransactions: const Permission(
            slug: Permissions.screensTransactions, isAllowed: false),
        Permissions.screensStockDetail: const Permission(
            slug: Permissions.screensStockDetail, isAllowed: false),
        Permissions.screensItemDetail: const Permission(
            slug: Permissions.screensItemDetail, isAllowed: false),
        Permissions.screensTxnDetail: const Permission(
            slug: Permissions.screensTxnDetail, isAllowed: false),
      };

  static const List<String> _allSlugs = [
    Permissions.inventoryScreen,
    Permissions.reportsScreen,
    Permissions.stockIn,
    Permissions.stockOut,
    Permissions.stockTransfer,
    Permissions.vendorPurchase,
    Permissions.inventoryQuantityView,
    Permissions.inventoryMetricsView,
    Permissions.transactionsQuantityView,
    Permissions.reportsMovement,
    Permissions.reportsNonMoving,
    Permissions.reportsTodaySummary,
    Permissions.reportStockLedger,
    Permissions.reportLowStock,
    Permissions.reportsOverview,
    Permissions.reportsExport,
    Permissions.ratesView,
    Permissions.saudaView,
    Permissions.saudaCreate,
    Permissions.usersView,
    Permissions.usersManage,
    Permissions.usersDelete,
    Permissions.dashboardView,
    Permissions.screensDashboard,
    Permissions.screensUsers,
    Permissions.screensQuotation,
    Permissions.screensCalculator,
    Permissions.screensSaudaBooking,
    Permissions.screensVendorPurchase,
    Permissions.screensSampleRate,
    Permissions.screensSalesDocCenter,
    Permissions.screensMasterSize,
    Permissions.screensStockSheet,
    Permissions.canAccessStockSheet,
    Permissions.screensInventoryDash,
    Permissions.screensCurrentStock,
    Permissions.screensTransactions,
    Permissions.screensStockDetail,
    Permissions.screensItemDetail,
    Permissions.screensTxnDetail,
  ];

  static List<String> get allSlugs => List.unmodifiable(_allSlugs);

  /// Merges role defaults with user-level overrides.
  static Map<String, Permission> resolve({
    required String roleId,
    required Map<String, Permission> customPermissions,
  }) {
    final defaults = roleId == 'admin' ? adminDefaults : staffDefaults;
    final merged = Map<String, Permission>.from(defaults);
    for (final entry in customPermissions.entries) {
      merged[entry.key] = entry.value;
    }
    return merged;
  }

  /// Converts legacy boolean permission flags from Google Sheet / old UserModel
  /// into the new `customPermissions` Map format.
  static Map<String, Permission> fromLegacyBooleans({
    required bool canViewReports,
    required bool canCheckRates,
    required bool canStockIn,
    required bool canStockOut,
    required bool canTransfer,
    required bool canVendorPurchase,
    required bool canViewStockMovement,
    required bool canViewNonMoving,
    required bool canViewTodaySummary,
    required bool canViewStockOverview,
  }) {
    return {
      Permissions.reportsView:
          Permission(slug: Permissions.reportsView, isAllowed: canViewReports),
      Permissions.reportsMovement: Permission(
          slug: Permissions.reportsMovement, isAllowed: canViewStockMovement),
      Permissions.reportsNonMoving: Permission(
          slug: Permissions.reportsNonMoving, isAllowed: canViewNonMoving),
      Permissions.reportsTodaySummary: Permission(
          slug: Permissions.reportsTodaySummary,
          isAllowed: canViewTodaySummary),
      Permissions.reportsOverview: Permission(
          slug: Permissions.reportsOverview, isAllowed: canViewStockOverview),
      Permissions.reportsExport: Permission(
          slug: Permissions.reportsExport, isAllowed: canViewReports),
      Permissions.ratesView:
          Permission(slug: Permissions.ratesView, isAllowed: canCheckRates),
      Permissions.stockIn:
          Permission(slug: Permissions.stockIn, isAllowed: canStockIn),
      Permissions.stockOut:
          Permission(slug: Permissions.stockOut, isAllowed: canStockOut),
      Permissions.stockTransfer:
          Permission(slug: Permissions.stockTransfer, isAllowed: canTransfer),
      Permissions.vendorPurchase: Permission(
          slug: Permissions.vendorPurchase, isAllowed: canVendorPurchase),
    };
  }
}

/// Metadata for a module shown in the PermissionManagerScreen.
class PermissionModule {
  final String id;
  final String label;
  final String icon; // Material icon name or emoji for display
  final List<PermissionEntry> entries;

  const PermissionModule({
    required this.id,
    required this.label,
    required this.icon,
    required this.entries,
  });
}

/// A single permission entry within a module.
class PermissionEntry {
  final String slug;
  final String label;
  final String? description;
  final String? parentSlug; // If set, disabling parent dims this entry

  const PermissionEntry({
    required this.slug,
    required this.label,
    this.description,
    this.parentSlug,
  });
}

/// The full list of modules and their entries, used by PermissionManagerScreen.
class PermissionModules {
  PermissionModules._();

  static const List<PermissionModule> all = [
    PermissionModule(
      id: 'inventory',
      label: 'Inventory Operations',
      icon: '📦',
      entries: [
        PermissionEntry(
            slug: Permissions.screensStockInventory,
            label: 'Stock Inventory Screen',
            description: 'Main inventory portal & dashboards'),
        PermissionEntry(
            slug: Permissions.inventoryQuantityView,
            label: 'View MT Quantities',
            description: 'See stock weights in the inventory list',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.inventoryMetricsView,
            label: 'View KPI Metrics',
            description: 'See Total MT, Yard/Factory totals on dashboard',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.stockIn,
            label: 'Stock In',
            description: 'Record incoming stock',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.stockOut,
            label: 'Stock Out',
            description: 'Record outgoing stock',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.stockTransfer,
            label: 'Stock Transfer',
            description: 'Move stock between locations',
            parentSlug: Permissions.screensStockInventory),

        // Detailed Drill-down (Children of Inventory Screen)
        PermissionEntry(
            slug: Permissions.screensInventoryDash,
            label: 'Inventory Dashboard',
            description: 'Main metrics & recent activity',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.screensCurrentStock,
            label: 'Current Stock Breakdown',
            description: 'View stock by category/item',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.screensTransactions,
            label: 'Transaction History',
            description: 'View full history list',
            parentSlug: Permissions.screensStockInventory),
        PermissionEntry(
            slug: Permissions.screensStockDetail,
            label: 'Stock Detail Drill-down',
            description: 'See specific item breakdown',
            parentSlug: Permissions.screensCurrentStock),
        PermissionEntry(
            slug: Permissions.screensItemDetail,
            label: 'Item Size Details',
            description: 'See quantity per size',
            parentSlug: Permissions.screensStockDetail),
        PermissionEntry(
            slug: Permissions.screensTxnDetail,
            label: 'Txn Drill-down Detail',
            description: 'View specific txn metadata',
            parentSlug: Permissions.screensTransactions),
      ],
    ),
    PermissionModule(
      id: 'reports',
      label: 'Reporting Suite',
      icon: '📊',
      entries: [
        PermissionEntry(
            slug: Permissions.screensReports,
            label: 'Reports Screen',
            description: 'Main access to reporting module'),
        PermissionEntry(
            slug: Permissions.reportsMovement,
            label: 'Stock Movement',
            description: 'IN/OUT/Transfer report',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.reportsNonMoving,
            label: 'Non-Moving Stock',
            description: 'Dead stock / slow movers',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.reportsTodaySummary,
            label: 'Today\'s Summary',
            description: 'Daily snapshot report',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.reportStockLedger,
            label: 'Stock Ledger',
            description: 'Access to Stock Ledger & Reconciliation Report',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.reportLowStock,
            label: 'Low Stock',
            description: 'Access to Low Stock Alert & Reorder Report',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.reportsOverview,
            label: 'Stock Overview',
            description: 'Consolidated location view',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.screensStockSheet,
            label: 'Stock Sheet Access',
            description: 'Access to export and share Dealer Stock Sheet',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.reportsExport,
            label: 'Export PDF/Excel',
            description: 'Download reports',
            parentSlug: Permissions.screensReports),
        PermissionEntry(
            slug: Permissions.transactionsQuantityView,
            label: 'View Txn Quantities',
            description: 'See +/- MT on transaction rows',
            parentSlug: Permissions.screensReports),
      ],
    ),
    PermissionModule(
      id: 'financials',
      label: 'Financials & Analytics',
      icon: '💰',
      entries: [
        PermissionEntry(
            slug: Permissions.screensSaudaBooking,
            label: 'Sauda Book Screen',
            description: 'Access to Sauda Booking screen'),
        PermissionEntry(
            slug: Permissions.saudaView,
            label: 'View Sauda Orders',
            description: 'View booking orders',
            parentSlug: Permissions.screensSaudaBooking),
        PermissionEntry(
            slug: Permissions.saudaCreate,
            label: 'Create Sauda',
            description: 'Add new booking orders',
            parentSlug: Permissions.saudaView),
        PermissionEntry(
            slug: Permissions.screensSampleRate,
            label: 'Sample Rate Screen',
            description: 'Access to Sample Rate Calc tool'),
        PermissionEntry(
            slug: Permissions.ratesView,
            label: 'View Sample Rates',
            description: 'Check item price rates',
            parentSlug: Permissions.screensSampleRate),
        PermissionEntry(
            slug: Permissions.screensVendorPurchase,
            label: 'Vendor Purchase Screen',
            description: 'Access to Vendor Purchase screen'),
        PermissionEntry(
            slug: Permissions.vendorPurchase,
            label: 'Log Vendor Purchase',
            description: 'Log vendor purchase entries',
            parentSlug: Permissions.screensVendorPurchase),
        PermissionEntry(
            slug: Permissions.screensCalculator,
            label: 'Netrate Calculator',
            description: 'Access to Netrate Calc tool'),
      ],
    ),
    PermissionModule(
      id: 'users',
      label: 'User Management',
      icon: '👤',
      entries: [
        PermissionEntry(
            slug: Permissions.usersView,
            label: 'View Users',
            description: 'See user list'),
        PermissionEntry(
            slug: Permissions.usersManage,
            label: 'Manage Users',
            description: 'Edit permissions',
            parentSlug: Permissions.usersView),
        PermissionEntry(
            slug: Permissions.usersDelete,
            label: 'Remove Users',
            description: 'Delete or deactivate',
            parentSlug: Permissions.usersManage),
      ],
    ),
    PermissionModule(
      id: 'screens',
      label: 'Global Access',
      icon: '📱',
      entries: [
        PermissionEntry(
            slug: Permissions.screensDashboard,
            label: 'Dashboard Screen',
            description: 'Main overview & Quick Actions'),
        PermissionEntry(
            slug: Permissions.screensUsers,
            label: 'User Management Screen',
            description: 'Access to the Users management tab'),
        PermissionEntry(
            slug: Permissions.screensQuotation,
            label: 'Quotation Screen',
            description: 'Access to Quotation creator'),
        PermissionEntry(
            slug: Permissions.screensSalesDocCenter,
            label: 'Sales Document Center',
            description: 'Official letterhead & documents'),
        PermissionEntry(
            slug: Permissions.screensMasterSize,
            label: 'Master Size',
            description: 'Management of categories & sizes'),
        PermissionEntry(
            slug: Permissions.screensStockSheet,
            label: 'Stock Sheet Access',
            description: 'Access to export and share Dealer Stock Sheet'),
      ],
    ),
  ];
}
