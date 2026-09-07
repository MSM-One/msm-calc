import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/user_session_notifier.dart';
import 'app_version_badge.dart';

class AppDrawerItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isVisible;

  const AppDrawerItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
    this.isVisible = true,
  });
}

/// Standardized navigation drawer for MSM Calc with dynamic version footer.
class AppDrawer extends StatelessWidget {
  final List<AppDrawerItem> items;
  final VoidCallback onLogout;

  const AppDrawer({
    super.key,
    required this.items,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((i) => i.isVisible).toList();

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            // Drawer Header with MSM branding & User info
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 20,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA),
                border: Border(bottom: BorderSide(color: borderLight)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderLight),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/msm_app_icon.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.calculate_rounded,
                          color: msmRed,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Metaroll Steel Mart',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        ValueListenableBuilder<PermissionSnapshot>(
                          valueListenable: UserSessionNotifier.instance,
                          builder: (context, snap, _) {
                            final role = snap.role.name;
                            return Text(
                              role.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: msmRed,
                                letterSpacing: 0.5,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: visibleItems.length,
                itemBuilder: (context, index) {
                  final item = visibleItems[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: item.isSelected
                          ? msmRed.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                          item.onTap();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                item.icon,
                                size: 18,
                                color: item.isSelected ? msmRed : textGrey,
                              ),
                              const SizedBox(width: 14),
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: item.isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: item.isSelected ? msmRed : textGrey,
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

            // Footer Section
            const Divider(height: 1, color: borderLight),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                    onLogout();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: textGrey.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 14),
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
            ),

            // Dynamic App Version text pinned cleanly at bottom above SafeArea
            const Padding(
              padding: EdgeInsets.only(bottom: 12, top: 2),
              child: AppVersionBadge(),
            ),
          ],
        ),
      ),
    );
  }
}
