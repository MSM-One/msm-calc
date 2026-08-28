import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/user_session_notifier.dart';
import '../models/stock_role.dart';

class ModernFloatingSidebar extends StatefulWidget {
  final String selectedTab;
  final Function(String) onTabChanged;
  final VoidCallback onLogout;

  const ModernFloatingSidebar({
    super.key,
    required this.selectedTab,
    required this.onTabChanged,
    required this.onLogout,
  });

  @override
  State<ModernFloatingSidebar> createState() => _ModernFloatingSidebarState();
}

class _ModernFloatingSidebarState extends State<ModernFloatingSidebar> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) => setState(() => _isExpanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: _isExpanded ? 240 : 80,
        margin: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: ValueListenableBuilder<PermissionSnapshot>(
                valueListenable: UserSessionNotifier.instance,
                builder: (context, snap, _) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 24),
                        _buildLogo(),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: [
                              _NavButton(
                                icon: Icons.dashboard_rounded,
                                label: "Dashboard",
                                isActive: widget.selectedTab == 'Dashboard',
                                isExpanded: _isExpanded,
                                onTap: () => widget.onTabChanged('Dashboard'),
                              ),
                              if (snap.canAccessStockInventory)
                                _NavButton(
                                  icon: Icons.inventory_2_rounded,
                                  label: "Inventory",
                                  isActive: widget.selectedTab == 'Inventory',
                                  isExpanded: _isExpanded,
                                  onTap: () => widget.onTabChanged('Inventory'),
                                ),
                              if (snap.canAccessStockInventory)
                                _NavButton(
                                  icon: Icons.share_rounded,
                                  label: "Stock Sheet",
                                  isActive: widget.selectedTab == 'Stock Sheet',
                                  isExpanded: _isExpanded,
                                  onTap: () =>
                                      widget.onTabChanged('Stock Sheet'),
                                ),
                              if (snap.canAccessSaudaBooking)
                                _NavButton(
                                  icon: Icons.book_rounded,
                                  label: "Sauda Book",
                                  isActive: widget.selectedTab == 'Sauda Book',
                                  isExpanded: _isExpanded,
                                  onTap: () =>
                                      widget.onTabChanged('Sauda Book'),
                                ),
                              if (snap.canAccessReports)
                                _NavButton(
                                  icon: Icons.insert_chart_rounded,
                                  label: "Reports",
                                  isActive: widget.selectedTab == 'Reports',
                                  isExpanded: _isExpanded,
                                  onTap: () => widget.onTabChanged('Reports'),
                                ),
                              if (snap.canAccessQuotation)
                                _NavButton(
                                  icon: Icons.description_rounded,
                                  label: "Quotations",
                                  isActive: widget.selectedTab == 'Quotations',
                                  isExpanded: _isExpanded,
                                  onTap: () =>
                                      widget.onTabChanged('Quotations'),
                                ),
                              if (snap.canAccessCalculator)
                                _NavButton(
                                  icon: Icons.calculate_rounded,
                                  label: "Netrate Calc",
                                  isActive:
                                      widget.selectedTab == 'Netrate Calc',
                                  isExpanded: _isExpanded,
                                  onTap: () =>
                                      widget.onTabChanged('Netrate Calc'),
                                ),
                              if (snap.canAccessSampleRate)
                                _NavButton(
                                  icon: Icons.bolt_rounded,
                                  label: "Sample Rate",
                                  isActive: widget.selectedTab == 'Sample Rate',
                                  isExpanded: _isExpanded,
                                  onTap: () =>
                                      widget.onTabChanged('Sample Rate'),
                                ),
                              if (snap.canAccessUsers)
                                _NavButton(
                                  icon: Icons.people_rounded,
                                  label: "Users",
                                  isActive: widget.selectedTab == 'Users',
                                  isExpanded: _isExpanded,
                                  onTap: () => widget.onTabChanged('Users'),
                                ),
                              if (snap.role == StockRole.ADMIN)
                                _NavButton(
                                  icon: Icons.rule_rounded,
                                  label: "Master Size",
                                  isActive: widget.selectedTab == 'Master Size',
                                  isExpanded: _isExpanded,
                                  onTap: () =>
                                      widget.onTabChanged('Master Size'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _NavButton(
                          icon: Icons.logout_rounded,
                          label: "Sign Out",
                          isActive: false,
                          isExpanded: _isExpanded,
                          onTap: widget.onLogout,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF0000).withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.2),
            blurRadius: 5,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          "M",
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black26,
                offset: Offset(2, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isExpanded;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          width: isExpanded
              ? 220
              : 54, // Reduced from 60 to fit within 80-12-12=56px area
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              vertical: 12,
              horizontal: isExpanded
                  ? 16
                  : 0, // No horizontal padding in slim to allow center alignment
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFFFF0000).withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isActive ? const Color(0xFFFF0000) : Colors.black54,
                  size: 22, // Slightly smaller for better fit
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color:
                            isActive ? const Color(0xFFFF0000) : Colors.black87,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
