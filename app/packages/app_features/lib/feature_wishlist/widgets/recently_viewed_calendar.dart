import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../controllers/recently_viewed_controller.dart';
import 'wishlist_components.dart';

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

final class RecentlyViewedCalendar extends StatelessWidget {
  const RecentlyViewedCalendar({
    required this.data,
    required this.controller,
    super.key,
  });

  final RecentlyViewedData data;
  final RecentlyViewedController controller;

  @override
  Widget build(BuildContext context) {
    final dayCount = DateTime.utc(
      data.visibleYear,
      data.visibleMonth + 1,
      0,
    ).day;
    return Material(
      key: const ValueKey('recently-viewed-calendar'),
      color: Colors.white,
      elevation: 5,
      shadowColor: const Color(0x29000000),
      borderRadius: BorderRadius.circular(25),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: Column(
          children: [
            Row(
              children: [
                _MonthButton(
                  key: const ValueKey('calendar-previous-month'),
                  icon: Icons.chevron_left,
                  tooltip: 'Previous month',
                  onPressed: controller.showPreviousMonth,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _monthNames[data.visibleMonth - 1],
                      style: wishlistRaleway(
                        size: 15,
                        weight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MonthButton(
                  key: const ValueKey('calendar-next-month'),
                  icon: Icons.chevron_right,
                  tooltip: 'Next month',
                  onPressed: controller.showNextMonth,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 2.0;
                final cellWidth = (constraints.maxWidth - spacing * 6) / 7;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 4,
                  children: [
                    for (var day = 1; day <= dayCount; day += 1)
                      SizedBox(
                        width: cellWidth,
                        height: 30,
                        child: _CalendarDay(
                          date: WishlistDate(
                            year: data.visibleYear,
                            month: data.visibleMonth,
                            day: day,
                          ),
                          selectedDate: data.pendingDate,
                          onPressed: () => controller.selectCalendarDay(day),
                        ),
                      ),
                  ],
                );
              },
            ),
            IconButton.filled(
              key: const ValueKey('calendar-apply'),
              tooltip: 'Apply selected date',
              onPressed: data.pendingDate == null
                  ? null
                  : controller.applyCalendarSelection,
              icon: const Icon(Icons.keyboard_arrow_up, size: 24),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF9BA9C8),
                elevation: 3,
                fixedSize: const Size.square(38),
                minimumSize: const Size.square(38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 22),
    style: IconButton.styleFrom(
      backgroundColor: AppColors.primarySurface,
      foregroundColor: AppColors.primary,
      fixedSize: const Size.square(30),
      minimumSize: const Size.square(30),
      padding: EdgeInsets.zero,
    ),
  );
}

final class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selectedDate,
    required this.onPressed,
  });

  final WishlistDate date;
  final WishlistDate? selectedDate;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isSelected = date == selectedDate;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${date.year}-${date.month}-${date.day}',
      child: Material(
        color: isSelected ? AppColors.primarySurface : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey<String>('calendar-day-${date.day}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: ExcludeSemantics(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  date.day.toString().padLeft(2, '0'),
                  style: wishlistRaleway(
                    size: 15,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
