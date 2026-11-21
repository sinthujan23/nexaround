import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/trip_wallet/data/trip_wallet_service.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/pages/join_trip_page.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/pages/wallet_trip_page.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/widgets/trip_wallet_widgets.dart';
import 'package:nexaround_app/core/widgets/app_back_button.dart';

/// The page behind the passes; also what shows through their notches.
const _pageBg = Color(0xFFEEF2F4);

/// Labels and the flight icon on a pass.
const _muted = Color(0xFF94A3B8);

/// The photo header's height below the status bar.
const double _headerBody = 178;

/// How far the first pass reaches up into the header photo.
const double _passOverlap = 30;

/// Trip Wallet's home, opened from the Curated Hubs tile: the traveller's
/// trips as boarding passes with their own balance on the stub, and a "+"
/// at the bottom right that opens "New trip" and "Join with code".
class TripWalletPage extends StatefulWidget {
  const TripWalletPage({super.key});

  @override
  State<TripWalletPage> createState() => _TripWalletPageState();
}

class _TripWalletPageState extends State<TripWalletPage> {
  final _service = TripWalletService();
  final _scroll = ScrollController();

  /// The list as last loaded on this device shows at once; the server's copy
  /// replaces it when it comes.
  late List<WalletTripCard>? _trips = _service.cachedTrips();
  String? _error;

  /// The top bar is see-through over the photo and turns solid once the
  /// photo has scrolled up under it.
  bool _barSolid = false;

  /// The "+" button's two choices, New trip and Join with code, are showing.
  bool _menuOpen = false;

  static const _menuAnim = Duration(milliseconds: 200);
  static const double _fabSize = 64;

  @override
  void initState() {
    super.initState();
    _load();
    TripWalletService.revision.addListener(_load);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    TripWalletService.revision.removeListener(_load);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final solid = _scroll.offset > _headerBody - kToolbarHeight;
    if (solid != _barSolid) setState(() => _barSolid = solid);
  }

