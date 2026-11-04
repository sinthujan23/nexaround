import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tour_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tours_classic_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';

/// Curated Hubs → City Guides home: "Where to next?" over big photo cards to
/// swipe through, one per city (the first five), with dots under them and
/// the other cities in a row below. A city with one guide opens it straight
/// away; with more, its list of guides. The search button swaps the heading
/// for a search box and the cards for a plain list of the matching cities.
///
/// [isTab]: shown as a bottom-navbar tab (no back button). [isActive]: whether
/// that tab is the one on screen; the page loads on its first showing.
class CityToursPage extends StatefulWidget {
  final bool isTab;
  final bool isActive;

  const CityToursPage({super.key, this.isTab = false, this.isActive = true});

  @override
  State<CityToursPage> createState() => _CityToursPageState();
}

/// true: show the previous City Guides home instead (header video, country
/// chips, photo wall; city_tours_classic_page.dart), if this one is dropped.
const bool kClassicCityGuidesHome = false;

const _navy = Color(0xFF0F172A);
const _slate = Color(0xFF64748B);
const _hint = Color(0xFF94A3B8);

// How many cities get a big card. The row under the cards has every city
// but the one on screen; See all lists them all.
const int _featuredCount = 5;

bool _sameCity(CityTourCity a, CityTourCity b) => a.city == b.city && a.country == b.country;

/// A city with one guide opens it straight away; with more, its list of guides.
void _openCityPage(BuildContext context, CityTourCity city) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => city.tours.length == 1
          ? CityTourPage(card: city.tours.first)
          : CityTourListPage(city: city),
    ),
  );
}

class _CityToursPageState extends State<CityToursPage> {
  final _service = CityToursService();
  final TextEditingController _searchController = TextEditingController();
  final PageController _pages = PageController();
  bool _started = false;
  bool _searching = false;
  int _page = 0;

