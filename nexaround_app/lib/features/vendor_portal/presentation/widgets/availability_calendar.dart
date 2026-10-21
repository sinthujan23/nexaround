import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

/// Every day [ranges] covers.
Set<DateTime> blockedDays(List<BlockedRange> ranges) {
  final days = <DateTime>{};
  for (final r in ranges) {
    for (var d = DateUtils.dateOnly(r.start);
        !d.isAfter(r.end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
  }
  return days;
}

/// [days] as the fewest ranges: back-to-back days join into one.
List<BlockedRange> rangesOf(Set<DateTime> days) {
  final sorted = days.map(DateUtils.dateOnly).toSet().toList()..sort();
  final ranges = <BlockedRange>[];
  for (final d in sorted) {
    if (ranges.isNotEmpty &&
        DateUtils.isSameDay(DateTime(ranges.last.end.year, ranges.last.end.month,
            ranges.last.end.day + 1), d)) {
      ranges[ranges.length - 1] = BlockedRange(ranges.last.start, d);
    } else {
      ranges.add(BlockedRange(d, d));
    }
  }
  return ranges;
}

/// Month by month, from this month to the end of the booking window. A day
/// travellers cannot pick is red; tapping a day blocks or frees it. Past
/// days are not shown as tappable: blocking them changes nothing.
class AvailabilityCalendar extends StatefulWidget {
  final List<BlockedRange> value;
  final int maxDays;
  final ValueChanged<List<BlockedRange>> onChanged;

  const AvailabilityCalendar({
    super.key,
    required this.value,
    required this.maxDays,
    required this.onChanged,
  });

  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar> {
  late DateTime _month;

  static const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _lastDay => _today.add(Duration(days: widget.maxDays));

  @override
  void initState() {
    super.initState();
    _month = DateTime(_today.year, _today.month);
  }

  void _toggle(DateTime day) {
    final days = blockedDays(widget.value);
    if (!days.remove(day)) days.add(day);
    widget.onChanged(rangesOf(days));
  }

  @override
  Widget build(BuildContext context) {
    final blocked = blockedDays(widget.value);
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = first.weekday - 1; // Monday first
    final canBack = _month.isAfter(DateTime(_today.year, _today.month));
    final canForward = DateTime(_month.year, _month.month + 1).isBefore(_lastDay) ||
        DateUtils.isSameDay(DateTime(_month.year, _month.month + 1), _lastDay);
    final blockedCount = blocked.where((d) => !d.isBefore(_today)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: canBack
                  ? () => setState(() => _month = DateTime(_month.year, _month.month - 1))
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${_months[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: canForward
                  ? () => setState(() => _month = DateTime(_month.year, _month.month + 1))
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (var d = 1; d <= daysInMonth; d++)
              _day(DateTime(_month.year, _month.month, d), blocked),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          blockedCount == 0
              ? 'Every day is open. Tap a day to block it.'
              : '$blockedCount ${blockedCount == 1 ? 'day' : 'days'} blocked. Tap a red day to open it again.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _day(DateTime day, Set<DateTime> blocked) {
    final inWindow = !day.isBefore(_today) && !day.isAfter(_lastDay);
    final isBlocked = blocked.contains(day);
    final color = !inWindow
        ? AppColors.textMuted
        : isBlocked
            ? Colors.white
            : AppColors.textPrimary;
    return Semantics(
      button: inWindow,
      selected: isBlocked,
      label: '${day.day} ${_months[day.month - 1]}${isBlocked ? ', blocked' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: inWindow ? () => _toggle(day) : null,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isBlocked && inWindow ? AppColors.error : null,
            borderRadius: BorderRadius.circular(10),
            border: DateUtils.isSameDay(day, _today)
                ? Border.all(color: AppColors.brandGreen, width: 1.5)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBlocked ? FontWeight.w700 : FontWeight.w500,
              color: color,
              decoration: isBlocked && inWindow ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
