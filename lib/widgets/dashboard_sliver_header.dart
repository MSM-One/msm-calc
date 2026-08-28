import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class DashboardSliverHeader extends StatelessWidget {
  final String userName;
  final String companyName;
  final bool isSyncing;
  final VoidCallback onRefresh;
  final VoidCallback onProfileTap;
  final VoidCallback? onLogout;

  const DashboardSliverHeader({
    super.key,
    required this.userName,
    required this.companyName,
    required this.isSyncing,
    required this.onRefresh,
    required this.onProfileTap,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final minHeight = 88.0 + topPadding;
    final maxHeight = 200.0 + topPadding;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _DashboardSliverHeaderDelegate(
        userName: userName,
        companyName: companyName,
        isSyncing: isSyncing,
        onRefresh: onRefresh,
        onProfileTap: onProfileTap,
        onLogout: onLogout,
        minHeight: minHeight,
        maxHeight: maxHeight,
        topPadding: topPadding,
      ),
    );
  }
}

class _DashboardSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String userName;
  final String companyName;
  final bool isSyncing;
  final VoidCallback onRefresh;
  final VoidCallback onProfileTap;
  final VoidCallback? onLogout;
  final double minHeight;
  final double maxHeight;
  final double topPadding;

  _DashboardSliverHeaderDelegate({
    required this.userName,
    required this.companyName,
    required this.isSyncing,
    required this.onRefresh,
    required this.onProfileTap,
    this.onLogout,
    required this.minHeight,
    required this.maxHeight,
    required this.topPadding,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  bool shouldRebuild(covariant _DashboardSliverHeaderDelegate oldDelegate) {
    return oldDelegate.userName != userName ||
        oldDelegate.isSyncing != isSyncing ||
        oldDelegate.companyName != companyName;
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final reverseProgress = 1.0 - progress;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [msmRed, kMetarollRed],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28 * reverseProgress),
          bottomRight: Radius.circular(28 * reverseProgress),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x308B0000)
                .withValues(alpha: 0.3 * reverseProgress),
            blurRadius: 20 * reverseProgress,
            offset: Offset(0, 8 * reverseProgress),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: CircleAvatar(
              radius: 60,
              backgroundColor:
                  Colors.white.withValues(alpha: 0.03 * reverseProgress),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                              width: 1),
                        ),
                        child: Text(
                          companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      _ProfileButton(
                        userName: userName,
                        companyName: companyName,
                        onProfileTap: onProfileTap,
                        onLogout: onLogout,
                      ),
                    ],
                  ),
                  if (reverseProgress > 0)
                    Expanded(
                      child: Opacity(
                        opacity: (reverseProgress * 2 - 1.0).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -20 * progress),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Welcome back,",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      userName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text("👋",
                                      style: TextStyle(fontSize: 26)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final String userName;
  final String companyName;
  final VoidCallback onProfileTap;
  final VoidCallback? onLogout;

  const _ProfileButton({
    required this.userName,
    required this.companyName,
    required this.onProfileTap,
    this.onLogout,
  });

  String get _initial => userName.isNotEmpty ? userName[0].toUpperCase() : "U";

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showProfileMenu(context),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _initial,
          style: const TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ProfileMenuBottomSheet(
        userName: userName,
        companyName: companyName,
        onProfileTap: () {
          Navigator.pop(context);
          onProfileTap();
        },
        onLogout: onLogout != null
            ? () {
                Navigator.pop(context);
                onLogout!();
              }
            : null,
      ),
    );
  }
}

class _ProfileMenuBottomSheet extends StatelessWidget {
  final String userName;
  final String companyName;
  final VoidCallback onProfileTap;
  final VoidCallback? onLogout;

  const _ProfileMenuBottomSheet({
    required this.userName,
    required this.companyName,
    required this.onProfileTap,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24),
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
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: msmRed.withValues(alpha: 0.1),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : "U",
                    style: const TextStyle(
                      color: msmRed,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        companyName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _buildMenuItem(
            icon: Icons.person_outline_rounded,
            title: "Profile",
            onTap: onProfileTap,
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _buildMenuItem(
            icon: Icons.logout_rounded,
            title: "Logout",
            color: Colors.red,
            onTap: onLogout ?? () {},
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? textDark),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color ?? textDark,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }
}
