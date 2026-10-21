import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class DashboardHeader extends StatefulWidget {
  final String userName;
  final String companyName;
  final bool isSyncing;
  final VoidCallback onRefresh;
  final VoidCallback onProfileTap;
  final VoidCallback? onLogout;

  const DashboardHeader({
    super.key,
    required this.userName,
    required this.companyName,
    required this.isSyncing,
    required this.onRefresh,
    required this.onProfileTap,
    this.onLogout,
  });

  @override
  State<DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends State<DashboardHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.isSyncing) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(DashboardHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing != oldWidget.isSyncing) {
      if (widget.isSyncing) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
        _rotationController.reset();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  String get _initial =>
      widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : "U";

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(24, topPadding + 16, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [msmRed, kMetarollRed],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x308B0000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Company Pill & Profile Avatar (Sync refresh icon removed)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Company Pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
                child: Text(
                  widget.companyName,
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
              // Profile Button
              _ProfileButton(
                initial: _initial,
                onTap: () => _showProfileMenu(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Greeting Section
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
                  widget.userName,
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
              const Text("👋", style: TextStyle(fontSize: 26)),
            ],
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ProfileMenuBottomSheet(
        userName: widget.userName,
        companyName: widget.companyName,
        onProfileTap: () {
          Navigator.pop(context);
          widget.onProfileTap();
        },
        onLogout: widget.onLogout != null
            ? () {
                Navigator.pop(context);
                widget.onLogout!();
              }
            : null,
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final String initial;
  final VoidCallback onTap;

  const _ProfileButton({
    required this.initial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
          initial,
          style: const TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
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
          // Handlebar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          // User Info Section
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
          // Menu Options
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
