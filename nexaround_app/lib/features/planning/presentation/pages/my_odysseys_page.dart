import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_detail_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_planner_page.dart';
import 'package:nexaround_app/features/mini_tour/presentation/pages/mini_tour_game_page.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh whenever an Odyssey is saved/deleted anywhere in the app.
    OdysseyRepository.revision.addListener(_load);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    OdysseyRepository.revision.removeListener(_load);
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
        _error = 'Could not load your odysseys.';
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

  void _openMiniTour() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MiniTourGamePage()),
    );
  }

  Widget _buildMiniTourCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _openMiniTour,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('🚩', style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MINI TOUR',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white70),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Nearby flag challenge',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Visit the stops, reach 🏁, earn XP',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34),
            ],
          ),
        ),
      ).animate().fade().slideY(begin: 0.1, end: 0),
    );
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
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPlanner,
        backgroundColor: Colors.black,
        icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
        label: const Text(
          'NEW ODYSSEY',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MY ODYSSEYS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Blueprints',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildMiniTourCard(),
            const SizedBox(height: 16),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.black));
    }
    if (_error != null) {
      return _buildMessage(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_odysseys.isEmpty) {
      return _buildMessage(
        icon: Icons.auto_awesome_rounded,
        title: 'No odysseys yet',
        subtitle: 'Generate an AI-crafted trip blueprint to get started.',
        actionLabel: 'Build an Odyssey',
        onAction: _openPlanner,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Colors.black,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
        itemCount: _odysseys.length,
        itemBuilder: (context, index) => _buildOdysseyCard(_odysseys[index]),
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

  Widget _buildOdysseyCard(Odyssey odyssey) {
    final accentColor = _statusColor(odyssey.status);
    final isGenerating = odyssey.status == 'generating';
    final isFailed = odyssey.status == 'failed';

    return GestureDetector(
      onTap: () => _openDetail(odyssey),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    odyssey.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: accentColor == Colors.black12 ? Colors.black45 : accentColor,
                    ),
                  ),
                ),
                if (isGenerating)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.actionTeal),
                  )
                else
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black26, size: 14),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              odyssey.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black),
            ),
            const SizedBox(height: 4),
            Text(
              odyssey.statsLabel,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (isGenerating)
              Row(
                children: const [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.actionTeal),
                  SizedBox(width: 6),
                  Text(
                    'AI is crafting your plan…',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54),
                  ),
                ],
              )
            else if (isFailed)
              Row(
                children: const [
                  Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Generation failed — tap to remove.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.auto_mode_rounded, size: 14, color: AppColors.ratingGold),
                  const SizedBox(width: 6),
                  const Text(
                    'AI Optimized Plan',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54),
                  ),
                  const Spacer(),
                  const Text(
                    'EXPLORE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ).animate().fade().slideY(begin: 0.1, end: 0),
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
