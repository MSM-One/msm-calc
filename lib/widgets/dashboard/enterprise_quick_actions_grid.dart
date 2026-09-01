import 'package:flutter/material.dart';
import '../../models/user_session_notifier.dart';
import '../../models/stock_role.dart';
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

/// Item descriptor for quick action tiles.
class QuickActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final bool isPrimary;
  final VoidCallback onTap;

  const QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    this.isPrimary = false,
    required this.onTap,
  });
}

/// High-Density Enterprise Quick Actions Grid.
/// Renders compact, uniform height tiles with 24px icon in subtle container,
/// bold title (13px, FontWeight.w600), and concise subtitle (11px).
class EnterpriseQuickActionsGrid extends StatelessWidget {
  const EnterpriseQuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, snap, _) {
        final List<QuickActionItem> primaryActions = [
          if (snap.canAccessStockInventory)
            QuickActionItem(
              title: 'Inventory In & Out',
              subtitle: 'Manage inward, outward & stock',
              icon: Icons.inventory_2_rounded,
              iconColor: const Color(0xFFD32F2F),
              iconBgColor: const Color(0xFFFEF2F2),
              isPrimary: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessStockInventory,
                    screenName: 'Inventory In & Out',
                    child: const MainInventoryShell(),
                  ),
                ),
              ),
            ),
          if (snap.canAccessSaudaBooking)
            QuickActionItem(
              title: 'Sauda Booking',
              subtitle: 'Contract rates & bookings',
              icon: Icons.menu_book_rounded,
              iconColor: const Color(0xFFD32F2F),
              iconBgColor: const Color(0xFFFEF2F2),
              isPrimary: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessSaudaBooking,
                    screenName: 'Sauda Book',
                    child: const SaudaBookingScreen(),
                  ),
                ),
              ),
            ),
          if (snap.canAccessReports)
            QuickActionItem(
              title: 'Reports Dashboard',
              subtitle: 'Analytics, ledger & movement',
              icon: Icons.bar_chart_rounded,
              iconColor: const Color(0xFFD32F2F),
              iconBgColor: const Color(0xFFFEF2F2),
              isPrimary: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessReports,
                    screenName: 'Reports',
                    child: const ReportsDashboardScreen(),
                  ),
                ),
              ),
            ),
          if (snap.canAccessCalculator)
            QuickActionItem(
              title: 'Netrate Calc',
              subtitle: 'Instant net rate calculator',
              icon: Icons.calculate_outlined,
              iconColor: const Color(0xFFD32F2F),
              iconBgColor: const Color(0xFFFEF2F2),
              isPrimary: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessCalculator,
                    screenName: 'Netrate Calc',
                    child: const CalculatorScreen(isQuotationMode: false),
                  ),
                ),
              ),
            ),
        ];

        final List<QuickActionItem> secondaryActions = [
          if (snap.canAccessVendorPurchaseScreen)
            QuickActionItem(
              title: 'Vendor Purchase',
              subtitle: 'Vendor orders & dispatches',
              icon: Icons.local_shipping_outlined,
              iconColor: const Color(0xFF2563EB),
              iconBgColor: const Color(0xFFEFF6FF),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessVendorPurchaseScreen,
                    screenName: 'Vendor Purchase',
                    child: const VendorPurchaseReportScreen(),
                  ),
                ),
              ),
            ),
          if (snap.canAccessStockInventory)
            QuickActionItem(
              title: 'Stock Sheet',
              subtitle: 'Dealer & internal share sheet',
              icon: Icons.share_rounded,
              iconColor: const Color(0xFF059669),
              iconBgColor: const Color(0xFFECFDF5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessStockInventory,
                    screenName: 'Stock Sheet',
                    child: const DealerStockShareScreen(),
                  ),
                ),
              ),
            ),
          if (snap.canAccessQuotation)
            QuickActionItem(
              title: 'Quotations',
              subtitle: 'Customer estimates & rates',
              icon: Icons.description_rounded,
              iconColor: const Color(0xFFD97706),
              iconBgColor: const Color(0xFFFEF3C7),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessQuotation,
                    screenName: 'Quotation',
                    child: const CalculatorScreen(isQuotationMode: true),
                  ),
                ),
              ),
            ),
          if (snap.canAccessSampleRate)
            QuickActionItem(
              title: 'Sample Rate',
              subtitle: 'Sample rate conversions',
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFF7C3AED),
              iconBgColor: const Color(0xFFF5F3FF),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessSampleRate,
                    screenName: 'Sample Rate',
                    child: const SampleRateCalcScreen(),
                  ),
                ),
              ),
            ),
          if (snap.role == StockRole.ADMIN)
            QuickActionItem(
              title: 'Sales Document Center',
              subtitle: 'Invoices, DOs & gate passes',
              icon: Icons.assignment_turned_in_outlined,
              iconColor: const Color(0xFF1E293B),
              iconBgColor: const Color(0xFFF1F5F9),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.role == StockRole.ADMIN,
                    screenName: 'Sales Document Center',
                    child: const SalesDocumentCenterScreen(),
                  ),
                ),
              ),
            ),
          if (snap.canAccessMasterSize)
            QuickActionItem(
              title: 'Master Size',
              subtitle: 'Section weight & size matrix',
              icon: Icons.rule_rounded,
              iconColor: const Color(0xFF0891B2),
              iconBgColor: const Color(0xFFECFEFF),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) => s.canAccessMasterSize,
                    screenName: 'Master Size',
                    child: const MasterSizeManagementScreen(),
                  ),
                ),
              ),
            ),
          if (snap.role == StockRole.ADMIN || snap.canAccessUsers)
            QuickActionItem(
              title: 'Users',
              subtitle: 'Roles & user permissions',
              icon: Icons.people_rounded,
              iconColor: const Color(0xFF475569),
              iconBgColor: const Color(0xFFF8FAFC),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScreenGate(
                    canAccess: (s) =>
                        s.role == StockRole.ADMIN || s.canAccessUsers,
                    screenName: 'Users',
                    child: const ManageUsersScreen(),
                  ),
                ),
              ),
            ),
        ];

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 18,
                        color: Color(0xFFD32F2F),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Direct Module Launch',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Section 1: Primary Operations
              if (primaryActions.isNotEmpty) ...[
                const Text(
                  'CORE OPERATIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                _buildActionGrid(primaryActions),
                const SizedBox(height: 18),
              ],

              // Section 2: Management & Utilities
              if (secondaryActions.isNotEmpty) ...[
                const Text(
                  'MANAGEMENT & UTILITIES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                _buildActionGrid(secondaryActions),
              ],
            ],
          ),
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
        } else if (width < 960) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 82, // Uniform compact height ~82px
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          transform: _isHovered
              ? Matrix4.translationValues(0, -2, 0)
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: item.isPrimary
                ? (_isHovered
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFFAFAFA))
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered
                  ? (item.isPrimary
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF94A3B8))
                  : (item.isPrimary
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFE2E8F0)),
              width: _isHovered ? 1.2 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? (item.isPrimary
                        ? const Color(0xFFD32F2F).withValues(alpha: 0.1)
                        : const Color(0xFF0F172A).withValues(alpha: 0.06))
                    : const Color(0xFF0F172A).withValues(alpha: 0.02),
                blurRadius: _isHovered ? 8 : 4,
                offset: Offset(0, _isHovered ? 3 : 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon Box
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: item.iconColor.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.icon,
                  size: 20,
                  color: item.iconColor,
                ),
              ),
              const SizedBox(width: 10),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: item.isPrimary && _isHovered
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Subtle Arrow Indicator on hover
              if (_isHovered)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: item.iconColor.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