  Future<void> _load() async {
    try {
      final trips = await _service.getTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userMessageFor(e, action: 'load your trips'));
    }
  }

  Future<void> _open(String tripId) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WalletTripPage(tripId: tripId)));
    _load();
  }

  Future<void> _newTrip() async {
    final trip = await showModalBottomSheet<WalletTrip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _NewTripSheet(),
    );
    if (trip == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await _open(trip.id);
  }

  Future<void> _joinWithCode() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _JoinCodeSheet(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    final tripId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => JoinTripPage(code: code.trim())),
    );
    await _load();
    if (tripId != null && mounted) _open(tripId);
  }

  void _setMenu(bool open) {
    if (open != _menuOpen) setState(() => _menuOpen = open);
  }

  /// Closes the menu, then starts the picked action.
  void _choose(Future<void> Function() action) {
    _setMenu(false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final fabBottom = padding.bottom + 16;
    return PopScope(
      // Back closes the open menu first.
      canPop: !_menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setMenu(false);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // White status bar icons, on the photo and on the solid bar alike.
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: _pageBg,
          body: Stack(
            children: [
              RefreshIndicator(
                color: AppColors.brandGreen,
                edgeOffset: padding.top + kToolbarHeight,
                onRefresh: _load,
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _content(padding.top + _headerBody)),
                    // Room to scroll the last pass clear of the "+" button.
                    SliverToBoxAdapter(child: SizedBox(height: 100 + padding.bottom)),
                  ],
                ),
              ),
              Positioned(left: 0, right: 0, top: 0, child: _topBar(padding.top)),
              // Dims the page while the menu is open; a tap on it closes it.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_menuOpen,
                  child: AnimatedOpacity(
                    opacity: _menuOpen ? 1 : 0,
                    duration: _menuAnim,
                    child: GestureDetector(
                      onTap: () => _setMenu(false),
                      child: const ColoredBox(color: Color(0x8C0F172A)),
                    ),
                  ),
                ),
              ),
              // The choices' icons line up over the middle of the "+".
              Positioned(right: 20 + (_fabSize - 52) / 2, bottom: fabBottom + _fabSize + 16, child: _menuChoices()),
              Positioned(right: 20, bottom: fabBottom, child: _fab()),
            ],
          ),
        ),
      ),
    );
  }

  /// The photo header and what sits under it. With trips, the passes start
  /// [_passOverlap] up inside the photo, so both share one box: the photo
  /// first, the passes painted over it.
  Widget _content(double headerHeight) {
    final trips = _trips;
    if (trips != null && trips.isNotEmpty) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          // The heading is the page's name, so no "TRIP SPLIT" line over it.
          _Header(height: headerHeight, title: 'Trip Split', eyebrow: false, textBottom: _passOverlap + 14),
          Padding(
            padding: EdgeInsets.fromLTRB(16, headerHeight - _passOverlap, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < trips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _TripPass(trip: trips[i], onTap: () => _open(trips[i].id)),
                ],
                // The refresh failed: these are the trips kept on the device.
                if (_error != null) const _SavedNote(padding: EdgeInsets.fromLTRB(4, 14, 4, 0)),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(height: headerHeight, title: 'Split trip costs\nwith friends', textBottom: 20),
        if (trips == null && _error == null)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: AppColors.brandGreen)),
          )
        else if (trips == null)
          WalletEmpty(
            icon: Icons.wifi_off_rounded,
            title: 'Trips not loaded',
            text: _error!,
            action: TextButton(onPressed: _load, child: const Text('Try again')),
          )
        else ...[
          const _FirstVisit(),
          if (_error != null) const _SavedNote(padding: EdgeInsets.fromLTRB(22, 4, 22, 0)),
        ],
      ],
    );
  }

  Widget _topBar(double topInset) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: topInset + kToolbarHeight,
      padding: EdgeInsets.only(top: topInset, right: 16),
      color: _barSolid ? AppColors.brandGreenDark : Colors.transparent,
      // Back button only: the photo's "TRIP SPLIT" heading names the page.
      child: const Row(
        children: [
          // The size an AppBar gives its leading button.
          SizedBox(width: 56, height: 56, child: AppBackButton(onImage: true)),
        ],
      ),
    );
  }

  /// New trip and Join with code, rising above the "+" when it opens.
  Widget _menuChoices() {
    return IgnorePointer(
      ignoring: !_menuOpen,
      child: AnimatedOpacity(
        opacity: _menuOpen ? 1 : 0,
        duration: _menuAnim,
        child: AnimatedSlide(
          offset: _menuOpen ? Offset.zero : const Offset(0, 0.12),
          duration: _menuAnim,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MenuChoice(
                title: 'New trip',
                icon: Icons.luggage_rounded,
                iconBg: AppColors.brandGreen,
                iconColor: Colors.white,
                onTap: () => _choose(_newTrip),
              ),
              const SizedBox(height: 14),
              _MenuChoice(
                title: 'Join with code',
                icon: Icons.dialpad_rounded,
                iconBg: Colors.white,
                iconColor: WalletColors.navy,
                onTap: () => _choose(_joinWithCode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The round-cornered teal "+", which turns white with an "×" while the
  /// menu is open.
  Widget _fab() {
    return Semantics(
      button: true,
      label: _menuOpen ? 'Close' : 'New trip or join a trip',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _setMenu(!_menuOpen),
        child: AnimatedContainer(
          duration: _menuAnim,
          width: _fabSize,
          height: _fabSize,
          decoration: BoxDecoration(
            color: _menuOpen ? Colors.white : AppColors.brandGreen,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: (_menuOpen ? Colors.black : AppColors.brandGreen).withValues(alpha: 0.45),
                blurRadius: 26,
                spreadRadius: -8,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          // An eighth of a turn (45°) makes the "+" an "×".
          child: AnimatedRotation(
            turns: _menuOpen ? 0.125 : 0,
            duration: _menuAnim,
            curve: Curves.easeOutCubic,
            child: Icon(Icons.add_rounded, size: 32, color: _menuOpen ? WalletColors.navy : Colors.white),
          ),
        ),
      ),
    );
  }
}

/// One choice of the "+" menu: a white label card with its name, then its
/// icon.
class _MenuChoice extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final VoidCallback onTap;

  const _MenuChoice({
    required this.title,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.onTap,
  });

  static const _shadow = [
    BoxShadow(color: Color(0x66000000), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8)),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: _shadow,
              ),
              child: Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: WalletColors.navy)),
            ),
            const SizedBox(width: 12),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
              child: Icon(icon, color: iconColor, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

/// The group photo with a dotted flight path and the page heading.
class _Header extends StatelessWidget {
  final double height;
  final String title;

  /// Space under the heading: room for the first pass, which overlaps the
  /// photo's foot.
  final double textBottom;

  /// The small "TRIP SPLIT" line over the heading.
  final bool eyebrow;

  const _Header({required this.height, required this.title, required this.textBottom, this.eyebrow = true});

  /// A soft dark glow behind the white heading, for the photo's bright spots.
  static const _headingShadow = [Shadow(color: Color(0x73000000), blurRadius: 12, offset: Offset(0, 1))];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/trip_wallet_header.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.brandGreenDark),
          ),
          // Dark over the bright sky for the back button, light over the
          // faces, then deep teal from mid-photo down so the white heading
          // reads on the bright clothes and grass.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.32, 0.6, 1],
                colors: [
                  WalletColors.navy.withValues(alpha: 0.45),
                  WalletColors.navy.withValues(alpha: 0.05),
                  AppColors.brandGreenDark.withValues(alpha: 0.6),
                  AppColors.brandGreenDark.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
          const CustomPaint(painter: _FlightPathPainter()),
          Positioned(
            left: 20,
            right: 20,
            bottom: textBottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow) ...[
                  const Text(
                    'TRIP SPLIT',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: Colors.white,
                      shadows: _headingShadow,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Colors.white,
                    shadows: _headingShadow,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A trip as a boarding pass: a code from its name, people, spent, items and
/// currency, and a tear-off stub with the traveller's own balance.
class _TripPass extends StatelessWidget {
  final WalletTripCard trip;
  final VoidCallback onTap;

  const _TripPass({required this.trip, required this.onTap});

  static const _codeColors = [
    Color(0xFF4F46E5),
    Color(0xFFDB2777),
    Color(0xFF007A7C),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF0284C7),
    Color(0xFF059669),
  ];

  /// The first three letters or digits of the name, like an airport code.
  String get _code {
    final letters = trip.name.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (letters.isEmpty) return 'TRP';
    return letters.characters.take(3).toString().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final net = trip.myNet;
    final codeColor = _codeColors[trip.id.hashCode.abs() % _codeColors.length];
    final people = trip.memberCount == 1 ? 'JUST YOU' : 'GROUP OF ${trip.memberCount}';

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _code,
              style: TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w900, letterSpacing: 1, color: codeColor),
            ),
            const SizedBox(width: 8),
            const RotatedBox(quarterTurns: 1, child: Icon(Icons.flight_rounded, size: 18, color: _muted)),
            const SizedBox(width: 6),
            Flexible(child: _label(people, size: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                trip.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
              ),
            ),
            if (trip.isOwner && trip.pendingCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFF4DE), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${trip.pendingCount} to approve',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                ),
              ),
            ],
          ],
        ),
        const Spacer(),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(child: _field('SPENT', money.format(trip.totalSpent))),
            const SizedBox(width: 16),
            _field('ITEMS', '${trip.expenseCount}'),
            const SizedBox(width: 16),
            _field('CUR', trip.currency),
          ],
        ),
      ],
    );

    final settled = net == 0;
    final stub = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _label(net > 0 ? 'YOU GET' : (net < 0 ? 'YOU OWE' : 'STATUS')),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: settled
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: WalletColors.slate),
                    SizedBox(width: 3),
                    Text('Settled',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: WalletColors.slate)),
                  ],
                )
              : Text(
                  money.format(net.abs()),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: net > 0 ? WalletColors.green : WalletColors.red,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: settled ? 0.25 : 0.8,
          child: const SizedBox(width: 78, height: 24, child: CustomPaint(painter: _BarcodePainter())),
        ),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: _passHeight),
      decoration: const ShapeDecoration(
        color: Colors.white,
        // A grey outline so each pass stands apart from the page (client's
        // request), following the notches too.
        shape: _PassBorder(side: BorderSide(color: Color(0xFFCBD5E1), width: 1.2)),
        shadows: [BoxShadow(color: Color(0x400F172A), blurRadius: 20, spreadRadius: -12, offset: Offset(0, 8))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const _PassBorder(),
          onTap: onTap,
          child: _passRow(main: main, stub: stub, perforation: const Color(0xFFD6DEE4)),
        ),
      ),
    );
  }
}

