import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// A month calendar for the enquiry sheet's preferred date.
///
/// [showDatePicker] greys out every day it will not accept, so a past day and
/// a day the vendor has blocked look the same and travellers cannot tell why a
/// future date is dead. Here blocked days are red, with a legend saying so,
/// and tapping one explains itself instead of doing nothing.
Future<DateTime?> showExperienceDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required bool Function(DateTime day) isUnavailable,
  String? helpText,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _ExperienceDatePicker(
      initialDate: DateUtils.dateOnly(initialDate),
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      isUnavailable: isUnavailable,
      helpText: helpText ?? 'Select date',
    ),
  );
}

const _unavailableRed = AppColors.error;
const _unavailableFill = Color(0x1FE53935); // ~12% of the red

class _ExperienceDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool Function(DateTime day) isUnavailable;
  final String helpText;

  const _ExperienceDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.isUnavailable,
    required this.helpText,
  });

  @override
  State<_ExperienceDatePicker> createState() => _ExperienceDatePickerState();
}

class _ExperienceDatePickerState extends State<_ExperienceDatePicker> {
  late DateTime _selected = widget.initialDate;
  late DateTime _month =
      DateTime(widget.initialDate.year, widget.initialDate.month);

  /// The blocked day the traveller last tapped, for the "not available" line.
  DateTime? _tappedUnavailable;

  bool get _canGoBack => _month.isAfter(
      DateTime(widget.firstDate.year, widget.firstDate.month));

  bool get _canGoForward => _month.isBefore(
      DateTime(widget.lastDate.year, widget.lastDate.month));

  bool _inRange(DateTime day) =>
      !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);

  void _changeMonth(int delta) {
    if (delta < 0 && !_canGoBack) return;
    if (delta > 0 && !_canGoForward) return;
    setState(() {
      _month = DateUtils.addMonthsToMonthDate(_month, delta);
      _tappedUnavailable = null;
    });
  }

  void _tapDay(DateTime day) {
    setState(() {
      if (widget.isUnavailable(day)) {
        _tappedUnavailable = day;
      } else {
        _selected = day;
        _tappedUnavailable = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.helpText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.formatMediumDate(_selected),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _buildMonthHeader(l10n),
              _buildWeekdays(l10n),
              GestureDetector(
                // Swipe between months, as the stock picker allows.
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -200) _changeMonth(1);
                  if (velocity > 200) _changeMonth(-1);
                },
                child: _buildGrid(l10n),
              ),
              const SizedBox(height: 8),
              _buildLegend(),
              if (_tappedUnavailable != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Text(
                    '${l10n.formatMediumDate(_tappedUnavailable!)} is not '
                    'available. Please pick another day.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _unavailableRed,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.brandGreen),
                      child: Text(l10n.cancelButtonLabel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.brandGreen),
                      child: Text(l10n.okButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthHeader(MaterialLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.formatMonthYear(_month),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          IconButton(
            onPressed: _canGoBack ? () => _changeMonth(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.textSecondary,
            tooltip: l10n.previousMonthTooltip,
          ),
          IconButton(
            onPressed: _canGoForward ? () => _changeMonth(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.textSecondary,
            tooltip: l10n.nextMonthTooltip,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdays(MaterialLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: SizedBox(
                height: 36,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      l10n.narrowWeekdays[(l10n.firstDayOfWeekIndex + i) % 7],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(MaterialLocalizations l10n) {
    final offset =
        DateUtils.firstDayOffset(_month.year, _month.month, l10n);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);

    // Always six rows, so the dialog keeps its height from month to month.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var row = 0; row < 6; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _buildCell(
                      l10n,
                      row * 7 + col - offset + 1,
                      daysInMonth,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCell(MaterialLocalizations l10n, int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 46);
    }

    final day = DateTime(_month.year, _month.month, dayNumber);
    final inRange = _inRange(day);
    final unavailable = inRange && widget.isUnavailable(day);
    final selected = DateUtils.isSameDay(day, _selected);
    final today = DateUtils.isSameDay(day, DateTime.now());

    Color textColor;
    Color? fill;
    if (selected) {
      textColor = Colors.white;
      fill = AppColors.brandGreen;
    } else if (unavailable) {
      textColor = _unavailableRed;
      fill = _unavailableFill;
    } else if (!inRange) {
      textColor = AppColors.textMuted;
    } else {
      textColor = AppColors.textPrimary;
    }

    final label = StringBuffer(l10n.formatFullDate(day));
    if (unavailable) label.write(', not available');

    return Semantics(
      label: label.toString(),
      button: inRange && !unavailable,
      selected: selected,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: inRange ? () => _tapDay(day) : null,
        child: SizedBox(
          height: 46,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: today && !selected
                    ? Border.all(color: AppColors.brandGreen)
                    : null,
              ),
              child: Text(
                '$dayNumber',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      selected || unavailable ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                  decoration: unavailable ? TextDecoration.lineThrough : null,
                  decorationColor: _unavailableRed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          _legendItem(
            const BoxDecoration(
              color: AppColors.brandGreen,
              shape: BoxShape.circle,
            ),
            'Selected',
          ),
          _legendItem(
            const BoxDecoration(
              color: _unavailableFill,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                  BorderSide(color: _unavailableRed, width: 1.5)),
            ),
            'Not available',
          ),
          _legendItem(
            BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandGreen),
            ),
            'Today',
          ),
        ],
      ),
    );
  }

  Widget _legendItem(BoxDecoration swatch, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: swatch),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