  List<CityTourCard>? _tours;
  bool _loading = true;
  String? _error;
  String _search = '';

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
    if (widget.isActive) _start();
  }

  @override
  void didUpdateWidget(covariant CityToursPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _start();
  }

  // First showing: load the guides.
  void _start() {
    if (_started || kClassicCityGuidesHome) return;
    _started = true;
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pages.dispose();
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

  void _openCity(CityTourCity city) => _openCityPage(context, city);

  void _seeAll(List<CityTourCity> cities) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _AllCitiesPage(cities: cities)),
    );
  }

  // The search button opens the search box in the heading's place; its close
  // button clears the search and brings the cards back.
  void _toggleSearch() {
    if (_searching) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
    }
    setState(() => _searching = !_searching);
  }

  List<CityTourCity> _matches(List<CityTourCity> cities) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return cities;
    return cities
        .where((c) =>
            c.city.toLowerCase().contains(q) ||
            c.country.toLowerCase().contains(q) ||
            c.tours.any((t) => t.title.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (kClassicCityGuidesHome) {
      return CityToursClassicPage(isTab: widget.isTab, isActive: widget.isActive);
    }
    final cities = CityTourCity.group(_tours ?? const []);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status bar icons on the white page.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.brandGreen,
                  onRefresh: _fetch,
                  child: _content(cities),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          if (!widget.isTab) ...[
            _CircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 18,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: _searching ? _searchBox() : _heading(),
            ),
          ),
          const SizedBox(width: 12),
          _CircleButton(
            icon: _searching ? Icons.close_rounded : Icons.search_rounded,
            onTap: _toggleSearch,
          ),
        ],
      ),
    );
  }

  Widget _heading() {
    return const Padding(
      key: ValueKey('heading'),
      padding: EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CITY GUIDES',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: AppColors.brandGreen,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Where to next?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: _navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      key: const ValueKey('search'),
      width: double.infinity,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15),
        decoration: const InputDecoration(
          hintText: 'Search cities or countries',
          hintStyle: TextStyle(fontSize: 15, color: AppColors.textTertiary),
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

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _content(List<CityTourCity> cities) {
    // Clear of the floating navbar (the home page's body runs under it).
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    if (_loading) {
      return _fill(const CircularProgressIndicator(color: AppColors.brandGreen));
    }
    if (_error != null) {
      return _fill(_Message(
        icon: Icons.wifi_off_rounded,
        title: _error!,
        action: TextButton(
          onPressed: () {
            setState(() => _loading = true);
            _fetch();
          },
          child: const Text('Try again'),
        ),
      ));
    }
    if (cities.isEmpty) {
      return _fill(const _Message(
        icon: Icons.route_outlined,
        title: 'No city guides yet',
        text: 'New cities are on the way.',
      ));
    }

    if (_searching) {
      final found = _matches(cities);
      if (found.isEmpty) {
        return _fill(const _Message(icon: Icons.search_off_rounded, title: 'No cities match'));
      }
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
        itemCount: found.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (_, i) => _CityRow(city: found[i], onTap: () => _openCity(found[i])),
      );
    }

    final featured = cities.take(_featuredCount).toList();
    final shown = featured[_page.clamp(0, featured.length - 1)];
    // Every city but the one on the card, so the row changes as cards swipe.
    final others = cities.where((c) => !_sameCity(c, shown)).toList();
    // A little shorter with the row under it, so more of the row shows.
    final cardHeight =
        (MediaQuery.sizeOf(context).height * (others.isEmpty ? 0.56 : 0.5)).clamp(340.0, 480.0);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: 6, bottom: bottom),
      children: [
        SizedBox(
          // Room under the card for its shadow.
          height: cardHeight + 26,
          child: PageView.builder(
            controller: _pages,
            itemCount: featured.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
              child: _FeaturedCard(city: featured[i], onTap: () => _openCity(featured[i])),
            ),
          ),
        ),
        if (featured.length > 1)
          _Dots(count: featured.length, index: _page.clamp(0, featured.length - 1)),
        if (others.isEmpty) const _Soon(),
        if (others.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'More cities',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _navy),
                  ),
                ),
                TextButton(
                  onPressed: () => _seeAll(cities),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brandGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('See all', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Icon(Icons.chevron_right_rounded, size: 19),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _SmallCityCard(city: others[i], onTap: () => _openCity(others[i])),
            ),
          ),
        ],
      ],
    );
  }

  // A message or spinner in the middle, still pull-to-refresh.
  Widget _fill(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: constraints.maxHeight, child: Center(child: child)),
        ],
      ),
    );
  }
}

// ── Page parts ──────────────────────────────────────────────────────────────

/// A white round button with a thin grey edge: back, search, close.
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, this.size = 22, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: Color(0xFFE5E7EB))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: size, color: _navy)),
      ),
    );
  }
}

/// A city's cover photo, or a soft gradient when it has none.
class _Cover extends StatelessWidget {
  final String url;
  final int cacheWidth;

  const _Cover({required this.url, required this.cacheWidth});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.secondaryGradient));
    }
    return CachedNetworkImage(
      imageUrl: cityTourMediaUrl(url),
      fit: BoxFit.cover,
      memCacheWidth: cacheWidth,
      placeholder: (_, __) => Container(color: AppColors.surface),
      errorWidget: (_, __, ___) => Container(
        color: AppColors.surface,
        child: const Icon(Icons.location_city_outlined, size: 32, color: AppColors.textTertiary),
      ),
    );
  }
}

