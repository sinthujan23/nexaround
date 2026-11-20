import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexaround_app/features/explorer_points/data/explorer_points_service.dart';
import 'package:nexaround_app/features/explorer_points/domain/explorer_points.dart';
import 'package:nexaround_app/features/explorer_points/presentation/pages/explorer_points_page.dart';

/// Levels 7+ are drawn in gold.
bool _isGold(int level) => level >= 7;

/// The small "?" next to anything about points or levels. Opens the
/// explainer sheet ([showPointsExplainer]).
class PointsHelpButton extends StatelessWidget {
  final double size;
  final Color? color;
  final int? highlightLevel;

  const PointsHelpButton({super.key, this.size = 18, this.color, this.highlightLevel});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => showPointsExplainer(context, highlightLevel: highlightLevel),
      icon: Icon(Icons.help_outline_rounded, size: size, color: color ?? AppColors.textTertiary),
      tooltip: 'What are Explorer Points?',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}

/// "🏴‍☠️ Lv 5 · Pirate" next to a reviewer's name. A tap explains it, with
/// this level picked out on the ladder.
class LevelChip extends StatelessWidget {
  final int level;
  final String? name;
  final bool compact;

  const LevelChip({super.key, required this.level, this.name, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PointsInfo?>(
      valueListenable: ExplorerPointsService.info,
      builder: (context, info, _) {
        final known = info?.level(level);
        final label = '${(known?.badge ?? '').isEmpty ? '' : '${known!.badge} '}'
            'Lv $level · ${name ?? known?.name ?? ''}';
        final gold = _isGold(level);
        return Semantics(
          button: true,
          label: 'Level $level, ${name ?? known?.name ?? ''}. What are Explorer Points?',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showPointsExplainer(context, highlightLevel: level),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 2 : 3),
                decoration: BoxDecoration(
                  color: gold ? AppColors.ratingGold.withValues(alpha: 0.16) : AppColors.brandGreenLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 11.5,
                    fontWeight: FontWeight.w700,
                    color: gold ? const Color(0xFF8A6100) : AppColors.brandGreen,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The explainer: what Explorer Points are, how to earn them, the ten
/// levels and the rules. [highlightLevel] picks one level out (a tapped
/// reviewer's level); otherwise the traveller's own level is marked.
Future<void> showPointsExplainer(
  BuildContext context, {
  int? highlightLevel,
  bool fromPointsPage = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PointsExplainerSheet(
      highlightLevel: highlightLevel,
      fromPointsPage: fromPointsPage,
    ),
  );
}

class _PointsExplainerSheet extends StatefulWidget {
  final int? highlightLevel;
  final bool fromPointsPage;

  const _PointsExplainerSheet({this.highlightLevel, this.fromPointsPage = false});

  @override
  State<_PointsExplainerSheet> createState() => _PointsExplainerSheetState();
}

class _PointsExplainerSheetState extends State<_PointsExplainerSheet> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Shown from the phone's copy at once; refreshed quietly behind it.
    _loading = ExplorerPointsService.info.value == null;
    _fetch();
  }

  Future<void> _fetch() async {
    await ExplorerPointsService.loadInfo(refresh: true);
    if (mounted) setState(() => _loading = false);
  }

  void _retry() {
    setState(() => _loading = true);
    _fetch();
  }

  void _openPoints() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => const ExplorerPointsPage()));
  }

  void _openSignIn() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ValueListenableBuilder<PointsInfo?>(
          valueListenable: ExplorerPointsService.info,
          builder: (context, info, _) => ValueListenableBuilder<PointsSummary?>(
            valueListenable: ExplorerPointsService.summary,
            builder: (context, mine, _) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.brandGreenLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.emoji_events_rounded, color: AppColors.brandGreen, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        info?.title ?? 'What are Explorer Points?',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                if (info == null) ..._unavailable() else ..._content(info, mine),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _unavailable() => [
        const SizedBox(height: 24),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: AppColors.brandGreen))
        else ...[
          const Text(
            'Could not load this right now. Check your connection and try again.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandGreen,
              side: const BorderSide(color: AppColors.brandGreen),
            ),
            child: const Text('Try again'),
          ),
        ],
      ];

