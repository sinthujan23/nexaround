import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/core/widgets/converted_currency_text.dart';


/// Renders a generated/saved [Odyssey] as a scrollable blueprint. Shared by the
/// planner's result step and the saved-odyssey detail page.
class OdysseyPlanView extends StatelessWidget {
  final Odyssey odyssey;
  final EdgeInsetsGeometry padding;

  /// When provided, each activity shows an edit button that asks the AI to swap
  /// that place. Called with the zero-based (dayIndex, activityIndex). When
  /// null the plan is read-only (e.g. the planner preview).
  final void Function(int dayIndex, int activityIndex)? onSwapActivity;

  /// Key of the activity currently being swapped ("dayIndex:activityIndex"),
  /// so that row can show a spinner instead of its edit button.
  final String? swappingKey;

  /// When provided, each activity gets a tappable check circle to mark it
  /// visited as the traveler completes the trip. Called with (dayIndex,
  /// activityIndex). When null the plan shows no check-off controls.
  final void Function(int dayIndex, int activityIndex)? onToggleVisited;

  const OdysseyPlanView({
    super.key,
    required this.odyssey,
    this.padding = const EdgeInsets.all(24),
    this.onSwapActivity,
    this.swappingKey,
    this.onToggleVisited,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.ratingGold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'AI GENERATED ODYSSEY',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            odyssey.title,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (odyssey.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              odyssey.summary,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _infoCard(
            'Duration',
            '${odyssey.days} ${odyssey.days == 1 ? 'Day' : 'Days'}'
                '${odyssey.nights > 0 ? ' / ${odyssey.nights} ${odyssey.nights == 1 ? 'Night' : 'Nights'}' : ''}',
            Icons.wb_sunny_rounded,
          ),
          if (odyssey.destination.isNotEmpty)
            _infoCard('Destination', odyssey.destination, Icons.place_rounded),
          if (odyssey.visa.isNotEmpty)
            _infoCard('Visa / Entry', odyssey.visa, Icons.description_rounded),
          if (odyssey.budgetSplit.isNotEmpty)
            _infoCard('Budget Split', odyssey.budgetSplit, Icons.pie_chart_rounded),
          if (odyssey.dayPlans.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'DAY-BY-DAY ITINERARY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            if (onToggleVisited != null) _buildProgress(),
            const SizedBox(height: 12),
            ...odyssey.dayPlans.asMap().entries.map(
                  (e) => _dayCard(e.key, e.value)
                      .animate()
                      .fade(delay: (80 * e.key).ms)
                      .slideY(begin: 0.1, end: 0),
                ),
          ],
          if (odyssey.logistics.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'LOGISTICS BLUEPRINT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                odyssey.logistics,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(int dayIndex, OdysseyDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'DAY ${day.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  day.theme,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...day.activities.asMap().entries.map(
                (a) => _activityRow(dayIndex, a.key, a.value),
              ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final total = odyssey.totalActivities;
    final done = odyssey.visitedActivities;
    final pct = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                odyssey.isComplete
                    ? 'Trip complete 🎉'
                    : 'Tick off each place as you go',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: odyssey.isComplete
                      ? AppColors.neonGreen
                      : Colors.black54,
                ),
              ),
              const Spacer(),
              Text(
                '$done / $total',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: Colors.black12,
              color: odyssey.isComplete
                  ? AppColors.neonGreen
                  : AppColors.actionTeal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(int dayIndex, int activityIndex, OdysseyActivity act) {
    final bool isCompleted = odyssey.status == 'completed';
    final bool editable = onSwapActivity != null && !isCompleted;
    final bool checkable = onToggleVisited != null;
    final bool isSwapping = swappingKey == '$dayIndex:$activityIndex';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (checkable) ...[
            GestureDetector(
              onTap: isCompleted ? null : () => onToggleVisited!(dayIndex, activityIndex),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Icon(
                  act.visited
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color:
                      act.visited ? AppColors.neonGreen : Colors.black26,
                ),
              ),
            ),
          ],
          SizedBox(
            width: 56,
            child: Text(
              act.time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: act.visited
                    ? Colors.black26
                    : AppColors.actionTeal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  act.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: act.visited ? Colors.black38 : Colors.black,
                    decoration:
                        act.visited ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (act.tip.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    act.tip,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (act.cost.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConvertedCurrencyText(
              rawText: act.cost,
              originalCurrency: odyssey.currency,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ],
          if (editable) ...[
            const SizedBox(width: 4),
            if (isSwapping)
              const SizedBox(
                width: 32,
                height: 32,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.actionTeal,
                  ),
                ),
              )
            else
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Swap this place',
                  icon: const Icon(
                    Icons.autorenew_rounded,
                    size: 18,
                    color: Colors.black45,
                  ),
                  onPressed: swappingKey != null
                      ? null
                      : () => onSwapActivity!(dayIndex, activityIndex),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