/// Frosted dark glass over a photo.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const _Glass({required this.child, this.radius = 12, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _navy.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A glass chip on a photo: a line icon and a short label.
class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double fontSize;

  const _GlassChip({required this.icon, required this.label, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 3, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// A city's big card: its photo, the place in a glass chip, an open arrow,
/// and at the bottom the guide's name, its stops and days, and Open guide.
/// A city with several guides shows its name, how many, and See N guides.
class _FeaturedCard extends StatelessWidget {
  final CityTourCity city;
  final VoidCallback onTap;

  const _FeaturedCard({required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = city.tours.length;
    final single = count == 1 ? city.tours.first : null;
    final place = [city.city, city.country].where((s) => s.isNotEmpty).join(', ');
    final title = single != null && single.title.isNotEmpty ? single.title : city.city;
    final chips = <Widget>[
      if (single == null)
        _GlassChip(icon: Icons.auto_stories_outlined, label: '$count guides')
      else ...[
        if (single.stopCount > 0)
          _GlassChip(
            icon: Icons.route_outlined,
            label: single.stopCount == 1 ? '1 stop' : '${single.stopCount} stops',
          ),
        if (single.dayCount > 0)
          _GlassChip(
            icon: Icons.calendar_today_outlined,
            label: single.dayCount == 1 ? '1 day' : '${single.dayCount} days',
          )
        else if (single.duration.isNotEmpty)
          _GlassChip(icon: Icons.schedule_outlined, label: single.duration),
      ],
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Cover(url: city.coverUrl, cacheWidth: 1000),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xC7000000), Color(0x00000000)],
                    stops: [0.0, 0.6],
                  ),
                ),
              ),
              if (place.isNotEmpty)
                Positioned(
                  top: 14,
                  left: 14,
                  right: 66,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _GlassChip(icon: Icons.location_on_outlined, label: place, fontSize: 13),
                  ),
                ),
              const Positioned(
                top: 14,
                right: 14,
                child: _Glass(
                  radius: 19,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.north_east_rounded, size: 19, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: chips),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            single != null ? 'Open guide' : 'See $count guides',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 19, color: _navy),
                        ],
                      ),
                    ),
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

/// Which big card is on screen: the picked dot stretches into a teal bar.
class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index ? AppColors.brandGreen : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// Under a lone city's card.
class _Soon extends StatelessWidget {
  const _Soon();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_location_alt_outlined, size: 18, color: _hint),
          SizedBox(width: 7),
          Text(
            'More cities are on the way',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _hint),
          ),
        ],
      ),
    );
  }
}

/// A city in the "More cities" row: a small photo card with its name.
class _SmallCityCard extends StatelessWidget {
  final CityTourCity city;
  final VoidCallback onTap;

  const _SmallCityCard({required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 132,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Cover(url: city.coverUrl, cacheWidth: 400),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                    stops: [0.0, 0.6],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      city.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    if (city.country.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: Color(0xE6FFFFFF)),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              city.country,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xE6FFFFFF)),
                            ),
                          ),
                        ],
                      ),
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

/// A city in the search results: thumbnail, name, country and what it has.
class _CityRow extends StatelessWidget {
  final CityTourCity city;
  final VoidCallback onTap;

  const _CityRow({required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = city.tours.length;
    final days = count == 1 ? city.tours.first.dayCount : 0;
    final what = count > 1
        ? '$count guides'
        : days > 0
            ? (days == 1 ? '1 day' : '$days days')
            : '1 guide';
    final line = [if (city.country.isNotEmpty) city.country, what].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(width: 56, height: 56, child: _Cover(url: city.coverUrl, cacheWidth: 200)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _navy),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: _slate),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: _slate),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: Color(0xFFF0FDFA), shape: BoxShape.circle),
              child: const Icon(Icons.north_east_rounded, size: 18, color: AppColors.brandGreen),
            ),
          ],
        ),
      ),
    );
  }
}

/// "See all": every city as a plain list.
class _AllCitiesPage extends StatelessWidget {
  final List<CityTourCity> cities;

  const _AllCitiesPage({required this.cities});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        titleSpacing: 0,
        title: const Text(
          'All cities',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
      ),
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: cities.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (_, i) => _CityRow(city: cities[i], onTap: () => _openCityPage(context, cities[i])),
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
