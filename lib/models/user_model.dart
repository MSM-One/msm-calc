import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/app_permissions.dart';

enum UserRole { admin, staff, unknown }

class UserModel {
  final String email;
  final UserRole role;
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

  bool get isAdmin => role == UserRole.admin;
  bool get isApproved => status.toLowerCase() == 'approved';

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
    // Requirement 4: Normalize email
    final String email = (json['email']?.toString() ?? '').toLowerCase().trim();

    final String allowedAccessStr = json['allowedAccess']?.toString() ?? "";

    // Parse Role from the role column first.
    final String roleStr =
        (json['role']?.toString() ?? '').trim().toLowerCase();
    UserRole r = UserRole.values.firstWhere(
      (e) => e.name == roleStr,
      orElse: () => UserRole.unknown,
    );

    // Only use allowedAccess as a fallback when the role column is genuinely
    // absent or unrecognised. An explicit 'admin' or 'staff' value must win.
    if (r == UserRole.unknown &&
        allowedAccessStr.trim().toLowerCase() == 'all screens') {
      r = UserRole.admin;
    }

    // Requirement 5: Parse and Normalize Permissions
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

    // Normalize module keys: reports, inventory, saudaBook, quotations, netrateCalc, sampleRate, vendorPurchase, users
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
      } else {
        perms[k] = v;
      }
    });

    final int version = int.tryParse(json['version']?.toString() ?? '0') ?? 0;
    final String? lastUpdatedBy = json['lastUpdatedBy']?.toString();

    return UserModel(
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

  /// Derives the human-readable "Allowed Access" summary string that is stored
  /// in the Google Sheet's "Allowed Access" column, based on the user's role
  /// and their permission map.
  ///
  /// - Admin  → "All Screens"
  /// - Staff  → comma-separated list of enabled screen groups, e.g.
  ///            "Stock Inventory Only, Reports Only"
  ///            Falls back to "Custom" if permissions are enabled but don't
  ///            match any known screen group.
  static String deriveAllowedAccess(UserRole role, Map<String, bool> perms) {
    if (role == UserRole.admin) return 'All Screens';

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
      'email': email,
      'role': role.name,
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
    String? email,
    UserRole? role,
    String? status,
    String? branchLocation,
    String? allowedAccess,
    Map<String, bool>? permissions,
    String? lastSeen,
    int? version,
    String? lastUpdatedBy,
  }) {
    return UserModel(
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
    return permissions[slug] == true;
  }
}
