import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/widgets/full_screen_image_viewer.dart';
import 'package:nexaround_app/features/trip_wallet/data/trip_wallet_service.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/pages/add_expense_page.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/widgets/trip_wallet_widgets.dart';
import 'package:nexaround_app/core/widgets/app_back_button.dart';

/// Opens a trip from a push or a link; a trip the traveller is no longer in
/// shows the page's own "not found" state.
Future<void> openWalletTripById(BuildContext context, String tripId) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => WalletTripPage(tripId: tripId)));
}

/// One trip: what everyone spent, each person's balance, and the payments
/// that settle it up. Reloads on open, on pull-down, after every change, and
/// when a Trip Wallet push arrives.
class WalletTripPage extends StatefulWidget {
  final String tripId;
  const WalletTripPage({super.key, required this.tripId});

  @override
  State<WalletTripPage> createState() => _WalletTripPageState();
}

class _WalletTripPageState extends State<WalletTripPage> {
  final _service = TripWalletService();

  /// The trip as last seen on this device shows at once; the server's copy
  /// replaces it when it comes.
  late WalletTrip? _trip = _service.cachedTrip(widget.tripId);
  String? _error;
  bool _busy = false;

  /// Whether [_trip] is the server's copy. Changes wait for it: the kept copy
  /// may be older, and settle-up amounts worked out from it may be wrong.
  bool _fresh = false;

  /// The page's outer scroll. Once the dark top, with its Add expense
  /// button, has scrolled away, a floating Add expense button takes over.
  final _outer = ScrollController();
  bool _showFab = false;

  @override
  void initState() {
    super.initState();
    _load();
    TripWalletService.revision.addListener(_load);
    _outer.addListener(_onOuterScroll);
  }

  @override
  void dispose() {
    TripWalletService.revision.removeListener(_load);
    _outer.dispose();
    super.dispose();
  }

  void _onOuterScroll() {
    final show = _outer.offset > 140;
    if (show != _showFab) setState(() => _showFab = show);
  }

