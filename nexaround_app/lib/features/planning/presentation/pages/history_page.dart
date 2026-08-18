import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_detail_page.dart';
import 'package:nexaround_app/features/mini_tour/data/mini_tour_repository.dart';
import 'package:nexaround_app/core/utils/number_format.dart';

/// Read-back of everything the traveler has finished: completed Odyssey trips
/// (status == 'completed', pulled from the backend) and completed Mini Tours
/// (kept locally in [CacheService]).
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _repo = OdysseyRepository();
  final _miniRepo = MiniTourRepository();
  List<Odyssey> _completedTrips = const [];
  List<Map<String, dynamic>> _miniTours = const [];

  @override
  void initState() {
    super.initState();
    // Render the last cached list instantly; the network refresh updates it in background.
    final cached = _repo.getCachedOdysseys();
    _completedTrips = cached.where((o) => o.status == 'completed').toList();
    _miniTours = CacheService.getMiniTourHistory();
    
    _load();
    OdysseyRepository.revision.addListener(_load);
    CacheService.historyNotifier.addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    OdysseyRepository.revision.removeListener(_load);
    CacheService.historyNotifier.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() => _load();

  Future<void> _load() async {
    // Completed Odyssey trips (server-synced).
    try {
      final list = await _repo.getMyOdysseys();
      if (mounted) {
        setState(() {
          _completedTrips = list.where((o) => o.status == 'completed').toList();
        });
      }
    } catch (_) {
      // Keep whatever we already have from cache.
    }

    // Mini tours: backend first, then merge any local-only (offline) records.
    List<Map<String, dynamic>> tours;
    try {
      final backend = await _miniRepo.getMiniTours();
      final local = CacheService.getMiniTourHistory();
      final seen = backend.map((t) => t['id'] ?? t['date']).toSet();
      tours = [
        ...backend,
        ...local.where((l) => !seen.contains(l['id'] ?? l['date'])),
      ]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
      // Persist permanently to local cache for instant future loads
      CacheService.cacheMiniTourHistory(tours);
    } catch (_) {
      tours = CacheService.getMiniTourHistory();
    }

    // Merge in-progress active tour if not already in list
    final active = CacheService.getActiveMiniTour();
    if (active != null) {
      final activeId = active['id']?.toString();
      final activeDate = active['date']?.toString();
      if (!tours.any((t) => (activeId != null && t['id'] == activeId) || t['date'] == activeDate)) {
        final stopsList = (active['stops'] as List?) ?? [];
        tours.insert(0, {
          'id': active['id'],
          'area': active['area'] ?? 'Walk',
          'places': stopsList.map((s) => (s['name'] ?? '').toString()).toList(),
          'visited_count': active['visited_count'] ?? stopsList.where((s) => s['visited'] == true).length,
          'total_places': active['total_places'] ?? stopsList.length,
          'xp': active['xp'] ?? 0,
          'status': active['status'] ?? 'incomplete',
          'date': active['date'] ?? DateTime.now().toIso8601String(),
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _miniTours = tours;
    });
  }

  DateTime _dateOf(Map<String, dynamic> r) =>
      DateTime.tryParse((r['date'] ?? '').toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'TRAVEL HISTORY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _sectionHeader('COMPLETED ODYSSEYS', _completedTrips.length),
            const SizedBox(height: 10),
            if (_completedTrips.isEmpty)
              _emptyCard('No completed Odyssey trips yet.')
            else
              ..._completedTrips.map(_odysseyCard),
            const SizedBox(height: 28),
            _sectionHeader('MINI TOURS', _miniTours.length),
            const SizedBox(height: 10),
            if (_miniTours.isEmpty)
              _emptyCard('No mini tours recorded yet.')
            else
              ..._miniTours.map(_miniTourCard),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.black54,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Center(
        child: Text(
          msg,
          style: const TextStyle(fontSize: 13, color: Colors.black38),
        ),
      ),
    );
  }

  Widget _odysseyCard(Odyssey o) {
    final prefixText = o.formattedDateRange.isNotEmpty
        ? '${o.destination.isNotEmpty ? "${o.destination} · " : ""}${o.formattedDateRange} · '
        : (o.destination.isNotEmpty
            ? '${o.destination} · ${o.actualDays} ${o.actualDays == 1 ? 'Day' : 'Days'} · '
            : '${o.actualDays} ${o.actualDays == 1 ? 'Day' : 'Days'} · ');

    final int total = o.totalActivities;
    final int done = o.visitedActivities;
    final double pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 1.0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OdysseyDetailPage(odyssey: o),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.flight_takeoff_rounded,
                      color: AppColors.brandGreen, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$prefixText${o.currency} ${formatAmount(o.budget)}',
                        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.black38),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    done == total ? 'All $total stops completed 🎉' : '$done / $total stops visited',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandGreen,
                    ),
                  ),
                  Text(
                    '${(pct * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 5,
                  width: double.infinity,
                  color: const Color(0xFFE2E8F0),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF007A7C)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniTourCard(Map<String, dynamic> t) {
    final area = (t['area'] ?? 'Walk').toString();
    final places = (t['places'] as List?)?.length ?? 0;
    final totalPlaces = (t['total_places'] as num?)?.toInt() ?? places;
    final visitedCount = (t['visited_count'] as num?)?.toInt() ?? places;
    final status = (t['status'] ?? 'completed').toString().toLowerCase();
    final isCompleted = status == 'completed';
    final xp = (t['xp'] as num?)?.toInt() ?? (visitedCount * 20);
    final date = _fmtDate((t['date'] ?? '').toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompleted ? Colors.black12 : Colors.amber.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.brandGreen.withValues(alpha: 0.12)
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isCompleted ? '🏁' : '🚶',
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? AppColors.brandGreen.withValues(alpha: 0.12)
                            : Colors.amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isCompleted ? 'COMPLETED' : 'INCOMPLETE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: isCompleted
                              ? AppColors.brandGreen
                              : const Color(0xFFB45309),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isCompleted
                      ? '$totalPlaces ${totalPlaces == 1 ? 'place' : 'places'} · +$xp XP${date.isNotEmpty ? ' · $date' : ''}'
                      : '$visitedCount of $totalPlaces places · +$xp XP${date.isNotEmpty ? ' · $date' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
