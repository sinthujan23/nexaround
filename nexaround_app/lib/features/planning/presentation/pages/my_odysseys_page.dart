import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_detail_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_planner_page.dart';
import 'package:nexaround_app/features/mini_tour/presentation/widgets/mini_tour_launcher.dart';
import 'package:nexaround_app/features/planning/presentation/pages/history_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/museums_list_page.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:video_player/video_player.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experiences_page.dart';

class MyOdysseysPage extends StatefulWidget {
  const MyOdysseysPage({super.key});

  @override
  State<MyOdysseysPage> createState() => _MyOdysseysPageState();
}

class _MyOdysseysPageState extends State<MyOdysseysPage> {
  final OdysseyRepository _repository = OdysseyRepository();

  bool _loading = false;
  String? _error;
  List<Odyssey> _odysseys = const [];
  Timer? _pollTimer;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    // Render the last cached list instantly; the network refresh updates it in background.
    _odysseys = _repository.getCachedOdysseys();
    _loading = false;
    _load();
    // Refresh whenever an Odyssey is saved/deleted anywhere in the app.
    OdysseyRepository.revision.addListener(_load);
    _initVideo();
  }

  void _initVideo() {
    _videoController = VideoPlayerController.asset(
      'assets/animations/odyssey_banner.mp4',
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
    _pollTimer?.cancel();
    OdysseyRepository.revision.removeListener(_load);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repository.getMyOdysseys();
      if (!mounted) return;
      setState(() {
        _odysseys = list;
        _loading = false;
        _error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Keep showing the cached list on failure — only surface the error
        // screen when there's nothing cached to fall back to.
        if (_odysseys.isEmpty) _error = 'Could not load your odysseys.';
      });
    }
  }

  /// While any Odyssey is still being built server-side, re-poll so its card
  /// flips from "Generating…" to the finished plan without a manual refresh.
  void _schedulePoll() {
    _pollTimer?.cancel();
    final anyGenerating = _odysseys.any((o) => o.status == 'generating');
    if (anyGenerating && mounted) {
      _pollTimer = Timer(const Duration(seconds: 5), _load);
    }
  }

  Future<void> _openPlanner() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const OdysseyPlannerPage()),
    );
    if (created == true) _load();
  }

  void _openMiniTour() => launchMiniTour(context);

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
  }

  void _openExperiences() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExperiencesPage()),
    );
  }

  Widget _buildExperienceBanner() {
    return GestureDetector(
      onTap: _openExperiences,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF061A14),
              Color(0xFF020B08),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background adventure collage image
              Image.asset(
                'assets/images/experiences_banner_bg.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              // Gradient scrim to make text highly readable
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xEE061A14),
                      Color(0x99030E0B),
                      Color(0x22000000),
                    ],
                    stops: [0.0, 0.65, 1.0],
                  ),
                ),
              ),
              // Content overlay
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.terrain_rounded, color: AppColors.brandGreen, size: 22),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UNFORGETTABLE EXPERIENCES',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: AppColors.brandGreen,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Handcrafted Tours',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '120+ Curated adventures',
                          style: TextStyle(fontSize: 10, color: Colors.white54),
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
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }

  Widget _buildCreatePlanCard() {
    return GestureDetector(
      onTap: _openPlanner,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: CustomPaint(
          painter: const _DottedBorderPainter(
            color: Color(0xFF94A3B8),
            strokeWidth: 1.6,
            dashLength: 4.5,
            dashGap: 4.5,
            radius: 16.0,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top: Tag + AI Sparkle Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: AppColors.brandGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.brandGreen.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'ODYSSEY',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: AppColors.brandGreen,
                        ),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brandGreen.withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.brandGreen,
                        size: 14,
                      ),
                    ),
                  ],
                ),

                // Center: Large glowing + button
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.brandGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandGreen.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),

                // Bottom: Title & Subtitle
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build Odyssey',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Chart your journey',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade().scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          duration: 200.ms,
        );
  }

  Widget _buildMuseumBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MuseumsListPage()),
      ),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF020617),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background modern museum image with overlay
              Image.asset(
                'assets/images/museum_banner_bg.png',
                fit: BoxFit.cover,
              ),
              // Gradient scrim to make text highly readable
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xEE0F172A),
                      Color(0x99020617),
                    ],
                  ),
                ),
              ),
              // Content overlay
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.museum_rounded, color: Color(0xFF00E5FF), size: 22),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOP MUSEUMS',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Master Guides',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Expert routes & timings',
                          style: TextStyle(fontSize: 10, color: Colors.white54),
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
    ).animate().fade(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Future<void> _openDetail(Odyssey odyssey) async {
    if (odyssey.status == 'generating') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still building this Odyssey — hang tight.')),
      );
      return;
    }
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OdysseyDetailPage(odyssey: odyssey)),
    );
    if (deleted == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    // Safety check: ensure video is playing if it was paused by lifecycle events
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        !_videoController!.value.isPlaying) {
      _videoController!.play();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        color: Colors.black,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 145,
              backgroundColor: const Color(0xFF0F172A),
              elevation: 0,
              scrolledUnderElevation: 4,
              automaticallyImplyLeading: false,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // History Pill Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openHistory,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.history_rounded,
                                    color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'History',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Walking Challenge Pill Button (Matching TOP MUSEUMS Cyan: 0xFF00E5FF)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openMiniTour,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.60),
                                width: 1.1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🚩', style: TextStyle(fontSize: 12)),
                                SizedBox(width: 4),
                                Text(
                                  'Challenge',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: false,
                titlePadding: const EdgeInsets.only(left: 20, right: 190, bottom: 16),
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MY ODYSSEYS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppColors.brandGreen,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Trip Blueprints',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_videoController != null &&
                        _videoController!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: Transform.scale(
                          scale: 1.16,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                      )
                    else
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0F172A), Color(0xFF020617)],
                          ),
                        ),
                      ),
                    // Atmospheric gradient overlay for optimal readability
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black54,
                            Colors.black26,
                            Colors.black87,
                          ],
                          stops: [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Side-by-side category banners row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Row(
                  children: [
                    Expanded(child: _buildExperienceBanner()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMuseumBanner()),
                  ],
                ),
              ),
            ),
            // Trip blueprints list cards
            _buildSliverContent(),
          ],
        ),
      ),
    );
  }

  /// Completed trips move to the History page, so the main list shows only
  /// in-progress ones (active / generating / failed).
  List<Odyssey> get _activeOdysseys =>
      _odysseys.where((o) => o.status != 'completed').toList();

  Widget _buildSliverContent() {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator(color: Colors.black)),
        ),
      );
    }
    if (_error != null) {
      return SliverToBoxAdapter(
        child: _buildMessage(
          icon: Icons.cloud_off_rounded,
          title: _error!,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }
    final active = _activeOdysseys;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth = (screenWidth - 32 - 12) / 2;
    final double childAspectRatio = cardWidth / 196.0;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return _buildCreatePlanCard();
            }
            return _buildCinematicCard(active[index - 1], index: index - 1);
          },
          childCount: 1 + active.length,
        ),
      ),
    );
  }


  MapEntry<String, String> _getCountryFlagAndName(String destination) {
    final parts = destination.split(',');
    if (parts.length < 2) {
      return const MapEntry('', '');
    }
    final country = parts.last.trim();
    final flag = _countryNameToFlag(country);
    return MapEntry(flag, country);
  }

  String _countryNameToFlag(String country) {
    final name = country.toLowerCase();
    if (name.contains('sri lanka')) return '🇱🇰';
    if (name.contains('uzbekistan')) return '🇺🇿';
    if (name.contains('france')) return '🇫🇷';
    if (name.contains('india')) return '🇮🇳';
    if (name.contains('united kingdom') || name.contains('uk') || name.contains('england')) return '🇬🇧';
    if (name.contains('united states') || name.contains('usa') || name.contains('us')) return '🇺🇸';
    if (name.contains('italy')) return '🇮🇹';
    if (name.contains('germany')) return '🇩🇪';
    if (name.contains('japan')) return '🇯🇵';
    if (name.contains('thailand')) return '🇹🇭';
    if (name.contains('singapore')) return '🇸🇬';
    if (name.contains('malaysia')) return '🇲🇾';
    if (name.contains('maldives')) return '🇲🇻';
    if (name.contains('indonesia')) return '🇮🇩';
    if (name.contains('australia')) return '🇦🇺';
    if (name.contains('canada')) return '🇨🇦';
    if (name.contains('spain')) return '🇪🇸';
    if (name.contains('switzerland')) return '🇨🇭';
    if (name.contains('china')) return '🇨🇳';
    if (name.contains('vietnam')) return '🇻🇳';
    if (name.contains('nepal')) return '🇳🇵';
    if (name.contains('uae') || name.contains('emirates')) return '🇦🇪';
    return '';
  }

  LinearGradient _getThemedGradient(String destination) {
    final hash = destination.hashCode;
    final gradients = [
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF065F46), Color(0xFF1E3A8A)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF581C87), Color(0xFF0F172A)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFB45309), Color(0xFF451A03)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF065F46), Color(0xFF1E3A8A)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF881337), Color(0xFF1C1917)],
      ),
    ];
    return gradients[hash.abs() % gradients.length];
  }

  Future<void> _confirmDelete(Odyssey odyssey) async {
    final id = odyssey.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Blueprint?'),
        content: Text('Are you sure you want to permanently delete "${odyssey.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      try {
        await _repository.delete(id);
        if (!mounted) return;
        _load();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Blueprint deleted successfully.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessageFor(e, action: 'delete the blueprint'))),
        );
      }
    }
  }

  Widget _buildCinematicCard(Odyssey odyssey, {required int index}) {
    final isGenerating = odyssey.status == 'generating';
    final isFailed = odyssey.status == 'failed';
    final hasImage = odyssey.coverUrl != null && odyssey.coverUrl!.isNotEmpty;

    final countryData = _getCountryFlagAndName(odyssey.destination);
    final flag = countryData.key;
    final countryName = countryData.value;

    final int totalStops = odyssey.totalActivities;
    final int visitedStops = odyssey.visitedActivities;
    final double progress = totalStops > 0 ? (visitedStops / totalStops).clamp(0.0, 1.0) : 0.0;
    final int percent = (progress * 100).toInt();

    return GestureDetector(
      onTap: isGenerating ? null : () => _openDetail(odyssey),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
              // ── Full-bleed photo / fallback gradient ──────────────────────
              if (hasImage)
                CachedNetworkImage(
                  imageUrl: odyssey.coverUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 1080, // full-bleed list card at 3x DPR
                  placeholder: (context, url) => Container(
                    color: const Color(0xFF0F172A),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    decoration: BoxDecoration(
                      gradient: _getThemedGradient(odyssey.destination),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: _getThemedGradient(odyssey.destination),
                  ),
                ),

              // ── Deep dark gradient scrim from bottom ──────────────────────
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x55000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),

              // ── Generating overlay ────────────────────────────────────────
              if (isGenerating)
                Container(
                  color: Colors.black38,
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandGreen,
                      ),
                    ),
                  ),
                )
              else if (isFailed)
                Container(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                  ),
                ),

              // ── Status badge (top-right) ──────────────────────────────────
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isGenerating
                        ? Colors.black54
                        : isFailed
                            ? Colors.redAccent
                            : odyssey.status == 'completed'
                                ? Colors.black54
                                : AppColors.brandGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    odyssey.status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),

              // ── Delete button (top-left) ──────────────────────────────────
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: () => _confirmDelete(odyssey),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white70,
                      size: 14,
                    ),
                  ),
                ),
              ),

              // ── Text content (bottom overlay) ─────────────────────────────
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Destination / country row
                    if (flag.isNotEmpty || countryName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            if (flag.isNotEmpty) ...[
                              Text(flag, style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                            ],
                            if (countryName.isNotEmpty)
                              Expanded(
                                child: Text(
                                  countryName.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white70,
                                    letterSpacing: 1.0,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    // Title
                    Text(
                      odyssey.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    // Progress Bar Pill
                    if (totalStops > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  visitedStops == totalStops
                                      ? 'Completed 🎉'
                                      : '$visitedStops / $totalStops Visited',
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  '$percent%',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: visitedStops == totalStops
                                        ? const Color(0xFF00E5FF)
                                        : const Color(0xFF38BDF8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 4.5,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF00E5FF), Color(0xFF007A7C)],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Days + Budget row
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _pillChip(
                          Icons.calendar_today_rounded,
                          odyssey.formattedShortDateRange.isNotEmpty
                              ? '${odyssey.formattedShortDateRange} (${odyssey.actualDays}d)'
                              : '${odyssey.actualDays} ${odyssey.actualDays == 1 ? 'Day' : 'Days'}',
                        ),
                        if (odyssey.travelers > 0)
                          _pillChip(
                            Icons.people_rounded,
                            '${odyssey.travelers} ${odyssey.travelers == 1 ? 'Pax' : 'Pax'}',
                          ),
                        if (odyssey.budget > 0)
                          _BudgetPill(
                            amount: odyssey.budget,
                            currency: odyssey.currency,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Bottom edge progress line ─────────────────────────────────
              if (totalStops > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    child: Container(
                      height: 3,
                      color: Colors.white.withValues(alpha: 0.12),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF007A7C)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ).animate().fade(duration: 400.ms).slideY(
          begin: 0.06,
          end: 0,
          curve: Curves.easeOutQuad,
        );
  }

  Widget _pillChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: Colors.white70),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    String? subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _BudgetPill extends StatelessWidget {
  final double amount;
  final String currency;
  const _BudgetPill({required this.amount, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$currency ${formatAmount(amount)}',
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }
}

/// A painter that draws a clean dotted / dashed rounded border (industry standard for upload/create cards).
class _DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;
  final double radius;

  const _DottedBorderPainter({
    required this.color,
    this.strokeWidth = 1.6,
    this.dashLength = 4.5,
    this.dashGap = 4.5,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final half = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        half,
        half,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular((radius - half).clamp(0.0, double.infinity)),
    );

    final path = Path()..addRRect(rrect);
    final dashedPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double len = (distance + dashLength < metric.length)
            ? dashLength
            : metric.length - distance;
        dashedPath.addPath(
          metric.extractPath(distance, distance + len),
          Offset.zero,
        );
        distance += dashLength + dashGap;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DottedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.dashGap != dashGap ||
        oldDelegate.radius != radius;
  }
}

