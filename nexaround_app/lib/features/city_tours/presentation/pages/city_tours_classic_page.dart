import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tour_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tours_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';
import 'package:video_player/video_player.dart';

/// The City Guides home as it was before the "Where to next?" cards (kept so
/// it can come back: set kClassicCityGuidesHome in city_tours_page.dart).
///
/// Curated Hubs → City Tours: the cities that have guides, under the header
/// video, which shrinks to a white bar as the page scrolls. A city with one
/// guide opens it straight away; with more, its list of guides.
///
/// [isTab]: shown as a bottom-navbar tab (no back button). [isActive]: whether
/// that tab is the one on screen; the page loads on its first showing and its
/// header video only plays while it is showing.
class CityToursClassicPage extends StatefulWidget {
  final bool isTab;
  final bool isActive;

  const CityToursClassicPage({super.key, this.isTab = false, this.isActive = true});

  @override
  State<CityToursClassicPage> createState() => _CityToursClassicPageState();
}

const _navy = Color(0xFF0F172A);

// The header video's height, as before the redesign.
const double _headerHeight = 200;

class _CityToursClassicPageState extends State<CityToursClassicPage> {
  final _service = CityToursService();
  VideoPlayerController? _videoController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  bool _searching = false;

  List<CityTourCard>? _tours;
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _search = _searchController.text);
    });
    _scrollController.addListener(() {
      if (!mounted) return;
      final collapsedOffset = _headerHeight - kToolbarHeight - 24;
      final isScrolled = _scrollController.hasClients &&
          _scrollController.offset > collapsedOffset;
      if (isScrolled != _isScrolled) {
        setState(() => _isScrolled = isScrolled);
      }
    });
    final cached = _service.cachedTours();
    if (cached.isNotEmpty) {
      _tours = cached;
      _loading = false;
    }
    if (widget.isActive) _start();
  }

  @override
  void didUpdateWidget(covariant CityToursClassicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive == oldWidget.isActive) return;
    if (widget.isActive) {
      if (_videoController == null) {
        _start();
      } else if (_videoController!.value.isInitialized) {
        _videoController!.play();
      }
    } else {
      _videoController?.pause();
    }
  }

  // First showing: load the guides and start the header video.
  void _start() {
    _fetch();
    _initVideo();
  }

  // The header's looping, silent video; the photo shows until it is ready.
  void _initVideo() {
    _videoController = VideoPlayerController.asset(
      'assets/animations/city_guides_banner.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..setVolume(0.0)
     ..initialize().then((_) {
        if (mounted) {
          _videoController?.setLooping(true);
          _videoController?.setVolume(0.0);
          // The tab may have been left while the video was loading.
          if (widget.isActive) _videoController?.play();
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final tours = await _service.getTours();
      if (!mounted) return;
      setState(() {
        _tours = tours;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Saved guides stay on screen; only an empty page shows the error.
        if ((_tours ?? const []).isEmpty) {
          _error = userMessageFor(e, action: 'load city guides');
        }
      });
    }
  }

  void _openCity(CityTourCity city) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => city.tours.length == 1
            ? CityTourPage(card: city.tours.first)
            : CityTourListPage(city: city),
      ),
    );
  }

  // The search button opens a search box under the header (scrolling back up
  // to it); its close button clears the search too.
  void _toggleSearch() {
    if (_searching) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
    } else if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _searching = !_searching);
  }

  List<String> _countries(List<CityTourCity> cities) {
    final set = cities.map((c) => c.country).where((c) => c.isNotEmpty).toSet();
    return set.toList()..sort();
  }

  List<CityTourCity> _filter(List<CityTourCity> cities) {
    var list = cities;
    if (_selectedCountry != null) {
      list = list.where((c) => c.country == _selectedCountry).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((c) =>
              c.city.toLowerCase().contains(q) ||
              c.country.toLowerCase().contains(q) ||
              c.tours.any((t) => t.title.toLowerCase().contains(q)))
          .toList();
    }
    return list;
  }

  /// A round button on the header: dark glass on the video, light grey once
  /// the header has shrunk to the white bar.
  Widget _barButton({required IconData icon, required double size, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: _isScrolled
              ? Colors.black.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: size, color: _isScrolled ? Colors.black : Colors.white),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: const InputDecoration(
          hintText: 'Search cities, countries…',
          hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          prefixIcon: Icon(Icons.search_rounded, color: AppColors.textTertiary),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _chips(List<String> countries) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: countries.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          // the first chip is "All"; tapping a picked country unpicks it
          final country = i == 0 ? null : countries[i - 1];
          final on = _selectedCountry == country;
          final colour = on ? Colors.white : AppColors.textSecondary;
          return GestureDetector(
            onTap: () => setState(
                () => _selectedCountry = on && country != null ? null : country),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? _navy : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (country == null) ...[
                    Icon(Icons.grid_view_rounded, size: 14, color: colour),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    country ?? 'All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      color: colour,
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

  // The cities as a photo wall: two columns whose tiles take turns at
  // different heights.
  Widget _wall(List<CityTourCity> cities) {
    const leftHeights = [214.0, 158.0, 200.0];
    const rightHeights = [158.0, 214.0, 190.0];
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < cities.length; i++) {
      final column = i.isEven ? left : right;
      final heights = i.isEven ? leftHeights : rightHeights;
      if (column.isNotEmpty) column.add(const SizedBox(height: 10));
      final city = cities[i];
      column.add(_CityTile(
        city: city,
        height: heights[(i ~/ 2) % heights.length],
        onTap: () => _openCity(city),
      ));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: 10),
        Expanded(child: Column(children: right)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cities = CityTourCity.group(_tours ?? const []);
    final countries = _countries(cities);
    final filtered = _filter(cities);
    final video = _videoController;
    const side = EdgeInsets.symmetric(horizontal: 16);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.brandGreen,
        onRefresh: _fetch,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── App Bar ────────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: _headerHeight,
              backgroundColor: _isScrolled ? Colors.white : _navy,
              elevation: _isScrolled ? 2 : 0,
              scrolledUnderElevation: 2,
              // As a tab there is nothing to go back to.
              automaticallyImplyLeading: false,
              leading: widget.isTab
                  ? null
                  : _barButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      onTap: () => Navigator.pop(context),
                    ),
              actions: [
                _barButton(
                  icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                  size: 20,
                  onTap: _toggleSearch,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                title: Text(
                  'City Guides',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _isScrolled ? Colors.black : Colors.white,
                    shadows: _isScrolled
                        ? null
                        : const [
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video != null && video.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: video.value.size.width,
                          height: video.value.size.height,
                          child: VideoPlayer(video),
                        ),
                      )
                    else
                      Image.asset(
                        'assets/images/city_tours_bg.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                            ),
                          ),
                        ),
                      ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black38, Colors.black87],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Search & country filter ────────────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _searchBox(),
                    ),
                  if (countries.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _chips(countries),
                  ],
                  const SizedBox(height: 14),
                ],
              ),
            ),

            // ── Content ────────────────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.brandGreen),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Message(
                  icon: Icons.wifi_off_rounded,
                  title: _error!,
                  action: TextButton(
                    onPressed: () {
                      setState(() => _loading = true);
                      _fetch();
                    },
                    child: const Text('Try again'),
                  ),
                ),
              )
            else if (cities.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _Message(
                  icon: Icons.route_rounded,
                  title: 'No city guides yet',
                  text: 'New cities are on the way.',
                ),
              )
            else if (filtered.isEmpty)
              const SliverToBoxAdapter(
                child: _Message(
                  icon: Icons.search_rounded,
                  title: 'No cities match',
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(padding: side, child: _wall(filtered)),
              ),

            SliverToBoxAdapter(
              child: SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page parts ──────────────────────────────────────────────────────────────

/// A city on the photo wall: its cover, the guide count, an open arrow, and
/// the name and country at the bottom.
class _CityTile extends StatelessWidget {
  final CityTourCity city;
  final double height;
  final VoidCallback onTap;

  const _CityTile({required this.city, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = city.tours.length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (city.coverUrl.isEmpty)
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.secondaryGradient,
                  ),
                )
              else
                CachedNetworkImage(
                  imageUrl: cityTourMediaUrl(city.coverUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 600, // half-width tile at 3x DPR
                  placeholder: (_, __) => Container(color: AppColors.surface),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surface,
                    child: const Icon(
                      Icons.location_city_rounded,
                      size: 32,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xBF000000), Color(0x00000000)],
                    stops: [0.0, 0.55],
                  ),
                ),
              ),
              Positioned(
                top: 9,
                left: 9,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.alt_route_rounded, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        count == 1 ? '1 guide' : '$count guides',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.north_east_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      city.city,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (city.country.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              size: 12, color: Color(0xE6FFFFFF)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              city.country,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xE6FFFFFF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  const _Message({required this.icon, required this.title, this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(
              text!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
