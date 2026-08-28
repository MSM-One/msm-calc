import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/app_permissions.dart';
import '../services/access_guard.dart';
import '../services/session_guard_service.dart';
import '../constants/app_colors.dart';
import '../main.dart' hide DashboardScreen;
import '../screens/dashboard_screen.dart';
import '../screens/main_inventory_shell.dart';
import '../screens/sauda_booking_screen.dart';
import '../screens/professional_reports_screen.dart';
import '../screens/manage_users_screen.dart';
import '../screens/calculator_screen.dart';
import '../screens/quick_rate_calculator_screen.dart';
import '../providers/inventory_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/m_loader.dart';
import 'package:intl/intl.dart';
import 'modern_floating_sidebar.dart';
import '../models/user_session_notifier.dart';
import '../services/auth_service.dart';
import '../models/stock_role.dart';

import '../screens/master_size_management_screen.dart';
import '../screens/dealer_stock_share_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  final GoogleSignIn _googleSignIn = AuthService.googleSignIn;

  // ── Security Session Guard key (passed to guard so it can navigate) ───────
  // We reuse the app-level key defined in main.dart.
  static final GlobalKey<NavigatorState> _navKey = appNavigatorKey;

  @override
  void initState() {
    super.initState();
    // Attach real-time eviction guard immediately after scaffold mounts.
    // Skipped for super-admin and skipped when there is no email (already
    // guarded inside the service).
    SessionGuardService.attach(_navKey);
  }

  @override
  void dispose() {
    SessionGuardService.detach();
    super.dispose();
  }

  // Define Navigation Items with Permissions
  List<NavMenuItem> _getAllMenuItems() {
    return [
      NavMenuItem(
        title: 'Dashboard',
        icon: FontAwesomeIcons.gaugeHigh,
        screen: const DashboardScreen(),
        permission: AppPermissions.screensDashboard,
      ),
      NavMenuItem(
        title: 'Inventory',
        icon: FontAwesomeIcons.boxesStacked,
        screen: const MainInventoryShell(),
        permission: AppPermissions.inventoryScreen,
      ),
      NavMenuItem(
        title: 'Stock Sheet',
        icon: FontAwesomeIcons.shareNodes,
        screen: const DealerStockShareScreen(),
        permission: AppPermissions.inventoryScreen,
      ),
      NavMenuItem(
        title: 'Sauda Book',
        icon: FontAwesomeIcons.bookOpen,
        screen: const SaudaBookingScreen(),
        permission: AppPermissions.screensSaudaBooking,
      ),
      NavMenuItem(
        title: 'Reports',
        icon: FontAwesomeIcons.chartColumn,
        screen: const ProfessionalReportsScreen(),
        permission: AppPermissions.reportsScreen,
      ),
      NavMenuItem(
        title: 'Quotations',
        icon: FontAwesomeIcons.fileInvoiceDollar,
        screen: const CalculatorScreen(isQuotationMode: true),
        permission: AppPermissions.screensQuotation,
      ),
      NavMenuItem(
        title: 'Netrate Calc',
        icon: FontAwesomeIcons.calculator,
        screen: const CalculatorScreen(isQuotationMode: false),
        permission: AppPermissions.screensCalculator,
      ),
      NavMenuItem(
        title: 'Sample Rate',
        icon: FontAwesomeIcons.bolt,
        screen: const SampleRateCalcScreen(),
        permission: AppPermissions.screensSampleRate,
      ),
      NavMenuItem(
        title: 'Users',
        icon: FontAwesomeIcons.usersGear,
        screen: const ManageUsersScreen(),
        permission: AppPermissions.screensUsers,
      ),
      NavMenuItem(
        title: 'Master Size',
        icon: FontAwesomeIcons.listCheck,
        screen: const MasterSizeManagementScreen(),
        permission: AppPermissions.screensMasterSize,
      ),
    ];
  }

  List<NavMenuItem> _getFilteredItems() {
    return _getAllMenuItems().where((item) {
      if (item.permission == 'admin_only') {
        return UserSession.isUserAdmin;
      }
      if (item.permission == null) return true;
      return AccessGuard.can(item.permission!);
    }).toList();
  }

  void _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, snapshot, _) {
        final filteredItems = _getFilteredItems();

        // Ensure selected index is within bounds if permissions changed
        if (_selectedIndex >= filteredItems.length) {
          _selectedIndex = 0;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;

            return Scaffold(
              backgroundColor: const Color(0xFFFFF8F8),
              body: Row(
                children: [
                  if (isDesktop)
                    ModernFloatingSidebar(
                      selectedTab: filteredItems[_selectedIndex].title,
                      onTabChanged: (tabTitle) {
                        final index = filteredItems
                            .indexWhere((item) => item.title == tabTitle);
                        if (index != -1) {
                          setState(() => _selectedIndex = index);
                        }
                      },
                      onLogout: _handleLogout,
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children:
                          filteredItems.map((item) => item.screen).toList(),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: null, // Follows modern dashboard style
            );
          },
        );
      },
    );
  }

  Widget _buildMobileBottomNav(List<NavMenuItem> allItems) {
    // Define the titles we want to show on the bottom nav for mobile
    final mobileTitles = [
      'Dashboard',
      'Inventory',
      'Sauda Book',
      'Reports',
      'Users'
    ];

    // Filter allowed items that match our mobile titles
    final navItems =
        allItems.where((item) => mobileTitles.contains(item.title)).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      color: Colors.transparent, // Background of the area
      child: Container(
        height: 65,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: navItems.map((item) {
              final isSelected = allItems[_selectedIndex].title == item.title;
              return Expanded(
                child: InkWell(
                  onTap: () {
                    final index = allItems.indexOf(item);
                    if (index != -1) {
                      setState(() => _selectedIndex = index);
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? msmRed.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: FaIcon(
                          item.icon,
                          size: 20,
                          color: isSelected ? msmRed : textGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? msmRed : textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showMoreMenu(List<NavMenuItem> allItems, List<NavMenuItem> moreItems) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ...moreItems.map((item) {
                return ListTile(
                  leading: FaIcon(item.icon,
                      size: 20, color: const Color(0xFF1F1A1A)),
                  title: Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final actualIndex = allItems.indexOf(item);
                    setState(() => _selectedIndex = actualIndex);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class NavMenuItem {
  final String title;
  final dynamic icon;
  final String? permission;
  final Widget screen;
  NavMenuItem({
    required this.title,
    required this.icon,
    required this.screen,
    this.permission,
  });
}

// ─── Premium Sidebar ───────────────────────────────────────────────────────
class _PremiumSidebar extends StatefulWidget {
  final int selectedIndex;
  final List<NavMenuItem> items;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onLogout;

  const _PremiumSidebar({
    required this.selectedIndex,
    required this.items,
    required this.onDestinationSelected,
    required this.onLogout,
  });

  @override
  State<_PremiumSidebar> createState() => _PremiumSidebarState();
}

class _PremiumSidebarState extends State<_PremiumSidebar> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFFF8F9FA),
      child: Column(
        children: [
          // ── Logo ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Image.asset(
              'assets/msm_app_icon.png',
              height: 52,
              fit: BoxFit.contain,
            ),
          ),
          const Divider(height: 1, color: borderLight),
          const SizedBox(height: 12),

          // ── Nav items ────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final isSelected = widget.selectedIndex == index;
                final isHovered = _hoveredIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hoveredIndex = index),
                    onExit: (_) => setState(() => _hoveredIndex = null),
                    child: GestureDetector(
                      onTap: () => widget.onDestinationSelected(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? msmRed.withValues(alpha: 0.07)
                              : isHovered
                                  ? Colors.black.withValues(alpha: 0.04)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            // Thick red left border for selected item
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 3,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isSelected ? msmRed : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(3),
                                  bottomRight: Radius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FaIcon(
                              item.icon,
                              size: 18,
                              color: isSelected ? msmRed : textGrey,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected ? msmRed : textGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Bottom area ──────────────────────────────────────────────────
          const Divider(height: 1, color: borderLight),
          const _LiveSyncStatusBar(),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: widget.onLogout,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded,
                        color: textGrey.withValues(alpha: 0.7), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textGrey.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ───────────────────────────────────────────────────────────────────────────

class _LiveSyncStatusBar extends StatefulWidget {
  const _LiveSyncStatusBar();

  @override
  State<_LiveSyncStatusBar> createState() => _LiveSyncStatusBarState();
}

class _LiveSyncStatusBarState extends State<_LiveSyncStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, provider, _) {
        if (!provider.isDesktopOrWeb) return const SizedBox.shrink();

        final timeStr = provider.lastUpdated != null
            ? DateFormat('h:mm a').format(provider.lastUpdated!)
            : 'Never';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _blinkController,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Live Sync: Active",
                    style: TextStyle(
                      color: textGrey.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Last: $timeStr",
                    style: TextStyle(
                      color: textGrey.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (provider.isBackgroundSyncing)
                    const MLoader(size: 10)
                  else
                    InkWell(
                      onTap: () => provider.refreshData(),
                      child: Icon(Icons.refresh_rounded,
                          size: 12, color: msmRed.withValues(alpha: 0.6)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
