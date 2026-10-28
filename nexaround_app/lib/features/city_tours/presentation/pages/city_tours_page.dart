import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/presentation/pages/city_tour_page.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';

/// Curated Hubs → City Tours: the cities that have guides. A city with one
/// guide opens it straight away; with more, its list of guides.
class CityToursPage extends StatefulWidget {
  const CityToursPage({super.key});

  @override
  State<CityToursPage> createState() => _CityToursPageState();
}

class _CityToursPageState extends State<CityToursPage> {
  final _service = CityToursService();
  List<CityTourCard>? _tours;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cached = _service.cachedTours();
    if (cached.isNotEmpty) {
      _tours = cached;
      _loading = false;
    }
    _fetch();
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

  @override
  Widget build(BuildContext context) {
    final cities = CityTourCity.group(_tours ?? const []);
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: AppColors.brandGreen,
        onRefresh: _fetch,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              title: Text(
                'City Guides',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'Step-by-step routes through famous cities: where to start, '
                  'which ride to take and what to see at every stop.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
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
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.separated(
                  itemCount: cities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _CityCard(
                    city: cities[i],
                    onTap: () => _openCity(cities[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CityCard extends StatelessWidget {
  final CityTourCity city;
  final VoidCallback onTap;

  const _CityCard({required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = city.tours.length;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 170,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (city.coverUrl.isEmpty)
                Container(color: AppColors.surfaceVariant)
              else
                CachedNetworkImage(
                  imageUrl: cityTourMediaUrl(city.coverUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 1080,
                  placeholder: (_, __) => Container(color: AppColors.surface),
                  errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    count == 1 ? '1 guide' : '$count guides',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      city.city,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                    if (city.country.isNotEmpty)
                      Text(
                        city.country,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
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
