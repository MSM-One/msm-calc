import 'package:flutter/material.dart';

/// Compact Executive Greeting & Live Telemetry Header for ERP Command Center.
/// Replaces bulky full-bleed banners with a high-density, 72-80px executive header.
class ExecutiveTelemetryHeader extends StatefulWidget {
  final String userName;
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
      duration: const Duration(seconds: 1),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;

          return isNarrow ? _buildNarrowLayout() : _buildWideLayout();
        },
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left: Greeting & Subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Welcome back, ${widget.userName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('👋', style: TextStyle(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Right: Telemetry Status Pills & Controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status Pill 1: Supabase Live
            _buildLiveStatusPill(),
            const SizedBox(width: 8),

            // Status Pill 2: Location
            _buildLocationPill(),
            const SizedBox(width: 8),

            // Status Pill 3: Critical Alerts
            _buildAlertsPill(),
            const SizedBox(width: 12),

            // Vertical separator
            Container(
              height: 28,
              width: 1,
              color: const Color(0xFFE2E8F0),
            ),
            const SizedBox(width: 12),

            // Sync Refresh Action
            _buildSyncButton(),
            const SizedBox(width: 10),

            // Profile Avatar
            _buildProfileAvatar(),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, ${widget.userName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSyncButton(),
                const SizedBox(width: 8),
                _buildProfileAvatar(),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildLiveStatusPill(),
            _buildLocationPill(),
            _buildAlertsPill(),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveStatusPill() {
    final bool isLive = widget.isSupabaseLive && !widget.isSyncing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isLive ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isLive ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.isSyncing
                ? 'Syncing...'
                : (isLive ? 'Supabase Live' : 'Connecting'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isLive ? const Color(0xFF065F46) : const Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_rounded,
            size: 13,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            widget.locationLabel,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsPill() {
    final hasAlerts = widget.attentionCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onAttentionTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                hasAlerts ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  hasAlerts ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasAlerts
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                size: 13,
                color: hasAlerts
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF10B981),
              ),
              const SizedBox(width: 5),
              Text(
                hasAlerts
                    ? '${widget.attentionCount} Items Attention'
                    : 'All Clear',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: hasAlerts
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncButton() {
    return Tooltip(
      message: 'Sync Data with Cloud ERP',
      child: InkWell(
        onTap: widget.isSyncing ? null : widget.onRefresh,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          alignment: Alignment.center,
          child: RotationTransition(
            turns: _spinController,
            child: const Icon(
              Icons.sync_rounded,
              size: 18,
              color: Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar() {
    final initial = widget.userName.isNotEmpty
        ? widget.userName[0].toUpperCase()
        : 'U';

    return Tooltip(
      message: 'Profile & Settings',
      child: InkWell(
        onTap: widget.onProfileTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
