import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/trip_wallet/data/trip_wallet_service.dart';
import 'package:nexaround_app/features/trip_wallet/domain/trip_wallet_models.dart';
import 'package:nexaround_app/features/trip_wallet/presentation/widgets/trip_wallet_widgets.dart';
import 'package:nexaround_app/core/widgets/app_back_button.dart';

/// Add or edit one expense: what, how much, who paid, who it was for, and a
/// receipt photo. Pops with the trip as the server answers it.
class AddExpensePage extends StatefulWidget {
  final WalletTrip trip;
  final WalletExpense? editing;
  const AddExpensePage({super.key, required this.trip, this.editing});

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _service = TripWalletService();
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final Map<String, TextEditingController> _exact = {};

  late final WalletMoney _money = widget.trip.money;
  late final List<WalletMember> _people;
  String _category = 'other';
  DateTime _date = DateTime.now();
  late String _paidBy;
  bool _exactMode = false;
  final Set<String> _inSplit = {};

  File? _receiptFile;
  String? _receiptUrl;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    final e = widget.editing;
    final onExpense = <String>{
      if (e != null) e.paidByMemberId,
      if (e != null) ...e.shares.map((s) => s.memberId),
    };
    // Active people, plus anyone who has left but is already on this expense.
    _people = trip.members.where((m) => !m.left || onExpense.contains(m.id)).toList();
    for (final m in _people) {
      _exact[m.id] = TextEditingController();
    }
    if (e == null) {
      _paidBy = trip.myMemberId;
      _inSplit.addAll(trip.activeMembers.map((m) => m.id));
    } else {
      _amount.text = _money.plain(e.amount);
      _title.text = e.title;
      _category = e.category;
      _date = e.spentOn;
      _paidBy = e.paidByMemberId;
      _exactMode = e.splitMode == 'exact';
      _inSplit.addAll(e.shares.map((s) => s.memberId));
      for (final s in e.shares) {
        _exact[s.memberId]?.text = _money.plain(s.amount);
      }
      _receiptUrl = e.receiptUrl;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    for (final c in _exact.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _total => _money.parse(_amount.text);

  /// Exact mode: what is still to give out (negative: too much).
  int get _left {
    final total = _total ?? 0;
    var sum = 0;
    for (final m in _people) {
      sum += _money.parse(_exact[m.id]!.text) ?? 0;
    }
    return total - sum;
  }

  /// Equal mode: each person's part, the leftover units to the first people,
  /// as the server splits it.
  Map<String, int> get _equalParts {
    final total = _total ?? 0;
    final ids = _people.where((m) => _inSplit.contains(m.id)).map((m) => m.id).toList();
    if (ids.isEmpty) return {};
    final base = total ~/ ids.length;
    final extra = total % ids.length;
    return {for (var i = 0; i < ids.length; i++) ids[i]: base + (i < extra ? 1 : 0)};
  }

  String? get _problem {
    if (_title.text.trim().isEmpty) return 'Add what it was for';
    final total = _total;
    if (total == null || total <= 0) {
      return _money.decimals == 0
          ? 'Enter the amount in whole ${_money.currency}'
          : 'Enter the amount, e.g. 1200 or 12.50';
    }
    if (_exactMode) {
      for (final m in _people) {
        final t = _exact[m.id]!.text.trim();
        if (t.isNotEmpty && _money.parse(t) == null) return 'Check ${m.displayName}\'s amount';
      }
      final left = _left;
      if (left != 0) {
        return left > 0
            ? '${_money.format(left)} still to assign'
            : '${_money.format(-left)} too much assigned';
      }
    } else if (_inSplit.isEmpty) {
      return 'Pick at least one person';
    }
    return null;
  }

  void _hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _pickDate() async {
    _hideKeyboard();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickReceipt() async {
    _hideKeyboard();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    } catch (e) {
      _snack(userMessageFor(e, action: 'open the photo'));
      return;
    }
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    setState(() {
      _receiptFile = file;
      _uploading = true;
    });
    try {
      final url = await _service.uploadReceipt(widget.trip.id, file.path);
      if (!mounted) return;
      setState(() {
        _receiptUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _receiptFile = null;
        _uploading = false;
      });
      _snack(userMessageFor(e, action: 'upload the receipt'));
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    _hideKeyboard();
    final problem = _problem;
    if (problem != null) {
      _snack(problem);
      return;
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'category': _category,
      'amount': _amount.text.replaceAll(',', '').trim(),
      'spent_on': DateFormat('yyyy-MM-dd').format(_date),
      'paid_by_member_id': _paidBy,
      'split_mode': _exactMode ? 'exact' : 'equal',
      if (!_exactMode) 'member_ids': _people.where((m) => _inSplit.contains(m.id)).map((m) => m.id).toList(),
      if (_exactMode)
        'shares': [
          for (final m in _people)
            if ((_money.parse(_exact[m.id]!.text) ?? 0) > 0)
              {'member_id': m.id, 'amount': _exact[m.id]!.text.replaceAll(',', '').trim()},
        ],
      'receipt_url': _receiptUrl,
    };
    try {
      final trip = await _service.saveExpense(widget.trip.id, body, expenseId: widget.editing?.id);
      if (mounted) Navigator.pop(context, trip);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(userMessageFor(e, action: 'save the expense'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: WalletColors.navy,
        elevation: 0,
        leading: const AppBackButton(),
        title: Text(widget.editing == null ? 'Add expense' : 'Edit expense',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem != null && _amount.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(problem, style: const TextStyle(fontSize: 13, color: WalletColors.red)),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving || _uploading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: problem == null ? AppColors.brandGreen : WalletColors.slate,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_uploading ? 'Uploading receipt…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        // Scrolling the form closes the keyboard. A tap on empty space does too
        // (the app-wide handler in app.dart); the pickers, the split switch
        // and Save close it themselves. No per-field onTapOutside: moving from
        // one field to the next would make the keyboard flicker.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Amount
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: WalletColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: WalletColors.line),
            ),
            child: Row(
              children: [
                Text(_money.symbol,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: WalletColors.slate)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: widget.editing == null,
                    keyboardType: TextInputType.numberWithOptions(decimal: _money.decimals > 0),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: WalletColors.navy),
                    decoration: const InputDecoration(border: InputBorder.none, hintText: '0', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('What was it for?', hint: 'e.g. Hotel, Taxi to airport, Dinner'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          _label('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in walletCategories)
                ChoiceChip(
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                  avatar: Icon(walletCategoryIcon(c), size: 16,
                      color: _category == c ? Colors.white : walletCategoryColor(c)),
                  label: Text(walletCategoryLabel(c)),
                  showCheckmark: false,
                  selectedColor: AppColors.brandGreen,
                  labelStyle: TextStyle(
                    color: _category == c ? Colors.white : WalletColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: WalletColors.card,
                  side: const BorderSide(color: WalletColors.line),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: _decoration('Date'),
                    child: Text(DateFormat('EEE d MMM').format(_date)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InputDecorator(
                  decoration: _decoration('Paid by'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _paidBy,
                      onTap: _hideKeyboard,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        for (final m in _people)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(m.isMe ? 'You' : m.displayName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _paidBy = v ?? _paidBy),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _label('Split between')),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Equally')),
                  ButtonSegment(value: true, label: Text('By amount')),
                ],
                selected: {_exactMode},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.brandGreen,
                  selectedForegroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (s) {
                  _hideKeyboard();
                  setState(() => _exactMode = s.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_exactMode) ..._exactRows() else ..._equalRows(),
          const SizedBox(height: 16),
          _label('Receipt (optional)'),
          _receipt(),
        ],
      ),
    );
  }

  List<Widget> _equalRows() {
    final parts = _equalParts;
    final allIn = _people.every((m) => _inSplit.contains(m.id));
    return [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => setState(() {
            if (allIn) {
              _inSplit.clear();
            } else {
              _inSplit.addAll(_people.map((m) => m.id));
            }
          }),
          child: Text(allIn ? 'Clear all' : 'Select all'),
        ),
      ),
      for (final m in _people)
        CheckboxListTile(
          value: _inSplit.contains(m.id),
          onChanged: (v) => setState(() => v == true ? _inSplit.add(m.id) : _inSplit.remove(m.id)),
          activeColor: AppColors.brandGreen,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: WalletAvatar(m, size: 34),
          title: Text(m.isMe ? 'You' : m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: _inSplit.contains(m.id) && (_total ?? 0) > 0
              ? Text(_money.format(parts[m.id] ?? 0))
              : null,
        ),
    ];
  }

  List<Widget> _exactRows() {
    final left = _left;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          left == 0
              ? 'All assigned'
              : left > 0
                  ? '${_money.format(left)} left to assign'
                  : '${_money.format(-left)} too much',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: left == 0 ? WalletColors.green : WalletColors.red,
          ),
        ),
      ),
      for (final m in _people)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              WalletAvatar(m, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(m.isMe ? 'You' : m.displayName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _exact[m.id],
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.numberWithOptions(decimal: _money.decimals > 0),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: _decoration('', hint: '0').copyWith(
                    prefixText: '${_money.symbol} ',
                    isDense: true,
                    labelText: null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _receipt() {
    final Widget? preview = _receiptFile != null
        ? Image.file(_receiptFile!, fit: BoxFit.cover)
        : _receiptUrl != null && _receiptUrl!.startsWith('http')
            ? CachedNetworkImage(imageUrl: _receiptUrl!, fit: BoxFit.cover)
            : null;
    if (preview == null && _receiptUrl == null) {
      return OutlinedButton.icon(
        onPressed: _pickReceipt,
        icon: const Icon(Icons.add_a_photo_outlined, size: 20),
        label: const Text('Add receipt photo'),
        style: OutlinedButton.styleFrom(
          foregroundColor: WalletColors.navy,
          side: const BorderSide(color: WalletColors.line),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              fit: StackFit.expand,
              children: [
                preview ?? const ColoredBox(color: WalletColors.card, child: Icon(Icons.receipt_long_rounded)),
                if (_uploading)
                  const ColoredBox(
                    color: Colors.black38,
                    child: Center(
                      child: SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: _uploading ? null : _pickReceipt, child: const Text('Change')),
        TextButton(
          onPressed: _uploading
              ? null
              : () => setState(() {
                    _receiptFile = null;
                    _receiptUrl = null;
                  }),
          child: const Text('Remove', style: TextStyle(color: WalletColors.red)),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: WalletColors.slate)),
      );

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label.isEmpty ? null : label,
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
}
