import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/motion_toast.dart';
import '../widgets/m_loader.dart';
import '../models/permission_model.dart';
import '../models/user_model.dart';
import '../models/stock_role.dart';
import '../services/data_repository.dart';
import '../constants/app_colors.dart';
import '../services/supabase_service.dart';
import '../utils/resilient_supabase_stream.dart';

const Color _kAccent = msmRed;
const Color _kBg = msmBg;
const Color _kSurface = cardBg;
const Color _kText = textDark;
const Color _kSubtext = textGrey;
const Color _kInherited = Color(0xFF9CA3AF);
const Color _kOverride = Color(0xFF2563EB);
const Color _kAdminClr = Color(0xFFFB923C);
const Color _kStaffClr = Color(0xFF3B82F6);

/// Enterprise Permission Manager Screen.
/// Opened from ManageUsersScreen via Navigator.push.
///
/// Constructor takes:
///   [user]        — the user whose permissions are being edited.
///   [allUsers]    — complete list of users required for "last admin" validation.
class PermissionManagerScreen extends StatefulWidget {
  final UserModel user;
  final List<UserModel> allUsers;

  const PermissionManagerScreen({
    super.key,
    required this.user,
    this.allUsers = const [],
  });

  @override
  State<PermissionManagerScreen> createState() =>
      _PermissionManagerScreenState();
}