/// Under a list kept on the device when the refresh failed, as the vendor
/// screens say it.
class _SavedNote extends StatelessWidget {
  final EdgeInsets padding;

  const _SavedNote({required this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: _muted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing saved trips. Pull down to refresh.',
              style: TextStyle(fontSize: 12.5, color: WalletColors.slate),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first-visit screen: an empty dashed pass and the three steps.
class _FirstVisit extends StatelessWidget {
  const _FirstVisit();

  @override
  Widget build(BuildContext context) {
    const ghost = Color(0xFFB8C4CC);
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('???',
                style: TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w900, letterSpacing: 1, color: ghost)),
            const SizedBox(width: 8),
            const RotatedBox(quarterTurns: 1, child: Icon(Icons.flight_rounded, size: 18, color: _muted)),
            const SizedBox(width: 6),
            Flexible(child: _label('YOUR GROUP', size: 12)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Your first trip pass',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _muted)),
        const Spacer(),
        const SizedBox(height: 8),
        Row(
          children: [
            _placeholderField('SPENT', 60),
            const SizedBox(width: 16),
            _placeholderField('ITEMS', 26),
          ],
        ),
      ],
    );
    final stub = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _label('YOUR BALANCE'),
        const SizedBox(height: 6),
        _placeholderLine(60),
        const SizedBox(height: 8),
        const Opacity(
          opacity: 0.15,
          child: SizedBox(width: 78, height: 24, child: CustomPaint(painter: _BarcodePainter())),
        ),
      ],
    );
    const steps = [
      (Icons.share_rounded, 'Invite friends with a link or code'),
      (Icons.receipt_long_rounded, 'Everyone adds what they paid'),
      (Icons.swap_horiz_rounded, 'See who owes whom and settle up'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomPaint(
            painter: const _DashedPassPainter(color: ghost),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _passHeight),
              child: _passRow(main: main, stub: stub, perforation: ghost),
            ),
          ),
          const SizedBox(height: 22),
          for (final (icon, text) in steps)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.brandGreen, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.4, color: Color(0xFF475569))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholderField(String label, double width) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [_label(label), const SizedBox(height: 5), _placeholderLine(width)],
      );

  Widget _placeholderLine(double width) => Container(
        width: width,
        height: 10,
        decoration: BoxDecoration(color: const Color(0xFFDCE3E8), borderRadius: BorderRadius.circular(5)),
      );
}

