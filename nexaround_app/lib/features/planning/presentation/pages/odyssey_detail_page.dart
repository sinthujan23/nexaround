import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/odyssey_plan_view.dart';

/// Read-only view of a saved Odyssey, with the option to delete it.
class OdysseyDetailPage extends StatefulWidget {
  final Odyssey odyssey;
  const OdysseyDetailPage({super.key, required this.odyssey});

  @override
  State<OdysseyDetailPage> createState() => _OdysseyDetailPageState();
}

class _OdysseyDetailPageState extends State<OdysseyDetailPage> {
  final _repo = OdysseyRepository();
  bool _deleting = false;

  /// Local working copy so AI swaps update the view in place.
  late Odyssey _odyssey = widget.odyssey;

  /// "dayIndex:activityIndex" of the activity being swapped, or null.
  String? _swappingKey;

  Future<void> _swapActivity(int dayIndex, int activityIndex) async {
    final id = _odyssey.id;
    if (id == null) return;
    final act = _odyssey.dayPlans[dayIndex].activities[activityIndex];

    final reason = await _askReason(act.name);
    if (reason == null || !mounted) return; // cancelled

    setState(() => _swappingKey = '$dayIndex:$activityIndex');
    try {
      final updated = await _repo.swapActivity(
        itineraryId: id,
        dayIndex: dayIndex,
        activityIndex: activityIndex,
        reason: reason,
      );
      if (!mounted) return;
      final newName =
          updated.dayPlans[dayIndex].activities[activityIndex].name;
      setState(() {
        _odyssey = updated;
        _swappingKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swapped in: $newName')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _swappingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not swap this place. Try again.')),
      );
    }
  }

  /// Bottom sheet asking why the place is being replaced. Returns the chosen
  /// reason text, or null if the user cancelled.
  Future<String?> _askReason(String placeName) {
    const presets = [
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
            const Text(
              'Tell the AI why, and it’ll suggest a different place for this slot.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                child: const Text('Ask AI for a different place'),
              ),
            ),
          ],
        ),
      ),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ODYSSEY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_deleting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.black54),
              onPressed: _delete,
            ),
        ],
      ),
      body: OdysseyPlanView(
        odyssey: _odyssey,
        onSwapActivity: _swapActivity,
        swappingKey: _swappingKey,
      ),
    );
  }
}