class _PermissionManagerScreenState extends State<PermissionManagerScreen>
    with TickerProviderStateMixin {
  late UserModel _user;
  late Map<String, Permission> _effectivePerms;
  late Map<String, Permission> _overrides;
  late UserRole _selectedRole;

  // ── Concurrency / unsaved-change tracking ─────────────────────────────────
  /// Version snapshot loaded from server at screen open time.
  int _savedVersion = 0;

  /// Role snapshot at screen open, to detect role changes as unsaved.
  late UserRole _savedRole;

  /// Permission snapshot at screen open, used to diff against current.
  late Map<String, bool> _savedPermissions;

  /// True when any permission or role differs from the saved snapshot.
  bool _hasUnsavedChanges = false;

  /// How many individual permission slugs differ from saved state.
  int _unsavedCount = 0;

  bool _isSaving = false;
  bool _isPreviewMode = false;
  String _search = '';

  // ── Live stream state ─────────────────────────────────────────────────────
  ResilientSupabaseStream<List<Map<String, dynamic>>>? _userStream;
  StreamSubscription<List<Map<String, dynamic>>>? _userStreamSub;

  /// True when a remote DB update arrived while the admin had local unsaved edits.
  /// Triggers the stale-data warning banner.
  bool _remoteUpdateWhileEditing = false;

  /// Tracks stream error state for the reconnecting indicator.
  bool _streamError = false;

  // Derived safety flags (computed once per build)
  bool get _isSelf =>
      _user.email.toLowerCase().trim() ==
      (UserSession.userEmail?.toLowerCase().trim() ?? '');

  bool get _isLastAdmin {
    // True when this user IS currently an admin AND no other admin exists.
    final otherAdmins = widget.allUsers.where(
      (u) => u.isAdmin && u.email != _user.email,
    );
    return _user.isAdmin && otherAdmins.isEmpty;
  }

  bool get _canChangeRole => UserSession.isUserAdmin && !_isSelf;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _selectedRole = _user.role;
    _savedRole = _user.role;
    _savedVersion = _user.version;
    _savedPermissions = Map<String, bool>.from(_user.permissions);

    // Start from staffDefaults so every slug has a baseline value
    final defaults = _selectedRole == UserRole.admin
        ? PermissionRegistry.adminDefaults
        : PermissionRegistry.staffDefaults;
    _overrides = Map<String, Permission>.from(defaults);

    // Apply the user's actual saved permissions on top
    for (final entry in _user.permissions.entries) {
      _overrides[entry.key] =
          Permission(slug: entry.key, isAllowed: entry.value);
    }
    _rebuildEffective();

    // ── Resilient realtime stream: users table filtered by this user's email ──
    _userStream = ResilientSupabaseStream<List<Map<String, dynamic>>>(
      streamFactory: () => SupabaseService.client
          .from('users')
          .stream(primaryKey: ['email']).eq('email', widget.user.email),
    );

    // Listen to stream error notifier to surface reconnecting indicator in UI.
    _userStream!.isErrorNotifier.addListener(_onStreamErrorChanged);

    _userStreamSub =
        _userStream!.stream.listen((List<Map<String, dynamic>> event) {
      if (event.isNotEmpty) {
        final freshUser = UserModel.fromJson(event.first);
        if (mounted) {
          setState(() {
            _user = freshUser;
            _savedVersion = freshUser.version;

            if (!_hasUnsavedChanges) {
              // No local edits — silently sync role + permissions to live data.
              _selectedRole = freshUser.role;
              _savedRole = freshUser.role;
              _savedPermissions = Map<String, bool>.from(freshUser.permissions);

              final defaults = _selectedRole == UserRole.admin
                  ? PermissionRegistry.adminDefaults
                  : PermissionRegistry.staffDefaults;
              _overrides = Map<String, Permission>.from(defaults);

              for (final entry in _user.permissions.entries) {
                _overrides[entry.key] =
                    Permission(slug: entry.key, isAllowed: entry.value);
              }
              _rebuildEffective();
            } else {
              // Admin has local unsaved edits — update saved snapshot but keep
              // local overrides intact. Flag the stale-data banner.
              _savedRole = freshUser.role;
              _savedPermissions = Map<String, bool>.from(freshUser.permissions);
              _recalcUnsaved();
              _remoteUpdateWhileEditing = true;
            }
          });
        }
      }
    });
  }

  void _onStreamErrorChanged() {
    if (mounted) {
      setState(() {
        _streamError = _userStream?.isErrorNotifier.value ?? false;
      });
    }
  }

  @override
  void dispose() {
    _userStream?.isErrorNotifier.removeListener(_onStreamErrorChanged);
    _userStreamSub?.cancel();
    _userStream?.dispose();
    super.dispose();
  }

  void _rebuildEffective() {
    _effectivePerms = PermissionRegistry.resolve(
      roleId: _selectedRole == UserRole.admin ? 'admin' : 'staff',
      customPermissions: _overrides,
    );
    _recalcUnsaved();
  }

  /// Recompute unsaved-change count and flag.
  void _recalcUnsaved() {
    if (_selectedRole != _savedRole) {
      _hasUnsavedChanges = true;
      _unsavedCount =
          PermissionRegistry.allSlugs.length; // all changed on role switch
      return;
    }
    int count = 0;
    for (final slug in PermissionRegistry.allSlugs) {
      final current = _effectivePerms[slug]?.isAllowed ?? false;
      final saved = _savedPermissions[slug] ?? false;
      if (current != saved) count++;
    }
    _unsavedCount = count;
    _hasUnsavedChanges = count > 0;
  }

  bool _getEffective(String slug) {
    if (_selectedRole == UserRole.admin) return true;
    return _effectivePerms[slug]?.isAllowed ?? false;
  }

  bool _isOverridden(String slug) => _overrides.containsKey(slug);

  bool _isParentBlocked(PermissionEntry entry) {
    if (entry.parentSlug == null) return false;
    return !_getEffective(entry.parentSlug!);
  }

  void _toggle(String slug, bool value) {
    if (_isSaving) return;
    setState(() {
      _overrides[slug] = Permission(slug: slug, isAllowed: value);
      if (slug == Permissions.screensStockSheet) {
        _overrides[Permissions.canAccessStockSheet] =
            Permission(slug: Permissions.canAccessStockSheet, isAllowed: value);
      } else if (slug == Permissions.canAccessStockSheet) {
        _overrides[Permissions.screensStockSheet] =
            Permission(slug: Permissions.screensStockSheet, isAllowed: value);
      }
      _rebuildEffective();
    });
  }

  void _resetOverride(String slug) {
    if (_isSaving) return;
    setState(() {
      _overrides.remove(slug);
      _rebuildEffective();
    });
  }

  void _setAllInModule(PermissionModule module, bool value) {
    if (_isSaving) return;
    setState(() {
      for (final e in module.entries) {
        _overrides[e.slug] = Permission(slug: e.slug, isAllowed: value);
      }
      _rebuildEffective();
    });
  }

  // ── Role Change Logic ──────────────────────────────────────────────────────

  Future<void> _requestRoleChange(UserRole newRole) async {
    if (!_canChangeRole) return;

    // Guard: prevent removing the last Admin.
    if (_user.isAdmin && newRole != UserRole.admin && _isLastAdmin) {
      _showWarning(
        title: 'Cannot Remove Last Admin',
        message: 'There must always be at least one Admin account. '
            'Promote another user to Admin before demoting this one.',
        icon: Icons.shield_rounded,
        iconColor: Colors.orange,
      );
      return;
    }

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            newRole == UserRole.admin
                ? Icons.admin_panel_settings_rounded
                : Icons.person_rounded,
            color: newRole == UserRole.admin ? _kAdminClr : _kStaffClr,
          ),
          const SizedBox(width: 8),
          const Text('Change Role', style: TextStyle(fontSize: 16)),
        ]),
        content: Text(
          'Change ${_user.email} from '
          '${_user.isAdmin ? "Admin" : "Staff"} '
          'to ${newRole == UserRole.admin ? "Admin" : "Staff"}?\n\n'
          '${newRole == UserRole.admin ? "This will grant full system access." : "This will restrict access to assigned permissions only."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  newRole == UserRole.admin ? _kAdminClr : _kAccent,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _selectedRole = newRole;
        // Re-seed overrides from the new role's defaults
        final newDefaults = newRole == UserRole.admin
            ? PermissionRegistry.adminDefaults
            : PermissionRegistry.staffDefaults;
        _overrides = Map<String, Permission>.from(newDefaults);
        // Carry over any previously toggled values (they override defaults) ONLY if previous role was not Admin
        if (_user.role != UserRole.admin) {
          for (final entry in _user.permissions.entries) {
            _overrides[entry.key] =
                Permission(slug: entry.key, isAllowed: entry.value);
          }
        }
        _rebuildEffective(); // also calls _recalcUnsaved()
      });
    }
  }

  void _showWarning({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        ]),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_isSaving || !_hasUnsavedChanges) return;
    setState(() => _isSaving = true);
    try {
      // Build a COMPLETE permissions map containing every known slug.
      final completePermsMap = <String, bool>{};
      for (final slug in PermissionRegistry.allSlugs) {
        if (_selectedRole == UserRole.admin) {
          completePermsMap[slug] = true;
        } else {
          completePermsMap[slug] = _effectivePerms[slug]?.isAllowed ?? false;
        }
      }
      for (final entry in _overrides.entries) {
        if (!completePermsMap.containsKey(entry.key)) {
          completePermsMap[entry.key] = entry.value.isAllowed;
        }
      }

      // Fetch latest user version to check for conflict
      final freshResponse = await SupabaseService.client
          .from('users')
          .select('version, lastUpdatedBy')
          .eq('email', _user.email)
          .maybeSingle();

      int currentVersion = 0;
      String? currentUpdatedBy;
      if (freshResponse != null) {
        currentVersion =
            int.tryParse(freshResponse['version']?.toString() ?? '0') ?? 0;
        currentUpdatedBy = freshResponse['lastUpdatedBy']?.toString();
      }

      if (currentVersion > _savedVersion) {
        // Save conflict!
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(Icons.sync_problem_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Save Conflict', style: TextStyle(fontSize: 15))),
            ]),
            content: Text(
              'This user\'s permissions were changed by ${currentUpdatedBy ?? "another admin"}.\n\n'
              'Please go back and reload to see the latest data before saving.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
        return;
      }

      final newVersion = _savedVersion + 1;
      final updated = _user.copyWith(
        role: _selectedRole,
        allowedAccess:
            UserModel.deriveAllowedAccess(_selectedRole, completePermsMap),
        permissions: completePermsMap,
        version: newVersion,
        lastUpdatedBy: UserSession.userEmail,
      );

      debugPrint(
          'DEBUG: [PermissionManagerScreen] Calling Supabase user update');
      await SupabaseService.client
          .from('users')
          .update(updated.toJson())
          .eq('email', _user.email);

      debugPrint('DEBUG: [PermissionManagerScreen] Server update SUCCESS');

      // ── Apply returned record to local state (no second round-trip) ────────
      UserModel finalUser = updated;

      // ── Immediate permission refresh on Commit Changes ─────────────────────
      debugPrint(
          'DEBUG: [PermissionManagerScreen] Commit Changes — refreshing current user permissions');
      await DataRepository.refreshCurrentUser(_user.email);
      await DataRepository.refreshCurrentUser();

      // Queue background re-sync for inventory etc.
      DataRepository.refreshAllStockData();

      if (mounted) {
        // Reset unsaved state
        setState(() {
          _user = finalUser;
          _savedVersion = finalUser.version;
          _savedRole = finalUser.role;
          _savedPermissions = Map<String, bool>.from(finalUser.permissions);
          _hasUnsavedChanges = false;
          _unsavedCount = 0;
        });

        MotionToast.show(context, 'Saved for ${_user.email}');
        Navigator.pop(context, finalUser);
      }
    } catch (e) {
      if (mounted) {
        MotionToast.show(context, 'Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isAdminRole = _selectedRole == UserRole.admin;

    final modules = _search.isEmpty
        ? PermissionModules.all
        : PermissionModules.all
            .map((m) => PermissionModule(
                  id: m.id,
                  label: m.label,
                  icon: m.icon,
                  entries: m.entries
                      .where((e) =>
                          e.label
                              .toLowerCase()
                              .contains(_search.toLowerCase()) ||
                          (e.description ?? '')
                              .toLowerCase()
                              .contains(_search.toLowerCase()))
                      .toList(),
                ))
            .where((m) => m.entries.isNotEmpty)
            .toList();

    return Scaffold(
      backgroundColor: _kBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: CustomScrollView(
            slivers: [
              // ── App Bar
              SliverAppBar(
                pinned: true,
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title: const Text(
                  'Permission Manager',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                actions: [
                  // ── Live stream indicator ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _streamError
                        ? const Tooltip(
                            message: 'Reconnecting to live updates…',
                            child: _LiveDot(isError: true),
                          )
                        : const Tooltip(
                            message: 'Live sync active',
                            child: _LiveDot(isError: false),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _isPreviewMode = !_isPreviewMode),
                      icon: Icon(
                        _isPreviewMode
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        _isPreviewMode ? 'Exit' : 'Preview',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Stale-data warning banner (remote change arrived mid-edit)
              if (_remoteUpdateWhileEditing)
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.sync_problem_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'This user was updated remotely. Your local edits are preserved — review before saving.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _remoteUpdateWhileEditing = false),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ]),
                  ),
                ),

              // ── Preview Banner
              if (_isPreviewMode)
                SliverToBoxAdapter(
                  child: Container(
                    color: const Color(0xFF1E40AF),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.preview_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Previewing as ${_user.email}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ]),
                  ),
                ),

              // ── User Identity & Role Selector Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _RoleCard(
                    user: _user,
                    selectedRole: _selectedRole,
                    isSelf: _isSelf,
                    isLastAdmin: _isLastAdmin,
                    canChangeRole: _canChangeRole,
                    onRoleChange: _requestRoleChange,
                  ),
                ),
              ),

              // ── Self / Last-Admin warning
              if (_isSelf)
                SliverToBoxAdapter(
                  child: _InfoBanner(
                    icon: Icons.person_off_rounded,
                    color: Colors.orange.shade700,
                    message: 'You cannot change your own role.',
                  ),
                ),
              if (!_isSelf && _isLastAdmin)
                const SliverToBoxAdapter(
                  child: _InfoBanner(
                    icon: Icons.shield_rounded,
                    color: Colors.deepPurple,
                    message:
                        'Last Admin — promoting another user to Admin first is required before demotion.',
                  ),
                ),

              // ── Legend
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    _LegendDot(color: _kInherited, label: 'Inherited'),
                    SizedBox(width: 16),
                    _LegendDot(color: _kOverride, label: 'Custom override'),
                  ]),
                ),
              ),

              // ── Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search permissions…',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: _kSubtext),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: _kSurface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Admin-locked info banner
              if (isAdminRole)
                const SliverToBoxAdapter(
                  child: _InfoBanner(
                    icon: Icons.admin_panel_settings_rounded,
                    color: _kAdminClr,
                    message: 'Admin accounts have full access to all features. '
                        'Per-permission settings are not applicable.',
                  ),
                ),

              // ── Permission Modules (hidden for admin role)
              if (!isAdminRole)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: _PermissionModuleCard(
                        module: modules[i],
                        getEffective: _getEffective,
                        isOverridden: _isOverridden,
                        isParentBlocked: _isParentBlocked,
                        onToggle: _toggle,
                        onReset: _resetOverride,
                        onSelectAll: () => _setAllInModule(modules[i], true),
                        onClearAll: () => _setAllInModule(modules[i], false),
                        isPreview: _isPreviewMode,
                      ),
                    ),
                    childCount: modules.length,
                  ),
                ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: 100)), // bottom padding for bar
            ],
          ),
        ),
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = MediaQuery.of(context).size.width >= 600;
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              child: isWide
                  // ── Web / Tablet layout ────────────────────────────────────
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Row(
                            children: [
                              // Status text (left)
                              Expanded(
                                child: _StatusText(
                                  hasUnsaved: _hasUnsavedChanges,
                                  count: _unsavedCount,
                                  isSaving: _isSaving,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Save button (right)
                              SizedBox(
                                width: 240,
                                child: _SaveButton(
                                  isSaving: _isSaving,
                                  hasUnsavedChanges: _hasUnsavedChanges,
                                  onSave: _save,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  // ── Mobile layout ──────────────────────────────────────────
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StatusText(
                          hasUnsaved: _hasUnsavedChanges,
                          count: _unsavedCount,
                          isSaving: _isSaving,
                        ),
                        const SizedBox(height: 8),
                        _SaveButton(
                          isSaving: _isSaving,
                          hasUnsavedChanges: _hasUnsavedChanges,
                          onSave: _save,
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role Selector Card
// ─────────────────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final UserModel user;
  final UserRole selectedRole;
  final bool isSelf;
  final bool isLastAdmin;
  final bool canChangeRole;
  final void Function(UserRole) onRoleChange;

  const _RoleCard({
    required this.user,
    required this.selectedRole,
    required this.isSelf,
    required this.isLastAdmin,
    required this.canChangeRole,
    required this.onRoleChange,
  });

  @override
  Widget build(BuildContext context) {
    final isAdminSelected = selectedRole == UserRole.admin;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            isAdminSelected ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAdminSelected
              ? const Color(0xFFFED7AA)
              : const Color(0xFFBFDBFE),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Identity row
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isAdminSelected ? _kAdminClr : _kStaffClr,
              child: Text(
                user.email.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.email,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _kText)),
                  const SizedBox(height: 2),
                  Text(user.status.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11,
                          color: _kSubtext,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 14),

          // ── Role Selector Row
          LayoutBuilder(builder: (context, constraints) {
            bool stack = constraints.maxWidth < 300;
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Role',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kText)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _RoleChip(
                              label: '👑 Admin',
                              isSelected: isAdminSelected,
                              selectedColor: _kAdminClr,
                              isDisabled: !canChangeRole ||
                                  (isAdminSelected && isLastAdmin),
                              disabledTooltip: isSelf
                                  ? 'Cannot modify own role'
                                  : isLastAdmin
                                      ? 'Last admin — cannot demote'
                                      : null,
                              onTap: () => onRoleChange(UserRole.admin),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _RoleChip(
                              label: '👤 Staff',
                              isSelected: !isAdminSelected,
                              selectedColor: _kStaffClr,
                              isDisabled: !canChangeRole ||
                                  (!isAdminSelected && isLastAdmin),
                              disabledTooltip: isSelf
                                  ? 'Cannot modify own role'
                                  : isLastAdmin
                                      ? 'Last admin — cannot demote'
                                      : null,
                              onTap: () => onRoleChange(UserRole.staff),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(children: [
                    const Text('Role',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kText)),
                    const Spacer(),
                    // Admin chip
                    _RoleChip(
                      label: '👑 Admin',
                      isSelected: isAdminSelected,
                      selectedColor: _kAdminClr,
                      isDisabled:
                          !canChangeRole || (isAdminSelected && isLastAdmin),
                      disabledTooltip: isSelf
                          ? 'Cannot modify own role'
                          : isLastAdmin
                              ? 'Last admin — cannot demote'
                              : null,
                      onTap: () => onRoleChange(UserRole.admin),
                    ),
                    const SizedBox(width: 8),
                    // Staff chip
                    _RoleChip(
                      label: '👤 Staff',
                      isSelected: !isAdminSelected,
                      selectedColor: _kStaffClr,
                      isDisabled:
                          !canChangeRole || (!isAdminSelected && isLastAdmin),
                      disabledTooltip: isSelf
                          ? 'Cannot modify own role'
                          : isLastAdmin
                              ? 'Last admin — cannot demote'
                              : null,
                      onTap: () => onRoleChange(UserRole.staff),
                    ),
                  ]);
          }),

          if (!canChangeRole) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                isSelf
                    ? 'Role change is disabled for your own account.'
                    : 'Only Admins can change user roles.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final bool isDisabled;
  final String? disabledTooltip;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.isDisabled,
    required this.onTap,
    this.disabledTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final Widget chip = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? selectedColor : Colors.grey.shade300,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : _kSubtext,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );

    if (isDisabled) {
      return Opacity(
        opacity: 0.45,
        child: disabledTooltip != null
            ? Tooltip(message: disabledTooltip!, child: chip)
            : chip,
      );
    }

    return GestureDetector(
      onTap: isSelected ? null : onTap,
      child: chip,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info Banner
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _InfoBanner(
      {required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Module Card
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionModuleCard extends StatefulWidget {
  final PermissionModule module;
  final bool Function(String) getEffective;
  final bool Function(String) isOverridden;
  final bool Function(PermissionEntry) isParentBlocked;
  final void Function(String, bool) onToggle;
  final void Function(String) onReset;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final bool isPreview;

  const _PermissionModuleCard({
    required this.module,
    required this.getEffective,
    required this.isOverridden,
    required this.isParentBlocked,
    required this.onToggle,
    required this.onReset,
    required this.onSelectAll,
    required this.onClearAll,
    required this.isPreview,
  });

  @override
  State<_PermissionModuleCard> createState() => _PermissionModuleCardState();
}

class _PermissionModuleCardState extends State<_PermissionModuleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (v) => setState(() => _expanded = v),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child:
                Text(widget.module.icon, style: const TextStyle(fontSize: 18)),
          ),
          title: Text(widget.module.label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
          subtitle: !_expanded
              ? Text(
                  '${widget.module.entries.where((e) => widget.getEffective(e.slug)).length}'
                  ' / ${widget.module.entries.length} enabled',
                  style: const TextStyle(fontSize: 11, color: _kSubtext),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_expanded) ...[
                _ModuleAction(
                  label: 'All',
                  icon: Icons.select_all_rounded,
                  onTap: widget.onSelectAll,
                ),
                const SizedBox(width: 6),
                _ModuleAction(
                  label: 'None',
                  icon: Icons.deselect_rounded,
                  onTap: widget.onClearAll,
                  isDestructive: true,
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _kSubtext,
              ),
            ],
          ),
          children: widget.module.entries
              .where((e) => !widget.isParentBlocked(e))
              .map((entry) {
            return _PermissionEntryRow(
              entry: entry,
              isAllowed: widget.getEffective(entry.slug),
              isOverridden: widget.isOverridden(entry.slug),
              isBlocked: widget.isParentBlocked(entry),
              isPreview: widget.isPreview,
              onToggle: (v) => widget.onToggle(entry.slug, v),
              onReset: () => widget.onReset(entry.slug),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission Entry Row
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionEntryRow extends StatelessWidget {
  final PermissionEntry entry;
  final bool isAllowed;
  final bool isOverridden;
  final bool isBlocked;
  final bool isPreview;
  final void Function(bool) onToggle;
  final VoidCallback onReset;

  const _PermissionEntryRow({
    required this.entry,
    required this.isAllowed,
    required this.isOverridden,
    required this.isBlocked,
    required this.isPreview,
    required this.onToggle,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final bool dimmed = isBlocked || (!isAllowed && isPreview);
    final bool isChild = entry.parentSlug != null;

    return Opacity(
      opacity: dimmed ? 0.38 : 1.0,
      child: Container(
        margin: EdgeInsets.fromLTRB(isChild ? 32 : 16, 0, 16, 0),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: isChild
              ? Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 16, color: Colors.grey.shade400)
              : null,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                entry.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isChild ? FontWeight.normal : FontWeight.w600,
                  color: _kText,
                ),
              ),
              if (isOverridden)
                GestureDetector(
                  onTap: isBlocked ? null : onReset,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kOverride.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _kOverride.withValues(alpha: 0.3)),
                    ),
                    child: const Text('override',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: _kOverride)),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kInherited.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('inherited',
                      style: TextStyle(fontSize: 9, color: _kInherited)),
                ),
            ],
          ),
          subtitle: entry.description != null
              ? Text(entry.description!,
                  style: const TextStyle(fontSize: 11, color: _kSubtext))
              : null,
          trailing: Switch.adaptive(
            value: isAllowed,
            activeThumbColor: _kAccent,
            onChanged: isBlocked ? null : onToggle,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auxiliary Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool isSaving;
  final bool hasUnsavedChanges;
  final VoidCallback onSave;
  const _SaveButton({
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    const brandRed = Color(0xFFED1C24);
    const brandRedDark = Color(0xFFC6131A);
    final isDisabled = isSaving || !hasUnsavedChanges;

    return AnimatedOpacity(
      opacity: isDisabled && !isSaving ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            colors: isSaving
                ? [Colors.grey.shade400, Colors.grey.shade500]
                : [brandRed, brandRedDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: isDisabled
                  ? Colors.transparent
                  : brandRed.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDisabled ? null : onSave,
            hoverColor: Colors.white.withValues(alpha: 0.12),
            splashColor: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSaving)
                    const MLoader(size: 18, color: Colors.white)
                  else
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    isSaving ? 'Saving Changes…' : 'Commit Changes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  const _ModuleAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red.shade700 : _kOverride;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: _kSubtext)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save Status Text
// ─────────────────────────────────────────────────────────────────────────────

/// Shows live unsaved-change status above the save button.
class _StatusText extends StatelessWidget {
  final bool hasUnsaved;
  final int count;
  final bool isSaving;
  const _StatusText({
    required this.hasUnsaved,
    required this.count,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    if (isSaving) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.orange.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Saving to server\u2026',
          style: TextStyle(
            fontSize: 12,
            color: Colors.orange.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]);
    }
    if (!hasUnsaved) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_rounded,
            size: 14, color: Colors.green.shade600),
        const SizedBox(width: 6),
        Text(
          'All changes saved',
          style: TextStyle(
            fontSize: 12,
            color: Colors.green.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.edit_rounded, size: 14, color: Colors.blue.shade600),
      const SizedBox(width: 6),
      Text(
        '$count unsaved change${count == 1 ? '' : 's'}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Dot — Animated pulse indicator for realtime stream status in AppBar
// ─────────────────────────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  final bool isError;
  const _LiveDot({required this.isError});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isError ? Colors.orange.shade300 : Colors.greenAccent;
    return SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, _) => Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