const double _passHeight = 124;
const double _stubWidth = 116;

/// A pass's two parts side by side with the dashed tear line between them.
/// The row takes the height of its taller part, at least [_passHeight].
Widget _passRow({required Widget main, required Widget stub, required Color perforation}) {
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 13, 12, 12), child: main)),
        SizedBox(width: 2, child: CustomPaint(painter: _PerforationPainter(perforation))),
        SizedBox(
          width: _stubWidth - 2,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: stub),
        ),
      ],
    ),
  );
}

/// A small grey capital label, as over each pass field.
Widget _label(String text, {double size = 9.5}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 1, color: _muted),
    );

Widget _field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(label),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: WalletColors.navy),
        ),
      ],
    );

/// A rounded ticket with a half-circle notch top and bottom where the stub
/// tears off. The notches are real holes, so the page shows through.
class _PassBorder extends ShapeBorder {
  /// The outline drawn along the edge and round the notches; none by default.
  final BorderSide side;

  const _PassBorder({this.side = BorderSide.none});

  static const _radius = 18.0;
  static const _notch = 10.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(_radius)));
    // On the middle of the 2-px tear line.
    final x = rect.right - _stubWidth + 1;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, rect.top), radius: _notch))
      ..addOval(Rect.fromCircle(center: Offset(x, rect.bottom), radius: _notch));
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => _PassBorder(side: side.scale(t));
}

