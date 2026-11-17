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
              leading: const AppBackButton(onImage: true),
              // Colours set here: the app's AppBar theme would paint the
              // title dark, which is lost on the photo.
              title: const Text('Trip Wallet', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
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
