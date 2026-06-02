import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

/// Renders a generated/saved [Odyssey] as a scrollable blueprint. Shared by the
/// planner's result step and the saved-odyssey detail page.
class OdysseyPlanView extends StatelessWidget {
  final Odyssey odyssey;
  final EdgeInsetsGeometry padding;

  const OdysseyPlanView({
    super.key,
    required this.odyssey,
    this.padding = const EdgeInsets.all(24),
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
            const SizedBox(height: 12),
            ...odyssey.dayPlans.asMap().entries.map(
                  (e) => _dayCard(e.value)
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

  Widget _dayCard(OdysseyDay day) {
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
          ...day.activities.map(_activityRow),
        ],
      ),
    );
  }

  Widget _activityRow(OdysseyActivity act) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              act.time,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.actionTeal,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
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
            Text(
              act.cost,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
