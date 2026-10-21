import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';

/// The vendor's notifications: the web portal bell's "For you" feed. A
/// request shows only as "New request: (package)" with the date and guests;
/// NexAround arranges the rest with the traveller.
class VendorNotificationsPage extends StatefulWidget {
  final VendorPortalApi api;

  const VendorNotificationsPage({super.key, required this.api});

  @override
  State<VendorNotificationsPage> createState() => _VendorNotificationsPageState();
}

class _VendorNotificationsPageState extends State<VendorNotificationsPage> {
  final List<VendorActivityItem> _items = [];
  DateTime? _seenAt;
  bool _hasMore = false;
  bool _loading = false;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page = await widget.api.activity(before: reset || _items.isEmpty ? null : _items.last.createdAt);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items.clear();
          // Lines newer than this stay marked as new while the page is open.
          _seenAt = page.seenAt;
        }
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _loaded = true;
        _error = null;
      });
      if (reset) await widget.api.markSeen();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static (IconData, Color) _look(String kind) => switch (kind) {
        'request.received' => (Icons.confirmation_number_rounded, AppColors.brandGreen),
        'request.confirmed' => (Icons.check_circle_rounded, AppColors.success),
        'request.cancelled' => (Icons.cancel_rounded, AppColors.error),
        'review.created' => (Icons.star_rounded, AppColors.ratingGold),
        'package.live' => (Icons.check_rounded, AppColors.success),
        'package.hidden' => (Icons.visibility_off_rounded, AppColors.textTertiary),
        'package.deleted' => (Icons.delete_outline_rounded, AppColors.error),
        'package.created' => (Icons.add_rounded, AppColors.actionTeal),
        'package.updated' => (Icons.edit_rounded, AppColors.actionTeal),
        _ => (Icons.notifications_none_rounded, AppColors.textTertiary),
      };

  String _age(DateTime d) {
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: const Text('Notifications', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(onRefresh: () => _load(reset: true), child: _body()),
    );
  }

  Widget _body() {
    if (_error != null && _items.isEmpty) {
      return ListView(children: [
        VendorEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load notifications',
          message: userMessageFor(_error),
          action: OutlinedButton(onPressed: () => _load(reset: true), child: const Text('Try again')),
        ),
      ]);
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return ListView(children: const [
        VendorEmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'Nothing new',
          message: 'New requests, reviews and changes NexAround makes to your listing show here.',
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return OutlinedButton(
            onPressed: _loading ? null : () => _load(),
            child: Text(_loading ? 'Loading…' : 'Show more'),
          );
        }
        final item = _items[i];
        final (icon, color) = _look(item.kind);
        final isNew = _seenAt == null || item.createdAt.isAfter(_seenAt!);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isNew ? AppColors.brandGreen.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isNew ? AppColors.brandGreen.withValues(alpha: 0.3) : AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
                    if ((item.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(item.body!,
                          style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 6),
                    Text(_age(item.createdAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
