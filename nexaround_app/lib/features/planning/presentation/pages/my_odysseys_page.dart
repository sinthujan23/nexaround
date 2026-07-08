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
import 'package:nexaround_app/core/widgets/converted_currency_text.dart';
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
              color: Colors.black.withOpacity(0.12),
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
              color: Colors.black.withOpacity(0.12),
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
                        Icon(Icons.museum_rounded, color: AppColors.brandGreen, size: 22),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOP MUSEUMS',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: AppColors.brandGreen,
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
              expandedHeight: 145, // Reduced from 200 to 145 for a tighter, cleaner layout
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              actions: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _openPlanner,
                      icon: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 12),
                      label: const Text(
                        'CREATE',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        backgroundColor: Colors.white.withOpacity(0.18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _openHistory,
                      tooltip: 'History',
                      icon: const Icon(Icons.history_rounded,
                          color: Colors.white70),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: false,
                titlePadding: const EdgeInsets.only(left: 24, bottom: 14),
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MY ODYSSEYS',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppColors.brandGreen,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Blueprints',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
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
                          scale: 1.16, // Zoom in slightly to crop out watermarks on outer edges
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
                    // Dark atmospheric gradient overlay for readability
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black45,
                            Colors.black87,
                          ],
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

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildRoadItem(index, active[index], active.length),
          childCount: active.length,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AppColors.ratingGold;
      case 'generating':
        return AppColors.actionTeal;
      case 'failed':
        return Colors.redAccent;
      case 'completed':
        return Colors.black12;
      default:
        return AppColors.actionTeal;
    }
  }

  Widget _buildRoadItem(int index, Odyssey odyssey, int totalCount) {
    final isLeft = index % 2 == 0;

    final dot = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: odyssey.status == 'failed'
              ? Colors.redAccent
              : AppColors.brandGreen,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        odyssey.status == 'generating'
            ? Icons.sync_rounded
            : odyssey.status == 'failed'
                ? Icons.error_outline_rounded
                : Icons.location_on_rounded,
        color: odyssey.status == 'failed' ? Colors.redAccent : AppColors.brandGreen,
        size: 15,
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left side card
          Expanded(
            child: isLeft
                ? Align(
                    alignment: Alignment.centerRight,
                    child: _buildCompactOdysseyCard(odyssey, isLeft: true),
                  )
                : const SizedBox.shrink(),
          ),
          // Road Line & Location Dot
          SizedBox(
            width: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: index == 0 ? 28 : 0,
                  bottom: index == totalCount - 1 ? 28 : 0,
                  child: Container(
                    width: 3,
                    color: Colors.black.withOpacity(0.06),
                  ),
                ),
                dot,
              ],
            ),
          ),
          // Right side card
          Expanded(
            child: !isLeft
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCompactOdysseyCard(odyssey, isLeft: false),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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

  Widget _buildCompactOdysseyCard(Odyssey odyssey, {required bool isLeft}) {
    final accentColor = _statusColor(odyssey.status);
    final isGenerating = odyssey.status == 'generating';
    final isFailed = odyssey.status == 'failed';
    final hasImage = odyssey.coverUrl != null && odyssey.coverUrl!.isNotEmpty;

    final countryData = _getCountryFlagAndName(odyssey.destination);
    final flag = countryData.key;
    final countryName = countryData.value;

    final cardContent = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isFailed ? Colors.redAccent.withOpacity(0.2) : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  odyssey.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: isFailed ? Colors.redAccent : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (isGenerating)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                )
              else
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 10),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            odyssey.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          ConvertedCurrencyText(
            amount: odyssey.budget,
            originalCurrency: odyssey.currency,
            prefix: '${odyssey.days} ${odyssey.days == 1 ? 'Day' : 'Days'} · ',
            style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (isGenerating)
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(100)),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Color(0x22FFFFFF),
                color: AppColors.brandGreen,
              ),
            )
          else if (isFailed)
            Row(
              children: const [
                Icon(Icons.error_outline_rounded, size: 10, color: Colors.redAccent),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Failed',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white70),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                if (flag.isNotEmpty) ...[
                  Text(flag, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                ],
                if (countryName.isNotEmpty)
                  Text(
                    countryName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                const Spacer(),
                const Text(
                  'EXPLORE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return GestureDetector(
      onTap: isGenerating ? null : () => _openDetail(odyssey),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: hasImage ? null : _getThemedGradient(odyssey.destination),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              if (hasImage) ...[
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: odyssey.coverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: const Color(0xFF0F172A),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      decoration: BoxDecoration(
                        gradient: _getThemedGradient(odyssey.destination),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xDD000000),
                          Color(0x44000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              cardContent,
            ],
          ),
        ),
      ),
    ).animate().fade(duration: 350.ms).slideX(
          begin: isLeft ? -0.12 : 0.12,
          end: 0,
          curve: Curves.easeOutQuad,
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
