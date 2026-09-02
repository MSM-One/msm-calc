import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_permissions.dart';
import '../models/stock_role.dart';
import '../models/user_model.dart';
import '../screens/dealer_stock_share_screen.dart';
import '../screens/permission_manager_screen.dart';
import '../services/access_guard.dart';
import '../services/data_repository.dart';
import '../services/supabase_service.dart';
import '../utils/resilient_supabase_stream.dart';

class ManageUsersScreen extends StatefulWidget {
  final bool isEmbedded;
  const ManageUsersScreen({super.key, this.isEmbedded = false});

  @override
  State<ManageUsersScreen> createState() => ManageUsersScreenState();
}

class ManageUsersScreenState extends State<ManageUsersScreen> {
  bool _isLoading = true;
  List<dynamic> _users = [];
  String _searchQuery = "";
  final TextEditingController _searchCtrl = TextEditingController();
  ResilientSupabaseStream<List<Map<String, dynamic>>>? _pendingStream;

  // ── Color Constants ────────────────────────────────────────────────────────
  static const Color primaryRed = Color(0xFFD32F2F);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color bgDark = Color(0xFF0F172A);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF1E293B);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF334155);
  static const Color successGreen = Color(0xFF059669);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color accentBlue = Color(0xFF2563EB);

  // ── Pricing Engine config controllers ──────────────────────────────────────
  final TextEditingController _gstCtrl = TextEditingController();
  final TextEditingController _lcCtrl = TextEditingController();
  final TextEditingController _ncCtrl = TextEditingController();
  bool _savingCharges = false;

  @override
  void initState() {
    super.initState();

    try {
      _pendingStream = ResilientSupabaseStream<List<Map<String, dynamic>>>(
        streamFactory: () => SupabaseService.client
            .from('users')
            .stream(primaryKey: ['email'])
            .map((rows) => rows.where((u) {
                  final status =
                      (u['status']?.toString() ?? '').toUpperCase().trim();
                  final isApproved = u['is_approved'];
                  return status == 'PENDING' ||
                      (isApproved != null &&
                          isApproved == false &&
                          status != 'APPROVED' &&
                          status != 'REJECTED');
                }).toList()),
      );
    } catch (e) {
      debugPrint("Pending users stream init skipped: $e");
      _pendingStream = null;
    }

    // --- Hard Navigation Guard ---
    if (!widget.isEmbedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (AccessGuard.cannot(AppPermissions.screensUsers)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Access Denied: Missing Permission"),
              backgroundColor: primaryRed,
            ),
          );
          if (Navigator.canPop(context)) Navigator.pop(context);
        }
      });
    }

    loadUsers();
    _initPricingControllers();
  }

  void _initPricingControllers() {
    final meta = DataRepository.sheetDataNotifier.value['meta']
            as Map<String, dynamic>? ??
        {};
    final String gstPct = meta['gst_pct']?.toString().isNotEmpty == true
        ? meta['gst_pct'].toString()
        : () {
            final r =
                double.tryParse(meta['gst_rate']?.toString() ?? '0.18') ?? 0.18;
            return (r > 1.0 ? r : r * 100).toStringAsFixed(2);
          }();
    final String lc = meta['loading_charge']?.toString() ?? '255';
    final String nc = meta['nc_discount']?.toString() ?? '3000';
    _gstCtrl.text = gstPct;
    _lcCtrl.text = double.tryParse(lc)?.toStringAsFixed(2) ?? lc;
    _ncCtrl.text = double.tryParse(nc)?.toStringAsFixed(2) ?? nc;
  }

  @override
  void dispose() {
    _pendingStream?.dispose();
    _searchCtrl.dispose();
    _gstCtrl.dispose();
    _lcCtrl.dispose();
    _ncCtrl.dispose();
    super.dispose();
  }

  Future<void> loadUsers() async {
    debugPrint("[USERS LOAD START]");
    if (mounted) setState(() => _isLoading = true);
    try {
      final currentEmail = UserSession.userEmail;
      if (currentEmail == 'j2833945@gmail.com') {
        try {
          final existingAdmin = await SupabaseService.client
              .from('users')
              .select()
              .eq('email', currentEmail!)
              .maybeSingle();
          if (existingAdmin == null) {
            await SupabaseService.client.from('users').insert({
              'email': currentEmail,
              'user_name': 'Admin',
              'role': 'admin',
              'status': 'APPROVED',
              'permissions': {},
              'version': 1,
            });
          }
        } catch (dbErr) {
          debugPrint("Admin auto-population skipped or duplicate: $dbErr");
        }
      }

      final List<dynamic> response =
          await SupabaseService.client.from('users').select();

      if (mounted) {
        setState(() {
          _users = response.toList();
          _isLoading = false;
        });
      }
      debugPrint("[USERS LOAD SUCCESS] ${_users.length}");
    } catch (e, stackTrace) {
      debugPrint("CRITICAL DEBUG - FETCH ERROR: $e");
      debugPrint("CRITICAL DEBUG - STACKTRACE: $stackTrace");
      if (mounted) {
        setState(() => _isLoading = false);
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error loading users: $e"),
              backgroundColor: primaryRed,
            ),
          );
        } catch (_) {}
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showResetConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.restart_alt_rounded, color: warningOrange),
          SizedBox(width: 8),
          Text('Reset Dashboard?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          'This will set current stock calculations to zero on your dashboard.\n\n'
          'Your Google Sheet data will remain 100% safe and untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: warningOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRM RESET'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resetting dashboard…')),
    );

    await DataRepository.clearLocalCacheOnly();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dashboard reset to zero! Cache cleared.'),
        backgroundColor: successGreen,
      ),
    );
  }

  Future<void> _changeUserStatus(dynamic user, String newStatus) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await SupabaseService.client.from('users').update({
        'status': newStatus.toUpperCase(),
      }).eq('email', user['email']);

      await loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User marked as $newStatus'),
          backgroundColor: successGreen,
        ),
      );
    } catch (e) {
      debugPrint("User status update error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update user status: $e'),
            backgroundColor: primaryRed,
          ),
        );
      }
    }
  }

  Future<void> _changeUserRole(dynamic user, String newRole) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await SupabaseService.client.from('users').update({
        'role': newRole.toLowerCase().trim(),
      }).eq('email', user['email']);

      await loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User role updated to $newRole'),
          backgroundColor: successGreen,
        ),
      );
    } catch (e) {
      debugPrint("User role update error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update user role: $e'),
            backgroundColor: primaryRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(dynamic user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete User?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to permanently delete ${user['email']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (mounted) setState(() => _isLoading = true);
    try {
      await SupabaseService.client
          .from('users')
          .delete()
          .eq('email', user['email']);

      await loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User deleted successfully'),
          backgroundColor: successGreen,
        ),
      );
    } catch (e) {
      debugPrint("User delete error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete user: $e'),
            backgroundColor: primaryRed,
          ),
        );
      }
    }
  }

  Future<void> _saveGlobalCharges() async {
    final double? gstPct = double.tryParse(_gstCtrl.text.trim());
    final double? lcRate = double.tryParse(_lcCtrl.text.trim());
    final double? ncRate = double.tryParse(_ncCtrl.text.trim());

    if (gstPct == null || lcRate == null || gstPct < 0 || lcRate < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please enter valid positive numbers for GST % and LC.'),
          backgroundColor: primaryRed,
        ),
      );
      return;
    }

    if (mounted) setState(() => _savingCharges = true);
    try {
      await DataRepository.updateGlobalCharges(
        gstPct: gstPct,
        lcRate: lcRate,
        ncDiscount: ncRate,
      );
      if (mounted) {
        _initPricingControllers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Pricing updated — GST ${gstPct.toStringAsFixed(2)}%, LC ₹${lcRate.toStringAsFixed(2)}/MT'
              '${ncRate != null ? ", NC ₹${ncRate.toStringAsFixed(2)}/MT" : ""}',
            ),
            backgroundColor: successGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving global charges: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save: $e'), backgroundColor: primaryRed),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCharges = false);
    }
  }

  Future<void> _showEditUserModal(dynamic user) async {
    dynamic liveUser = user;
    try {
      final response = await SupabaseService.client
          .from('users')
          .select()
          .eq('email', user['email'])
          .maybeSingle();
      if (response != null) {
        liveUser = response;
      }
    } catch (e) {
      debugPrint("Error fetching live user: $e");
    }

    if (!mounted) return;

    UserModel? userModel;
    try {
      userModel = UserModel.fromJson(Map<String, dynamic>.from(liveUser));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error parsing user permissions: $e'),
            backgroundColor: primaryRed),
      );
      return;
    }

    List<UserModel> allUserModels = [];
    for (var u in _users) {
      try {
        allUserModels.add(UserModel.fromJson(Map<String, dynamic>.from(u)));
      } catch (_) {}
    }

    final updatedUser = await Navigator.of(context).push<UserModel>(
      MaterialPageRoute(
        builder: (_) => PermissionManagerScreen(
          user: userModel!,
          allUsers: allUserModels,
        ),
      ),
    );

    if (updatedUser != null && mounted) {
      await loadUsers();
    }
  }

  void _showUserActionBottomSheet(dynamic u, String statusStr) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? cardDark : cardLight;
    final textColor = isDark ? Colors.white : textDark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: cardColor,
      builder: (ctx) {
        final isUserAdmin = u['role']?.toString().toLowerCase() == 'admin';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 6.0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isUserAdmin
                              ? primaryRed.withValues(alpha: 0.1)
                              : accentBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            (u['email']?.toString() ?? '?')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isUserAdmin ? primaryRed : accentBlue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          u['email']?.toString() ?? 'User Actions',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  color: isDark ? borderDark : borderLight,
                  height: 16,
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primaryRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        color: primaryRed, size: 18),
                  ),
                  title: Text('Edit Permissions',
                      style: TextStyle(fontSize: 13, color: textColor)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditUserModal(u);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primaryRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded,
                        color: primaryRed, size: 18),
                  ),
                  title: Text('View Stock Sheet',
                      style: TextStyle(
                          fontSize: 13,
                          color: textColor,
                          fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DealerStockShareScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isUserAdmin
                          ? Icons.person_rounded
                          : Icons.admin_panel_settings_rounded,
                      color: accentBlue,
                      size: 18,
                    ),
                  ),
                  title: Text(
                      isUserAdmin ? 'Demote to Staff' : 'Promote to Admin',
                      style: TextStyle(fontSize: 13, color: textColor)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeUserRole(u, isUserAdmin ? 'staff' : 'admin');
                  },
                ),
                if (statusStr != 'approved')
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: successGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded,
                          color: successGreen, size: 18),
                    ),
                    title: Text('Approve Account',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeUserStatus(u, 'APPROVED');
                    },
                  ),
                if (statusStr != 'hold')
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: warningOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.pause_circle_outline_rounded,
                          color: warningOrange, size: 18),
                    ),
                    title: Text('Place on Hold',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeUserStatus(u, 'HOLD');
                    },
                  ),
                if (statusStr != 'rejected')
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.block_rounded,
                          color: Colors.deepOrange, size: 18),
                    ),
                    title: Text('Reject Registration',
                        style: TextStyle(fontSize: 13, color: textColor)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeUserStatus(u, 'REJECTED');
                    },
                  ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.vpn_key_rounded, color: textGrey, size: 18),
                  ),
                  title: const Text('Reset Password (OAuth Managed)',
                      style: TextStyle(fontSize: 13, color: textGrey)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Password reset is managed securely by Google Sign-In.")),
                    );
                  },
                ),
                Divider(
                  color: isDark ? borderDark : borderLight,
                  height: 16,
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primaryRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_forever_rounded,
                        color: primaryRed, size: 18),
                  ),
                  title: const Text('Delete Account',
                      style: TextStyle(
                          fontSize: 13,
                          color: primaryRed,
                          fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteUser(u);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? bgDark : bgLight;

    // Filter users list based on search query
    final filteredUsers = _users.where((u) {
      final email = (u['email']?.toString() ?? "").toLowerCase();
      final name = (u['user_name']?.toString() ?? "").toLowerCase();
      final query = _searchQuery.toLowerCase();
      return email.contains(query) || name.contains(query);
    }).toList();

    // Summary statistics
    final totalUsersCount = _users.length;
    final pendingCount = _users
        .where(
            (u) => (u['status']?.toString() ?? '').toUpperCase() == 'PENDING')
        .length;
    final adminCount = _users
        .where((u) => (u['role']?.toString() ?? '').toLowerCase() == 'admin')
        .length;
    final activeCount = _users
        .where(
            (u) => (u['status']?.toString() ?? '').toUpperCase() == 'APPROVED')
        .length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Manage Users",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            Text(
              "Admin dashboard",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: primaryRed,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: "Refresh List",
            onPressed: loadUsers,
          )
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(primaryRed),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: loadUsers,
                    color: primaryRed,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Dashboard Summary Metric Strip (4 cards)
                          _buildDashboardSummaryStrip(
                            totalUsers: totalUsersCount,
                            pending: pendingCount,
                            admins: adminCount,
                            active: activeCount,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 24),

                          // 2. Pending Registrations Section
                          if (UserSession.isUserAdmin) ...[
                            _buildPendingRegistrationsHeader(isDark: isDark),
                            const SizedBox(height: 12),
                            _buildPendingRegistrationsStream(isDark: isDark),
                            const SizedBox(height: 24),
                          ],

                          // 3. All Users Section
                          _buildSectionHeader('All Users', isDark: isDark),
                          const SizedBox(height: 12),
                          _buildSearchField(isDark: isDark),
                          const SizedBox(height: 12),
                          _buildFilteredUsersList(filteredUsers, isDark: isDark),
                          const SizedBox(height: 24),

                          // 4. Admin settings (Pricing Engine Configuration)
                          _buildSectionHeader('Admin Settings', isDark: isDark),
                          const SizedBox(height: 12),
                          _buildPricingConfigCard(isDark: isDark),
                          const SizedBox(height: 24),

                          // 5. System Tools
                          _buildSectionHeader('System Tools', isDark: isDark),
                          const SizedBox(height: 12),
                          _buildSystemToolsCard(isDark: isDark),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Stat Card Builder ──────────────────────────────────────────────────────
  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
    required bool isDark,
  }) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textGrey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardSummaryStrip({
    required int totalUsers,
    required int pending,
    required int admins,
    required int active,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;

        if (isWide) {
          return Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.people_alt_rounded,
                  value: totalUsers.toString(),
                  label: 'Total Users',
                  iconColor: accentBlue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.pending_actions_rounded,
                  value: pending.toString(),
                  label: 'Pending Requests',
                  iconColor: warningOrange,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.admin_panel_settings_rounded,
                  value: admins.toString(),
                  label: 'Admins',
                  iconColor: primaryRed,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.check_circle_rounded,
                  value: active.toString(),
                  label: 'Active Users',
                  iconColor: successGreen,
                  isDark: isDark,
                ),
              ),
            ],
          );
        }

        // Mobile 2x2 grid layout
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.people_alt_rounded,
                    value: totalUsers.toString(),
                    label: 'Total Users',
                    iconColor: accentBlue,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.pending_actions_rounded,
                    value: pending.toString(),
                    label: 'Pending Requests',
                    iconColor: warningOrange,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.admin_panel_settings_rounded,
                    value: admins.toString(),
                    label: 'Admins',
                    iconColor: primaryRed,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.check_circle_rounded,
                    value: active.toString(),
                    label: 'Active Users',
                    iconColor: successGreen,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title,
      {Widget? trailing, required bool isDark}) {
    final textColor = isDark ? Colors.white : textDark;

    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primaryRed,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _buildPendingRegistrationsHeader({required bool isDark}) {
    return _buildSectionHeader(
      "Pending Registrations",
      isDark: isDark,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: warningOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: warningOrange.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: warningOrange,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              "LIVE",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFFD97706),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingRegistrationsStream({required bool isDark}) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;

    final List<Map<String, dynamic>> fallbackPending = _users
        .where((u) {
          final status = (u['status']?.toString() ?? '').toUpperCase().trim();
          final isApproved = u['is_approved'];
          return status == 'PENDING' ||
              (isApproved != null &&
                  isApproved == false &&
                  status != 'APPROVED' &&
                  status != 'REJECTED');
        })
        .map((u) => Map<String, dynamic>.from(u as Map))
        .toList();

    if (_pendingStream == null) {
      if (fallbackPending.isEmpty) {
        return _buildPendingEmptyContainer(isDark);
      }
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _pendingStream?.stream,
      initialData: _pendingStream?.latestData ?? fallbackPending,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError && (!snapshot.hasData || snapshot.data == null)) {
          if (snapshot.error.toString().contains('_isInitialized')) {
            return _buildPendingEmptyContainer(isDark);
          }
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.red.shade900.withValues(alpha: 0.2)
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.red.shade800 : Colors.red.shade100,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Unable to load pending registrations: ${snapshot.error}",
                    style: TextStyle(
                      color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final pendingUsers = snapshot.data ?? [];
        if (pendingUsers.isEmpty) {
          return _buildPendingEmptyContainer(isDark);
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: pendingUsers.length,
          itemBuilder: (context, index) {
            final u = pendingUsers[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: warningOrange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.person_add_alt_1_rounded,
                            color: warningOrange, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u['email']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Name: ${u['user_name'] ?? 'N/A'}",
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined,
                              color: primaryRed, size: 22),
                          onPressed: () => _changeUserStatus(u, 'REJECTED'),
                          tooltip: 'Reject',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              color: successGreen, size: 22),
                          onPressed: () => _changeUserStatus(u, 'APPROVED'),
                          tooltip: 'Approve',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPendingEmptyContainer(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? borderDark : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.inbox_outlined,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No pending registrations',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'New signup requests will appear here.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
  }) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 24,
                color:
                    isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: textGrey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({required bool isDark}) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(fontSize: 13, color: textColor),
        decoration: InputDecoration(
          hintText: 'Search users by email or name...',
          hintStyle: const TextStyle(color: textGrey, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, color: textGrey, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: textGrey, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = "");
                  },
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
      ),
    );
  }

  Widget _buildFilteredUsersList(List<dynamic> filteredUsers,
      {required bool isDark}) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;

    if (filteredUsers.isEmpty) {
      return _buildPremiumEmptyState(
        title: "No users found",
        subtitle: "Try matching with another email or name query.",
        icon: Icons.people_outline_rounded,
        isDark: isDark,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final u = filteredUsers[index];
        final isUserAdmin = u['role']?.toString().toLowerCase() == 'admin';
        final isCurrentUser =
            u['email'] == SupabaseService.client.auth.currentUser?.email;

        Color statusBg;
        Color statusText;
        final statusStr = (u['status']?.toString() ?? 'pending').toLowerCase();
        switch (statusStr) {
          case 'approved':
            statusBg = isDark
                ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                : const Color(0xFFECFDF5);
            statusText = successGreen;
            break;
          case 'pending':
            statusBg = isDark
                ? const Color(0xFF78350F).withValues(alpha: 0.5)
                : const Color(0xFFFFFBEB);
            statusText = const Color(0xFFD97706);
            break;
          case 'hold':
            statusBg = isDark
                ? const Color(0xFF713F12).withValues(alpha: 0.5)
                : const Color(0xFFFEFCE8);
            statusText = const Color(0xFFB45309);
            break;
          default:
            statusBg = isDark
                ? const Color(0xFF7F1D1D).withValues(alpha: 0.5)
                : const Color(0xFFFEF2F2);
            statusText = const Color(0xFFDC2626);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Circular Avatar
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isUserAdmin
                        ? primaryRed.withValues(alpha: 0.1)
                        : accentBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (u['email']?.toString() ?? '?')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isUserAdmin ? primaryRed : accentBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              u['email']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: primaryRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: primaryRed,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Status chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              statusStr.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: statusText,
                              ),
                            ),
                          ),
                          // Role chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isUserAdmin
                                  ? primaryRed.withValues(alpha: 0.08)
                                  : (isDark
                                      ? Colors.white10
                                      : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (u['role']?.toString() ?? 'staff').toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isUserAdmin
                                    ? primaryRed
                                    : (isDark
                                        ? Colors.white70
                                        : const Color(0xFF475569)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Quick Stock Sheet link
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_rounded,
                      size: 20, color: primaryRed),
                  tooltip: 'View Stock Sheet',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DealerStockShareScreen(),
                      ),
                    );
                  },
                ),

                // Manage action trigger (Clean Overflow Menu)
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: textGrey),
                  tooltip: 'User actions',
                  onPressed: isCurrentUser
                      ? null
                      : () => _showUserActionBottomSheet(u, statusStr),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPricingConfigCard({required bool isDark}) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;
    final inputBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    InputDecoration inputDeco({
      required String hint,
      String? suffixText,
      String? prefixText,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.grey.shade400,
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        suffixText: suffixText,
        suffixStyle: const TextStyle(
          color: primaryRed,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
          color: textGrey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        filled: true,
        fillColor: inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryRed, width: 1.4),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GST (%)',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: textGrey)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _gstCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                      ],
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor),
                      decoration: inputDeco(hint: '18.00', suffixText: '%'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LC (₹/MT)',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: textGrey)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _lcCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                      ],
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor),
                      decoration: inputDeco(hint: '255.00', prefixText: '₹ '),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NC (₹/MT)',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: textGrey)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _ncCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                      ],
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor),
                      decoration: inputDeco(hint: '3000.00', prefixText: '₹ '),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Save Changes full width Red button
          SizedBox(
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _savingCharges ? null : _saveGlobalCharges,
              child: _savingCharges
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.4),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemToolsCard({required bool isDark}) {
    final cardColor = isDark ? cardDark : cardLight;
    final borderColor = isDark ? borderDark : borderLight;
    final textColor = isDark ? Colors.white : textDark;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showResetConfirmation,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: warningOrange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.restart_alt_rounded,
                        color: warningOrange, size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Soft Reset Dashboard',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: textColor),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Hide transaction history and reset stock totals to zero. Steel data stays untouched.',
                        style: TextStyle(fontSize: 11.5, color: textGrey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right_rounded, color: textGrey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