  List<Widget> _content(PointsInfo info, PointsSummary? mine) {
    final signedIn = CacheService.isLoggedIn();
    final myLevel = signedIn ? mine?.level.level : null;
    final picked = widget.highlightLevel != null ? info.level(widget.highlightLevel!) : null;
    final max = info.levels.length;
    return [
      const SizedBox(height: 10),
      Text(info.intro, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      if (picked != null)
        _spotlight(
          badge: picked.badge,
          title: picked.name,
          line: 'Level ${picked.level} of $max · from ${picked.minPoints} points',
          tagline: picked.tagline,
          gold: _isGold(picked.level),
        )
      else if (mine != null && signedIn)
        _spotlight(
          badge: mine.level.badge,
          title: 'You are a ${mine.level.name}',
          line: 'Level ${mine.level.level} of $max · ${mine.total} points',
          tagline: mine.level.isTop
              ? mine.level.tagline
              : '${mine.level.pointsToNext} points to ${mine.level.nextName}',
          gold: _isGold(mine.level.level),
        ),
      const SizedBox(height: 20),
      _heading('How to earn'),
      ...info.earn.map(_earnRow),
      const SizedBox(height: 20),
      _heading('The $max levels'),
      ...info.levels.map((l) => _levelRow(
            l,
            mark: l.level == (widget.highlightLevel ?? myLevel),
            reached: myLevel == null || l.level <= myLevel,
          )),
      if (info.rules.isNotEmpty) ...[
        const SizedBox(height: 20),
        _heading('Good to know'),
        ...info.rules.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.brandGreen),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r, style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            )),
      ],
      const SizedBox(height: 20),
      if (!widget.fromPointsPage)
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: signedIn ? _openPoints : _openSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              signedIn ? 'See my points' : 'Sign in to start earning',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
    ];
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      );

  Widget _spotlight({
    required String badge,
    required String title,
    required String line,
    required String tagline,
    required bool gold,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gold ? AppColors.ratingGold.withValues(alpha: 0.14) : AppColors.brandGreenLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text(badge, style: const TextStyle(fontSize: 38)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(line, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                if (tagline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('“$tagline”', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _earnRow(EarnRule e) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
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
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brandGreenLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('+${e.points}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brandGreen)),
            ),
          ],
        ),
      );

  Widget _levelRow(PointsLevel l, {required bool mark, required bool reached}) {
    final gold = _isGold(l.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mark ? (gold ? AppColors.ratingGold.withValues(alpha: 0.14) : AppColors.brandGreenLight) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mark ? (gold ? AppColors.ratingGold : AppColors.brandGreen) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Opacity(
        opacity: reached || mark ? 1 : 0.55,
        child: Row(
          children: [
            SizedBox(width: 34, child: Text(l.badge, style: const TextStyle(fontSize: 22))),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lv ${l.level} · ${l.name}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text(l.tagline, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!reached && !mark)
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

/// "Level up!" after an action that crossed a level.
Future<void> showLevelUpDialog(BuildContext context, {required int level, String? name}) async {
  final info = ExplorerPointsService.info.value ?? await ExplorerPointsService.loadInfo();
  if (!context.mounted) return;
  final l = info?.level(level);
  final max = info?.levels.length ?? 10;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l?.badge ?? '🎉', style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 10),
            const Text('Level up!',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.brandGreen, letterSpacing: 0.6)),
            const SizedBox(height: 4),
            Text("You're now a ${l?.name ?? name ?? ''}",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Level $level of $max',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            if ((l?.tagline ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('“${l!.tagline}”',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExplorerPointsPage()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('See my points', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Nice!', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}
