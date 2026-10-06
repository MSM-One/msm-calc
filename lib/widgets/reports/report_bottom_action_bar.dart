import 'package:flutter/material.dart';

/// Standardized Persistent Bottom Summary & Action Bar for MSM Reports.
///
/// Features:
/// - Sticky bottom bar with safe area padding and upper elevation shadow.
/// - Top summary metric row with dynamic label and high-contrast rounded pill container.
/// - Full-width red 'Export PDF' action button (supporting loading indicator state).
class ReportBottomActionBar extends StatelessWidget {
  final String label;
  final double totalQty;
  final VoidCallback? onExportPdf;
  final bool isPdfLoading;
  final Color? badgeColor;
  final Color? badgeTextColor;
  final String unit;
  final String buttonText;
  final IconData buttonIcon;
  final Key? barKey;

  const ReportBottomActionBar({
    super.key,
    required this.label,
    required this.totalQty,
    required this.onExportPdf,
    this.isPdfLoading = false,
    this.badgeColor,
    this.badgeTextColor,
    this.unit = 'MT',
    this.buttonText = 'Export PDF',
    this.buttonIcon = Icons.picture_as_pdf_rounded,
    this.barKey,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPositiveOrZero = totalQty >= 0;
    final Color effectiveBadgeBg = badgeColor ??
        (isPositiveOrZero ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE));
    final Color effectiveBadgeText = badgeTextColor ??
        (isPositiveOrZero ? const Color(0xFF2E7D32) : const Color(0xFFC62828));

    return Container(
      key: barKey ?? const Key('report_bottom_action_bar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: effectiveBadgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${totalQty.toStringAsFixed(3)} $unit',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: effectiveBadgeText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                icon: isPdfLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(buttonIcon, size: 20),
                label: Text(
                  isPdfLoading ? 'Exporting...' : buttonText,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                onPressed: isPdfLoading ? null : onExportPdf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
