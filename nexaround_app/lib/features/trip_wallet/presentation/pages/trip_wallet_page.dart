import 'package:flutter/material.dart';
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

/// Trip Wallet's home, opened from the Curated Hubs tile: the traveller's
/// trips with their own balance in each, "New trip" and "Join with code".
class TripWalletPage extends StatefulWidget {
  const TripWalletPage({super.key});

  @override
  State<TripWalletPage> createState() => _TripWalletPageState();
}

class _TripWalletPageState extends State<TripWalletPage> {
  final _service = TripWalletService();
  List<WalletTripCard>? _trips;
  String? _error;

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
    final code = await showDialog<String>(context: context, builder: (_) => const _CodeDialog());
    if (code == null || code.trim().isEmpty || !mounted) return;
    final tripId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => JoinTripPage(code: code.trim())),
    );
    await _load();
    if (tripId != null && mounted) _open(tripId);
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: AppColors.brandGreen,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: WalletColors.navy,
              foregroundColor: Colors.white,
              title: const Text('Trip Wallet', style: TextStyle(fontWeight: FontWeight.w800)),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/trip_wallet_bg.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.2),
                      errorBuilder: (_, __, ___) => const ColoredBox(color: WalletColors.navy),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            WalletColors.navy.withValues(alpha: 0.9),
                            WalletColors.navy.withValues(alpha: 0.2),
                          ],
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 20,
                      right: 20,
                      bottom: 18,
                      child: Text(
                        'Split group trip costs.\nSee who owes whom, settle up in a few payments.',
                        style: TextStyle(color: Colors.white, fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _newTrip,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('New trip'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _joinWithCode,
                        icon: const Icon(Icons.group_add_rounded, size: 20),
                        label: const Text('Join with code'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WalletColors.navy,
                          side: const BorderSide(color: WalletColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (trips == null && _error == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.brandGreen)),
              )
            else if (trips == null)
              SliverToBoxAdapter(
                child: WalletEmpty(
                  icon: Icons.wifi_off_rounded,
                  title: 'Trips not loaded',
                  text: _error!,
                  action: TextButton(onPressed: _load, child: const Text('Try again')),
                ),
              )
            else if (trips.isEmpty)
              const SliverToBoxAdapter(
                child: WalletEmpty(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'No trips yet',
                  text: 'Make a trip, invite your friends with a link, and everyone adds what they paid. '
                      'Trip Wallet works out who owes whom.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.separated(
                  itemCount: trips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _TripCard(trip: trips[i], onTap: () => _open(trips[i].id)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final WalletTripCard trip;
  final VoidCallback onTap;

  const _TripCard({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final money = trip.money;
    final net = trip.myNet;
    final (label, color) = net > 0
        ? ('You get back ${money.format(net)}', WalletColors.green)
        : net < 0
            ? ('You owe ${money.format(-net)}', WalletColors.red)
            : ('All settled', WalletColors.slate);
    return Material(
      color: WalletColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: WalletColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.brandGreenLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.luggage_rounded, color: AppColors.brandGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: WalletColors.navy)),
                    const SizedBox(height: 3),
                    Text(
                      '${trip.memberCount} ${trip.memberCount == 1 ? 'person' : 'people'} · '
                      '${money.format(trip.totalSpent)} spent',
                      style: const TextStyle(fontSize: 13, color: WalletColors.slate),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                    if (trip.isOwner && trip.pendingCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${trip.pendingCount} ${trip.pendingCount == 1 ? 'payment' : 'payments'} to approve',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: WalletColors.slate),
            ],
          ),
        ),
      ),
    );
  }
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

  Future<void> _pickCurrency() async {
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
              decoration: _fieldDecoration('Trip name', hint: 'e.g. Munnar trip'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 4),
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

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a trip'),
      content: TextField(
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 8,
        style: const TextStyle(fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w800),
        decoration: const InputDecoration(hintText: 'CODE', counterText: ''),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _code.text), child: const Text('Next')),
      ],
    );
  }
}