  Future<void> _load() async {
    try {
      final t = await _service.getTrip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = t;
        _error = null;
        _fresh = true;
      });
    } catch (e) {
      if (!mounted) return;
      if (statusCodeOf(e) == 404) {
        // Gone for this traveller: drop the kept copy and say so.
        _service.forgetTrip(widget.tripId);
        setState(() {
          _trip = null;
          _error = 'This trip was deleted, or you are no longer in it.';
        });
        return;
      }
      setState(() => _error = userMessageFor(e, action: 'load the trip'));
    }
  }

  /// True once the server's copy is in; otherwise says why a change has to
  /// wait, and tries loading again if the last try failed.
  bool _ready() {
    if (_fresh) return true;
    _snack(_error == null
        ? 'Still loading the latest copy of this trip. Try again in a moment.'
        : 'Can’t reach NexAround to check for changes. Connect, then try again.');
    if (_error != null) _load();
    return false;
  }

  /// Runs a change that answers with the trip, showing the server's reason
  /// when it is refused.
  Future<WalletTrip?> _run(Future<WalletTrip> Function() call, String action) async {
    if (!_ready()) return null;
    setState(() => _busy = true);
    try {
      final t = await call();
      if (!mounted) return t;
      setState(() {
        _trip = t;
        _busy = false;
      });
      return t;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _busy = false);
      _snack(userMessageFor(e, action: action));
      return null;
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addExpense([WalletExpense? editing]) async {
    final trip = _trip;
    if (trip == null || !_ready()) return;
    final updated = await Navigator.push<WalletTrip>(
      context,
      MaterialPageRoute(builder: (_) => AddExpensePage(trip: trip, editing: editing)),
    );
    if (updated != null && mounted) setState(() => _trip = updated);
  }

  void _invite() {
    final trip = _trip;
    if (trip == null) return;
    showWalletInviteSheet(
      context,
      trip,
      onReset: trip.isOwner ? () => _run(() => _service.resetInvite(trip.id), 'make a new link') : null,
    );
  }

  Future<void> _rename() async {
    if (!_ready()) return;
    final trip = _trip!;
    final ctrl = TextEditingController(text: trip.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename trip'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == trip.name) return;
    await _run(() => _service.updateTrip(trip.id, name: name), 'rename the trip');
  }

  Future<bool> _confirm(String title, String text, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes, style: const TextStyle(color: WalletColors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _leaveTrip() async {
    if (!_ready()) return;
    final trip = _trip!;
    if (!await _confirm('Leave ${trip.name}?', 'You can only leave once you are all settled up.', 'Leave')) return;
    try {
      await _service.leave(trip.id);
      TripWalletService.revision.value++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(userMessageFor(e, action: 'leave the trip'));
    }
  }

  Future<void> _deleteTrip() async {
    if (!_ready()) return;
    final trip = _trip!;
    if (!await _confirm(
      'Delete ${trip.name}?',
      'Every expense and payment in it is deleted for everyone. This cannot be undone.',
      'Delete',
    )) {
      return;
    }
    try {
      await _service.deleteTrip(trip.id);
      TripWalletService.revision.value++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(userMessageFor(e, action: 'delete the trip'));
    }
  }

  void _people() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PeopleSheet(
        trip: _trip!,
        onRemove: (m) => _run(() => _service.removeMember(_trip!.id, m.id), 'remove ${m.displayName}'),
        onInvite: _invite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (trip == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: WalletColors.navy,
          elevation: 0,
          leading: const AppBackButton(),
        ),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator(color: AppColors.brandGreen)
              : WalletEmpty(
                  icon: Icons.luggage_rounded,
                  title: 'Trip not loaded',
                  text: _error!,
                  action: TextButton(onPressed: _load, child: const Text('Try again')),
                ),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        // Dark like the summary under it, so the two read as one top.
        appBar: AppBar(
          backgroundColor: _tripNavy,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          leading: const AppBackButton(onImage: true),
          centerTitle: true,
          // Colour set here: the app's AppBar theme would paint it dark.
          title: Text(
            trip.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          actions: [
            // Invite moved into the summary's quick buttons.
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'people':
                    _people();
                  case 'rename':
                    _rename();
                  case 'leave':
                    _leaveTrip();
                  case 'delete':
                    _deleteTrip();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'people', child: Text('People')),
                if (trip.isOwner) const PopupMenuItem(value: 'rename', child: Text('Rename trip')),
                if (!trip.isOwner) const PopupMenuItem(value: 'leave', child: Text('Leave trip')),
                if (trip.isOwner)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete trip', style: TextStyle(color: WalletColors.red)),
                  ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(_error != null ? 30 : 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The refresh failed: this is the trip as kept on the device.
                if (_error != null)
                  const SizedBox(
                    height: 28,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 15, color: Color(0xFFCBD5E1)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Showing saved data. Pull down to refresh.',
                              style: TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                _busy
                    ? const LinearProgressIndicator(minHeight: 2, color: AppColors.brandGreen)
                    : const SizedBox(height: 2),
              ],
            ),
          ),
        ),
        // Only once the summary's own Add expense button is out of sight.
        floatingActionButton: _showFab
            ? FloatingActionButton.extended(
                onPressed: () => _addExpense(),
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w700)),
              )
            : null,
        body: NestedScrollView(
          controller: _outer,
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(
              child: _Summary(
                trip: trip,
                onPeople: _people,
                onInvite: _invite,
                onAddExpense: () => _addExpense(),
              ),
            ),
            SliverPersistentHeader(pinned: true, delegate: _TabsHeader(trip.pendingCount)),
          ],
          body: TabBarView(
            children: [
              _refreshable(_ExpensesTab(trip: trip, onOpen: _openExpense, onInvite: _invite)),
              _refreshable(_BalancesTab(trip: trip)),
              _refreshable(_SettleTab(
                trip: trip,
                onMarkPaid: _markPaid,
                onApprove: (p) => _run(() => _service.approvePaid(trip.id, p.id!), 'approve the payment'),
                onRemove: _removePayment,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _refreshable(Widget child) =>
      RefreshIndicator(color: AppColors.brandGreen, onRefresh: _load, child: child);

  Future<void> _markPaid(WalletPayment p) async {
    if (!_ready()) return;
    final trip = _trip!;
    final money = trip.money;
    final ctrl = TextEditingController(text: money.plain(p.amount));
    final amount = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mark as paid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${trip.nameOf(p.fromMemberId)} paid ${trip.nameOf(p.toMemberId)}',
                style: const TextStyle(color: WalletColors.slate)),
            if (!trip.isOwner) ...[
              const SizedBox(height: 6),
              Text('${trip.owner?.displayName ?? 'The trip owner'} approves it before it counts.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFB45309))),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(prefixText: '${money.symbol} ', labelText: 'Amount'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Mark paid')),
        ],
      ),
    );
    if (amount == null || amount.isEmpty) return;
    if (money.parse(amount) == null) {
      _snack('Enter an amount like ${money.plain(p.amount)}');
      return;
    }
    final t = await _run(() => _service.markPaid(trip.id, p, amount.replaceAll(',', '')), 'mark it paid');
    if (t != null && !t.isOwner && mounted) {
      _snack('Sent to ${t.owner?.displayName ?? 'the trip owner'} for approval');
    }
  }

  /// Reject or undo (owner), or withdraw (who marked it, while waiting).
  Future<void> _removePayment(WalletPayment p) async {
    if (!_ready()) return;
    final trip = _trip!;
    final what = '${trip.nameOf(p.fromMemberId)} paid ${trip.nameOf(p.toMemberId)} ${trip.money.format(p.amount)}';
    final (title, text, yes) = !p.isPending
        ? ('Undo this payment?', '$what. It stops counting and the balances go back.', 'Undo')
        : p.canApprove
            ? ('Reject this payment?', '$what. It is removed and the person who marked it is told.', 'Reject')
            : ('Withdraw this payment?', '$what. It is removed before the owner approves it.', 'Withdraw');
    if (!await _confirm(title, text, yes)) return;
    await _run(() => _service.undoPaid(trip.id, p.id!), 'remove the payment');
  }

  void _openExpense(WalletExpense e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => _ExpenseSheet(
        trip: _trip!,
        expense: e,
        onEdit: () {
          Navigator.pop(sheet);
          _addExpense(e);
        },
        onDelete: () async {
          Navigator.pop(sheet);
          if (!_ready()) return;
          if (await _confirm('Delete ${e.title}?', 'Balances are worked out again without it.', 'Delete')) {
            await _run(() => _service.deleteExpense(_trip!.id, e.id), 'delete the expense');
          }
        },
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  /// Payments waiting for the owner, shown as a badge on Settle up.
  final int pending;
  _TabsHeader(this.pending);

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // The white sheet's rounded top over the dark summary; the corners show
    // the summary's navy, also once pinned under the navy bar.
    // Fills the header's whole 56 px: the gap plus the tab bar alone come to
    // a little less, and a pinned header whose child is shorter than its
    // extent is invalid, which left the whole page blank.
    return SizedBox.expand(
      child: ColoredBox(
        color: _tripNavy,
        child: Container(
          padding: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: TabBar(
            labelColor: WalletColors.navy,
            unselectedLabelColor: WalletColors.slate,
            indicatorColor: AppColors.brandGreen,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            tabs: [
              const Tab(text: 'Expenses'),
              const Tab(text: 'Balances'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Settle up'),
                    if (pending > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(9)),
                        child: Text('$pending',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader oldDelegate) => oldDelegate.pending != pending;
}

/// The trip page's dark top (the bar above and the tabs' corners use it too).
const _tripNavy = Color(0xFF0F172A);

/// The trip page's top, kept compact: your balance with the trip total and
/// people beside a spending ring, one line of category shares, then Add
/// expense and three quick buttons. It scrolls away; the tabs stay.
class _Summary extends StatelessWidget {
  final WalletTrip trip;
  final VoidCallback onPeople;
  final VoidCallback onInvite;
  final VoidCallback onAddExpense;
  const _Summary({
    required this.trip,
    required this.onPeople,
    required this.onInvite,
    required this.onAddExpense,
  });

  static const _muted = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final net = trip.myNet;
    final (label, labelColor) = net > 0
        ? ('YOU GET BACK', const Color(0xFF86EFAC))
        : net < 0
            ? ('YOU OWE', const Color(0xFFFCA5A5))
            : ('YOUR BALANCE', _muted);
    final people = trip.activeMembers.length;
    final shares = _categoryShares(trip);
    final shareTotal = shares.fold<int>(0, (a, s) => a + s.$2);
    return Container(
      color: _tripNavy,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(color: labelColor, fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        net == 0 ? 'Settled' : money.format(net.abs()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Opens the people list, as the old people row did.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onPeople,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Trip total ${money.format(trip.totalSpent)} · $people ${people == 1 ? 'person' : 'people'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SpendRing(shares: shares, total: money.format(trip.totalSpent)),
            ],
          ),
          if (shareTotal > 0) ...[
            const SizedBox(height: 10),
            // One line, shrunk to fit if a trip has many categories.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  for (var i = 0; i < shares.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: walletCategoryColor(shares[i].$1), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${walletCategoryLabel(shares[i].$1)} ${(shares[i].$2 * 100 / shareTotal).round()}%',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _QuickButton(icon: Icons.add_rounded, label: 'Add expense', primary: true, onTap: onAddExpense),
              ),
              const SizedBox(width: 8),
              _QuickButton(icon: Icons.person_add_alt_1_rounded, label: 'Invite', onTap: onInvite),
              const SizedBox(width: 8),
              _QuickButton(icon: Icons.group_rounded, label: 'People', onTap: onPeople),
              const SizedBox(width: 8),
              _QuickButton(
                icon: Icons.check_circle_rounded,
                label: 'Settle up',
                onTap: () => DefaultTabController.of(context).animateTo(2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Each category's part of the trip's spending, biggest first.
List<(String, int)> _categoryShares(WalletTrip trip) {
  final sums = <String, int>{};
  for (final e in trip.expenses) {
    sums[e.category] = (sums[e.category] ?? 0) + e.amount;
  }
  final list = [
    for (final entry in sums.entries)
      if (entry.value > 0) (entry.key, entry.value),
  ];
  list.sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}

/// A quick button under the summary: the primary one is teal with its label,
/// the others are round-cornered glass squares with the label as tooltip.
class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _QuickButton({required this.icon, required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: primary ? const Color(0xFF14B8A6) : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          width: primary ? null : 52,
          child: primary
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 19, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              : Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
    return primary ? child : Tooltip(message: label, child: Semantics(label: label, button: true, child: child));
  }
}

/// The spending ring: one arc per category in its colour, the trip total in
/// the middle. A plain faint ring before any expense is added.
class _SpendRing extends StatelessWidget {
  final List<(String, int)> shares;
  final String total;
  const _SpendRing({required this.shares, required this.total});

  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        painter: _RingPainter(shares),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('TOTAL',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 8.5, letterSpacing: 1, fontWeight: FontWeight.w800)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(total,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<(String, int)> shares;
  const _RingPainter(this.shares);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.12;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = Colors.white.withValues(alpha: 0.1));
    final sum = shares.fold<int>(0, (a, s) => a + s.$2);
    if (sum <= 0) return;
    // A small gap between arcs, none when one category has it all.
    final gap = shares.length > 1 ? 0.05 : 0.0;
    var start = -math.pi / 2;
    for (final (category, amount) in shares) {
      final sweep = 2 * math.pi * amount / sum;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.01),
        false,
        paint..color = walletCategoryColor(category),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.shares != shares;
}

class _ExpensesTab extends StatelessWidget {
  final WalletTrip trip;
  final void Function(WalletExpense) onOpen;
  final VoidCallback onInvite;
  const _ExpensesTab({required this.trip, required this.onOpen, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    if (trip.expenses.isEmpty) {
      return ListView(
        children: [
          WalletEmpty(
            icon: Icons.receipt_long_rounded,
            title: 'No expenses yet',
            text: trip.activeMembers.length < 2
                ? 'Invite your friends first, then add the hotel, taxis, meals and anything else you share.'
                : 'Add the hotel, taxis, meals and anything else you share.',
            action: trip.activeMembers.length < 2
                ? OutlinedButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Invite friends'),
                  )
                : null,
          ),
        ],
      );
    }
    final money = trip.money;
    final day = DateFormat('EEE d MMM');
    // Grouped by day, newest first (the server sends them newest first).
    final items = <Widget>[];
    String? lastDay;
    for (final e in trip.expenses) {
      final d = day.format(e.spentOn);
      if (d != lastDay) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(d.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: WalletColors.slate)),
        ));
        lastDay = d;
      }
      final myShare = e.shares.where((s) => s.memberId == trip.myMemberId).fold<int>(0, (a, s) => a + s.amount);
      final paidByMe = e.paidByMemberId == trip.myMemberId;
      final String mine;
      if (paidByMe) {
        mine = 'you lent ${money.format(e.amount - myShare)}';
      } else if (myShare > 0) {
        mine = 'your share ${money.format(myShare)}';
      } else {
        mine = 'not in it';
      }
      items.add(Material(
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onOpen(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                WalletCategoryIcon(e.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: WalletColors.navy)),
                          ),
                          if (e.receiptUrl != null) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.photo_outlined, size: 14, color: WalletColors.slate),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${trip.nameOf(e.paidByMemberId)} paid · ${e.shares.length} '
                          '${e.shares.length == 1 ? 'person' : 'people'}',
                          style: const TextStyle(fontSize: 12.5, color: WalletColors.slate)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money.format(e.amount),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: WalletColors.navy)),
                    const SizedBox(height: 2),
                    Text(mine,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: paidByMe ? WalletColors.green : (myShare > 0 ? WalletColors.red : WalletColors.slate),
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: items);
  }
}

class _BalancesTab extends StatelessWidget {
  final WalletTrip trip;
  const _BalancesTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final rows = trip.members.where((m) {
      final b = trip.balanceOf(m.id);
      return !m.left || (b != null && (b.paid != 0 || b.share != 0));
    }).toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: rows.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: 8) : const Divider(height: 1, color: WalletColors.line),
      itemBuilder: (_, i) {
        if (i == 0) {
          return const Text('Paid is what each person spent for the group. Share is their part of the expenses. '
              'Green gets money back, red owes.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: WalletColors.slate));
        }
        final m = rows[i - 1];
        final b = trip.balanceOf(m.id);
        final net = b?.net ?? 0;
        final color = net > 0 ? WalletColors.green : (net < 0 ? WalletColors.red : WalletColors.slate);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              WalletAvatar(m, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.isMe ? '${m.displayName} (you)' : m.displayName + (m.left ? ' (left)' : ''),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: WalletColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text('Paid ${money.format(b?.paid ?? 0)} · Share ${money.format(b?.share ?? 0)}',
                        style: const TextStyle(fontSize: 12.5, color: WalletColors.slate)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(net == 0 ? 'Settled' : money.format(net, signed: true),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                  if (net != 0)
                    Text(net > 0 ? 'gets back' : 'owes',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettleTab extends StatelessWidget {
  final WalletTrip trip;
  final Future<void> Function(WalletPayment) onMarkPaid;
  final Future<WalletTrip?> Function(WalletPayment) onApprove;
  final Future<void> Function(WalletPayment) onRemove;
  const _SettleTab({
    required this.trip,
    required this.onMarkPaid,
    required this.onApprove,
    required this.onRemove,
  });

  static const _amber = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final when = DateFormat('d MMM, HH:mm');
    final ownerName = trip.isOwner ? 'you' : (trip.owner?.displayName.split(' ').first ?? 'the owner');
    final pending = trip.pendingPayments;
    final confirmed = trip.confirmedPayments;
    final children = <Widget>[];

    // Payments waiting for the owner: on top, so the owner sees their to-do.
    if (pending.isNotEmpty) {
      children.add(_heading(trip.isOwner ? 'APPROVE THESE PAYMENTS' : 'WAITING FOR APPROVAL'));
      for (final p in pending) {
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFCD34D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 18, color: _amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${trip.nameOf(p.fromMemberId)} paid ${trip.nameOf(p.toMemberId)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WalletColors.navy)),
                  ),
                  Text(money.format(p.amount),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: WalletColors.navy)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p.canApprove
                    ? 'Check you know it was paid, then approve. It counts only after that.'
                    : 'Waiting for $ownerName to approve. It counts in balances after that.'
                        '${p.createdAt == null ? '' : ' · ${when.format(p.createdAt!)}'}',
                style: const TextStyle(fontSize: 12.5, height: 1.35, color: _amber),
              ),
              if (p.canApprove || p.canDelete) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (p.canDelete)
                      TextButton(
                        onPressed: () => onRemove(p),
                        child: Text(p.canApprove ? 'Reject' : 'Withdraw',
                            style: const TextStyle(color: WalletColors.red, fontWeight: FontWeight.w700)),
                      ),
                    if (p.canApprove) ...[
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => onApprove(p),
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.brandGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ));
      }
      children.add(const SizedBox(height: 8));
    }

    if (trip.settleUp.isEmpty) {
      children.add(WalletEmpty(
        icon: Icons.verified_rounded,
        title: trip.expenses.isEmpty
            ? 'Nothing to settle yet'
            : pending.isEmpty
                ? 'All settled up'
                : 'Almost there',
        text: trip.expenses.isEmpty
            ? 'Once expenses are added, the fewest payments to square everyone up appear here.'
            : pending.isEmpty
                ? 'Nobody owes anybody. Nice trip!'
                : 'Everything is paid. Waiting for the approvals above.',
      ));
    } else {
      children.add(_heading('PAYMENTS TO MAKE'));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
          '${trip.settleUp.length} ${trip.settleUp.length == 1 ? 'payment settles' : 'payments settle'} everyone up. '
          'Pay each other any way you like, then tap Mark paid.'
          '${trip.isOwner ? '' : ' $ownerName approves each one.'}',
          style: const TextStyle(fontSize: 12.5, height: 1.4, color: WalletColors.slate),
        ),
      ));
      for (final p in trip.settleUp) {
        final mine = p.fromMemberId == trip.myMemberId || p.toMemberId == trip.myMemberId;
        final waiting = trip.pendingBetween(p.fromMemberId, p.toMemberId) != null;
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mine ? AppColors.brandGreenLight : WalletColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: mine ? AppColors.brandGreen.withValues(alpha: 0.3) : WalletColors.line),
          ),
          child: Row(
            children: [
              WalletAvatar(trip.member(p.fromMemberId), size: 34),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: WalletColors.slate),
              ),
              WalletAvatar(trip.member(p.toMemberId), size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${trip.nameOf(p.fromMemberId)} pays ${trip.nameOf(p.toMemberId)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WalletColors.navy)),
                    const SizedBox(height: 2),
                    Text(money.format(p.amount),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: WalletColors.navy)),
                  ],
                ),
              ),
              if (waiting)
                const Text('Awaiting\napproval',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _amber))
              else
                TextButton(
                  onPressed: () => onMarkPaid(p),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Mark paid', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
            ],
          ),
        ));
      }
    }

    if (confirmed.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      children.add(_heading('APPROVED PAYMENTS'));
      for (final s in confirmed) {
        children.add(ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.check_circle_rounded, color: WalletColors.green),
          title: Text('${trip.nameOf(s.fromMemberId)} paid ${trip.nameOf(s.toMemberId)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${money.format(s.amount)}${s.createdAt == null ? '' : ' · ${when.format(s.createdAt!)}'}',
          ),
          trailing: s.canDelete ? TextButton(onPressed: () => onRemove(s), child: const Text('Undo')) : null,
        ));
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: children);
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: WalletColors.slate)),
      );
}

