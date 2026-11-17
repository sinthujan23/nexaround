import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';
import 'package:share_plus/share_plus.dart';

/// Trip Wallet's own few colours, beside the app theme.
class WalletColors {
  static const navy = Color(0xFF0F172A);
  static const slate = Color(0xFF64748B);
  static const line = Color(0xFFE5E9EF);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const card = Color(0xFFF8FAFC);
}

String walletCategoryLabel(String c) => switch (c) {
      'hotel' => 'Hotel',
      'transport' => 'Transport',
      'food' => 'Food',
      'activities' => 'Activities',
      'shopping' => 'Shopping',
      _ => 'Other',
    };

IconData walletCategoryIcon(String c) => switch (c) {
      'hotel' => Icons.hotel_rounded,
      'transport' => Icons.local_taxi_rounded,
      'food' => Icons.restaurant_rounded,
      'activities' => Icons.local_activity_rounded,
      'shopping' => Icons.shopping_bag_rounded,
      _ => Icons.receipt_long_rounded,
    };

Color walletCategoryColor(String c) => switch (c) {
      'hotel' => const Color(0xFF6366F1),
      'transport' => const Color(0xFFF59E0B),
      'food' => const Color(0xFFEF4444),
      'activities' => const Color(0xFF10B981),
      'shopping' => const Color(0xFFEC4899),
      _ => WalletColors.slate,
    };

/// A round category icon, as on each expense row.
class WalletCategoryIcon extends StatelessWidget {
  final String category;
  final double size;

  const WalletCategoryIcon(this.category, {super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final color = walletCategoryColor(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(walletCategoryIcon(category), color: color, size: size * 0.5),
    );
  }
}

/// A member's photo, or their initials.
class WalletAvatar extends StatelessWidget {
  final WalletMember? member;
  final double size;

  const WalletAvatar(this.member, {super.key, this.size = 36});

  static const _palette = [
    Color(0xFF007A7C), Color(0xFF6366F1), Color(0xFFF59E0B),
    Color(0xFFEC4899), Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFFEF4444),
  ];

  @override
  Widget build(BuildContext context) {
    final m = member;
    final color = _palette[(m?.id.hashCode ?? 0).abs() % _palette.length];
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Text(
        m?.initials ?? '?',
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: color),
      ),
    );
    final url = m?.avatarUrl;
    if (url == null || url.isEmpty) return initials;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => initials,
        errorWidget: (_, __, ___) => initials,
      ),
    );
  }
}

/// The invite link and code, with Share and Copy.
Future<void> showWalletInviteSheet(
  BuildContext context,
  WalletTrip trip, {
  Future<WalletTrip?> Function()? onReset,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => _InviteSheet(trip: trip, onReset: onReset),
  );
}

class _InviteSheet extends StatefulWidget {
  final WalletTrip trip;
  final Future<WalletTrip?> Function()? onReset;

  const _InviteSheet({required this.trip, this.onReset});

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  late WalletTrip _trip = widget.trip;
  bool _resetting = false;

  String get _message =>
      'Join "${_trip.name}" on nexARound Trip Split so we can split our trip expenses.\n'
      '${_trip.inviteUrl}\n'
      'Or open Trip Split and enter code ${_trip.inviteCode}';

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(ShareParams(
        text: _message,
        subject: 'Join ${_trip.name} on Trip Split',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (_) {
      await _copy();
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied')));
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Make a new invite link?'),
        content: const Text('The old link and code stop working. People already in the trip stay in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('New link')),
        ],
      ),
    );
    if (ok != true || widget.onReset == null) return;
    setState(() => _resetting = true);
    final t = await widget.onReset!();
    if (!mounted) return;
    setState(() {
      _resetting = false;
      if (t != null) _trip = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // No handle drawn here: the app's sheet theme already shows one
        // (app_theme.dart showDragHandle), so a second bar appeared.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Invite friends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WalletColors.navy)),
            const SizedBox(height: 4),
            Text('Anyone with this link or code can join ${_trip.name}.',
                style: const TextStyle(fontSize: 14, color: WalletColors.slate)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.brandGreenLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.brandGreen.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  const Text('TRIP CODE',
                      style: TextStyle(
                          fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: AppColors.brandGreen)),
                  const SizedBox(height: 6),
                  _resetting
                      ? const SizedBox(
                          height: 36, width: 36, child: CircularProgressIndicator(color: AppColors.brandGreen))
                      : SelectableText(
                          _trip.inviteCode,
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 6, color: WalletColors.navy),
                        ),
                  const SizedBox(height: 4),
                  Text(_trip.inviteUrl.replaceFirst('https://', ''),
                      style: const TextStyle(fontSize: 13, color: WalletColors.slate)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _resetting ? null : _share,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Share invite'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _resetting ? null : _copy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WalletColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: WalletColors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (widget.onReset != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: _resetting ? null : _reset,
                child: const Text('Make a new link', style: TextStyle(color: WalletColors.slate)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The empty state of a list.
class WalletEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  const WalletEmpty({super.key, required this.icon, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(color: AppColors.brandGreenLight, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.brandGreen, size: 30),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: WalletColors.navy)),
          const SizedBox(height: 6),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.4, color: WalletColors.slate)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
