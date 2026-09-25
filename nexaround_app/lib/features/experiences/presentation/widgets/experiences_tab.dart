import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_package_detail_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_category.dart';
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

class ExperiencesTabState extends State<ExperiencesTab> {
  final ScrollController _scrollController = ScrollController();

  List<ExperiencePackageEntity> _packages = [];
  String? _category;
  ExperienceCountry? _selectedCountry;
  List<ExperienceCountry> _availableCountries = [];
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
    _loadCountries();
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

  Future<void> _loadCountries() async {
    final list = await ExperiencesService.fetchActiveCountries();
    if (!mounted) return;
    setState(() {
      if (list.isNotEmpty) {
        _availableCountries = list;
      } else {
        _availableCountries = [
          const ExperienceCountry(code: 'LK', name: 'Sri Lanka', count: 0, latitude: 6.9271, longitude: 79.8612),
          const ExperienceCountry(code: 'AE', name: 'United Arab Emirates', count: 0, latitude: 25.2048, longitude: 55.2708),
          const ExperienceCountry(code: 'TH', name: 'Thailand', count: 0, latitude: 13.7563, longitude: 100.5018),
          const ExperienceCountry(code: 'ID', name: 'Indonesia', count: 0, latitude: -8.3405, longitude: 115.0920),
          const ExperienceCountry(code: 'FR', name: 'France', count: 0, latitude: 48.8566, longitude: 2.3522),
          const ExperienceCountry(code: 'JP', name: 'Japan', count: 0, latitude: 35.6762, longitude: 139.6503),
        ];
      }
    });
  }

