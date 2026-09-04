import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/core/services/discovery_history_service.dart';

import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';

/// The bell inbox: lists notifications received via FCM. Tapping an
/// "odyssey_ready" or "discovery_ready" item jumps directly to the exact plan. Opening the page marks
/// everything read.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // Pull in notifications saved by the FCM background isolate, then show them
    // and clear the unread badge.
    await CacheService.reload();
    if (!mounted) return;
    setState(() {});
    await CacheService.markNotificationsRead();
  }

  bool _isHandlingTap = false;

  void _onTap(Map<String, dynamic> n) async {
    if (_isHandlingTap) return;
    _isHandlingTap = true;
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _isHandlingTap = false;
    });

    final type = (n['type'] ?? '').toString();
    final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? n;
    final odysseyId = (data['odyssey_id'] ?? data['itinerary_id'] ?? data['id'] ?? data['odysseyId'] ?? n['odyssey_id'] ?? n['id'])?.toString();

    if (type == 'odyssey_ready' || type == 'odyssey_generated' || type == 'plan_ready' || (odysseyId != null && odysseyId.isNotEmpty && type.contains('odyssey'))) {
      Navigator.pop(context);
      if (odysseyId != null && odysseyId.isNotEmpty) {
        await HomePage.homeKey.currentState?.openOdysseyById(odysseyId);
      } else {
        try {
          final repo = OdysseyRepository();
          final list = await repo.getMyOdysseys();
          if (list.isNotEmpty) {
            HomePage.homeKey.currentState?.openOdysseyDetail(list.first);
          } else {
            HomePage.homeKey.currentState?.switchToPlans();
          }
        } catch (_) {
          HomePage.homeKey.currentState?.switchToPlans();
        }
      }
    } else if (type == 'discovery_ready' || type.contains('discovery')) {
      Navigator.pop(context);
      final discoveryId = (data['discovery_id'] ?? data['id'] ?? n['discovery_id'] ?? n['id'])?.toString();
      try {
        final history = await DiscoveryHistoryService.fetchHistory();
        Map<String, dynamic>? target;
        if (discoveryId != null && discoveryId.isNotEmpty) {
          for (final item in history) {
            if (item['id']?.toString() == discoveryId) {
              target = item;
              break;
            }
          }
        }
        target ??= history.isNotEmpty ? history.first : null;
        if (target != null) {
          final res = target['result'] as String?;
          final loc = target['location'] as String?;
          final mode = target['mode'] as String?;
          final mood = target['mood'] as String?;
          if (res != null && res.isNotEmpty) {
            HomePage.homeKey.currentState?.openDiscoveryPlan(res, location: loc, mode: mode, mood: mood);
          }
        }
      } catch (e) {
        debugPrint('Error opening discovery plan from inbox notification: $e');
      }
    }
  }

  String _fmt(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'odyssey_ready':
        return Icons.auto_awesome_rounded;
      case 'discovery_ready':
        return Icons.explore_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = CacheService.getNotifications();
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
          'NOTIFICATIONS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                await CacheService.clearNotifications();
                if (mounted) setState(() {});
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: items.isEmpty
          ? _empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _tile(items[i]),
            ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded,
                size: 56, color: Colors.black26),
            const SizedBox(height: 16),
            const Text('No notifications yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'When your Odyssey is ready or there\'s news, it shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString();
    final unread = n['read'] != true;
    return GestureDetector(
      onTap: () => _onTap(n),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: unread ? AppColors.brandGreen.withValues(alpha: 0.4) : Colors.black12,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconFor(type), color: AppColors.brandGreen, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (n['title'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.brandGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if ((n['body'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      (n['body'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _fmt((n['date'] ?? '').toString()),
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
