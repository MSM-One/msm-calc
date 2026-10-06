import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import 'global_view_wrapper.dart';
import 'motion_toast.dart';

/// Premium SaaS-style Preview Order Modal Dialog
class PreviewOrderDialog extends StatefulWidget {
  final String Function(bool includeDetails) messageBuilder;
  final VoidCallback onPrint;
  final String firmName;
  final String totalQty;
  final int itemCount;
  final bool initialShowDetails;

  const PreviewOrderDialog({
    super.key,
    required this.messageBuilder,
    required this.onPrint,
    required this.firmName,
    required this.totalQty,
    this.itemCount = 0,
    this.initialShowDetails = true,
  });

  /// Shows the modal with a smooth scale-and-fade entrance animation
  static Future<void> show(
    BuildContext context, {
    required String Function(bool includeDetails) messageBuilder,
    required VoidCallback onPrint,
    required String firmName,
    required String totalQty,
    int itemCount = 0,
    bool initialShowDetails = true,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Preview Order',
      barrierColor: const Color(0x80000000), // 50% opacity backdrop
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, anim1, anim2) => PreviewOrderDialog(
        messageBuilder: messageBuilder,
        onPrint: onPrint,
        firmName: firmName,
        totalQty: totalQty,
        itemCount: itemCount,
        initialShowDetails: initialShowDetails,
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<PreviewOrderDialog> createState() => _PreviewOrderDialogState();
}

class _PreviewOrderDialogState extends State<PreviewOrderDialog> {
  late bool _showDetails;
  late String _currentMessage;
  bool _isCopied = false;

  @override
  void initState() {
    super.initState();
    _showDetails = widget.initialShowDetails;
    _currentMessage = widget.messageBuilder(_showDetails);
  }

  void _toggleDetails(bool value) {
    setState(() {
      _showDetails = value;
      _currentMessage = widget.messageBuilder(_showDetails);
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _currentMessage));
    setState(() => _isCopied = true);
    MotionToast.show(context, "Copied order text to clipboard!");
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  void _handleShare() {
    Navigator.pop(context);
    safeShare(context, _currentMessage);
  }

  void _handlePrint() {
    Navigator.pop(context);
    widget.onPrint();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isNarrow = mediaQuery.size.width < 600;
    final dialogWidth = isNarrow ? mediaQuery.size.width * 0.94 : 640.0;
    final maxDialogHeight = mediaQuery.size.height * 0.88;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(
            maxHeight: maxDialogHeight,
            maxWidth: 640,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E0F172A),
                blurRadius: 36,
                spreadRadius: 2,
                offset: Offset(0, 16),
              ),
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Header Section
              _buildHeader(isNarrow),

              // Soft Divider with Subtle Shadow
              _buildSoftDivider(),

              // 2. Preview Card (Order Details Box)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isNarrow ? 14 : 20,
                    14,
                    isNarrow ? 14 : 20,
                    12,
                  ),
                  child: _buildPreviewCard(),
                ),
              ),

