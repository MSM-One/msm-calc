import 'package:flutter/material.dart';
import '../widgets/motion_toast.dart';
import 'package:flutter/services.dart';

import '../models/user_model.dart';
import '../services/data_repository.dart';
import '../screens/permission_manager_screen.dart';
import '../screens/dealer_stock_share_screen.dart';

import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../services/supabase_service.dart';
import '../models/stock_role.dart';

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

  // ── Color Constants ────────────────────────────────────────────────────────
  static const Color primaryRed = Color(0xFFD71920);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color warningOrange = Color(0xFFF97316);

  // ── Pricing Engine config controllers ─────────────────────────────────────────────
  final TextEditingController _gstCtrl = TextEditingController();
  final TextEditingController _lcCtrl = TextEditingController();
  final TextEditingController _ncCtrl = TextEditingController();
  bool _savingCharges = false;

  @override
  void initState() {
    super.initState();

    // --- Hard Navigation Guard ---
    if (!widget.isEmbedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (AccessGuard.cannot(AppPermissions.screensUsers)) {
          MotionToast.show(context, "Access Denied: Missing Permission",
              isError: true);
          if (mounted) Navigator.pop(context);
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
        MotionToast.show(context, "Error loading users: $e", isError: true);
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
        title: Row(children: const [
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
      SnackBar(
        content: const Text('Dashboard reset to zero! Cache cleared.'),
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

      if (mounted) {
        await loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User marked as $newStatus'),
            backgroundColor: successGreen,
          ),
        );
      }
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

      if (mounted) {
        await loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User role updated to $newRole'),
            backgroundColor: successGreen,
          ),
        );
      }
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
        title: const Text('Delete User?'),
        content: Text(
            'Are you sure you want to permanently delete ${user['email']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
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

      if (mounted) {
        await loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('User deleted successfully'),
            backgroundColor: successGreen,
          ),
        );
      }
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: cardBg,
      builder: (ctx) {
        final isUserAdmin = u['role']?.toString().toLowerCase() == 'admin';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 8.0),
                  child: Text(
                    u['email']?.toString() ?? 'User Actions',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.tune_rounded, color: primaryRed),
                  title: const Text('Edit Permissions',
                      style: TextStyle(fontSize: 13, color: textDark)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditUserModal(u);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_rounded, color: primaryRed),
                  title: const Text('View Stock Sheet',
                      style: TextStyle(
                          fontSize: 13,
                          color: textDark,
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
                  leading: Icon(
                      isUserAdmin
                          ? Icons.person_rounded
                          : Icons.admin_panel_settings,
                      color: Colors.blue),
                  title: Text(
                      isUserAdmin ? 'Demote to Staff' : 'Promote to Admin',
                      style: const TextStyle(fontSize: 13, color: textDark)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeUserRole(u, isUserAdmin ? 'staff' : 'admin');
                  },
                ),
                if (statusStr != 'approved')
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline_rounded,
                        color: successGreen),
                    title: const Text('Approve Account',
                        style: TextStyle(fontSize: 13, color: textDark)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeUserStatus(u, 'APPROVED');
                    },
                  ),
                if (statusStr != 'hold')
                  ListTile(
                    leading: const Icon(Icons.pause_circle_outline_rounded,
                        color: warningOrange),
                    title: const Text('Place on Hold',
                        style: TextStyle(fontSize: 13, color: textDark)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeUserStatus(u, 'HOLD');
                    },
                  ),
                if (statusStr != 'rejected')
                  ListTile(
                    leading: const Icon(Icons.block_rounded,
                        color: Colors.deepOrange),
                    title: const Text('Reject Registration',
                        style: TextStyle(fontSize: 13, color: textDark)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _changeUserStatus(u, 'REJECTED');
                    },
                  ),
                ListTile(
                  leading:
                      const Icon(Icons.vpn_key_rounded, color: Colors.grey),
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
                const Divider(),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded,
                      color: primaryRed.withValues(alpha: 0.8)),
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
      backgroundColor: bgLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
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
            constraints: const BoxConstraints(maxWidth: 800),
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
                          // 1. Dashboard Summary Widgets (2x2 Grid)
                          _buildDashboardSummary(
                            totalUsers: totalUsersCount,
                            pending: pendingCount,
                            admins: adminCount,
                            active: activeCount,
                          ),
                          const SizedBox(height: 24),

                          // 2. Pending Registrations Section
                          if (UserSession.isUserAdmin) ...[
                            _buildPendingRegistrationsHeader(),
                            const SizedBox(height: 12),
                            _buildPendingRegistrationsStream(),
                            const SizedBox(height: 24),
                          ],

                          // 3. All Users Section
                          _buildSectionTitle('All Users'),
                          const SizedBox(height: 12),
                          _buildSearchField(),
                          const SizedBox(height: 12),
                          _buildFilteredUsersList(filteredUsers),
                          const SizedBox(height: 24),

                          // 4. Admin settings (Pricing Engine Configuration)
                          _buildSectionTitle('Admin Settings'),
                          const SizedBox(height: 12),
                          _buildPricingConfigCard(),
                          const SizedBox(height: 24),

                          // 5. System Tools
                          _buildSectionTitle('System Tools'),
                          const SizedBox(height: 12),
                          _buildSystemToolsCard(),
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

  // ── Stat Card builder ──────────────────────────────────────────────────────
  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
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

  Widget _buildDashboardSummary({
    required int totalUsers,
    required int pending,
    required int admins,
    required int active,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.95,
      children: [
        _buildStatCard(
          icon: Icons.people_rounded,
          value: totalUsers.toString(),
          label: 'Total Users',
          iconColor: Colors.blue,
        ),
        _buildStatCard(
          icon: Icons.pending_actions_rounded,
          value: pending.toString(),
          label: 'Pending Requests',
          iconColor: warningOrange,
        ),
        _buildStatCard(
          icon: Icons.admin_panel_settings_rounded,
          value: admins.toString(),
          label: 'Admins',
          iconColor: primaryRed,
        ),
        _buildStatCard(
          icon: Icons.check_circle_rounded,
          value: active.toString(),
          label: 'Active Users',
          iconColor: successGreen,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: textDark,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildPendingRegistrationsHeader() {
    return Row(
      children: [
        _buildSectionTitle("Pending Registrations"),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: warningOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            "LIVE",
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: warningOrange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRegistrationsStream() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client
          .from('users')
          .stream(primaryKey: ['id']).eq('status', 'PENDING'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(warningOrange),
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Text(
              "Error streaming pending registrations: ${snapshot.error}",
              style: TextStyle(color: Colors.red.shade800, fontSize: 12),
            ),
          );
        }
        final pendingUsers = snapshot.data ?? [];
        if (pendingUsers.isEmpty) {
          return _buildPremiumEmptyState(
            title: "No pending registrations",
            subtitle: "New signup requests will appear here.",
            icon: Icons.assignment_turned_in_rounded,
          );
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
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderLight, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
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
                        color: warningOrange.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.person_add_rounded,
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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Name: ${u['user_name'] ?? 'N/A'}",
                            style: const TextStyle(
                              fontSize: 11,
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
                              color: primaryRed, size: 20),
                          onPressed: () => _changeUserStatus(u, 'REJECTED'),
                          tooltip: 'Reject',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              color: successGreen, size: 20),
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

  Widget _buildPremiumEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: textDark),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: textGrey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        style: const TextStyle(fontSize: 13, color: textDark),
        decoration: InputDecoration(
          hintText: 'Search users',
          hintStyle: const TextStyle(color: textGrey, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, color: textGrey, size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
      ),
    );
  }

  Widget _buildFilteredUsersList(List<dynamic> filteredUsers) {
    if (filteredUsers.isEmpty) {
      return _buildPremiumEmptyState(
        title: "No users found",
        subtitle: "Try matching with another email or name query.",
        icon: Icons.people_outline_rounded,
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
        final dynamic dynamicTimestamp = u['last_seen'] ??
            u['lastSeen'] ??
            u['updated_at'] ??
            u['updatedAt'];

        Color statusBg;
        Color statusText;
        final statusStr = (u['status']?.toString() ?? 'pending').toLowerCase();
        switch (statusStr) {
          case 'approved':
            statusBg = const Color(0xFFE8F5E9);
            statusText = successGreen;
            break;
          case 'pending':
            statusBg = const Color(0xFFFFF3E0);
            statusText = warningOrange;
            break;
          case 'hold':
            statusBg = const Color(0xFFFFFDE7);
            statusText = Colors.yellow.shade900;
            break;
          default:
            statusBg = const Color(0xFFFFEBEE);
            statusText = primaryRed;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderLight, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
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
                        ? primaryRed.withValues(alpha: 0.08)
                        : textGrey.withValues(alpha: 0.06),
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
                        color: isUserAdmin ? primaryRed : textGrey,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textDark,
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
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
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
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (u['role']?.toString() ?? 'staff').toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color:
                                    isUserAdmin ? primaryRed : Colors.grey[700],
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

  Widget _buildPricingConfigCard() {
    InputDecoration inputDeco({
      required String hint,
      String? suffixText,
      String? prefixText,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
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
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderLight, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderLight, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryRed, width: 1.5),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                            fontSize: 11,
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
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textDark),
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
                            fontSize: 11,
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
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textDark),
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
                            fontSize: 11,
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
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textDark),
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
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                          letterSpacing: 0.5),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemToolsCard() {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _showResetConfirmation,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: warningOrange.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restart_alt_rounded,
                      color: warningOrange, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Soft Reset Dashboard',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textDark),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Hide transaction history and reset stock totals to zero. Steel data stays untouched.',
                        style: TextStyle(fontSize: 11, color: textGrey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right_rounded, color: textGrey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
