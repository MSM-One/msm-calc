import 'package:flutter/material.dart';
import '../../models/user_session_notifier.dart';
import '../../models/stock_role.dart';
import '../../services/data_repository.dart';
import '../../widgets/screen_gate.dart';
import '../../screens/main_inventory_shell.dart';
import '../../screens/sauda_booking_screen.dart';
import '../../screens/reports/reports_dashboard_screen.dart';
import '../../screens/calculator_screen.dart';
import '../../screens/sauda_report_screen.dart';
import '../../screens/dealer_stock_share_screen.dart';
import '../../screens/quick_rate_calculator_screen.dart';
import '../../screens/sales_document_center_screen.dart';
import '../../screens/master_size_management_screen.dart';
import '../../screens/manage_users_screen.dart';
import '../../services/access_guard.dart';
import '../../core/app_permissions.dart';
import '../../constants/enterprise_design_tokens.dart';

/// Item descriptor for quick action tiles.
class QuickActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final Color iconBorderColor;
  final bool isCoreOperation;
  final bool hasSelectionHighlight;
  final VoidCallback onTap;

  const QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.iconBorderColor,
    this.isCoreOperation = false,
    this.hasSelectionHighlight = false,
    required this.onTap,
  });
}

/// Organized Categorical Quick Actions Grid for Executive ERP Command Center.
/// Features high density, crisp 1px borders, subtle elevation, and refined enterprise color palette.
class EnterpriseQuickActionsGrid extends StatelessWidget {
  const EnterpriseQuickActionsGrid({super.key});