  void _selectCountry(ExperienceCountry? country) {
    if (_selectedCountry == country) return;
    setState(() {
      _selectedCountry = country;
      if (country != null && country.latitude != null && country.longitude != null) {
        _lat = country.latitude;
        _lng = country.longitude;
      } else {
        _lat = widget.latitude ?? CacheService.getLastFetchLat();
        _lng = widget.longitude ?? CacheService.getLastFetchLng();
      }
    });
    _load();
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
        countryCode: _selectedCountry?.code,
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
        countryCode: _selectedCountry?.code,
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


  static const _gutter = EdgeInsets.symmetric(horizontal: 24);

  @override
  Widget build(BuildContext context) {
    final showList = !_loading && !_awaitingLocation && _error == null && _packages.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          Padding(padding: _gutter, child: _buildHero()),
          const SizedBox(height: 14),
          Padding(padding: _gutter, child: _buildCountrySelector()),
          const SizedBox(height: 14),
          _buildCategoryChips(),
          const SizedBox(height: 22),
          if (showList && !_hasNearby && _selectedCountry == null)
            Padding(padding: _gutter, child: _buildDistanceBanner()),
          if (showList)
            Padding(padding: _gutter, child: _buildSectionHeader()),
          ..._buildContent().map((w) => Padding(padding: _gutter, child: w)),
        ],
      ),
    );
  }

  /// The country dropdown / pill selector.
  Widget _buildCountrySelector() {
    final hasCountry = _selectedCountry != null;
    return Row(
      children: [
        InkWell(
          onTap: _showCountryPicker,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: hasCountry ? AppColors.brandGreenLight : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasCountry ? AppColors.brandGreen : AppColors.border,
                width: hasCountry ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasCountry ? _selectedCountry!.flag : '📍',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(width: 8),
                Text(
                  hasCountry ? _selectedCountry!.name : 'Near Me (GPS)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: hasCountry ? AppColors.brandGreen : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: hasCountry ? AppColors.brandGreen : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (hasCountry) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _selectCountry(null),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text(
                    'Reset',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: const [
                    Icon(Icons.public_rounded, color: AppColors.brandGreen, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Select Destination',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Browse experiences in specific countries or near your current spot.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.border),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Near Me option
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _selectedCountry == null
                              ? AppColors.brandGreenLight
                              : AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.near_me_rounded,
                          color: _selectedCountry == null
                              ? AppColors.brandGreen
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Near Me (Current Location)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      subtitle: const Text(
                        'Experiences closest to your current spot',
                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                      ),
                      trailing: _selectedCountry == null
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _selectCountry(null);
                      },
                    ),
                    const Divider(indent: 20, endIndent: 20, height: 1, color: AppColors.border),
                    // Countries list
                    ..._availableCountries.map((c) {
                      final isSelected = _selectedCountry?.code == c.code;
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.brandGreenLight
                                : AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(c.flag, style: const TextStyle(fontSize: 20)),
                        ),
                        title: Text(
                          c.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 15,
                            color: isSelected ? AppColors.brandGreen : AppColors.textPrimary,
                          ),
                        ),
                        subtitle: c.count > 0
                            ? Text(
                                '${c.count} ${c.count == 1 ? 'experience' : 'experiences'}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen)
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          _selectCountry(c);
                        },
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// The banner at the top of the tab. Its last line tracks the load, so it
  /// doubles as the status line.
  Widget _buildHero() {
    final String status;
    if (_selectedCountry != null) {
      if (_loading) {
        status = 'Finding experiences in ${_selectedCountry!.name}…';
      } else if (_error != null) {
        status = 'Pull down to try again';
      } else if (_packages.isEmpty) {
        status = 'No experiences available in ${_selectedCountry!.name} yet';
      } else {
        final count = '$_total ${_total == 1 ? 'experience' : 'experiences'}';
        status = '$count in ${_selectedCountry!.name}';
      }
    } else if (_awaitingLocation) {
      status = 'Turn on location to see what is around you';
    } else if (_loading) {
      status = 'Finding experiences around you…';
    } else if (_error != null) {
      status = 'Pull down to try again';
    } else if (_packages.isEmpty) {
      status = 'Local operators are joining soon';
    } else {
      final count = '$_total ${_total == 1 ? 'experience' : 'experiences'}';
      status = _nearestDistanceM == null
          ? count
          : '$count · nearest ${formatDistanceCoarse(_nearestDistanceM)} away';
    }

    final badgeText = _selectedCountry != null
        ? '${_selectedCountry!.flag} ${_selectedCountry!.name.toUpperCase()}'
        : 'LOCAL EXPERIENCES';

    final heroTitle = _selectedCountry != null
        ? 'Explore\n${_selectedCountry!.name}'
        : 'Do something\nunforgettable';

    return Container(
      height: 156,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00A3A6), AppColors.brandGreen, AppColors.brandGreenDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreen.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -36, top: -44, child: _bubble(150, 0.10)),
          Positioned(right: 70, bottom: -60, child: _bubble(120, 0.07)),
          const Positioned(
            right: 20,
            bottom: 18,
            child: Text('🛥️', style: TextStyle(fontSize: 54)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 90, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  heroTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _selectedCountry != null ? Icons.place_rounded : Icons.near_me_rounded,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }

  static Widget _bubble(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: _gutter,
        itemCount: experienceCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final chip = experienceCategories[index];
          final selected = _category == chip.value;
          return GestureDetector(
            onTap: () => _selectCategory(chip.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                // Charcoal, not brand green: the Discovery tab bar right above
                // already uses green for its selection.
                color: selected ? AppColors.charcoal : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? AppColors.charcoal : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(chip.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text(
                    chip.chipLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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

  Widget _buildSectionHeader() {
    final String title;
    if (_selectedCountry != null) {
      title = _category == null
          ? 'Experiences in ${_selectedCountry!.name}'
          : '${experienceCategoryFor(_category).label} in ${_selectedCountry!.name}';
    } else {
      title = _category == null
          ? 'Nearest to you'
          : '${experienceCategoryFor(_category).label} near you';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const Text(
            'Closest first',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandGreenLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.explore_rounded, size: 18, color: AppColors.brandGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No experiences nearby yet. Showing the nearest, '
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
      return List.generate(3, (_) => _buildShimmerCard());
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
          actionLabel: 'Try again',
          onAction: _load,
        ),
      ];
    }

    if (_packages.isEmpty) {
      return [
        _category == null
            ? _buildEmptyState(
                Icons.kayaking_rounded,
                'No experiences yet',
                'Local agencies are being added soon. Check back shortly.',
              )
            : _buildEmptyState(
                Icons.kayaking_rounded,
                'Nothing here yet',
                'No ${experienceCategoryFor(_category).label.toLowerCase()} experiences nearby. Try another category.',
                actionLabel: 'Show all',
                onAction: () => _selectCategory(null),
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

  /// Same shape as ExperiencePackageCard, so the swap to real cards does not
  /// jump.
  Widget _buildShimmerCard() {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(color: Colors.grey[200]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(220, 16),
                const SizedBox(height: 10),
                bar(140, 12),
                const SizedBox(height: 18),
                Row(
                  children: [
                    bar(70, 26),
                    const Spacer(),
                    bar(90, 20),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 1200.ms, color: Colors.white54);
  }

  Widget _buildEmptyState(
    IconData icon,
    String title,
    String body, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandGreenLight,
            ),
            child: Icon(icon, size: 32, color: AppColors.brandGreen),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandGreen,
                side: const BorderSide(color: AppColors.brandGreen),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}
