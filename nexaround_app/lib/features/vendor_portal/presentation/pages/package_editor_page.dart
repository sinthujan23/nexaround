import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import '../widgets/availability_calendar.dart';
import '../widgets/description_editor.dart';
import '../widgets/photo_editor.dart';

/// Opens the editor; completes with true when the package was saved or
/// deleted, so the list reloads. [initial] is the list's copy, shown while
/// the package is fetched.
Future<bool?> openPackageEditor(BuildContext context, VendorPortalApi api,
        {String? packageId, VendorPackage? initial}) =>
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => PackageEditorPage(api: api, packageId: packageId, initial: initial)),
    );

/// A new package or an existing one, field for field the web portal's editor.
class PackageEditorPage extends StatefulWidget {
  final VendorPortalApi api;
  final String? packageId;

  /// The package as a list showed it (maybe from what the device kept):
  /// shown at once, then replaced by the server's copy.
  final VendorPackage? initial;

  const PackageEditorPage({super.key, required this.api, this.packageId, this.initial});

  @override
  State<PackageEditorPage> createState() => _PackageEditorPageState();
}

class _PackageEditorPageState extends State<PackageEditorPage> {
  final _formKey = GlobalKey<FormState>();
  VendorPackage? _form;
  String _base = '';
  Object? _loadError;
  bool _saving = false;
  bool _photosBusy = false;
  // Whether the form holds the server's copy. A save replaces the whole
  // package, so it waits for it: the list's copy may be an older one.
  bool _fresh = false;
  // Rebuilds the fields when the server's copy replaces the list's.
  int _revision = 0;

