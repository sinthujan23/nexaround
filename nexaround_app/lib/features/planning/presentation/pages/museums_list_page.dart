import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/data/museum_repository.dart';
import 'package:nexaround_app/features/planning/domain/museum.dart';
import 'package:nexaround_app/features/planning/presentation/pages/museum_guide_page.dart';

/// Lists all 63 top world museums as premium cards. Tapping one opens the
/// curated guide page where the user picks their available time.
class MuseumsListPage extends StatefulWidget {
  const MuseumsListPage({super.key});

  @override
  State<MuseumsListPage> createState() => _MuseumsListPageState();
}

class _MuseumsListPageState extends State<MuseumsListPage> {
  final _repo = MuseumRepository();

  List<MuseumListItem>? _museums;
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.getMuseums();
      if (!mounted) return;
      setState(() {
        _museums = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<MuseumListItem> get _filtered {
    if (_museums == null) return [];
    if (_search.isEmpty) return _museums!;
    final q = _search.toLowerCase();
    return _museums!
        .where((m) =>
            m.name.toLowerCase().contains(q) ||
            m.city.toLowerCase().contains(q) ||
            m.country.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: const FlexibleSpaceBar(
              title: Text(
                'World\'s Top Museums',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                  ),
                ),
              ),
            ),
          ),

          // ── Search Bar ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search museums, cities, countries…',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brandGreen),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.black),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final museum = _filtered[index];
                  return _MuseumCard(
                    museum: museum,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MuseumGuidePage(museum: museum),
                      ),
                    ),
                  );
                },
                childCount: _filtered.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ── Museum Card ─────────────────────────────────────────────────────────────

class _MuseumCard extends StatelessWidget {
  final MuseumListItem museum;
  final VoidCallback onTap;

  const _MuseumCard({required this.museum, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: museum.rank != null && museum.rank! <= 3
                        ? AppColors.achievementGradient
                        : AppColors.secondaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '#${museum.rank ?? '–'}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: museum.rank != null && museum.rank! <= 3
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        museum.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.place_rounded,
                              size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${museum.city}, ${museum.country}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (museum.annualVisitors != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.people_rounded,
                                size: 12, color: AppColors.textTertiary),
                            const SizedBox(width: 3),
                            Text(
                              '${(museum.annualVisitors! / 1e6).toStringAsFixed(1)}M visitors/year',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Masterpiece count
                if (museum.masterpieceCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brandGreenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${museum.masterpieceCount}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandGreen,
                          ),
                        ),
                        const Text(
                          'items',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.brandGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
