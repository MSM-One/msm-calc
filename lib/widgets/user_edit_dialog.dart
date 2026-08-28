import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../core/app_permissions.dart';
import '../models/permission_model.dart';

// ────────────────────────────────────────────────────────────────────────────
// Colours & constants
// ────────────────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFE52823);
const _kGray = Color(0xFF2C2C2C);
const _kBlue = Color(0xFF2196F3);
const _kBg = Color(0xFFF8F9FA);
const _kCardRadius = 16.0;

// ────────────────────────────────────────────────────────────────────────────
// Public entry-point — opens the bottom-sheet
// ────────────────────────────────────────────────────────────────────────────
void showUserEditDialog(
  BuildContext context, {
  required UserModel user,
  required Future<void> Function(UserModel) onSave,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UserEditSheet(user: user, onSave: onSave),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Root StatefulWidget
// ────────────────────────────────────────────────────────────────────────────
class _UserEditSheet extends StatefulWidget {
  final UserModel user;
  final Future<void> Function(UserModel) onSave;
  const _UserEditSheet({required this.user, required this.onSave});

  @override
  State<_UserEditSheet> createState() => _UserEditSheetState();
}

class _UserEditSheetState extends State<_UserEditSheet>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  late UserModel _u;
  late List<String> _selectedAccess;
  bool _isSaving = false;

  // Animation controller for the reports expansion
  late AnimationController _reportAnimCtrl;
  late Animation<double> _reportFade;

  final List<String> _accessOptions = const [
    'All Screens',
    'Stock Inventory Only',
    'Stock Sheet Only',
    'Sauda Book Only',
    'Netrate Calc Only',
    'Quotation Only',
    'Sample Rate Only',
    'Reports Only',
  ];

  // ── Init ───────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _u = widget.user;

    final raw = _u.allowedAccess;
    _selectedAccess = raw.isEmpty
        ? ['All Screens']
        : raw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    if (_selectedAccess.isEmpty) _selectedAccess = ['All Screens'];

    _reportAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _u.hasPermission(AppPermissions.reportsView) ? 1.0 : 0.0,
    );
    _reportFade =
        CurvedAnimation(parent: _reportAnimCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _reportAnimCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  UserRole get _role => _u.role;
  bool get _isAdmin => _role == UserRole.admin;

  void _onRoleChanged(UserRole? v) {
    if (v == null) return;
    setState(() {
      final isAdm = v == UserRole.admin;
      final newPerms = Map<String, bool>.from(_u.permissions);

      if (isAdm) {
        // Grant common admin permissions (AccessGuard handles the rest, but UI needs this)
        for (final slug in AppPermissions.allSlugs) {
          newPerms[slug] = true;
        }
      }

      _u = _u.copyWith(
        role: v,
        permissions: newPerms,
      );

      if (isAdm) {
        _reportAnimCtrl.forward();
      } else {
        _reportAnimCtrl.reverse();
      }
    });
  }

  void _onInventoryMasterToggled(bool v) {
    setState(() {
      final newPerms = Map<String, bool>.from(_u.permissions);
      newPerms[AppPermissions.stockIn] = v;
      newPerms[AppPermissions.stockOut] = v;
      newPerms[AppPermissions.stockTransfer] = v;
      _u = _u.copyWith(permissions: newPerms);
    });
  }

  void _onReportsMasterToggled(bool v) {
    setState(() {
      final newPerms = Map<String, bool>.from(_u.permissions);
      newPerms[AppPermissions.reportsView] = v;
      newPerms[AppPermissions.reportsMovement] = v;
      newPerms[AppPermissions.reportsNonMoving] = v;
      newPerms[AppPermissions.reportsTodaySummary] = v;
      newPerms[AppPermissions.reportStockLedger] = v;
      newPerms[AppPermissions.reportLowStock] = v;
      newPerms[AppPermissions.reportsOverview] = v;

      _u = _u.copyWith(permissions: newPerms);

      if (v) {
        _reportAnimCtrl.forward();
      } else {
        _reportAnimCtrl.reverse();
      }
    });
  }

  void _onChipToggled(String option, bool selected) {
    setState(() {
      final newPerms = Map<String, bool>.from(_u.permissions);
      if (option == 'All Screens') {
        if (selected) {
          _selectedAccess = ['All Screens'];
          newPerms[AppPermissions.stockIn] = true;
          newPerms[AppPermissions.stockOut] = true;
          newPerms[AppPermissions.stockTransfer] = true;
          newPerms[AppPermissions.usersDelete] = true; // mapped from canDelete
          newPerms[AppPermissions.reportsView] = true;
          newPerms[AppPermissions.ratesView] = true;
          newPerms[AppPermissions.vendorPurchase] = _u.isAdmin;
          _u = _u.copyWith(permissions: newPerms);
          _reportAnimCtrl.forward();
        }
      } else {
        if (selected) {
          _selectedAccess.remove('All Screens');
          if (!_selectedAccess.contains(option)) {
            _selectedAccess.add(option);
          }
          if (option == 'Stock Inventory Only') {
            newPerms[AppPermissions.stockIn] = true;
            newPerms[AppPermissions.stockOut] = true;
            newPerms[AppPermissions.stockTransfer] = true;
          } else if (option == 'Reports Only') {
            newPerms[AppPermissions.reportsView] = true;
            _reportAnimCtrl.forward();
          } else if (option == 'Netrate Calc Only' ||
              option == 'Quotation Only' ||
              option == 'Sauda Book Only' ||
              option == 'Sample Rate Only') {
            newPerms[AppPermissions.ratesView] = true;
            if (option == 'Sample Rate Only') {
              newPerms[AppPermissions.screensSampleRate] = true;
            }
          }
          _u = _u.copyWith(permissions: newPerms);
        } else {
          _selectedAccess.remove(option);
          if (option == 'Reports Only') {
            newPerms[AppPermissions.reportsView] = false;
            _u = _u.copyWith(permissions: newPerms);
            _reportAnimCtrl.reverse();
          }
          if (_selectedAccess.isEmpty) _selectedAccess = ['All Screens'];
        }
      }
    });
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    // Build a COMPLETE permissions map seeded from role defaults
    final defaults = _u.isAdmin
        ? PermissionRegistry.adminDefaults
        : PermissionRegistry.staffDefaults;
    final newPerms = Map<String, bool>.from(
      defaults.map((k, v) => MapEntry(k, v.isAllowed)),
    );
    // Override with current user's saved permissions
    for (final entry in _u.permissions.entries) {
      newPerms[entry.key] = entry.value;
    }
    newPerms[AppPermissions.vendorPurchase] = _u.isAdmin;
    final finalUser = _u.copyWith(
      allowedAccess: _selectedAccess.join(', '),
      permissions: newPerms,
    );
    try {
      await widget.onSave(finalUser);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      _isAdmin ? Colors.indigo.shade50 : _kRed.withAlpha(20),
                  child: Icon(
                    _isAdmin
                        ? Icons.admin_panel_settings
                        : Icons.person_outline,
                    color: _isAdmin ? Colors.indigo : _kRed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _u.email,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _u.isAdmin
                            ? 'Administrator'
                            : _u.role.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: _u.isAdmin ? Colors.indigo : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_u.isAdmin)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      'ADMIN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Scrollable body ───────────────────────────────────────────────
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shrinkWrap: true,
              children: [
                // ════════════════════════════════════════════════════════════
                // CARD 1: Basic Information
                // ════════════════════════════════════════════════════════════
                _SectionCard(
                  icon: Icons.person_outline,
                  title: 'Basic Information',
                  iconColor: _kBlue,
                  children: [
                    _StyledDropdown<UserRole>(
                      label: 'Role',
                      icon: Icons.badge_outlined,
                      value: _u.role,
                      items: const [UserRole.admin, UserRole.staff],
                      itemLabel: (r) => r.name.toUpperCase(),
                      onChanged: _onRoleChanged,
                    ),
                    const SizedBox(height: 12),
                    _StyledDropdown<String>(
                      label: 'Account Status',
                      icon: Icons.verified_user_outlined,
                      value:
                          ['approved', 'pending', 'blocked'].contains(_u.status)
                              ? _u.status
                              : 'pending',
                      items: const ['approved', 'pending', 'blocked'],
                      itemLabel: (s) => s.toUpperCase(),
                      onChanged: (v) {
                        if (v != null)
                          setState(() => _u = _u.copyWith(status: v));
                      },
                    ),
                    const SizedBox(height: 16),
                    // Allowed Screens Chips
                    const Row(
                      children: [
                        Icon(Icons.display_settings_outlined,
                            size: 14, color: _kGray),
                        SizedBox(width: 6),
                        Text('Allowed Screens',
                            style: TextStyle(
                                fontSize: 12,
                                color: _kGray,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _accessOptions.map((option) {
                        final isSelected = _selectedAccess.contains(option);
                        return FilterChip(
                          label: Text(option,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : _kGray.withValues(alpha: 0.8))),
                          selected: isSelected,
                          onSelected: (s) => _onChipToggled(option, s),
                          selectedColor: _kRed,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                                color:
                                    isSelected ? _kRed : Colors.grey.shade300),
                          ),
                          showCheckmark: isSelected,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ════════════════════════════════════════════════════════════
                // CARD 2: System Access & Permissions
                // ════════════════════════════════════════════════════════════
                _SectionCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Access Management',
                  iconColor: _kRed,
                  children: [
                    // --- GROUP 1: INVENTORY ---
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: const Icon(Icons.inventory_2_outlined,
                            color: _kGray, size: 20),
                        title: const Text('Inventory Operations',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _kGray)),
                        subtitle: Text(
                            (_u.hasPermission(AppPermissions.stockIn) ||
                                    _u.hasPermission(AppPermissions.stockOut) ||
                                    _u.hasPermission(
                                        AppPermissions.stockTransfer))
                                ? 'Active'
                                : 'Restricted',
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    (_u.hasPermission(AppPermissions.stockIn) ||
                                            _u.hasPermission(
                                                AppPermissions.stockOut) ||
                                            _u.hasPermission(
                                                AppPermissions.stockTransfer))
                                        ? Colors.green
                                        : Colors.grey)),
                        trailing: Switch.adaptive(
                          value: _u.isAdmin
                              ? true
                              : (_u.hasPermission(AppPermissions.stockIn) ||
                                  _u.hasPermission(AppPermissions.stockOut) ||
                                  _u.hasPermission(
                                      AppPermissions.stockTransfer)),
                          activeThumbColor: _kRed,
                          onChanged:
                              _u.isAdmin ? null : _onInventoryMasterToggled,
                        ),
                        childrenPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        children: [
                          _PermSwitch(
                            icon: Icons.add_business_outlined,
                            title: 'Stock IN',
                            subtitle: 'Add entries',
                            value: _u.hasPermission(AppPermissions.stockIn),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.stockIn] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _PermSwitch(
                            icon: Icons.local_shipping_outlined,
                            title: 'Stock OUT',
                            subtitle: 'Remove entries',
                            value: _u.hasPermission(AppPermissions.stockOut),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.stockOut] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _PermSwitch(
                            icon: Icons.move_up_outlined,
                            title: 'Transfer',
                            subtitle: 'Move between locations',
                            value:
                                _u.hasPermission(AppPermissions.stockTransfer),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.stockTransfer] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _PermSwitch(
                            icon: Icons.history_edu_outlined,
                            title: 'Reverse/Delete',
                            subtitle: 'Modify history',
                            value: _u.hasPermission(AppPermissions.usersDelete),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.usersDelete] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // --- GROUP 2: REPORTS ---
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: const Icon(Icons.bar_chart_outlined,
                            color: _kRed, size: 20),
                        title: const Text('Reporting Suite',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _kGray)),
                        subtitle: Text(
                            _u.hasPermission(AppPermissions.reportsView)
                                ? 'Full Access'
                                : 'No Access',
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    _u.hasPermission(AppPermissions.reportsView)
                                        ? Colors.green
                                        : Colors.grey)),
                        trailing: Switch.adaptive(
                          value: _u.hasPermission(AppPermissions.reportsView),
                          activeThumbColor: _kRed,
                          onChanged:
                              _u.isAdmin ? null : _onReportsMasterToggled,
                        ),
                        childrenPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        children: [
                          _SubPermSwitch(
                            title: 'Stock Movement',
                            subtitle: 'IN/OUT/Transfer',
                            value: _u
                                .hasPermission(AppPermissions.reportsMovement),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.reportsMovement] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _SubPermSwitch(
                            title: 'Non-Moving',
                            subtitle: 'Dead stock',
                            value: _u
                                .hasPermission(AppPermissions.reportsNonMoving),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.reportsNonMoving] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _SubPermSwitch(
                            title: 'Today Summary',
                            subtitle: 'Daily snapshot',
                            value: _u.hasPermission(
                                AppPermissions.reportsTodaySummary),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.reportsTodaySummary] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _SubPermSwitch(
                            title: 'Stock Ledger',
                            subtitle:
                                'Access to Stock Ledger & Reconciliation Report',
                            value: _u.hasPermission(
                                AppPermissions.reportStockLedger),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.reportStockLedger] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _SubPermSwitch(
                            title: 'Low Stock',
                            subtitle:
                                'Access to Low Stock Alert & Reorder Report',
                            value:
                                _u.hasPermission(AppPermissions.reportLowStock),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.reportLowStock] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _SubPermSwitch(
                            title: 'Stock Overview',
                            subtitle: 'Consolidated',
                            value: _u
                                .hasPermission(AppPermissions.reportsOverview),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.reportsOverview] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // --- GROUP 3: FINANCIALS ---
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.blueGrey,
                            size: 20),
                        title: const Text('Financial & Analytics',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _kGray)),
                        subtitle: const Text('Rates & Purchases',
                            style: TextStyle(fontSize: 11)),
                        childrenPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        children: [
                          _PermSwitch(
                            icon: Icons.price_check,
                            title: 'Check Rates',
                            subtitle: 'Pricing view',
                            value: _u.hasPermission(AppPermissions.ratesView),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.ratesView] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          _PermSwitch(
                            icon: Icons.picture_as_pdf_outlined,
                            title: 'Stock Sheet Access',
                            subtitle: 'Share & export Stock Sheet',
                            value: _u.hasPermission(
                                    AppPermissions.screensStockSheet) ||
                                _u.hasPermission(
                                    AppPermissions.canAccessStockSheet),
                            isLocked: _u.isAdmin,
                            onChanged: _u.isAdmin
                                ? null
                                : (v) {
                                    final p =
                                        Map<String, bool>.from(_u.permissions);
                                    p[AppPermissions.screensStockSheet] = v;
                                    p[AppPermissions.canAccessStockSheet] = v;
                                    setState(
                                        () => _u = _u.copyWith(permissions: p));
                                  },
                          ),
                          // Vendor Purchase Switch Removed: Now Admin-only global restriction
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Sync Progress Bar ──────────────────────────────────────────
                if (_isSaving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        backgroundColor: _kGray.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(_kRed),
                        minHeight: 4,
                      ),
                    ),
                  ),

                // ── Save Button ───────────────────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSaving ? Colors.grey : _kGray,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: _isSaving ? 0 : 4,
                    shadowColor: _kGray.withValues(alpha: 0.3),
                  ),
                  onPressed: _isSaving ? null : _onSave,
                  child: _isSaving
                      ? const Text('SYNCING TO SHEETS...',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2))
                      : const Text(
                          'COMMIT CHANGES',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8),
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;
  final Widget? headerSuffix;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
    this.headerSuffix,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kCardRadius),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (headerSuffix != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: headerSuffix!),
                ],
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?)? onChanged;

  const _StyledDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.itemLabel,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade600),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      initialValue: value,
      items: items
          .map((item) =>
              DropdownMenuItem(value: item, child: Text(itemLabel(item))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _PermSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isLocked;
  final void Function(bool)? onChanged;

  const _PermSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.isLocked = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? _kBlue : Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (isLocked)
            Icon(Icons.lock_outline, size: 14, color: Colors.red.shade300)
          else
            Switch.adaptive(
              value: value,
              activeThumbColor: _kBlue,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

class _MasterSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isLocked;
  final void Function(bool)? onChanged;

  const _MasterSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.isLocked = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: value ? _kRed.withAlpha(10) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value ? _kRed.withAlpha(60) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? _kRed : Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: value ? Colors.black87 : Colors.grey)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (isLocked)
            Icon(Icons.lock_outline, size: 14, color: Colors.red.shade300)
          else
            Switch.adaptive(
              value: value,
              activeThumbColor: _kBlue,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

class _SubPermSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool isLocked;
  final Color accentColor;
  final void Function(bool)? onChanged;

  const _SubPermSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    this.isLocked = false,
    this.accentColor = Colors.blue,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? accentColor : Colors.grey.shade300,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (isLocked)
            Icon(Icons.lock_outline, size: 12, color: Colors.red.shade200)
          else
            Switch.adaptive(
              value: value,
              activeThumbColor: accentColor,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Divider(height: 1, thickness: 1),
      );
}
