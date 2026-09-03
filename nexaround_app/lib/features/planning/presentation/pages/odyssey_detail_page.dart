import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/odyssey_plan_view.dart';
import 'package:nexaround_app/features/planning/presentation/pages/history_page.dart';

/// Read-only view of a saved Odyssey, with the option to delete it.
class OdysseyDetailPage extends StatefulWidget {
  final Odyssey odyssey;
  final bool isReadOnly;
  const OdysseyDetailPage({
    super.key,
    required this.odyssey,
    this.isReadOnly = false,
  });

  @override
  State<OdysseyDetailPage> createState() => _OdysseyDetailPageState();
}

class _OdysseyDetailPageState extends State<OdysseyDetailPage> {
  final _repo = OdysseyRepository();
  bool _deleting = false;
  bool _loadingFresh = false;
  Timer? _pollTimer;

  /// Local working copy so AI swaps update the view in place.
  late Odyssey _odyssey = widget.odyssey;

  bool get _isEffectivelyReadOnly =>
      widget.isReadOnly || _odyssey.status == 'completed';

  /// "dayIndex:activityIndex" of the activity being swapped, or null.

  /// Name of the partner currently being swapped, or null.
  String? _swappingPartnerName;

  @override
  void initState() {
    super.initState();
    _fetchFreshPlan();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchFreshPlan() async {
    final id = _odyssey.id;
    if (id == null) return;

    if (_odyssey.dayPlans.isEmpty || _odyssey.isGenerating) {
      setState(() => _loadingFresh = true);
    }

    try {
      final fresh = await _repo.getOdysseyById(id);
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _odyssey = fresh;
          _loadingFresh = false;
        });

        // If it's still being generated on the server, poll until ready
        if (fresh.isGenerating || fresh.dayPlans.isEmpty) {
          _startPollTimer(id);
        } else {
          _pollTimer?.cancel();
        }
      } else {
        setState(() => _loadingFresh = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFresh = false);
    }
  }

  void _startPollTimer(String id) {
    _pollTimer?.cancel();
    int attempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      if (attempts > 20 || !mounted) {
        timer.cancel();
        return;
      }
      try {
        final fresh = await _repo.getOdysseyById(id);
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (fresh != null && (fresh.dayPlans.isNotEmpty || !fresh.isGenerating)) {
          setState(() {
            _odyssey = fresh;
            _loadingFresh = false;
          });
          timer.cancel();
        }
      } catch (_) {}
    });
  }

  /// Move a place to a new position, possibly into a different day.
  ///
  /// Saves through the same path as ticking a place off: optimistic update,
  /// persist, revert on failure. Reordering rewrites `dayPlans`, which is
  /// already what gets stored, so no schema or endpoint change is involved.
  Future<void> _reorderActivity(
    int fromDay,
    int fromIndex,
    int toDay,
    int toIndex,
  ) async {
    final before = _odyssey;
    final days = List<OdysseyDay>.from(before.dayPlans);
    if (fromDay < 0 || fromDay >= days.length) return;
    if (toDay < 0 || toDay >= days.length) return;

    final source = List<OdysseyActivity>.from(days[fromDay].activities);
    if (fromIndex < 0 || fromIndex >= source.length) return;
    final moved = source.removeAt(fromIndex);

    // Within one day the destination is read against the list the place has
    // already left, so it needs no adjustment; across days the target list is
    // untouched and the index applies directly.
    if (toDay == fromDay) {
      days[fromDay] = days[fromDay].copyWith(
        activities: source..insert(toIndex.clamp(0, source.length), moved),
      );
    } else {
      final target = List<OdysseyActivity>.from(days[toDay].activities);
      target.insert(toIndex.clamp(0, target.length), moved);
      days[fromDay] = days[fromDay].copyWith(activities: source);
      days[toDay] = days[toDay].copyWith(activities: target);
    }

    final updated = before.copyWith(dayPlans: days);
    setState(() => _odyssey = updated); // optimistic
    try {
      final saved = await _repo.updateOdyssey(updated);
      if (!mounted) return;
      setState(() => _odyssey = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _odyssey = before); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the new order. Try again.')),
      );
    }
  }

  Future<void> _swapPartner(String partnerName) async {
    final id = _odyssey.id;
    if (id == null) return;

    final reason = await _askReason(partnerName, isPartner: true);
    if (reason == null || !mounted) return; // cancelled

    setState(() => _swappingPartnerName = partnerName);
    try {
      final updated = await _repo.swapPartner(
        itineraryId: id,
        partnerName: partnerName,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _odyssey = updated;
        _swappingPartnerName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swapped in new partner for $partnerName')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _swappingPartnerName = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not swap partner: $e')),
      );
    }
  }

  /// Bottom sheet asking why the place is being replaced. Returns the chosen
  /// reason text, or null if the user cancelled.
  Future<String?> _askReason(String placeName, {bool isPartner = false}) {
    final presets = isPartner 
      ? [
          'Not supported here',
          'Prefer another site',
          'Too expensive',
          'Bad experience',
          'Suggest something else',
        ]
      : [
          'Already visited',
          'Not interested',
          'Too expensive',
          'Too far',
          'Suggest something else',
        ];
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Swap “$placeName”',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              isPartner
                  ? 'Tell the AI why, and it’ll suggest a different partner.'
                  : 'Tell the AI why, and it’ll suggest a different place for this slot.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in presets)
                  ActionChip(
                    label: Text(p),
                    backgroundColor: const Color(0xFFF1F1F3),
                    side: BorderSide.none,
                    onPressed: () => Navigator.pop(ctx, p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Or type your own reason…',
                filled: true,
                fillColor: const Color(0xFFF1F1F3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () =>
                    Navigator.pop(ctx, controller.text.trim().isEmpty
                        ? 'Suggest something else'
                        : controller.text.trim()),
                child: Text(
                  isPartner 
                      ? 'Ask AI for a different partner' 
                      : 'Ask AI for a different place',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle a single place visited/not and persist. When every place is
  /// ticked the trip auto-completes (status → 'completed') and moves to
  /// History; un-ticking re-opens it.
  Future<void> _toggleVisited(int dayIndex, int activityIndex, {String? actualCost}) async {
    final before = _odyssey;
    final day = before.dayPlans[dayIndex];
    final acts = List<OdysseyActivity>.from(day.activities);
    final target = acts[activityIndex];
    final newVisited = !target.visited;
    acts[activityIndex] = target.copyWith(
      visited: newVisited,
      actualCost: actualCost ?? (newVisited ? target.actualCost : ''),
    );
    final newDays = List<OdysseyDay>.from(before.dayPlans);
    newDays[dayIndex] = day.copyWith(activities: acts);

    var updated = before.copyWith(dayPlans: newDays);
    updated = updated.copyWith(status: updated.isComplete ? 'completed' : 'active');
    final justCompleted =
        updated.status == 'completed' && before.status != 'completed';

    setState(() => _odyssey = updated); // optimistic
    try {
      final saved = await _repo.updateOdyssey(updated);
      if (!mounted) return;
      setState(() => _odyssey = saved);
      if (justCompleted) _celebrate();
    } catch (e) {
      if (!mounted) return;
      setState(() => _odyssey = before); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save progress. Try again.')),
      );
    }
  }

  /// Update the actual cost for a completed activity and persist.
  Future<void> _updateActualCost(int dayIndex, int activityIndex, String actualCost) async {
    final before = _odyssey;
    final day = before.dayPlans[dayIndex];
    final acts = List<OdysseyActivity>.from(day.activities);
    acts[activityIndex] = acts[activityIndex].copyWith(actualCost: actualCost);
    final newDays = List<OdysseyDay>.from(before.dayPlans);
    newDays[dayIndex] = day.copyWith(activities: acts);

    final updated = before.copyWith(dayPlans: newDays);
    setState(() => _odyssey = updated); // optimistic
    try {
      final saved = await _repo.updateOdyssey(updated);
      if (!mounted) return;
      setState(() => _odyssey = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _odyssey = before); // revert on failure
    }
  }

  void _celebrate() {
    final destination = _odyssey.destination.isNotEmpty
        ? _odyssey.destination
        : _odyssey.title;
    final totalStops = _odyssey.totalActivities;
    final totalDays = _odyssey.days;
    final earnedXp = totalStops * 15;

    // Bump explorer XP
    CacheService.addExploration(placesVisited: totalStops, xp: earnedXp);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 32,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Trophy Icon Badge with pulse animation
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF9100)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🏆', style: TextStyle(fontSize: 38)),
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(
                    begin: const Offset(1.0, 1.0),
                    end: const Offset(1.08, 1.08),
                    duration: 1200.ms,
                    curve: Curves.easeInOut,
                  ),
              const SizedBox(height: 18),

              // Title
              const Text(
                'You Did It, Explorer! 🎉',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fade().slideY(begin: 0.2, curve: Curves.easeOutQuad),
              const SizedBox(height: 10),

              // Engaging sentence
              Text(
                'Incredible journey! You conquered every stop in $destination. Your adventure is permanently recorded in your Travel History.',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFCBD5E1),
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ).animate().fade(delay: 150.ms),
              const SizedBox(height: 20),

              // Summary Stats Chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCelebrateStat('📍', '$totalStops', 'Stops Visited'),
                    Container(width: 1, height: 28, color: Colors.white12),
                    _buildCelebrateStat('⏱️', '$totalDays', 'Days Complete'),
                    Container(width: 1, height: 28, color: Colors.white12),
                    _buildCelebrateStat('⭐', '+$earnedXp', 'Explorer XP'),
                  ],
                ),
              ).animate().fade(delay: 250.ms).scale(begin: const Offset(0.95, 0.95)),
              const SizedBox(height: 24),

              // Primary Action: View in Travel History
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF007A7C)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HistoryPage()),
                      );
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_rounded, color: Colors.black, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'View in Travel History',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fade(delay: 350.ms).slideY(begin: 0.1),
              const SizedBox(height: 10),

              // Secondary Action: Stay on plan
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Stay on Plan',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrateStat(String emoji, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final id = _odyssey.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Odyssey?'),
        content: const Text('This trip blueprint will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await _repo.delete(id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 44,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ODYSSEY',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_deleting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              ),
            )
          else if (!_isEffectivelyReadOnly)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.black54, size: 20),
              onPressed: _delete,
            ),
        ],
      ),
      body: (_loadingFresh && _odyssey.dayPlans.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Finalizing your Odyssey blueprint...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Generating days, activities, and strategies',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : OdysseyPlanView(
              odyssey: _odyssey,
              onReorderActivity: _isEffectivelyReadOnly ? null : _reorderActivity,
              onToggleVisited: _isEffectivelyReadOnly ? null : _toggleVisited,
              onSwapPartner: _isEffectivelyReadOnly ? null : _swapPartner,
              swappingPartnerName: _swappingPartnerName,
              onActualCostChanged: _isEffectivelyReadOnly ? null : _updateActualCost,
            ),
    );
  }
}