              // 3. Action Buttons Section
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 14 : 20,
                  4,
                  isNarrow ? 14 : 20,
                  6,
                ),
                child: _buildActionButtonsRow(isNarrow),
              ),

              // 4. Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Header Section with receipt icon, title, iOS toggle switch & top close button
  Widget _buildHeader(bool isNarrow) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 16 : 22,
        isNarrow ? 16 : 20,
        isNarrow ? 12 : 16,
        14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Receipt / Document Icon Container
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA), width: 1),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: msmRed,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Title & Subtitle
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "Preview Order",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  "Toggle switch to show/hide item size breakdown",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                    fontStyle: FontStyle.normal,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // iOS-style Toggle Switch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.82,
                child: CupertinoSwitch(
                  value: _showDetails,
                  activeTrackColor: msmRed,
                  inactiveTrackColor: const Color(0xFFE2E8F0),
                  onChanged: _toggleDetails,
                ),
              ),
              const SizedBox(width: 4),

              // Small Close Button (✕)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: const Color(0xFF94A3B8),
                hoverColor: const Color(0xFFF1F5F9),
                splashRadius: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                tooltip: "Close",
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Soft Divider with subtle shadow
  Widget _buildSoftDivider() {
    return Container(
      height: 1,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }

  /// 2. Preview Card (Order Details Box)
  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Status Bar: Ready to Send Confirmation Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4), // Light emerald
              border: Border(
                bottom: BorderSide(color: Color(0xFFDCFCE7), width: 1),
                left: BorderSide(color: Color(0xFF16A34A), width: 4), // Accent stripe
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Order Ready to Send",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15803D),
                  ),
                ),
                const Spacer(),
                if (widget.itemCount > 0 || widget.totalQty.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Text(
                      "${widget.itemCount > 0 ? '${widget.itemCount} Items • ' : ''}${widget.totalQty}",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // WhatsApp Message Content Area
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: SelectableText.rich(
                    _buildFormattedSpans(_currentMessage),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: Color(0xFF334155),
                      fontFamily: 'Inter',
                    ),
                  ),
                ),

                // Floating Copy Icon in top-right of preview card
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _copyToClipboard,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFE2E8F0), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isCopied
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded,
                              size: 13,
                              color: _isCopied
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isCopied ? "Copied" : "Copy",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _isCopied
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parses WhatsApp markdown formatting (*bold*, • bullets, total badges)
  TextSpan _buildFormattedSpans(String rawText) {
    final List<InlineSpan> spans = [];
    final lines = rawText.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }

      // Divider line
      if (line.contains('──────────')) {
        spans.add(
          const TextSpan(
            text: '─────────────────────────────\n',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 11,
              fontWeight: FontWeight.w300,
            ),
          ),
        );
        continue;
      }

      // Standard Line formatting (parsing *bold* tokens)
      final parts = line.split('*');
      for (int j = 0; j < parts.length; j++) {
        final part = parts[j];
        if (part.isEmpty) continue;

        final isBold = (j % 2 == 1);
        if (isBold) {
          spans.add(
            TextSpan(
              text: part,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          );
        } else {
          spans.add(
            TextSpan(
              text: part,
              style: TextStyle(
                color: line.startsWith('•')
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF334155),
                fontWeight: line.startsWith('•')
                    ? FontWeight.w500
                    : FontWeight.normal,
              ),
            ),
          );
        }
      }

      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }

  /// 3. Action Buttons (Copy, Share, Print) with micro-interactions & gradients
  Widget _buildActionButtonsRow(bool isNarrow) {
    return Row(
      children: [
        // Copy Button (Outlined / Light Neutral)
        Expanded(
          child: _TactileButton(
            onPressed: _copyToClipboard,
            backgroundColor: const Color(0xFFF8FAFC),
            foregroundColor: const Color(0xFF1E293B),
            borderColor: const Color(0xFFCBD5E1),
            icon: _isCopied ? Icons.check_rounded : Icons.copy_rounded,
            iconColor: _isCopied ? const Color(0xFF16A34A) : const Color(0xFF475569),
            label: _isCopied ? "Copied!" : "Copy",
          ),
        ),
        const SizedBox(width: 12),

        // Share Button (WhatsApp Solid Gradient Green)
        Expanded(
          child: _TactileButton(
            onPressed: _handleShare,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF25D366), Color(0xFF1EBE57)],
            ),
            foregroundColor: Colors.white,
            icon: Icons.share_rounded,
            iconColor: Colors.white,
            label: "Share",
            shadowColor: const Color(0x4025D366),
          ),
        ),
        const SizedBox(width: 12),

        // Print Button (Solid Gradient Brand Red)
        Expanded(
          child: _TactileButton(
            onPressed: _handlePrint,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
            ),
            foregroundColor: Colors.white,
            icon: Icons.print_rounded,
            iconColor: Colors.white,
            label: "Print",
            shadowColor: const Color(0x40DC2626),
          ),
        ),
      ],
    );
  }

  /// 4. Footer Section with ghost Close button
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Center(
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            "Close",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile interactive button with press-down micro-interaction scale & elevation
class _TactileButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Color foregroundColor;
  final Color? backgroundColor;
  final Gradient? gradient;
  final Color? borderColor;
  final Color? shadowColor;

  const _TactileButton({
    required this.onPressed,
    required this.label,
    required this.icon,
    this.iconColor,
    required this.foregroundColor,
    this.backgroundColor,
    this.gradient,
    this.borderColor,
    this.shadowColor,
  });

  @override
  State<_TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<_TactileButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(11),
              border: widget.borderColor != null
                  ? Border.all(
                      color: _isHovered
                          ? const Color(0xFF94A3B8)
                          : widget.borderColor!,
                      width: 1.2,
                    )
                  : null,
              boxShadow: widget.shadowColor != null
                  ? [
                      BoxShadow(
                        color: widget.shadowColor!,
                        blurRadius: _isHovered ? 12 : 8,
                        offset: Offset(0, _isHovered ? 5 : 3),
                      ),
                    ]
                  : [
                      const BoxShadow(
                        color: Color(0x08000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.iconColor ?? widget.foregroundColor,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.foregroundColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
