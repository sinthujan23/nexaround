import 'dart:async';
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

// How many cities get a big card. The row under the cards, which stays put
// while they play, has the cities after them (all of them when they all fit
// on cards); See all lists every city.
const int _featuredCount = 5;

// The home's fixed heights, which size the big card so the page fits the
// screen: the card gets whatever these leave.
const double _cardRoom = 26; // 4 above the card, 22 under it for its shadow
const double _dotsHeight = 7;
const double _soonHeight = 22; // "More cities are on the way"
const double _rowTitleHeight = 56; // 14 above, the 36 title row, 6 under
const double _rowHeight = 140;
const double _endGap = 12; // above the navbar

// The cards loop: their PageView has no end and page n shows city n % count.
// It starts far in, so a first swipe back works too; 6000 is a multiple of
// every count up to _featuredCount (5), so it opens on the first city.
const int _loopStart = 6000;
// Like the big apps' carousels: the next card slides in every few seconds.
const Duration _autoPlayEvery = Duration(seconds: 5);
const Duration _autoPlaySlide = Duration(milliseconds: 650);

/// TURN OFF BEFORE A STORE RELEASE. true: six sample cities follow the real
/// ones, each tagged SAMPLE, so the TL and the client can see the home with
/// many guides. Their photos are app assets (assets/images/city_sample_*.jpg);
/// nothing is on the server, and a tap on one only says it is a sample.
const bool kCityGuidesSampleCities = true;

const String _samplePrefix = 'sample-';

const List<CityTourCard> _sampleTours = [
  CityTourCard(
    id: '${_samplePrefix}tokyo',
    city: 'Tokyo',
    country: 'Japan',
    title: 'Tokyo in Bloom: Parks, Temples and Neon Streets',
    summary: '',
    coverUrl: 'asset:assets/images/city_sample_tokyo.jpg',
    duration: '',
    budget: '',
    stopCount: 28,
    dayCount: 4,
  ),
  CityTourCard(
    id: '${_samplePrefix}singapore',
    city: 'Singapore',
    country: 'Singapore',
    title: 'Singapore: Hawker Halls to Garden Domes',
    summary: '',
    coverUrl: 'asset:assets/images/city_sample_singapore.jpg',
    duration: '',
    budget: '',
    stopCount: 22,
    dayCount: 3,
  ),
  CityTourCard(
    id: '${_samplePrefix}cusco',
    city: 'Cusco',
    country: 'Peru',
    title: 'Cusco: Inca Stones and Andean Markets',
    summary: '',
    coverUrl: 'asset:assets/images/city_sample_cusco.jpg',
    duration: '',
    budget: '',
    stopCount: 18,
    dayCount: 3,
  ),
  CityTourCard(
    id: '${_samplePrefix}hongkong',
    city: 'Hong Kong',
    country: 'Hong Kong',
    title: 'Hong Kong: Harbour, Peaks and Night Markets',
    summary: '',
    coverUrl: 'asset:assets/images/city_sample_hongkong.jpg',
    duration: '',
    budget: '',
    stopCount: 24,
    dayCount: 3,
  ),
  CityTourCard(
    id: '${_samplePrefix}oaxaca',
    city: 'Oaxaca',
    country: 'Mexico',
    title: 'Oaxaca: Colour, Mezcal and Old Churches',
    summary: '',
    coverUrl: 'asset:assets/images/city_sample_oaxaca.jpg',
    duration: '',
    budget: '',
    stopCount: 16,
    dayCount: 2,
  ),
  CityTourCard(
    id: '${_samplePrefix}bangkok',
    city: 'Bangkok',
    country: 'Thailand',
    title: 'Bangkok: Temples, Canals and Street Food',
    summary: '',
    coverUrl: 'asset:assets/images/city_sample_bangkok.jpg',
    duration: '',
    budget: '',
    stopCount: 26,
    dayCount: 3,
  ),
];

extension on CityTourCity {
  bool get isSample => tours.first.id.startsWith(_samplePrefix);
}

