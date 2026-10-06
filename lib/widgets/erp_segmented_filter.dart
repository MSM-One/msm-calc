import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class ERPSegmentedFilter extends StatelessWidget {
  final List<String> options;
  final String selectedOption;
  final Function(String) onOptionSelected;
  final bool isFullWidth;
  final Color? activeBgColor;
  final Color? inactiveBgColor;
  final Color? activeTextColor;
  final Color? inactiveTextColor;

  const ERPSegmentedFilter({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onOptionSelected,
    this.isFullWidth = true,
    this.activeBgColor,
    this.inactiveBgColor,
    this.activeTextColor,
    this.inactiveTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((opt) {
        final isSelected = opt == selectedOption;

        if (isFullWidth) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _buildBaseChip(isSelected, opt),
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildBaseChip(isSelected, opt, horizontalPadding: 16),
          );
        }
      }).toList(),
    );
  }

  Widget _buildBaseChip(bool isSelected, String label,
      {double horizontalPadding = 0}) {
    return GestureDetector(
      onTap: () => onOptionSelected(label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 0),
        decoration: BoxDecoration(
          color: isSelected
              ? (activeBgColor ?? msmRed)
              : (inactiveBgColor ?? Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: msmRed),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (activeTextColor ?? Colors.white)
                    : (inactiveTextColor ?? msmRed),
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
