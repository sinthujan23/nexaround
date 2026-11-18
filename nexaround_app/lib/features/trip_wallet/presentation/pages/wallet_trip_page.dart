import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
  WalletTrip? _trip;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    TripWalletService.revision.addListener(_load);
  }

  @override
  void dispose() {
    TripWalletService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await _service.getTrip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = t;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = statusCodeOf(e) == 404
          ? 'This trip was deleted, or you are no longer in it.'
          : userMessageFor(e, action: 'load the trip'));
    }
  }

  /// Runs a change that answers with the trip, showing the server's reason
  /// when it is refused.
  Future<WalletTrip?> _run(Future<WalletTrip> Function() call, String action) async {
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
    if (trip == null) return;
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
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: WalletColors.navy,
          elevation: 0,
          leading: const AppBackButton(),
          title: Text(trip.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(tooltip: 'Invite', icon: const Icon(Icons.person_add_alt_1_rounded), onPressed: _invite),
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
            preferredSize: const Size.fromHeight(2),
            child: _busy
                ? const LinearProgressIndicator(minHeight: 2, color: AppColors.brandGreen)
                : const SizedBox(height: 2),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addExpense(),
          backgroundColor: AppColors.brandGreen,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(child: _Summary(trip: trip, onPeople: _people)),
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
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
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
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader oldDelegate) => oldDelegate.pending != pending;
}

class _Summary extends StatelessWidget {
  final WalletTrip trip;
  final VoidCallback onPeople;
  const _Summary({required this.trip, required this.onPeople});

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final net = trip.myNet;
    final (label, color) = net > 0
        ? ('You get back', const Color(0xFF4ADE80))
        : net < 0
            ? ('You owe', const Color(0xFFFCA5A5))
            : ('You are', Colors.white70);
    final active = trip.activeMembers;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [WalletColors.navy, Color(0xFF134E4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TRIP TOTAL',
                        style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(money.format(trip.totalSpent),
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(label.toUpperCase(),
                      style: const TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(net == 0 ? 'Settled' : money.format(net.abs()),
                      style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          if (trip.expenses.isNotEmpty) _EveryoneBalances(trip: trip),
          const SizedBox(height: 14),
          InkWell(
            onTap: onPeople,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                SizedBox(
                  height: 30,
                  width: 30.0 + 20.0 * ((active.length.clamp(1, 5)) - 1),
                  child: Stack(
                    children: [
                      for (var i = 0; i < active.length && i < 5; i++)
                        Positioned(
                          left: i * 20.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: WalletColors.navy, width: 2),
                            ),
                            child: WalletAvatar(active[i], size: 26),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text('${active.length} ${active.length == 1 ? 'person' : 'people'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const Icon(Icons.chevron_right_rounded, color: Colors.white60, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Each person's balance inside the summary card: a bar out from the middle
/// (left red = owes, right green = gets back, scaled to the biggest balance)
/// and the amount. More than six people: the rest are on the Balances tab.
class _EveryoneBalances extends StatelessWidget {
  final WalletTrip trip;
  const _EveryoneBalances({required this.trip});

  static const _gets = Color(0xFF4ADE80);
  static const _owes = Color(0xFFFCA5A5);
  static const _maxRows = 6;

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final rows = [
      for (final m in trip.members)
        if (!m.left || (trip.balanceOf(m.id)?.net ?? 0) != 0) (m, trip.balanceOf(m.id)?.net ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (rows.isEmpty) return const SizedBox.shrink();
    final biggest = rows.fold<int>(0, (a, r) => r.$2.abs() > a ? r.$2.abs() : a);
    final shown = rows.take(_maxRows).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (final (m, net) in shown) _personLine(m, net, biggest, money),
            if (rows.length > shown.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => DefaultTabController.of(context).animateTo(1),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('+${rows.length - shown.length} more in Balances',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _personLine(WalletMember m, int net, int biggest, WalletMoney money) {
    final name = m.isMe ? 'You' : m.displayName + (m.left ? ' (left)' : '');
    final (text, color) = net > 0
        ? ('${m.isMe ? 'get back' : 'gets back'} ${money.format(net)}', _gets)
        : net < 0
            ? ('${m.isMe ? 'owe' : 'owes'} ${money.format(-net)}', _owes)
            : ('settled', Colors.white54);
    final part = biggest == 0 ? 0.0 : net.abs() / biggest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          WalletAvatar(m, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: 6,
                  child: LayoutBuilder(builder: (_, box) {
                    final half = box.maxWidth / 2;
                    final w = half * part;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if (w > 0)
                          Positioned(
                            left: net > 0 ? half : half - w,
                            width: w,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                            ),
                          ),
                        Positioned(
                          left: half - 0.5,
                          width: 1,
                          top: 0,
                          bottom: 0,
                          child: Container(color: Colors.white38),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
