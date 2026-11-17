import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/trip_wallet/data/trip_wallet_service.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/pages/wallet_trip_page.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/widgets/trip_wallet_widgets.dart';

/// "Join <trip>?": what an invite link (`https://nexaround.com/w/<code>`) or a
/// typed code opens.
///
/// From a link it is opened at /home/w/:code (lib/app/routes.dart), over Home;
/// once joined it shows the trip in its place, so Back returns to Home. From
/// "Join with code" it is pushed with [fromLink] false and pops with the
/// trip's id instead.
class JoinTripPage extends StatefulWidget {
  final String code;
  final bool fromLink;
  final bool standalone;

  const JoinTripPage({super.key, required this.code, this.fromLink = false, this.standalone = false});

  @override
  State<JoinTripPage> createState() => _JoinTripPageState();
}

class _JoinTripPageState extends State<JoinTripPage> {
  final _service = TripWalletService();
  WalletInvitePreview? _preview;
  String? _error;
  bool _loading = true;
  bool _joining = false;
  String? _joinedTripId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _service.previewInvite(widget.code);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = statusCodeOf(e) == 404
            ? 'This invite is not valid any more. Ask the trip owner to share it again.'
            : userMessageFor(e, action: 'open the invite');
        _loading = false;
      });
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final trip = await _service.join(widget.code);
      if (!mounted) return;
      _done(trip.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessageFor(e, action: 'join the trip'))));
    }
  }

  void _done(String tripId) {
    TripWalletService.revision.value++;
    if (widget.fromLink) {
      setState(() => _joinedTripId = tripId);
    } else {
      Navigator.of(context).pop(tripId);
    }
  }

  void _leave() {
    if (widget.standalone) {
      context.go('/');
    } else if (!Navigator.of(context).canPop()) {
      context.go('/home');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final joined = _joinedTripId;
    final Widget page = joined != null ? WalletTripPage(tripId: joined) : _buildJoin();
    if (!widget.standalone) return page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: page,
    );
  }

  Widget _buildJoin() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: WalletColors.navy,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _leave),
        title: const Text('Trip Wallet', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandGreen))
          : _preview == null
              ? Center(
                  child: WalletEmpty(
                    icon: Icons.link_off_rounded,
                    title: 'Invite not found',
                    text: _error ?? '',
                  ),
                )
              : _buildPreview(_preview!),
    );
  }

  Widget _buildPreview(WalletInvitePreview p) {
    final who = p.ownerName?.split(' ').first;
    final names = p.memberNames.join(', ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: AppColors.brandGreenLight, shape: BoxShape.circle),
                child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.brandGreen, size: 38),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              who == null ? 'You are invited' : '$who invited you',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: WalletColors.slate, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              p.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: WalletColors.navy),
            ),
            const SizedBox(height: 10),
            Text(
              '${p.memberCount} ${p.memberCount == 1 ? 'person' : 'people'} · amounts in ${p.currency}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: WalletColors.slate),
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(names,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: WalletColors.slate)),
            ],
            const SizedBox(height: 24),
            const _Point(icon: Icons.receipt_long_rounded, text: 'Add what you paid, with a receipt photo'),
            const _Point(icon: Icons.groups_rounded, text: 'Everyone sees every expense'),
            const _Point(icon: Icons.handshake_rounded, text: 'Settle up with the fewest payments'),
            const Spacer(flex: 2),
            ElevatedButton(
              onPressed: _joining
                  ? null
                  : p.alreadyMember
                      ? () => _done(p.tripId)
                      : _join,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              child: _joining
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(p.alreadyMember ? 'Open trip' : 'Join trip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.brandGreen),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5, color: WalletColors.navy))),
        ],
      ),
    );
  }
}
