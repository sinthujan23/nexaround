import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_package_detail_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_package_card.dart';

/// The Discovery "Experiences" tab: vendor packages, nearest first.
///
/// Deliberately does **not** go through MapBloc or the banded-places path that
/// the other tabs use. Those exist to ration Google Places calls across three
/// distance bands; this reads first-party rows from our own database with one
/// unbounded nearest-first query, so the whole machinery would be cost without
/// benefit. It also keeps this tab out of the rebuild churn of the BlocBuilder
/// that wraps the Discovery PageView.
class ExperiencesTab extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  const ExperiencesTab({super.key, this.latitude, this.longitude});

  @override
  // Public State type: discover_page holds a GlobalKey<ExperiencesTabState> so
  // it can call refresh() when the tab is selected or the location changes.
  State<ExperiencesTab> createState() => ExperiencesTabState();
}

class _CategoryChip {
  final String? value;
  final String emoji;
  final String label;
  const _CategoryChip(this.value, this.emoji, this.label);
}

const _categories = <_CategoryChip>[
  _CategoryChip(null, '✨', 'All'),
  _CategoryChip('boat', '🛥️', 'Boat'),
  _CategoryChip('water_sports', '🏄', 'Water'),
  _CategoryChip('guided_tour', '🧭', 'Guides'),
  _CategoryChip('wildlife', '🐘', 'Wildlife'),
  _CategoryChip('cultural', '🛕', 'Cultural'),
  _CategoryChip('adventure', '🧗', 'Adventure'),
  _CategoryChip('food', '🍽️', 'Food'),
];

class ExperiencesTabState extends State<ExperiencesTab> {
  final ScrollController _scrollController = ScrollController();

  List<ExperiencePackageEntity> _packages = [];
  String? _category;
  double? _nearestDistanceM;
  bool _hasNearby = false;
  int _total = 0;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// True when we have no coordinate to search from. Distinct from an empty
  /// result: the user needs to be told to enable location, not that there are
  /// no experiences.
  bool _awaitingLocation = false;

  double? _lat;
  double? _lng;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _lat = widget.latitude;
    _lng = widget.longitude;
    _scrollController.addListener(_onScroll);
    if (_lat != null && _lng != null) {
      _load();
    } else {
      // No fix yet. Without this the tab sits on its skeleton indefinitely
      // when location is denied or unavailable, because _fetchForTab returns
      // early in that case and refresh() is never called.
      _loading = false;
      _awaitingLocation = true;
    }
  }

  @override
  void didUpdateWidget(covariant ExperiencesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent rebuilds this widget with fresh coordinates once a fix lands.
    // refresh() covers the tab-selection path; this covers a fix arriving while
    // the tab is already on screen.
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat != null && lng != null && (lat != _lat || lng != _lng)) {
      refresh(lat, lng);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Called by discover_page when the tab is opened or the user moves.
  void refresh(double latitude, double longitude) {
    final moved = _lat != latitude || _lng != longitude;
    final firstFix = _awaitingLocation;
    _lat = latitude;
    _lng = longitude;
    if (moved || firstFix || (_packages.isEmpty && _error == null)) {
      _load();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || _loading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (_lat == null || _lng == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _awaitingLocation = false;
      _page = 0;
    });

    try {
      final result = await ExperiencesService.fetchNearby(
        latitude: _lat!,
        longitude: _lng!,
        category: _category,
      );
      if (!mounted) return;
      setState(() {
        _packages = result.packages;
        _total = result.total;
        _nearestDistanceM = result.nearestDistanceM;
        _hasNearby = result.hasNearby;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load experiences. Pull down to try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_lat == null || _lng == null) return;
    if (_packages.length >= _total) return;
    if (_page + 1 >= ExperiencesService.maxPages) return;

    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await ExperiencesService.fetchNearby(
        latitude: _lat!,
        longitude: _lng!,
        category: _category,
        offset: next * ExperiencesService.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _packages = [..._packages, ...result.packages];
        _page = next;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _selectCategory(String? value) {
    if (_category == value) return;
    setState(() => _category = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          _buildCategoryChips(),
          const SizedBox(height: 20),
          if (!_loading && !_hasNearby && _packages.isNotEmpty)
            _buildDistanceBanner(),
          ..._buildContent(),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final chip = _categories[index];
          final selected = _category == chip.value;
          return GestureDetector(
            onTap: () => _selectCategory(chip.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 86,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.brandGreen : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.brandGreen : AppColors.border,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(chip.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(
                    chip.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDistanceBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.explore_off_rounded,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No experiences nearby — showing the nearest, '
              '${formatDistanceCoarse(_nearestDistanceM)} away.',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent() {
    if (_loading) {
      return List.generate(6, (_) => _buildShimmerCard());
    }

    if (_awaitingLocation) {
      return [
        _buildEmptyState(
          Icons.location_off_rounded,
          'Location needed',
          'Turn on location to see the experiences closest to you.',
        ),
      ];
    }

    if (_error != null) {
      return [
        _buildEmptyState(
          Icons.cloud_off_rounded,
          'Something went wrong',
          _error!,
        ),
      ];
    }

    if (_packages.isEmpty) {
      return [
        _buildEmptyState(
          Icons.kayaking_rounded,
          'No experiences yet',
          _category == null
              ? 'Local agencies are being added soon. Check back shortly.'
              : 'Nothing in this category yet. Try another one.',
        ),
      ];
    }

    return [
      ...List.generate(
        _packages.length,
        (index) => ExperiencePackageCard(
          package: _packages[index],
          index: index,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExperiencePackageDetailPage(
                package: _packages[index],
                userLatitude: _lat,
                userLongitude: _lng,
              ),
            ),
          ),
        ),
      ),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
    ];
  }

  Widget _buildShimmerCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 15, color: Colors.grey[200]),
                const SizedBox(height: 8),
                Container(height: 12, width: 120, color: Colors.grey[200]),
                const SizedBox(height: 10),
                Container(height: 12, width: 80, color: Colors.grey[200]),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 1200.ms, color: Colors.white54);
  }

  Widget _buildEmptyState(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}