/// The empty pass's dashed outline, notches included.
class _DashedPassPainter extends CustomPainter {
  final Color color;

  const _DashedPassPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = const _PassBorder().getOuterPath((Offset.zero & size).deflate(1));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPassPainter old) => old.color != color;
}

/// The tear line between a pass and its stub, stopping at the notches.
class _PerforationPainter extends CustomPainter {
  final Color color;

  const _PerforationPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width;
    final x = size.width / 2;
    for (var y = 12.0; y < size.height - 12; y += 9) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 5, size.height - 12)), paint);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => old.color != color;
}

/// A decorative barcode on the stub.
class _BarcodePainter extends CustomPainter {
  const _BarcodePainter();

  // Bar and gap widths, repeated across.
  static const _pattern = [2.0, 2.0, 1.0, 3.0, 3.0, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = WalletColors.navy;
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final w = _pattern[i % _pattern.length];
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, math.min(w, size.width - x), size.height), paint);
      x += w;
      i++;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => false;
}

/// A dotted flight path curving across the header photo.
class _FlightPathPainter extends CustomPainter {
  const _FlightPathPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 390 x 228 header, stretched to the real one.
    final sx = size.width / 390, sy = size.height / 228;
    final path = Path()
      ..moveTo(-10 * sx, 190 * sy)
      ..cubicTo(90 * sx, 120 * sy, 220 * sx, 210 * sy, 400 * sx, 60 * sy);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 2, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FlightPathPainter old) => false;
}

class _NewTripSheet extends StatefulWidget {
  const _NewTripSheet();

  @override
  State<_NewTripSheet> createState() => _NewTripSheetState();
}

class _NewTripSheetState extends State<_NewTripSheet> {
  final _name = TextEditingController();
  String _currency = 'USD';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated) {
      final pref = auth.user.preferences['currency']?.toString().toUpperCase();
      if (pref != null && CurrencyService.supportedCurrencies.any((c) => c['code'] == pref)) {
        _currency = pref;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _hideKeyboard();
    setState(() => _saving = true);
    try {
      final trip = await TripWalletService().createTrip(name: name, currency: _currency);
      if (mounted) Navigator.pop(context, trip);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessageFor(e, action: 'make the trip'))));
    }
  }

  void _hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _pickCurrency() async {
    // Close the keyboard first, or it pops back up over the sheet after a
    // currency is picked.
    _hideKeyboard();
    final code = await pickWalletCurrency(context, _currency);
    if (code != null) setState(() => _currency = code);
  }

  @override
  Widget build(BuildContext context) {
    final cur = CurrencyService.supportedCurrencies.firstWhere(
      (c) => c['code'] == _currency,
      orElse: () => {'code': _currency, 'name': _currency, 'flag': ''},
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          // A tap anywhere on the sheet that is not a field closes the keyboard.
          behavior: HitTestBehavior.opaque,
          onTap: _hideKeyboard,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New trip', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WalletColors.navy)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: _fieldDecoration('Trip name', hint: 'e.g. Munnar trip'),
              onChanged: (_) => setState(() {}),
              // "Done" closes the keyboard; with a name typed it also creates.
              onSubmitted: (_) {
                if (_name.text.trim().isEmpty) {
                  _hideKeyboard();
                } else {
                  _create();
                }
              },
              onTapOutside: (_) => _hideKeyboard(),
            ),
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickCurrency,
              child: InputDecorator(
                decoration: _fieldDecoration('Currency for this trip'),
                child: Row(
                  children: [
                    Text('${cur['flag']}  ${cur['code']} · ${cur['name']}',
                        style: const TextStyle(fontSize: 15, color: WalletColors.navy)),
                    const Spacer(),
                    const Icon(Icons.expand_more_rounded, color: WalletColors.slate),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Everyone in the trip enters amounts in this currency.',
                style: TextStyle(fontSize: 12.5, color: WalletColors.slate)),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _saving || _name.text.trim().isEmpty ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create trip'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: WalletColors.card,
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: WalletColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: WalletColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.brandGreen, width: 1.5),
      ),
    );

