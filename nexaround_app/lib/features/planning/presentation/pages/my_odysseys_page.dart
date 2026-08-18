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

class MyOdysseysPage extends StatefulWidget {
  const MyOdysseysPage({super.key});

  @override
  State<MyOdysseysPage> createState() => _MyOdysseysPageState();
}

class _MyOdysseysPageState extends State<MyOdysseysPage> {
  final OdysseyRepository _repository = OdysseyRepository();

  bool _loading = true;
  String? _error;
  List<Odyssey> _odysseys = const [];
  Timer? _pollTimer;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    // Render the last cached list instantly; the network refresh updates it.
    _odysseys = _repository.getCachedOdysseys();
    _loading = _odysseys.isEmpty;
    _load();
    // Refresh whenever an Odyssey is saved/deleted anywhere in the app.
    OdysseyRepository.revision.addListener(_load);
    _initVideo();
  }

  void _initVideo() {
    _videoController = VideoPlayerController.asset(
      'assets/animations/odyssey_banner.mp4',
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
    _pollTimer?.cancel();
    OdysseyRepository.revision.removeListener(_load);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _odysseys.isEmpty);
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

  Widget _buildMiniTourCard() {
    return GestureDetector(
      onTap: _openMiniTour,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('🚩', style: TextStyle(fontSize: 22)),
                Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 28),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TAKE A WALK',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Walking Challenge',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Visit stops & earn XP',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fade().slideY(begin: 0.1, end: 0);
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
                  padding: const EdgeInsets.only(top: 8, right: 20),
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
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.history_rounded,
                                    color: Colors.white, size: 15),
                                SizedBox(width: 5),
                                Text(
                                  'History',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Create Plan Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openPlanner,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF007A7C), Color(0xFF00B4D8)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF007A7C)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.auto_awesome_rounded,
                                    color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  '+ Create Plan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    letterSpacing: 0.3,
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
                titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
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
                      style: TextStyle(
                        fontSize: 22,
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
                    Expanded(child: _buildMiniTourCard()),
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
    if (active.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildMessage(
          icon: Icons.auto_awesome_rounded,
          title: 'No odysseys yet',
          subtitle: 'Generate an AI-crafted trip blueprint to get started.',
          actionLabel: 'Build an Odyssey',
          onAction: _openPlanner,
        ),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth = (screenWidth - 32 - 12) / 2;
    final double childAspectRatio = cardWidth / 175.0;

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
          (context, index) => _buildCinematicCard(active[index], index: index),
          childCount: active.length,
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
        colors: [Color(0xFF0F766E), Color(0xFF312E81)],
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
          SnackBar(content: Text('Error deleting blueprint: $e')),
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
                    const SizedBox(height: 6),
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