class _ExpenseSheet extends StatelessWidget {
  final WalletTrip trip;
  final WalletExpense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ExpenseSheet({required this.trip, required this.expense, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final money = trip.money;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WalletCategoryIcon(e.category, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: WalletColors.navy)),
                        Text('${walletCategoryLabel(e.category)} · ${DateFormat('EEE d MMM yyyy').format(e.spentOn)}',
                            style: const TextStyle(fontSize: 13, color: WalletColors.slate)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(money.format(e.amount),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: WalletColors.navy)),
              Text('Paid by ${trip.nameOf(e.paidByMemberId)} · '
                  '${e.splitMode == 'exact' ? 'split by amounts' : 'split equally'}',
                  style: const TextStyle(fontSize: 13.5, color: WalletColors.slate)),
              const SizedBox(height: 14),
              for (final s in e.shares)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      WalletAvatar(trip.member(s.memberId), size: 28),
                      const SizedBox(width: 10),
                      Expanded(child: Text(trip.nameOf(s.memberId), style: const TextStyle(fontSize: 14))),
                      Text(money.format(s.amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (e.receiptUrl != null) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrls: [e.receiptUrl!])),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: e.receiptUrl!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(height: 160, color: WalletColors.card),
                      errorWidget: (_, __, ___) => Container(
                        height: 160,
                        color: WalletColors.card,
                        child: const Icon(Icons.broken_image_outlined, color: WalletColors.slate),
                      ),
                    ),
                  ),
                ),
              ],
              if (e.canEdit) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WalletColors.red,
                          side: const BorderSide(color: WalletColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Edit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PeopleSheet extends StatefulWidget {
  final WalletTrip trip;
  final Future<WalletTrip?> Function(WalletMember m) onRemove;
  final VoidCallback onInvite;
  const _PeopleSheet({required this.trip, required this.onRemove, required this.onInvite});

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  late WalletTrip _trip = widget.trip;

  Future<void> _remove(WalletMember m) async {
    final t = await widget.onRemove(m);
    if (t != null && mounted) setState(() => _trip = t);
  }

  @override
  Widget build(BuildContext context) {
    final active = _trip.activeMembers;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('People', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WalletColors.navy)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in active)
                    ListTile(
                      leading: WalletAvatar(m, size: 38),
                      title: Text(m.isMe ? '${m.displayName} (you)' : m.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(m.isOwner ? 'Owner' : (m.hasApp ? 'Member' : 'Added by name')),
                      trailing: _trip.isOwner && !m.isMe
                          ? IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.person_remove_outlined, color: WalletColors.slate),
                              onPressed: () => _remove(m),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onInvite();
                },
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Invite link'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
