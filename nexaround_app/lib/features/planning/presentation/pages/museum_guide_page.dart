import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/planning/data/museum_repository.dart';
import 'package:nexaround_app/features/planning/domain/museum.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Displays a curated, time-filtered itinerary for a single museum.
///
/// The user picks a duration (5 Hours / 1 Day / 2 Days) and sees the
/// masterpieces grouped by building in a beautiful vertical timeline.
class MuseumGuidePage extends StatefulWidget {
  final MuseumListItem museum;

  const MuseumGuidePage({super.key, required this.museum});

  @override
  State<MuseumGuidePage> createState() => _MuseumGuidePageState();
}

class _MuseumGuidePageState extends State<MuseumGuidePage> {
  final _repo = MuseumRepository();

  static const _durations = ['5h', '1d', '2d'];
  static const _durationLabels = {'5h': '5 Hours', '1d': '1 Day', '2d': '2 Days'};

  String _selected = '1d';
  MuseumItinerary? _itinerary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _fetch();
  }

  void _loadCache() {
    final cached = _repo.getCachedItinerary(
      slug: widget.museum.slug,
      duration: _selected,
    );
    if (cached != null) {
      _itinerary = cached;
      _loading = false;
    }
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = _itinerary == null;
      _error = null;
    });
    try {
      final it = await _repo.getItinerary(
        slug: widget.museum.slug,
        duration: _selected,
      );
      if (!mounted) return;
      setState(() {
        _itinerary = it;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_itinerary == null) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ── Category → color mapping ─────────────────────────────────────────────
  Color _categoryColor(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('imperial')) return const Color(0xFFDAA520);
    if (lower.contains('renaissance')) return const Color(0xFF1565C0);
    if (lower.contains('sculpture')) return const Color(0xFF6D4C41);
    if (lower.contains('antiquit')) return const Color(0xFFBF360C);
    if (lower.contains('dutch') || lower.contains('flemish')) {
      return const Color(0xFFE65100);
    }
    if (lower.contains('impressioni')) return const Color(0xFF7B1FA2);
    if (lower.contains('modern') || lower.contains('cubism')) {
      return const Color(0xFF00897B);
    }
    if (lower.contains('baroque')) return const Color(0xFF880E4F);
    if (lower.contains('decorative')) return const Color(0xFF00838F);
    if (lower.contains('french')) return const Color(0xFF283593);
    if (lower.contains('spanish')) return const Color(0xFFC62828);
    if (lower.contains('british') || lower.contains('german')) {
      return const Color(0xFF37474F);
    }
    if (lower.contains('treasury')) return const Color(0xFFFF8F00);
    if (lower.contains('architect')) return const Color(0xFF558B2F);
    if (lower.contains('arms')) return const Color(0xFF455A64);
    return AppColors.brandGreen;
  }

  IconData _categoryIcon(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('imperial')) return Icons.castle_rounded;
    if (lower.contains('sculpture')) return Icons.accessibility_new_rounded;
    if (lower.contains('antiquit')) return Icons.temple_hindu_rounded;
    if (lower.contains('decorative')) return Icons.diamond_rounded;
    if (lower.contains('arms')) return Icons.shield_rounded;
    if (lower.contains('treasury')) return Icons.lock_rounded;
    if (lower.contains('architect')) return Icons.architecture_rounded;
    return Icons.palette_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.museum.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.museum.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: widget.museum.imageUrl!.startsWith('/')
                          ? '${ApiConstants.baseUrl}${widget.museum.imageUrl}'
                          : widget.museum.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.charcoal,
                        child: const Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.brandGreen,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.charcoal,
                        child: const Icon(Icons.museum_rounded,
                            color: Colors.white38, size: 80),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.charcoal,
                      child: const Icon(Icons.museum_rounded,
                          color: Colors.white38, size: 80),
                    ),
                  // Gradient scrim
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  // City / Country label
                  Positioned(
                    left: 16,
                    bottom: 56,
                    child: Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.museum.city}, ${widget.museum.country}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Sticky Duration Selector ─────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _DurationHeaderDelegate(
              selected: _selected,
              onChanged: (d) {
                setState(() => _selected = d);
                _fetch();
              },
              labels: _durationLabels,
              durations: _durations,
            ),
          ),

          // ── Ticket Banner ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Material(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    // Open ticket URL or a generic search
                    final url = 'https://www.getyourguide.com/s/?q=${Uri.encodeComponent(widget.museum.name)}';
                    launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.brandGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.confirmation_num_rounded,
                              color: AppColors.brandGreen, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Skip-the-Line Tickets',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Book fast-track entry & guided tours',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white38, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Stats Row ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _statChip(
                    Icons.visibility_rounded,
                    _itinerary != null
                        ? '${_itinerary!.totalItems} Must-See'
                        : '…',
                  ),
                  const SizedBox(width: 10),
                  _statChip(
                    Icons.schedule_rounded,
                    _durationLabels[_selected] ?? _selected,
                  ),
                  if (widget.museum.annualVisitors != null) ...[
                    const SizedBox(width: 10),
                    _statChip(
                      Icons.people_rounded,
                      '${(widget.museum.annualVisitors! / 1e6).toStringAsFixed(1)}M/yr',
                    ),
                  ],
                ],
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
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _fetch,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_itinerary != null)
            ..._buildTimeline(_itinerary!),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Timeline builder ──────────────────────────────────────────────────────

  List<Widget> _buildTimeline(MuseumItinerary itinerary) {
    final slivers = <Widget>[];
    for (int bi = 0; bi < itinerary.buildings.length; bi++) {
      final section = itinerary.buildings[bi];
      // Building header
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.domain_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.building,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${section.items.length} stops',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));

      // Items as timeline cards
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final mp = section.items[index];
            final isFirst = index == 0;
            final isLast = index == section.items.length - 1;
            final color = _categoryColor(mp.category);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Timeline rail ──
                    SizedBox(
                      width: 36,
                      child: Column(
                        children: [
                          if (!isFirst)
                            Expanded(child: Container(width: 2, color: color.withOpacity(0.3)))
                          else
                            const Expanded(child: SizedBox()),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: color.withOpacity(0.3),
                                    blurRadius: 6),
                              ],
                            ),
                          ),
                          if (!isLast)
                            Expanded(child: Container(width: 2, color: color.withOpacity(0.3)))
                          else
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                    ),
                    // ── Card ──
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x08000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: rank + category badge
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_categoryIcon(mp.category),
                                            size: 12, color: color),
                                        const SizedBox(width: 4),
                                        Text(
                                          mp.category,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '#${mp.rank}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Title
                              Text(
                                mp.mustSeeItem,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              if (mp.artist != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  mp.artist!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              // Room
                              Row(
                                children: [
                                  const Icon(Icons.room_rounded,
                                      size: 12,
                                      color: AppColors.textTertiary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      mp.roomGallery,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (mp.description != null &&
                                  mp.description!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  mp.description!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: section.items.length,
        ),
      ));
    }
    return slivers;
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Sticky duration header delegate ─────────────────────────────────────────

class _DurationHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String selected;
  final ValueChanged<String> onChanged;
  final Map<String, String> labels;
  final List<String> durations;

  const _DurationHeaderDelegate({
    required this.selected,
    required this.onChanged,
    required this.labels,
    required this.durations,
  });

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  bool shouldRebuild(covariant _DurationHeaderDelegate old) =>
      old.selected != selected;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Text(
            'I have',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          ...durations.map((d) {
            final isActive = d == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ChoiceChip(
                  label: Text(labels[d] ?? d),
                  selected: isActive,
                  onSelected: (_) => onChanged(d),
                  selectedColor: Colors.black,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : AppColors.textPrimary,
                  ),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
