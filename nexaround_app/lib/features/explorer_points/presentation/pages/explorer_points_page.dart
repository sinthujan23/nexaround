import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/explorer_points/data/explorer_points_service.dart';
import 'package:nexaround_app/features/explorer_points/domain/explorer_points.dart';
import 'package:nexaround_app/features/explorer_points/presentation/widgets/points_help.dart';

/// The traveller's Explorer Points: their level and how far to the next,
/// how to earn more, what they have done, and the whole ladder.
class ExplorerPointsPage extends StatefulWidget {
  const ExplorerPointsPage({super.key});

  @override
  State<ExplorerPointsPage> createState() => _ExplorerPointsPageState();
}

class _ExplorerPointsPageState extends State<ExplorerPointsPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _fetch();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _fetch();
  }

  Future<void> _fetch() async {
    await Future.wait([
      ExplorerPointsService.refresh(),
      ExplorerPointsService.loadInfo(refresh: true),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Explorer Points',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            onPressed: () => showPointsExplainer(context, fromPointsPage: true),
            icon: const Icon(Icons.help_outline_rounded, color: AppColors.textSecondary),
            tooltip: 'What are Explorer Points?',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ValueListenableBuilder<PointsSummary?>(
        valueListenable: ExplorerPointsService.summary,
        builder: (context, mine, _) => ValueListenableBuilder<PointsInfo?>(
          valueListenable: ExplorerPointsService.info,
          builder: (context, info, _) {
            if (mine == null) {
              return Center(
                child: _loading
                    ? const CircularProgressIndicator(color: AppColors.brandGreen)
                    : Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Could not load your points. Check your connection and try again.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _refresh,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.brandGreen,
                                side: const BorderSide(color: AppColors.brandGreen),
                              ),
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
              );
            }
            return RefreshIndicator(
              color: AppColors.brandGreen,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  _levelCard(mine),
                  const SizedBox(height: 22),
                  if (info != null) ...[
                    _heading('How to earn more'),
                    ...info.earn.map(_earnRow),
                    const SizedBox(height: 22),
                  ],
                  _heading('What you have done'),
                  _countsGrid(mine),
                  if (info != null) ...[
                    const SizedBox(height: 22),
                    _heading('All levels'),
                    ...info.levels.map((l) => _levelRow(l, mine.level.level)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      );

  Widget _levelCard(PointsSummary mine) {
    final lv = mine.level;
    final gold = lv.level >= 7;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gold ? AppColors.achievementGradient : AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(lv.badge, style: const TextStyle(fontSize: 46)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Level ${lv.level} of ${mine.maxLevel}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: gold ? Colors.black87 : Colors.white70)),
                    Text(lv.name,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: gold ? Colors.black : Colors.white)),
                    if (lv.tagline.isNotEmpty)
                      Text('“${lv.tagline}”',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: gold ? Colors.black87 : Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${mine.total}',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: gold ? Colors.black : Colors.white)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('points',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: gold ? Colors.black87 : Colors.white70)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: lv.progress,
              minHeight: 8,
              backgroundColor: (gold ? Colors.black : Colors.white).withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(gold ? Colors.black87 : Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lv.isTop ? 'Top level reached. Legendary!' : '${lv.pointsToNext} points to ${lv.nextName}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: gold ? Colors.black87 : Colors.white),
          ),
          if (mine.pendingPoints > 0) ...[
            const SizedBox(height: 4),
            Text('+${mine.pendingPoints} more once our team approves your photos',
                style: TextStyle(fontSize: 12, color: gold ? Colors.black87 : Colors.white70)),
          ],
        ],
      ),
    );
  }

  Widget _earnRow(EarnRule e) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (e.note.isNotEmpty)
                    Text(e.note, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
            Text('+${e.points}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.brandGreen)),
          ],
        ),
      );

  Widget _countsGrid(PointsSummary mine) {
    final items = <(String, int, IconData)>[
      ('Ratings', mine.count('ratings'), Icons.star_rounded),
      ('Reviews', mine.count('reviews'), Icons.rate_review_rounded),
      ('Photos', mine.count('photos'), Icons.photo_camera_rounded),
      ('First photos', mine.count('trailblazer_photos'), Icons.flag_rounded),
      ('Odysseys', mine.count('odysseys'), Icons.flight_takeoff_rounded),
      ('Mini Tours', mine.count('mini_tours'), Icons.directions_walk_rounded),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        for (final (label, n, icon) in items)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: AppColors.brandGreen),
                const SizedBox(height: 4),
                Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _levelRow(PointsLevel l, int myLevel) {
    final mine = l.level == myLevel;
    final reached = l.level <= myLevel;
    final gold = l.level >= 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? (gold ? AppColors.ratingGold.withValues(alpha: 0.14) : AppColors.brandGreenLight) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mine ? (gold ? AppColors.ratingGold : AppColors.brandGreen) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Opacity(
        opacity: reached ? 1 : 0.55,
        child: Row(
          children: [
            SizedBox(width: 34, child: Text(l.badge, style: const TextStyle(fontSize: 22))),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lv ${l.level} · ${l.name}${mine ? '  (you)' : ''}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text(l.tagline, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (!reached)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.lock_rounded, size: 14, color: AppColors.textTertiary),
              ),
            Text('${l.minPoints}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