  static const Set<String> _salesOnlyAllowedTitles = {
    'Quotation',
    'Netrate Calc',
    'Sample Rate',
    'Sales Document Center',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DataRepository.salesOnlyModeNotifier,
      builder: (context, isSalesOnly, _) {
        return ValueListenableBuilder<PermissionSnapshot>(
          valueListenable: UserSessionNotifier.instance,
          builder: (context, snap, _) {
            final bool isRestricted = isSalesOnly &&
                !UserSession.isSuperAdmin &&
                !snap.isAdmin &&
                !UserSession.isUserAdmin;

            // ---------------- CATEGORY 1: CORE OPERATIONS ----------------
            final List<QuickActionItem> coreOperations = [
              if (snap.isAdmin || snap.canAccessStockInventory)
                QuickActionItem(
                  title: 'Inventory In & Out',
                  subtitle: 'Manage inward, outward & stock',
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFFCC2127),
                  iconBgColor: const Color(0xFFFEF3F2),
                  iconBorderColor: const Color(0xFFFECDCA),
                  isCoreOperation: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) =>
                            s.isAdmin || s.canAccessStockInventory,
                        screenName: 'Inventory In & Out',
                        child: const MainInventoryShell(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.canAccessSaudaBooking)
                QuickActionItem(
                  title: 'Sauda & Delivery Order',
                  subtitle: 'Contract rates & bookings',
                  icon: Icons.menu_book_outlined,
                  iconColor: const Color(0xFFCC2127),
                  iconBgColor: const Color(0xFFFEF3F2),
                  iconBorderColor: const Color(0xFFFECDCA),
                  isCoreOperation: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) => s.isAdmin || s.canAccessSaudaBooking,
                        screenName: 'Sauda Book',
                        child: const SaudaBookingScreen(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.canAccessReports)
                QuickActionItem(
                  title: 'Reports Dashboard',
                  subtitle: 'Analytics, ledger & movement',
                  icon: Icons.bar_chart_rounded,
                  iconColor: const Color(0xFFCC2127),
                  iconBgColor: const Color(0xFFFEF3F2),
                  iconBorderColor: const Color(0xFFFECDCA),
                  isCoreOperation: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) => s.isAdmin || s.canAccessReports,
                        screenName: 'Reports',
                        child: const ReportsDashboardScreen(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.canAccessCalculator)
                QuickActionItem(
                  title: 'Netrate Calc',
                  subtitle: 'Instant net rate calculator',
                  icon: Icons.calculate_outlined,
                  iconColor: const Color(0xFFCC2127),
                  iconBgColor: const Color(0xFFFEF3F2),
                  iconBorderColor: const Color(0xFFFECDCA),
                  isCoreOperation: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) => s.isAdmin || s.canAccessCalculator,
                        screenName: 'Netrate Calc',
                        child: const CalculatorScreen(isQuotationMode: false),
                      ),
                    ),
                  ),
                ),
            ];

            // ---------------- CATEGORY 2: MANAGEMENT & UTILITIES ----------------
            final List<QuickActionItem> managementUtilities = [
              if (snap.isAdmin || snap.canAccessVendorPurchaseScreen)
                QuickActionItem(
                  title: 'Vendor Purchase',
                  subtitle: 'Vendor orders & dispatches',
                  icon: Icons.shopping_bag_outlined,
                  iconColor: const Color(0xFF0284C7), // Blue 600
                  iconBgColor: const Color(0xFFF0F9FF), // Sky 50
                  iconBorderColor: const Color(0xFFBAE6FD), // Sky 200
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) =>
                            s.isAdmin || s.canAccessVendorPurchaseScreen,
                        screenName: 'Vendor Purchase',
                        child: const VendorPurchaseReportScreen(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.canAccessStockSheet)
                QuickActionItem(
                  title: 'Stock Sheet',
                  subtitle: 'Dealer & internal share sheet',
                  icon: Icons.table_chart_outlined,
                  iconColor: const Color(0xFF059669), // Emerald 600
                  iconBgColor: const Color(0xFFECFDF5), // Emerald 50
                  iconBorderColor: const Color(0xFFA7F3D0), // Emerald 200
                  hasSelectionHighlight: true,
                  onTap: () {
                    if (!snap.isAdmin &&
                        !AccessGuard.can(AppPermissions.screensStockSheet) &&
                        !AccessGuard.can(AppPermissions.canAccessStockSheet)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              "Restricted Access: You do not have permission to view the Stock Sheet screen."),
                          backgroundColor: Color(0xFFD92D20),
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScreenGate(
                          canAccess: (s) => s.isAdmin || s.canAccessStockSheet,
                          screenName: 'Stock Sheet',
                          child: const DealerStockShareScreen(),
                        ),
                      ),
                    );
                  },
                ),
              if (snap.isAdmin || snap.canAccessQuotation)
                QuickActionItem(
                  title: 'Quotation',
                  subtitle: 'Customer estimates & rates',
                  icon: Icons.receipt_long_outlined,
                  iconColor: const Color(0xFFD97706), // Amber 600
                  iconBgColor: const Color(0xFFFFFBEB), // Amber 50
                  iconBorderColor: const Color(0xFFFDE68A), // Amber 200
                  hasSelectionHighlight: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) => s.isAdmin || s.canAccessQuotation,
                        screenName: 'Quotation',
                        child: const CalculatorScreen(isQuotationMode: true),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.canAccessSampleRate)
                QuickActionItem(
                  title: 'Sample Rate',
                  subtitle: 'Sample rate conversions',
                  icon: Icons.tune_rounded,
                  iconColor: const Color(0xFF7C3AED), // Violet 600
                  iconBgColor: const Color(0xFFF5F3FF), // Violet 50
                  iconBorderColor: const Color(0xFFDDD6FE), // Violet 200
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) => s.isAdmin || s.canAccessSampleRate,
                        screenName: 'Sample Rate',
                        child: const SampleRateCalcScreen(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.role == StockRole.ADMIN || isRestricted)
                QuickActionItem(
                  title: 'Sales Document Center',
                  subtitle: 'Invoices, DOs & gate passes',
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF2563EB), // Blue 600
                  iconBgColor: const Color(0xFFEFF6FF), // Blue 50
                  iconBorderColor: const Color(0xFFBFDBFE), // Blue 200
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) =>
                            s.isAdmin ||
                            s.role == StockRole.ADMIN ||
                            isRestricted,
                        screenName: 'Sales Document Center',
                        child: const SalesDocumentCenterScreen(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin || snap.canAccessMasterSize)
                QuickActionItem(
                  title: 'Master Size',
                  subtitle: 'Section weight & size matrix',
                  icon: Icons.straighten_outlined,
                  iconColor: const Color(0xFF0891B2), // Cyan 600
                  iconBgColor: const Color(0xFFECFEFF), // Cyan 50
                  iconBorderColor: const Color(0xFFCFFAFE), // Cyan 200
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) => s.isAdmin || s.canAccessMasterSize,
                        screenName: 'Master Size',
                        child: const MasterSizeManagementScreen(),
                      ),
                    ),
                  ),
                ),
              if (snap.isAdmin ||
                  snap.role == StockRole.ADMIN ||
                  snap.canAccessUsers)
                QuickActionItem(
                  title: 'Users',
                  subtitle: 'Roles & user permissions',
                  icon: Icons.people_outline_rounded,
                  iconColor: const Color(0xFF475467), // Slate 600
                  iconBgColor: const Color(0xFFF8FAFC), // Slate 50
                  iconBorderColor: const Color(0xFFE2E8F0), // Slate 200
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScreenGate(
                        canAccess: (s) =>
                            s.isAdmin ||
                            s.role == StockRole.ADMIN ||
                            s.canAccessUsers,
                        screenName: 'Users',
                        child: const ManageUsersScreen(),
                      ),
                    ),
                  ),
                ),
            ];

            final List<QuickActionItem> finalCore = isRestricted
                ? coreOperations
                    .where((a) => _salesOnlyAllowedTitles.contains(a.title))
                    .toList()
                : coreOperations;
            final List<QuickActionItem> finalManagement = isRestricted
                ? managementUtilities
                    .where((a) => _salesOnlyAllowedTitles.contains(a.title))
                    .toList()
                : managementUtilities;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: EnterpriseColors.cardSurface,
                borderRadius: EnterpriseBorders.r14,
                border:
                    Border.all(color: EnterpriseColors.borderLight, width: 1),
                boxShadow: EnterpriseShadows.elevation1,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Row: Grid icon + "Quick Actions", right side subtext "Direct Module Launch"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFFECDCA),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.grid_view_rounded,
                              size: 16,
                              color: Color(0xFFCC2127),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Direct Module Launch',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Section 1: CORE OPERATIONS (prefixed by vertical red accent bar)
                  if (finalCore.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          width: 3.5,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCC2127),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'CORE OPERATIONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildActionGrid(finalCore),
                    const SizedBox(height: 20),
                  ],

                  // Section 2: MANAGEMENT & UTILITIES (prefixed by vertical slate accent bar)
                  if (finalManagement.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          width: 3.5,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFF64748B),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'MANAGEMENT & UTILITIES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildActionGrid(finalManagement),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionGrid(List<QuickActionItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int crossAxisCount = 4;
        if (width < 600) {
          crossAxisCount = 2;
        } else if (width < 900) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 78,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _ActionTile(item: items[index]);
          },
        );
      },
    );
  }
}

class _ActionTile extends StatefulWidget {
  final QuickActionItem item;

  const _ActionTile({required this.item});

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeInOut,
          transform: _isHovered
              ? Matrix4.translationValues(0, -2, 0)
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? EnterpriseColors.cardSurfaceHover
                : EnterpriseColors.backgroundSecondary,
            borderRadius: EnterpriseBorders.r10,
            border: Border.all(
              color: _isHovered
                  ? item.iconColor.withValues(alpha: 0.5)
                  : EnterpriseColors.borderLight,
              width: 1.0,
            ),
            boxShadow: _isHovered ? EnterpriseShadows.elevation1 : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.iconBgColor,
                  borderRadius: EnterpriseBorders.r8,
                  border: Border.all(color: item.iconBorderColor, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.icon,
                  size: 17,
                  color: item.iconColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: EnterpriseColors.darkNavy,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: EnterpriseColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (item.hasSelectionHighlight)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: EnterpriseColors.textSubtle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
