import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/app_permissions.dart';
import 'stock_role.dart';
import '../services/app_config_service.dart';

class UserModel {
  final String? id;
  final String email;
  final AppRole role;
  final String status;
  final String? branchLocation;
  final String allowedAccess;
  final Map<String, bool> permissions;
  final String lastSeen;

  /// Optimistic concurrency version — incremented by backend on every save.
  final int version;

  /// Email of the admin who last updated this user's permissions.
  final String? lastUpdatedBy;

  UserModel({
    this.id,
    required this.email,
    required this.role,
    required this.status,
    this.branchLocation,
    this.allowedAccess = "",
    required this.permissions,
    this.lastSeen = "",
    this.version = 0,
    this.lastUpdatedBy,
  });

  /// Dynamic Super Admin check sourced from Supabase app_config
  bool get isSuperAdmin => AppConfigService.isSuperAdmin(email);

  /// True if role is admin or dynamic super admin
  bool get isAdmin => role.isAdmin || isSuperAdmin;

  /// True if role is manager
  bool get isManager => role.isManager;

  /// True if role is staff
  bool get isStaff => role.isStaff;

  bool get isApproved => status.toLowerCase() == 'approved';

  /// Self-contained Stock Sheet permission check directly from internal state
  bool get canAccessStockSheet {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensStockSheet] == true ||
        permissions[AppPermissions.canAccessStockSheet] == true ||
        permissions['screens.stock_sheet'] == true ||
        permissions['can_access_stock_sheet'] == true ||
        permissions['stock_sheet'] == true;
  }

  bool get canAccessMasterSize {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensMasterSize] == true ||
        permissions['screens.master_size'] == true ||
        permissions['master_size'] == true;
  }

  bool get canAccessUsers {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensUsers] == true ||
        permissions['screens.users'] == true ||
        permissions['users'] == true;
  }

  bool get canAccessReports {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensReports] == true ||
        permissions[AppPermissions.reportsScreen] == true ||
        permissions['screens.reports'] == true ||
        permissions['reports'] == true;
  }

  bool get canAccessDashboard {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensDashboard] == true ||
        permissions['screens.dashboard'] == true ||
        permissions['dashboard'] == true;
  }

  bool get canAccessCalculator {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensCalculator] == true ||
        permissions['screens.calculator'] == true ||
        permissions['calculator'] == true ||
        permissions['netratecalc'] == true;
  }

  bool get canAccessQuotation {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensQuotation] == true ||
        permissions['screens.quotation'] == true ||
        permissions['quotation'] == true ||
        permissions['quotations'] == true;
  }

  bool get canAccessSaudaBooking {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensSaudaBooking] == true ||
        permissions['screens.sauda_booking'] == true ||
        permissions['sauda'] == true ||
        permissions['saudabook'] == true;
  }

  bool get canAccessVendorPurchase {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensVendorPurchase] == true ||
        permissions[AppPermissions.vendorPurchase] == true ||
        permissions['vendor_purchase'] == true ||
        permissions['log_vendor_purchase'] == true ||
        permissions['vendorpurchase'] == true;
  }

  bool get canAccessVendorPurchaseScreen => canAccessVendorPurchase;

  bool get canAccessStockInventory {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensStockInventory] == true ||
        permissions[AppPermissions.inventoryScreen] == true ||
        permissions['screens.stock_inventory'] == true ||
        permissions['inventory'] == true;
  }

  bool get canAccessSampleRate {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensSampleRate] == true ||
        permissions['screens.sample_rate'] == true ||
        permissions['samplerate'] == true ||
        permissions['sample_rate'] == true;
  }

  bool get canAccessSalesDocCenter {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensSalesDocCenter] == true ||
        permissions['screens.sales_doc_center'] == true ||
        permissions['sales_doc_center'] == true;
  }

  bool get canAccessInventoryDash {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensInventoryDash] == true ||
        permissions['screens.inventory_dash'] == true;
  }

  bool get canAccessCurrentStock {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensCurrentStock] == true ||
        permissions['screens.current_stock'] == true;
  }

  bool get canAccessTransactions {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensTransactions] == true ||
        permissions['screens.transactions'] == true;
  }

  bool get canAccessStockDetail {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensStockDetail] == true ||
        permissions['screens.stock_detail'] == true;
  }

  bool get canAccessItemDetail {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensItemDetail] == true ||
        permissions['screens.item_detail'] == true;
  }

  bool get canAccessTxnDetail {
    if (isAdmin) return true;
    return permissions[AppPermissions.screensTxnDetail] == true ||
        permissions['screens.txn_detail'] == true;
  }

  /// Online if last seen within 10 minutes
  bool get isOnline {
    if (lastSeen.isEmpty) return false;
    try {
      final dt = DateTime.parse(lastSeen);
      return DateTime.now().difference(dt).inMinutes < 10;
    } catch (_) {
      return false;
    }
  }

  String get formattedLastSeen {
    if (lastSeen.isEmpty) return "Never";
    try {
      final dt = DateTime.parse(lastSeen).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 2) return "Just now";
      if (diff.inMinutes < 60) return "${diff.inMinutes} mins ago";
      if (diff.inHours < 24) return "${diff.inHours} hours ago";
      if (diff.inDays == 1) return "Yesterday";
      return "${diff.inDays} days ago";
    } catch (_) {
      return "Unknown";
    }
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Normalize email
    final String email = (json['email']?.toString() ?? '').toLowerCase().trim();

    final String allowedAccessStr = json['allowedAccess']?.toString() ?? "";

    // Parse AppRole using robust fromString mapper
    AppRole r = AppRole.fromString(json['role']?.toString());

    // Only use allowedAccess as a fallback when role is staff but allowedAccess indicates All Screens
    if (!r.isAdmin &&
        (allowedAccessStr.trim().toLowerCase() == 'all screens' ||
            AppConfigService.isSuperAdmin(email))) {
      r = AppRole.admin;
    }

    // Parse and Normalize Permissions
    Map<String, bool> perms = {};
    final Object? rawPerms = json['permissions'];

    Map<String, dynamic> permsMap = {};
    if (rawPerms != null) {
      if (rawPerms is Map) {
        permsMap = Map<String, dynamic>.from(rawPerms);
      } else if (rawPerms is String && rawPerms.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawPerms);
          if (decoded is Map) {
            permsMap = Map<String, dynamic>.from(decoded);
          }
        } catch (e) {
          debugPrint("[UserModel] Error decoding permissions JSON string: $e");
        }
      }
    }

    // Normalize module keys
    permsMap.forEach((key, value) {
      final k = key.toString().toLowerCase().trim();
      final v = value == true || value == 'true' || value == 1;

      if (k == 'reports') {
        perms[AppPermissions.screensReports] = v;
      } else if (k == 'inventory') {
        perms[AppPermissions.screensStockInventory] = v;
      } else if (k == 'saudabook' || k == 'sauda') {
        perms[AppPermissions.screensSaudaBooking] = v;
      } else if (k == 'quotations' || k == 'quotation') {
        perms[AppPermissions.screensQuotation] = v;
      } else if (k == 'netratecalc' || k == 'calculator') {
        perms[AppPermissions.screensCalculator] = v;
      } else if (k == 'samplerate') {
        perms[AppPermissions.screensSampleRate] = v;
      } else if (k == 'vendorpurchase') {
        perms[AppPermissions.screensVendorPurchase] = v;
      } else if (k == 'users') {
        perms[AppPermissions.screensUsers] = v;
      } else if (k == 'stocksheet' ||
          k == 'stock_sheet' ||
          k == 'can_access_stock_sheet' ||
          k == 'screens.stock_sheet') {
        perms[AppPermissions.screensStockSheet] = v;
        perms[AppPermissions.canAccessStockSheet] = v;
      } else {
        perms[k] = v;
      }
    });

    final String? id = json['id']?.toString();
    final int version = int.tryParse(json['version']?.toString() ?? '0') ?? 0;
    final String? lastUpdatedBy = json['lastUpdatedBy']?.toString();

    return UserModel(
      id: id,
      email: email,
      role: r,
      status: (json['status']?.toString() ?? 'pending').trim().toLowerCase(),
      branchLocation: json['branchLocation']?.toString(),
      allowedAccess: allowedAccessStr,
      permissions: perms,
      lastSeen: json['lastSeen']?.toString() ?? "",
      version: version,
      lastUpdatedBy: lastUpdatedBy,
    );
  }

  /// Derives the human-readable "Allowed Access" summary string based on role and permissions.
  static String deriveAllowedAccess(AppRole role, Map<String, bool> perms) {
    if (role.isAdmin) return 'All Screens';

    bool p(String slug) => perms[slug] == true;

    final groups = <String>[];

    if (p(AppPermissions.inventoryScreen) ||
        p(AppPermissions.stockIn) ||
        p(AppPermissions.stockOut) ||
        p(AppPermissions.stockTransfer)) {
      groups.add('Stock Inventory Only');
    }

    if (p(AppPermissions.reportsScreen)) {
      groups.add('Reports Only');
    }

    if (p(AppPermissions.screensStockSheet) ||
        p(AppPermissions.canAccessStockSheet) ||
        p('stock_sheet')) {
      groups.add('Stock Sheet Only');
    }

    if (p(AppPermissions.screensSaudaBooking) || p(AppPermissions.saudaView)) {
      groups.add('Sauda Book Only');
    }

    if (p(AppPermissions.screensCalculator)) {
      groups.add('Netrate Calc Only');
    }

    if (p(AppPermissions.screensQuotation)) {
      groups.add('Quotation Only');
    }

    if (p(AppPermissions.screensSampleRate)) {
      groups.add('Sample Rate Only');
    }

    if (p(AppPermissions.screensVendorPurchase) ||
        p(AppPermissions.vendorPurchase)) {
      groups.add('Vendor Purchase Only');
    }

    if (groups.isEmpty) return 'No Access';
    return groups.join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'email': email,
      'role': role.value,
      'status': status.toUpperCase(),
      'branchLocation': branchLocation,
      'allowedAccess': allowedAccess,
      'permissions': jsonEncode(permissions),
      'lastSeen': lastSeen,
      'version': version,
      'lastUpdatedBy': lastUpdatedBy,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    AppRole? role,
    String? status,
    String? branchLocation,
    String? allowedAccess,
    Map<String, bool>? permissions,
    String? lastSeen,
    int? version,
    String? lastUpdatedBy,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      branchLocation: branchLocation ?? this.branchLocation,
      allowedAccess: allowedAccess ?? this.allowedAccess,
      permissions: permissions ?? Map.from(this.permissions),
      lastSeen: lastSeen ?? this.lastSeen,
      version: version ?? this.version,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
    );
  }

  /// Helper to check a specific permission slug
  bool hasPermission(String slug) {
    if (isAdmin) return true;
    if (slug == AppPermissions.screensStockSheet ||
        slug == AppPermissions.canAccessStockSheet ||
        slug == 'stock_sheet') {
      return permissions[AppPermissions.screensStockSheet] == true ||
          permissions[AppPermissions.canAccessStockSheet] == true ||
          permissions['screens.stock_sheet'] == true ||
          permissions['can_access_stock_sheet'] == true ||
          permissions['stock_sheet'] == true;
    }
    return permissions[slug] == true;
  }
}
