import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/notifications/notification_router.dart';

/// The bell inbox: lists notifications received via FCM. Tapping one opens
/// what it is about, exactly as tapping its push does ([NotificationRouter]).
/// Leaving the page marks everything read.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  /// Whether the bell is open, so a push for an announcement doesn't open a
  /// second one over it.
  static bool get isShowing => _NotificationsPageState._showing > 0;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static int _showing = 0;

  @override
  void initState() {
    super.initState();
    _showing++;
    // A push that arrives (or is tapped) while the bell is open shows here.
    CacheService.notificationsNotifier.addListener(_onChanged);
    _refresh();
  }

  @override
  void dispose() {
    _showing--;
    CacheService.notificationsNotifier.removeListener(_onChanged);
    // Read once seen: on leaving, so the new ones keep their dot meanwhile.
    CacheService.markNotificationsRead();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    // Pull in notifications saved by the FCM background isolate.
    await CacheService.reload();
    if (mounted) setState(() {});
  }

  void _onTap(Map<String, dynamic> n) {
    // The push's data as it came, with its type (also kept on the line).
    final data = <String, dynamic>{
      ...?(n['data'] as Map?)?.cast<String, dynamic>(),
    };
    final type = (n['type'] ?? '').toString();
    if (type.isNotEmpty) data['type'] = type;
    NotificationRouter.open(data, fromInbox: true);
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
      case 'vendor_request':
      case 'vendor_review':
        return Icons.storefront_rounded;
      case 'experience_request':
        return Icons.receipt_long_rounded;
      case 'city_tour_trip':
        return Icons.route_rounded;
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