/// A searchable list of the app's currencies; returns the picked code.
Future<String?> pickWalletCurrency(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _CurrencyPicker(current: current),
  );
}

class _CurrencyPicker extends StatefulWidget {
  final String current;
  const _CurrencyPicker({required this.current});

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = CurrencyService.supportedCurrencies
        .where((c) => q.isEmpty || '${c['code']} ${c['name']}'.toLowerCase().contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: _fieldDecoration('Search currency').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                final selected = c['code'] == widget.current;
                return ListTile(
                  leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 22)),
                  title: Text('${c['code']} · ${c['name']}'),
                  trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.brandGreen) : null,
                  onTap: () => Navigator.pop(context, c['code']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Join a trip": the 6-character invite code in six boxes, like the app's
/// sign-in code screen. One hidden field takes the typing (so backspace and
/// paste just work); the boxes show it. Pops with the code.
class _JoinCodeSheet extends StatefulWidget {
  const _JoinCodeSheet();

  @override
  State<_JoinCodeSheet> createState() => _JoinCodeSheetState();
}

class _JoinCodeSheetState extends State<_JoinCodeSheet> {
  static const _length = 6;

  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.length == _length;

  void _hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _submit() {
    if (!_complete) return;
    _hideKeyboard();
    Navigator.pop(context, _code.text);
  }

  /// Fills the boxes from a copied invite: the whole WhatsApp message, the
  /// link (nexaround.com/w/CODE) or just the code.
  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final link = RegExp(r'/w/([A-Za-z0-9]{6})').firstMatch(text);
    final code = link?.group(1) ??
        RegExp(r'\b[A-Za-z0-9]{6}\b').allMatches(text).map((m) => m.group(0)!).firstWhere(
              (c) => RegExp(r'\d').hasMatch(c) || text.trim().length == _length,
              orElse: () => '',
            );
    if (!mounted) return;
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trip code found in what you copied')),
      );
      return;
    }
    _code.value = TextEditingValue(
      text: code.toUpperCase(),
      selection: const TextSelection.collapsed(offset: _length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = _code.text;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          // A tap on the sheet outside the boxes closes the keyboard.
          behavior: HitTestBehavior.opaque,
          onTap: _hideKeyboard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Join a trip',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WalletColors.navy)),
              const SizedBox(height: 6),
              const Text(
                'Enter the 6-character code from the invite the trip owner shared with you.',
                style: TextStyle(fontSize: 14, height: 1.4, color: WalletColors.slate),
              ),
              const SizedBox(height: 20),
              // The boxes, with the real (invisible) field on top of them.
              SizedBox(
                height: 58,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: _box(i < text.length ? text[i] : '', _isActive(i, text))),
                        ],
                      ],
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _code,
                          focusNode: _focus,
                          autofocus: true,
                          maxLength: _length,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.go,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                            _UpperCase(),
                          ],
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _complete ? _submit() : _hideKeyboard(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: const Text('Paste invite'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.brandGreen),
                ),
              ),
              const SizedBox(height: 6),
              ElevatedButton(
                onPressed: _complete ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The box the next character goes in (the last one once all are filled).
  bool _isActive(int i, String text) =>
      _focus.hasFocus && (i == text.length || (text.length == _length && i == _length - 1));

  Widget _box(String char, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: char.isEmpty ? WalletColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? AppColors.brandGreen : (char.isEmpty ? WalletColors.line : WalletColors.slate.withValues(alpha: 0.5)),
          width: active ? 1.8 : 1,
        ),
      ),
      child: Text(
        char,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: WalletColors.navy),
      ),
    );
  }
}

/// Typed letters show as capitals, as the codes are written.
class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
