import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_detail_page.dart';
import 'package:nexaround_app/features/mini_tour/data/mini_tour_repository.dart';
import 'package:nexaround_app/core/widgets/converted_currency_text.dart';

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
  bool _loading = true;
  List<Odyssey> _completedTrips = const [];
  List<Map<String, dynamic>> _miniTours = const [];

  @override
  void initState() {
    super.initState();
    // Render the last cached list instantly; the network refresh updates it.
    final cached = _repo.getCachedOdysseys();
    _completedTrips = cached.where((o) => o.status == 'completed').toList();
    _miniTours = CacheService.getMiniTourHistory();
    _loading = _completedTrips.isEmpty && _miniTours.isEmpty;
    
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
        _completedTrips = list.where((o) => o.status == 'completed').toList();
      }
    } catch (_) {
      // Keep whatever we already have.
    }

    // Mini tours: backend first, then merge any local-only (offline) records.
    List<Map<String, dynamic>> tours;
    try {
      final backend = await _miniRepo.getMiniTours();
      final local = CacheService.getMiniTourHistory();
      final seen = backend.map((t) => t['date']).toSet();
      tours = [
        ...backend,
        ...local.where((l) => !seen.contains(l['date'])),
      ]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    } catch (_) {
      tours = CacheService.getMiniTourHistory();
    }

    if (!mounted) return;
    setState(() {
      _miniTours = tours;
      _loading = false;
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
    final tours = _miniTours;
    final bool empty = _completedTrips.isEmpty && tours.isEmpty;

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
          'HISTORY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : empty
              ? _buildEmpty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                  children: [
                    _sectionLabel('COMPLETED TRIPS', _completedTrips.length),
                    if (_completedTrips.isEmpty)
                      _emptyNote('No completed trips yet.')
                    else
                      ..._completedTrips.map(_tripCard),
                    const SizedBox(height: 24),
                    _sectionLabel('COMPLETED WALKS', tours.length),
                    if (tours.isEmpty)
                      _emptyNote('No walks completed yet.')
                    else
                      ...tours.map(_miniTourCard),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history_rounded, size: 56, color: Colors.black26),
            const SizedBox(height: 16),
            const Text(
              'Nothing here yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Finish an Odyssey trip or complete a Walk and it’ll show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _tripCard(Odyssey o) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OdysseyDetailPage(odyssey: o)),
        );
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.neonGreen, size: 24),
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
                  ConvertedCurrencyText(
                    amount: o.budget,
                    originalCurrency: o.currency,
                    prefix: o.destination.isNotEmpty
                        ? '${o.destination} · ${o.days} ${o.days == 1 ? 'Day' : 'Days'} · '
                        : '${o.days} ${o.days == 1 ? 'Day' : 'Days'} · ',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _miniTourCard(Map<String, dynamic> t) {
    final area = (t['area'] ?? 'Walk').toString();
    final places = (t['places'] as List?)?.length ?? 0;
    final xp = (t['xp'] as num?)?.toInt() ?? 0;
    final date = _fmtDate((t['date'] ?? '').toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('🏁', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$places ${places == 1 ? 'place' : 'places'} · +$xp XP'
                  '${date.isNotEmpty ? ' · $date' : ''}',
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
