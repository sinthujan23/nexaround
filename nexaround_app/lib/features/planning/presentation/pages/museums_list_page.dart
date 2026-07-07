import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/data/museum_repository.dart';
import 'package:nexaround_app/features/planning/domain/museum.dart';
import 'package:nexaround_app/features/planning/presentation/pages/museum_guide_page.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Lists all 63 top world museums as premium cards. Tapping one opens the
/// curated guide page where the user picks their available time.
class MuseumsListPage extends StatefulWidget {
  const MuseumsListPage({super.key});

  @override
  State<MuseumsListPage> createState() => _MuseumsListPageState();
}

class _MuseumsListPageState extends State<MuseumsListPage> {
  final _repo = MuseumRepository();
  VideoPlayerController? _videoController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  List<MuseumListItem>? _museums;
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _search = _searchController.text;
        });
      }
    });
    _scrollController.addListener(() {
      if (!mounted) return;
      final collapsedOffset = 200 - kToolbarHeight - 24;
      final isScrolled = _scrollController.hasClients &&
          _scrollController.offset > collapsedOffset;
      if (isScrolled != _isScrolled) {
        setState(() {
          _isScrolled = isScrolled;
        });
      }
    });
    // Load from cache instantly
    final cached = _repo.getCachedMuseums();
    if (cached.isNotEmpty) {
      _museums = cached;
      _loading = false;
    }
    _fetch();
    _initVideo();
  }

  void _initVideo() {
    _videoController = VideoPlayerController.asset(
      'assets/animations/museum_banner.mp4',
    )..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _videoController?.setLooping(true);
          _videoController?.setVolume(0.0);
          _videoController?.play();
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
    if (!mounted) return;
    setState(() {
      _loading = _museums == null || _museums!.isEmpty;
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
      if (_museums == null || _museums!.isEmpty) {
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

  List<String> get _countries {
    if (_museums == null) return [];
    final set = _museums!.map((m) => m.country).toSet();
    final list = set.toList()..sort();
    return list;
  }

  List<MuseumListItem> get _filtered {
    if (_museums == null) return [];
    var list = _museums!;
    if (_selectedCountry != null) {
      list = list.where((m) => m.country == _selectedCountry).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((m) =>
              m.name.toLowerCase().contains(q) ||
              m.city.toLowerCase().contains(q) ||
              m.country.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: _isScrolled ? Colors.black : Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'World\'s Top Museums',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _isScrolled ? Colors.black : Colors.white,
                ),
              ),
              background: _videoController != null &&
                      _videoController!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black38,
                                Colors.black87,
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const DecoratedBox(
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

          // ── Search Bar & Filter ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
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
                if (_countries.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _countries.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          final isSelected = _selectedCountry == null;
                          return ChoiceChip(
                            label: const Text('All'),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) setState(() => _selectedCountry = null);
                            },
                            selectedColor: AppColors.brandGreen,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            backgroundColor: AppColors.surface,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          );
                        }
                        final country = _countries[index - 1];
                        final isSelected = _selectedCountry == country;
                        return ChoiceChip(
                          label: Text(country),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _selectedCountry = selected ? country : null);
                          },
                          selectedColor: AppColors.brandGreen,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          backgroundColor: AppColors.surface,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
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
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top part: Image / Rank / Item Count
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Museum Image or fallback
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: museum.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: museum.imageUrl!.startsWith('/')
                                  ? '${ApiConstants.baseUrl}${museum.imageUrl}'
                                  : museum.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: AppColors.surface,
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.brandGreen,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.surface,
                                child: const Center(
                                  child: Icon(
                                    Icons.museum_rounded,
                                    size: 32,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: museum.rank != null && museum.rank! <= 3
                                    ? AppColors.achievementGradient
                                    : AppColors.secondaryGradient,
                              ),
                            ),
                    ),
                    // Masterpiece count badge (top-right)
                    if (museum.masterpieceCount > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${museum.masterpieceCount} items',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Bottom part: Info details
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      museum.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 11, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '${museum.city}, ${museum.country}',
                            style: const TextStyle(
                              fontSize: 11,
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
                              size: 11, color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${(museum.annualVisitors! / 1e6).toStringAsFixed(1)}M/yr',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
