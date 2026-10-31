import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tour_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';
import 'package:video_player/video_player.dart';

/// Curated Hubs → City Tours: the cities that have guides. A city with one
/// guide opens it straight away; with more, its list of guides.
class CityToursPage extends StatefulWidget {
  const CityToursPage({super.key});

  @override
  State<CityToursPage> createState() => _CityToursPageState();
}

// The header is the video with the big title on it; the search box sits half
// on the video's bottom edge.
const double _headerHeight = 290;
const double _searchHeight = 52;
const _navy = Color(0xFF0F172A);

class _CityToursPageState extends State<CityToursPage> {
  final _service = CityToursService();
  VideoPlayerController? _videoController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

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
    _searchFocus.dispose();
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

  // The collapsed bar's search button: back to the top, into the search box.
  Future<void> _focusSearch() async {
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    if (mounted) _searchFocus.requestFocus();
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

  Widget _countryChip(String label, bool isSelected, ValueChanged<bool> onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: _navy,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: AppColors.surface,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _header() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _searchHeight / 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_videoController != null &&
                  _videoController!.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  // the white strip under the video holds half the search box
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
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
                    colors: [
                      Color(0x59000000),
                      Color(0x590F172A),
                      Color(0xE00F172A),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              const Positioned(
                left: 20,
                right: 20,
                bottom: _searchHeight / 2 + 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'City Guides',
                      style: TextStyle(
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Where to start, which ride to take and what to see at every stop, with tickets and tours on the way.',
                      style: TextStyle(
                        fontSize: 13.5,
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
        Positioned(
          left: 16,
          right: 16,
          bottom: 0,
          height: _searchHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search cities, countries…',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: AppColors.textTertiary),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cities = CityTourCity.group(_tours ?? const []);
    final countries = _countries(cities);
    final filtered = _filter(cities);
    // The newest guide (the server sends them oldest first), shown big above
    // the unfiltered list when there is more than one city under it.
    final latest = _search.isEmpty && _selectedCountry == null && cities.length > 1
        ? _tours!.last
        : null;
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
              surfaceTintColor: Colors.white,
              elevation: _isScrolled ? 2 : 0,
              scrolledUnderElevation: 2,
              centerTitle: true,
              // Open, the title is the big one on the video; collapsed, a
              // plain white bar with the title and a search button.
              title: AnimatedOpacity(
                opacity: _isScrolled ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Text(
                  'City Guides',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: _isScrolled
                        ? Colors.black.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: _isScrolled ? Colors.black : Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              actions: [
                IgnorePointer(
                  ignoring: !_isScrolled,
                  child: AnimatedOpacity(
                    opacity: _isScrolled ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.06),
                          shape: const CircleBorder(),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.search_rounded,
                                size: 20, color: Colors.black),
                            onPressed: _focusSearch,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(background: _header()),
            ),

            // ── Country filter ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: countries.isEmpty
                    ? const SizedBox.shrink()
                    : SizedBox(
                        height: 40,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: countries.length + 1,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _countryChip(
                                'All',
                                _selectedCountry == null,
                                (selected) {
                                  if (selected) {
                                    setState(() => _selectedCountry = null);
                                  }
                                },
                              );
                            }
                            final country = countries[index - 1];
                            return _countryChip(
                              country,
                              _selectedCountry == country,
                              (selected) => setState(() =>
                                  _selectedCountry = selected ? country : null),
                            );
                          },
                        ),
                      ),
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
            else ...[
              if (latest != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionLabel(
                          icon: Icons.star_rounded,
                          text: 'LATEST GUIDE',
                        ),
                        _LatestGuide(
                          card: latest,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CityTourPage(card: latest),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SectionLabel(
                    icon: Icons.location_city_rounded,
                    text: 'ALL CITIES',
                    trailing: filtered.length == 1
                        ? '1 city'
                        : '${filtered.length} cities',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _CityRow(
                      city: filtered[index],
                      last: index == filtered.length - 1,
                      onTap: () => _openCity(filtered[index]),
                    ),
                    childCount: filtered.length,
                  ),
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ── List parts ──────────────────────────────────────────────────────────────

/// A small teal heading over a part of the list, with an optional count.
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? trailing;

  const _SectionLabel({required this.icon, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.brandGreen),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.brandGreen,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
        ],
      ),
    );
  }
}

/// The newest guide as a big photo card: its place, title and facts on the
/// photo, and an arrow to open it.
class _LatestGuide extends StatelessWidget {
  final CityTourCard card;
  final VoidCallback onTap;

  const _LatestGuide({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final place = [card.city, card.country]
        .where((s) => s.isNotEmpty)
        .join(' · ')
        .toUpperCase();
    final facts = <(IconData, String)>[
      if (card.dayCount > 1)
        (Icons.calendar_today_rounded, '${card.dayCount} days'),
      if (card.stopCount > 0)
        (
          Icons.place_rounded,
          card.stopCount == 1 ? '1 stop' : '${card.stopCount} stops',
        ),
      if (card.budget.isNotEmpty) (Icons.payments_rounded, card.budget),
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (card.coverUrl.isEmpty)
                Container(color: AppColors.surfaceVariant)
              else
                CachedNetworkImage(
                  imageUrl: cityTourMediaUrl(card.coverUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 1080,
                  placeholder: (_, __) => Container(color: AppColors.surface),
                  errorWidget: (_, __, ___) =>
                      Container(color: AppColors.surfaceVariant),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE00F172A), Color(0x1A0F172A)],
                    stops: [0.0, 0.65],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (place.isNotEmpty)
                            Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.3,
                                color: Color(0xFF5EEAD4),
                              ),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            card.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                          if (facts.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                for (final (icon, text) in facts)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 13, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(
                                        text,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          size: 20, color: _navy),
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

/// A city in the list: photo, name, country, and how many guides it has (with
/// one guide, how long it is too).
class _CityRow extends StatelessWidget {
  final CityTourCity city;
  final bool last;
  final VoidCallback onTap;

  const _CityRow({required this.city, required this.last, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = city.tours.length;
    final duration = count == 1 ? city.tours.first.duration : '';
    final meta = [
      count == 1 ? '1 guide' : '$count guides',
      if (duration.isNotEmpty) duration,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFEEF0F3))),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 70,
                height: 70,
                child: city.coverUrl.isEmpty
                    ? Container(
                        decoration: const BoxDecoration(
                          gradient: AppColors.secondaryGradient,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: cityTourMediaUrl(city.coverUrl),
                        fit: BoxFit.cover,
                        memCacheWidth: 240, // 70 px at 3x DPR
                        placeholder: (_, __) =>
                            Container(color: AppColors.surface),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.surface,
                          child: const Icon(
                            Icons.location_city_rounded,
                            size: 24,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
              ),
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
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (city.country.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            city.country,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandGreen,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 22, color: Color(0xFF94A3B8)),
          ],
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
