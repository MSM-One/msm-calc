import 'package:flutter/material.dart';

class MsmDateFilterSheet extends StatelessWidget {
  final DateTimeRange initialRange;
  final ValueChanged<DateTimeRange> onRangeSelected;

  const MsmDateFilterSheet({
    super.key,
    required this.initialRange,
    required this.onRangeSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required DateTimeRange initialRange,
    required ValueChanged<DateTimeRange> onRangeSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => MsmDateFilterSheet(
        initialRange: initialRange,
        onRangeSelected: onRangeSelected,
      ),
    );
  }

  bool _isSameRange(DateTimeRange a, DateTimeRange b) {
    return a.start.year == b.start.year &&
        a.start.month == b.start.month &&
        a.start.day == b.start.day &&
        a.end.year == b.end.year &&
        a.end.month == b.end.month &&
        a.end.day == b.end.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = DateTime(yesterdayStart.year, yesterdayStart.month,
        yesterdayStart.day, 23, 59, 59);

    final last7DaysStart = todayStart.subtract(const Duration(days: 6));
    final last7DaysEnd = todayEnd;

    final thisMonthStart = DateTime(now.year, now.month, 1);
    final thisMonthEnd = todayEnd;

    final presets = [
      _DatePreset(
        label: "Today",
        range: DateTimeRange(start: todayStart, end: todayEnd),
      ),
      _DatePreset(
        label: "Yesterday",
        range: DateTimeRange(start: yesterdayStart, end: yesterdayEnd),
      ),
      _DatePreset(
        label: "Last 7 Days",
        range: DateTimeRange(start: last7DaysStart, end: last7DaysEnd),
      ),
      _DatePreset(
        label: "This Month",
        range: DateTimeRange(start: thisMonthStart, end: thisMonthEnd),
      ),
    ];

    final matchesAnyPreset =
        presets.any((preset) => _isSameRange(initialRange, preset.range));
    final isCustomSelected = !matchesAnyPreset;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select Date Filter",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212121),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8.0,
              runSpacing: 10.0,
              children: [
                ...presets.map((preset) {
                  final isSelected = _isSameRange(initialRange, preset.range);
                  return GestureDetector(
                    onTap: () {
                      onRangeSelected(preset.range);
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 10.0),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFB71C1C)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: Text(
                        preset.label,
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF212121),
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context); // Wipes out the modal view cleanly

                    final DateTimeRange? pickedRange =
                        await showDateRangePicker(
                      context: context,
                      initialDateRange: initialRange,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );

                    if (pickedRange != null) {
                      final startNormalized = DateTime(pickedRange.start.year,
                          pickedRange.start.month, pickedRange.start.day);
                      final endNormalized = DateTime(pickedRange.end.year,
                          pickedRange.end.month, pickedRange.end.day);
                      onRangeSelected(DateTimeRange(
                          start: startNormalized, end: endNormalized));
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: isCustomSelected
                          ? const Color(0xFFB71C1C)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(color: Colors.transparent),
                    ),
                    child: Text(
                      "Custom Range",
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w500,
                        color: isCustomSelected
                            ? Colors.white
                            : const Color(0xFF212121),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DatePreset {
  final String label;
  final DateTimeRange range;

  _DatePreset({required this.label, required this.range});
}