/// A city with one guide opens it straight away; with more, its list of guides.
/// A sample city only says what it is.
void _openCityPage(BuildContext context, CityTourCity city) {
  if (city.isSample) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('A sample city, to show the layout. It has no guide yet.'),
      ));
    return;
  }
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
  final PageController _pages = PageController(initialPage: _loopStart);
  Timer? _autoPlay;
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
    _restartAutoPlay();
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
    _autoPlay?.cancel();
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

  // Every few seconds the next card slides in, round from the last to the
  // first. A finger on the cards holds it; it starts again a full wait after
  // the finger lifts.
  void _restartAutoPlay() {
    _autoPlay?.cancel();
    _autoPlay = Timer.periodic(_autoPlayEvery, (_) => _advance());
  }

  void _holdAutoPlay() => _autoPlay?.cancel();

  void _advance() {
    if (!mounted || !widget.isActive || _searching || !_pages.hasClients) return;
    // Not with the app in the background, under a guide opened over this
    // page, or when the phone asks for less motion.
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    // Mid-swipe or mid-slide: wait for the next turn.
    final page = _pages.page;
    if (page == null || (page - page.roundToDouble()).abs() > 0.01) return;
    _pages.nextPage(duration: _autoPlaySlide, curve: Curves.easeInOutCubic);
  }

  // The card on screen: from the loop's page while the cards are showing.
  int _shownIndex(int count) {
    if (count <= 1) return 0;
    final page = _pages.hasClients ? _pages.page : null;
    return page == null ? _page.clamp(0, count - 1) : page.round() % count;
  }

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
    final cities = [
      ...CityTourCity.group(_tours ?? const []),
      // Samples once the real guides are in (not over a spinner or an error).
      if (kCityGuidesSampleCities && !_loading && _error == null)
        ...CityTourCity.group(_sampleTours),
    ];
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
    final shownIndex = _shownIndex(featured.length);
    // The row under the cards stays put while they play: the cities after
    // the cards, or every city when they all fit on the cards.
    final others = cities.length > _featuredCount
        ? cities.skip(_featuredCount).toList()
        : cities.length > 1
            ? cities
            : const <CityTourCity>[];
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Everything but the card: the room around it, the dots, the More cities
    // title and row (or the "on the way" line), and the gap above the navbar.
    final double around = 6.0 +
        _cardRoom +
        (featured.length > 1 ? _dotsHeight : 0.0) +
        (others.isEmpty ? _soonHeight : _rowTitleHeight + _rowHeight) +
        _endGap +
        bottomInset +
        2.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The card takes what is left, so the whole page fits the screen with
        // no scrolling (only a very small screen still scrolls a little).
        final cardHeight = (constraints.maxHeight - around).clamp(300.0, 480.0);
        return _home(featured, shownIndex, others, cities, cardHeight, bottomInset);
      },
    );
  }

  Widget _home(
    List<CityTourCity> featured,
    int shownIndex,
    List<CityTourCity> others,
    List<CityTourCity> cities,
    double cardHeight,
    double bottomInset,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: 6, bottom: _endGap + bottomInset),
      children: [
        SizedBox(
          // Room above and under the card for its shadow.
          height: cardHeight + _cardRoom,
          child: featured.length == 1
              // One city: a still card, nothing to swipe or play.
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                  child: _FeaturedCard(city: featured.first, onTap: () => _openCity(featured.first)),
                )
              : Listener(
                  // A finger on the cards holds the auto-play.
                  onPointerDown: (_) => _holdAutoPlay(),
                  onPointerUp: (_) => _restartAutoPlay(),
                  onPointerCancel: (_) => _restartAutoPlay(),
                  child: PageView.builder(
                    controller: _pages,
                    // No itemCount: the cards loop.
                    onPageChanged: (i) => setState(() => _page = i % featured.length),
                    itemBuilder: (_, i) {
                      final city = featured[i % featured.length];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                        child: _FeaturedCard(city: city, onTap: () => _openCity(city)),
                      );
                    },
                  ),
                ),
        ),
        if (featured.length > 1) _Dots(count: featured.length, index: shownIndex),
        if (others.isEmpty) const _Soon(),
        if (others.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
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
                    // Exactly 36 high, as _rowTitleHeight counts it.
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            height: _rowHeight,
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
    // A sample city's photo ships with the app.
    if (url.startsWith('asset:')) {
      return Image.asset(url.substring(6), fit: BoxFit.cover, cacheWidth: cacheWidth);
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
                  child: Row(
                    children: [
                      Flexible(
                        child: _GlassChip(icon: Icons.location_on_outlined, label: place, fontSize: 13),
                      ),
                      if (city.isSample) ...[const SizedBox(width: 6), const _SampleTag()],
                    ],
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
              if (city.isSample) const Positioned(top: 8, left: 8, child: _SampleTag()),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          city.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _navy),
                        ),
                      ),
                      if (city.isSample) ...[const SizedBox(width: 6), const _SampleTag()],
                    ],
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

/// Marks a sample city (kCityGuidesSampleCities).
class _SampleTag extends StatelessWidget {
  const _SampleTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'SAMPLE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: Color(0xFF422006),
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
