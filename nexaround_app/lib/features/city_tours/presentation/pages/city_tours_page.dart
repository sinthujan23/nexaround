import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tour_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';
import 'package:video_player/video_player.dart';

/// Curated Hubs → City Tours: the cities that have guides, under the header
/// video. A city with one guide opens it straight away; with more, its list
/// of guides.
class CityToursPage extends StatefulWidget {
  const CityToursPage({super.key});

  @override
  State<CityToursPage> createState() => _CityToursPageState();
}

const _navy = Color(0xFF0F172A);

class _CityToursPageState extends State<CityToursPage> {
  final _service = CityToursService();
  VideoPlayerController? _videoController;
  final TextEditingController _searchController = TextEditingController();
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
    final cached = _service.cachedTours();
    if (cached.isNotEmpty) {
      _tours = cached;
      _loading = false;
    }
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
          _videoController?.play();
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  // The search button opens a search box in the top bar; its close button
  // clears the search too.
  void _toggleSearch() {
    if (_searching) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _searching
                ? Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search cities, countries…',
                        hintStyle: TextStyle(
                            fontSize: 14, color: AppColors.textTertiary),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 10),
          _CircleButton(
            icon: _searching
                ? Icons.close_rounded
                : Icons.search_rounded,
            onTap: _toggleSearch,
          ),
        ],
      ),
    );
  }

  // The header video in a rounded window, with the title on it.
  Widget _videoWindow() {
    final video = _videoController;
    return Container(
      height: 252,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.24),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
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
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x000F172A), Color(0xE60F172A)],
                  stops: [0.35, 1.0],
                ),
              ),
            ),
            const Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'City Guides',
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Where to start, which ride to take and what to see at every stop, with tickets and tours on the way.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: Color(0xD9FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counters(List<CityTourCity> cities, List<String> countries) {
    final guides = _tours?.length ?? 0;
    return Row(
      children: [
        Expanded(
          child: _Counter(
            icon: Icons.apartment_rounded,
            value: cities.length,
            label: cities.length == 1 ? 'city' : 'cities',
            tint: const Color(0xFFE6F6F5),
            colour: const Color(0xFF0D9488),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Counter(
            icon: Icons.alt_route_rounded,
            value: guides,
            label: guides == 1 ? 'guide' : 'guides',
            tint: const Color(0xFFEFEAFE),
            colour: const Color(0xFF7C3AED),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Counter(
            icon: Icons.public_rounded,
            value: countries.length,
            label: countries.length == 1 ? 'country' : 'countries',
            tint: const Color(0xFFFEF3DC),
            colour: const Color(0xFFD97706),
          ),
        ),
      ],
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
    const side = EdgeInsets.symmetric(horizontal: 16);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.brandGreen,
                  onRefresh: _fetch,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                        bottom: 32 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      Padding(padding: side, child: _videoWindow()),
                      if (cities.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(padding: side, child: _counters(cities, countries)),
                      ],
                      if (countries.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _chips(countries),
                      ],
                      const SizedBox(height: 14),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.brandGreen),
                          ),
                        )
                      else if (_error != null)
                        _Message(
                          icon: Icons.wifi_off_rounded,
                          title: _error!,
                          action: TextButton(
                            onPressed: () {
                              setState(() => _loading = true);
                              _fetch();
                            },
                            child: const Text('Try again'),
                          ),
                        )
                      else if (cities.isEmpty)
                        const _Message(
                          icon: Icons.route_rounded,
                          title: 'No city guides yet',
                          text: 'New cities are on the way.',
                        )
                      else if (filtered.isEmpty)
                        const _Message(
                          icon: Icons.search_rounded,
                          title: 'No cities match',
                        )
                      else
                        Padding(padding: side, child: _wall(filtered)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Page parts ──────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 20, color: _navy),
        ),
      ),
    );
  }
}

/// A count under the video (cities, guides, countries) with its two-tone
/// icon on a soft colour tile.
class _Counter extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color tint;
  final Color colour;

  const _Counter({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF0F3)),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: colour),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                // shrinks rather than cuts "countries" on narrow phones
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

/// A city's guides, when it has more than one.
class CityTourListPage extends StatelessWidget {
  final CityTourCity city;

  const CityTourListPage({super.key, required this.city});

  @override
  Widget build(BuildContext context) {
    final count = city.tours.length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              city.city,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              [if (city.country.isNotEmpty) city.country, '$count guides'].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 22),
        itemBuilder: (_, i) => CityTourCardTile(
          card: city.tours[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CityTourPage(card: city.tours[i])),
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
