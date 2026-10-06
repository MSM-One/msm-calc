import 'package:flutter/material.dart';
import '../../constants/enterprise_design_tokens.dart';

/// Professional Enterprise System Status & Telemetry Header for MSM Command Center.
/// Replaces consumer greeting with real-time operational status, role badge,
/// sync timestamp, and high-density telemetry controls.
class ExecutiveTelemetryHeader extends StatefulWidget {
  final String userName;
  final String userRole;
  final String subtitle;
  final bool isSupabaseLive;
  final bool isSyncing;
  final String locationLabel;
  final int attentionCount;
  final VoidCallback onRefresh;
  final VoidCallback onProfileTap;
  final VoidCallback? onAttentionTap;

  const ExecutiveTelemetryHeader({
    super.key,
    required this.userName,
    this.userRole = 'OPERATIONS DESK',
    this.subtitle = 'MSM Yard Inventory & Operations',
    this.isSupabaseLive = true,
    this.isSyncing = false,
    this.locationLabel = 'Yard: All',
    required this.attentionCount,
    required this.onRefresh,
    required this.onProfileTap,
    this.onAttentionTap,
  });

  @override
  State<ExecutiveTelemetryHeader> createState() =>
      _ExecutiveTelemetryHeaderState();
}

class _ExecutiveTelemetryHeaderState extends State<ExecutiveTelemetryHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isSyncing) {
      _spinController.repeat();
    }
  }

  @override
  void didUpdateWidget(ExecutiveTelemetryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing != oldWidget.isSyncing) {
      if (widget.isSyncing) {
        _spinController.repeat();
      } else {
        _spinController.stop();
        _spinController.reset();
      }
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _triggerRefreshAnimation() {
    if (!_spinController.isAnimating) {
      _spinController.forward(from: 0.0);
    }
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EnterpriseColors.cardSurface,
        borderRadius: EnterpriseBorders.r14,
        border: Border.all(color: EnterpriseColors.borderLight, width: 1),
        boxShadow: EnterpriseShadows.elevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top Brand Navy Accent Bar ──
          Container(
            height: 3.5,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  EnterpriseColors.darkNavy,
                  EnterpriseColors.accentSteel,
                  EnterpriseColors.darkCharcoal,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),

          // ── Header Content ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 768;
                return isNarrow ? _buildNarrowLayout() : _buildWideLayout();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    final displayName =
        widget.userName.isNotEmpty ? widget.userName : 'Operations Manager';
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left side: "Welcome back, [Dynamic User Name] 👋" + subtext
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Welcome back, $displayName',
                      style: const TextStyle(
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        color: EnterpriseColors.darkNavy,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '👋',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: EnterpriseColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Right side:
        // * Yard Pill: "📍 Yard: All" (#F1F5F9 fill, dark border).
        // * Attention Tag: "⚠️ [X] Items Attention" (#FEF3F2 fill, red text, red border).
        // * Refresh Button: Square rounded icon button with rotating sync icon.
        // * Profile Avatar: Red circle with white initial.
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildLocationPill(),
            const SizedBox(width: 10),
            _buildAttentionPill(),
            const SizedBox(width: 12),
            _buildRefreshButton(),
            const SizedBox(width: 10),
            _buildProfileAvatar(initial),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    final displayName =
        widget.userName.isNotEmpty ? widget.userName : 'Operations Manager';
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Welcome back, $displayName',
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: EnterpriseColors.darkNavy,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '👋',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: EnterpriseColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRefreshButton(),
                const SizedBox(width: 8),
                _buildProfileAvatar(initial),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildLocationPill(),
            _buildAttentionPill(),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationPill() {
    final label = widget.locationLabel.startsWith('Yard:')
        ? widget.locationLabel
        : 'Yard: ${widget.locationLabel}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '📍',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionPill() {
    final count = widget.attentionCount;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onAttentionTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFECDCA), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '⚠️',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(width: 5),
              Text(
                '$count Items Attention',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD92D20),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton() {
    return Tooltip(
      message: 'Refresh Dashboard Data',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isSyncing ? null : _triggerRefreshAnimation,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
            ),
            alignment: Alignment.center,
            child: RotationTransition(
              turns: _spinController,
              child: const Icon(
                Icons.sync_rounded,
                size: 18,
                color: Color(0xFF475467),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(String initial) {
    return Tooltip(
      message: 'Profile & Settings',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onProfileTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFCC2127),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