  bool get _isNew => widget.packageId == null;
  bool get _dirty => _form != null && jsonEncode(_form!.toJson()) != _base;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _setLoaded(const VendorPackage());
      _fresh = true;
    } else {
      if (widget.initial != null) _setLoaded(widget.initial!);
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() => _loadError = null);
    try {
      final pkg = await widget.api.package(widget.packageId!);
      if (!mounted) return;
      _form == null ? _setLoaded(pkg) : _refresh(pkg);
      setState(() => _fresh = true);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// The server's copy, come while the list's showed: taken as it is, or
  /// with the changes already typed moved onto it.
  void _refresh(VendorPackage fresh) {
    final freshJson = fresh.toJson();
    if (jsonEncode(freshJson) == _base) return;
    final form = _dirty
        ? fresh.withContent(
            rebaseEdits(jsonDecode(_base) as Map<String, dynamic>, _form!.toJson(), freshJson))
        : fresh;
    setState(() {
      _form = form;
      _base = jsonEncode(freshJson);
      _revision++;
    });
  }

  void _setLoaded(VendorPackage pkg) {
    // A new package starts with one blank price; a blank row is not sent, so
    // it does not count as a change.
    if (_isNew && pkg.priceOptions.isEmpty) {
      pkg = pkg.copyWith(priceOptions: [VendorPriceOption()]);
    }
    setState(() {
      _form = pkg;
      _base = jsonEncode(pkg.toJson());
    });
  }

  void _patchOption(int index, VendorPriceOption Function(VendorPriceOption o) change) =>
      _patch((p) => p.copyWith(priceOptions: [
            for (var i = 0; i < p.priceOptions.length; i++)
              i == index ? change(p.priceOptions[i]) : p.priceOptions[i],
          ]));

  void _patch(VendorPackage Function(VendorPackage f) change) =>
      setState(() => _form = change(_form!));

  Future<void> _save() async {
    if (!_fresh) {
      showVendorSnack(
          context,
          _loadError == null
              ? 'Still loading the latest copy of this package. Try again in a moment.'
              : 'Can’t reach NexAround to check for changes. Connect, then save again.',
          error: true);
      if (_loadError != null) _fetch();
      return;
    }
    // The field at fault may be far up the form: say so.
    if (!_formKey.currentState!.validate()) {
      showVendorSnack(context, 'Check the fields marked in red.', error: true);
      return;
    }
    final form = _form!;
    if (_photosBusy) {
      showVendorSnack(context, 'Photos are still uploading. Wait for them to finish, then save.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.api.savePackage(form);
      if (!mounted) return;
      final sent = saved.review.isPending && saved.review.submittedAt != form.review.submittedAt;
      showVendorSnack(
          context,
          sent
              ? 'Sent for review. NexAround will check it before travellers see it.'
              : 'Package saved');
      _base = jsonEncode(form.toJson());
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showVendorSnack(context, userMessageFor(e, action: 'save the package'), error: true);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${_form!.title}"?'),
        content: const Text('Travellers will no longer see it. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete package'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deletePackage(widget.packageId!);
      if (!mounted) return;
      showVendorSnack(context, 'Package deleted');
      _base = jsonEncode(_form!.toJson());
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showVendorSnack(context, userMessageFor(e, action: 'delete the package'), error: true);
    }
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard your changes?'),
        content: const Text('You have changes that are not saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_photosBusy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _base = jsonEncode(_form!.toJson());
          _photosBusy = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: vendorAppBar(
          context,
          _isNew ? 'New package' : 'Edit package',
          actions: [
            if (!_isNew && _form != null)
              VendorCircleButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete package',
                color: AppColors.error,
                onPressed: _delete,
              ),
          ],
        ),
        body: _body(),
        bottomNavigationBar: _form == null
            ? null
            : VendorActionBar(
                child: VendorPrimaryButton(
                  label: _saving ? 'Saving…' : (_isNew ? 'Send for review' : 'Save changes'),
                  onPressed: _saving ? null : _save,
                ),
              ),
      ),
    );
  }

  Widget _body() {
    // Deleted meanwhile: the list's copy is no use.
    if (_loadError != null && (_form == null || statusCodeOf(_loadError) == 404)) {
      return VendorEmptyState(
        icon: Icons.confirmation_number_outlined,
        title: 'Package not found',
        message: userMessageFor(_loadError, action: 'load this package'),
      );
    }
    final f = _form;
    if (f == null) return const Center(child: CircularProgressIndicator());
    final windows = {
      ...bookingWindows,
      if (!bookingWindows.containsKey(f.bookingWindowDays))
        f.bookingWindowDays: '${f.bookingWindowDays} days ahead',
    };
    final currencies = [
      if (!packageCurrencies.any((c) => c['code'] == f.priceCurrency))
        {'code': f.priceCurrency, 'name': 'not in the list'},
      ...packageCurrencies,
    ];

    return Form(
      key: _formKey,
      child: ListView(
        key: ValueKey(_revision),
        padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (_loadError != null)
            const VendorSavedNote(message: 'Showing the saved copy. Connect to save changes.'),
          VendorReviewBanner(review: f.review, firstTime: _isNew || !f.isApproved),
          // The web editor's "Show in the app" switch: applies at once.
          VendorCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            margin: const EdgeInsets.only(bottom: 14),
            child: VendorSwitchRow(
              title: f.isActive ? 'Show in the app' : 'Hidden (draft)',
              subtitle: !f.isActive
                  ? 'Only you can see it. Switch on when it is ready.'
                  : _isNew || !f.isApproved
                      ? 'Travellers can find it once NexAround approves it.'
                      : 'Travellers can find it. This switch applies at once.',
              value: f.isActive,
              onChanged: (v) => _patch((p) => p.copyWith(isActive: v)),
            ),
          ),
          VendorSection(
            icon: Icons.confirmation_number_outlined,
            title: 'Basic details',
            hint: 'What travellers see first.',
            children: [
              TextFormField(
                initialValue: f.title,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 255,
                decoration: vendorInput('Title *', hint: 'Pigeon Island snorkelling & boat safari'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Give the package a title.' : null,
                onChanged: (v) => _patch((p) => p.copyWith(title: v)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: vendorCategories.any((c) => c.value == f.category) ? f.category : 'other',
                icon: vendorDropdownIcon,
                style: vendorDropdownText(context),
                decoration: vendorInput('Category'),
                items: [
                  for (final c in vendorCategories)
                    DropdownMenuItem(value: c.value, child: Text('${c.emoji}  ${c.label}')),
                ],
                onChanged: (v) => _patch((p) => p.copyWith(category: v)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: f.summary,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: vendorInput('Summary', hint: 'One line for the card in the app'),
                onChanged: (v) => _patch((p) => p.copyWith(summary: v)),
              ),
              const SizedBox(height: 8),
              DescriptionEditor(
                value: f.description,
                onChanged: (v) => _patch((p) => p.copyWith(description: v)),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.payments_outlined,
            title: 'Price & capacity',
            hint: 'The main price shows on the card; travellers choose between all of them '
                'when they ask to book. Remove every price to show “On request”.',
            children: [
              DropdownButtonFormField<String>(
                initialValue: f.priceCurrency,
                isExpanded: true,
                icon: vendorDropdownIcon,
                style: vendorDropdownText(context),
                decoration: vendorInput('Currency'),
                items: [
                  for (final c in currencies)
                    DropdownMenuItem(
                      value: c['code'],
                      child: Text('${c['code']} · ${c['name']}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => _patch((p) => p.copyWith(priceCurrency: v)),
              ),
              for (var i = 0; i < f.priceOptions.length; i++) _priceOption(f, i),
              if (f.priceOptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No price: travellers see “Price on request”.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ),
              if (f.priceOptions.length < maxPriceOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _patch((p) =>
                        p.copyWith(priceOptions: [...p.priceOptions, VendorPriceOption()])),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add price option'),
                  ),
                ),
              const SizedBox(height: 12),
              // One per row: side by side, a phone cuts their labels off.
              _intField('Duration (minutes)', '180', f.durationMinutes,
                  (v) => _patch((p) => p.copyWith(durationMinutes: () => v))),
              const SizedBox(height: 12),
              _intField('Max participants', '8', f.maxParticipants,
                  (v) => _patch((p) => p.copyWith(maxParticipants: () => v)), min: 1),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: f.bookingWindowDays,
                icon: vendorDropdownIcon,
                style: vendorDropdownText(context),
                decoration: vendorInput('Bookable', helper: 'How far ahead travellers can pick a date'),
                items: [
                  for (final e in windows.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => _patch((p) => p.copyWith(bookingWindowDays: () => v)),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.event_busy_outlined,
            title: 'Availability',
            hint: 'Available every day unless you block dates here, for example when you are '
                'on leave or fully booked. Travellers cannot pick a blocked day.',
            children: [
              AvailabilityCalendar(
                value: f.unavailableRanges,
                maxDays: f.bookingWindowDays ?? 365,
                onChanged: (r) => _patch((p) => p.copyWith(unavailableRanges: r)),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.photo_library_outlined,
            title: 'Photos',
            hint: 'The first photo is the one shown on the card.',
            children: [
              PhotoEditor(
                api: widget.api,
                value: f.photoUrls,
                onBusy: (busy) => setState(() => _photosBusy = busy),
                onChanged: (urls) => _patch((p) => p.copyWith(photoUrls: urls)),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.checklist_rounded,
            title: 'Included & languages',
            hint: 'One item per line.',
            children: [
              _linesField('What’s included', 'Snorkelling gear\nLife jackets\nBottled water',
                  f.inclusions, (v) => _patch((p) => p.copyWith(inclusions: v))),
              const SizedBox(height: 12),
              _linesField('Languages', 'English\nTamil\nSinhala', f.languages,
                  (v) => _patch((p) => p.copyWith(languages: v))),
            ],
          ),
        ],
      ),
    );
  }

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// One price: amount, basis, and the guests it allows.
  Widget _priceOption(VendorPackage f, int index) {
    final o = f.priceOptions[index];
    return Container(
      key: ValueKey(o.key),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(index == 0 ? 'Main price' : 'Option ${index + 1}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: () => _patch((p) => p.copyWith(priceOptions: [
                      for (var i = 0; i < p.priceOptions.length; i++)
                        if (i != index) p.priceOptions[i],
                    ])),
                child: const Text('Remove'),
              ),
            ],
          ),
          TextFormField(
            initialValue: o.amount == null ? '' : _num(o.amount!),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: vendorInput('Price (${f.priceCurrency})', hint: '7500'),
            validator: (v) => (v ?? '').isNotEmpty && double.tryParse(v!) == null
                ? 'Enter a number.'
                : null,
            onChanged: (v) => _patchOption(index, (x) => x.copyWith(amount: () => double.tryParse(v))),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: optionBases.containsKey(o.basis) ? o.basis : 'per_person',
            icon: vendorDropdownIcon,
            style: vendorDropdownText(context),
            decoration: vendorInput('Basis'),
            items: [
              for (final e in optionBases.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => _patchOption(index, (x) => x.copyWith(basis: v)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _intField('Min people', '1', o.minPeople,
                    (v) => _patchOption(index, (x) => x.copyWith(minPeople: () => v)), min: 1),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _intField(
                  'Max people',
                  f.maxParticipants?.toString() ?? 'Any',
                  o.maxPeople,
                  (v) => _patchOption(index, (x) => x.copyWith(maxPeople: () => v)),
                  min: o.minPeople ?? 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _intField(String label, String hint, int? value, ValueChanged<int?> onChanged, {int min = 0}) =>
      TextFormField(
        initialValue: value?.toString() ?? '',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: vendorInput(label, hint: hint),
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return n != null && n < min ? 'At least $min.' : null;
        },
        onChanged: (v) => onChanged(int.tryParse(v)),
      );

  Widget _linesField(String label, String hint, List<String> value, ValueChanged<List<String>> onChanged) =>
      TextFormField(
        initialValue: value.join('\n'),
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        decoration: vendorInput(label, hint: hint),
        onChanged: (v) => onChanged(
            v.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()),
      );
}
