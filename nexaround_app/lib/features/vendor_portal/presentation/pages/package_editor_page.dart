import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import '../widgets/availability_calendar.dart';
import '../widgets/description_editor.dart';
import '../widgets/photo_editor.dart';
import '../widgets/place_picker.dart';

/// Opens the editor; completes with true when the package was saved or
/// deleted, so the list reloads.
Future<bool?> openPackageEditor(BuildContext context, VendorPortalApi api, {String? packageId}) =>
    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PackageEditorPage(api: api, packageId: packageId)),
    );

/// A new package or an existing one, field for field the web portal's editor.
class PackageEditorPage extends StatefulWidget {
  final VendorPortalApi api;
  final String? packageId;

  const PackageEditorPage({super.key, required this.api, this.packageId});

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

  bool get _isNew => widget.packageId == null;
  bool get _dirty => _form != null && jsonEncode(_form!.toJson()) != _base;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _setLoaded(const VendorPackage());
    } else {
      widget.api.package(widget.packageId!).then(_setLoaded).catchError((Object e) {
        if (mounted) setState(() => _loadError = e);
      });
    }
  }

  void _setLoaded(VendorPackage pkg) {
    setState(() {
      _form = pkg;
      _base = jsonEncode(pkg.toJson());
    });
  }

  void _patch(VendorPackage Function(VendorPackage f) change) =>
      setState(() => _form = change(_form!));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final form = _form!;
    if (_photosBusy) {
      showVendorSnack(context, 'Photos are still uploading. Wait for them to finish, then save.',
          error: true);
      return;
    }
    if (!form.usesVendorLocation && (form.latitude == null || form.longitude == null)) {
      showVendorSnack(context, 'Pick the meeting point on the map, or use your business address.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.savePackage(form);
      if (!mounted) return;
      showVendorSnack(context, _isNew ? 'Package created' : 'Package saved');
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
        appBar: AppBar(
          backgroundColor: AppColors.background,
          scrolledUnderElevation: 0,
          title: Text(_isNew ? 'New package' : 'Edit package',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            if (!_isNew && _form != null)
              IconButton(
                tooltip: 'Delete package',
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                onPressed: _delete,
              ),
          ],
        ),
        body: _body(),
        bottomNavigationBar: _form == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(_saving ? 'Saving…' : (_isNew ? 'Create package' : 'Save changes')),
                ),
              ),
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: vendorCategories.any((c) => c.value == f.category) ? f.category : 'other',
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
              const SizedBox(height: 4),
              DescriptionEditor(
                value: f.description,
                onChanged: (v) => _patch((p) => p.copyWith(description: v)),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.payments_outlined,
            title: 'Price & capacity',
            hint: 'Leave the price empty to show “On request”.',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: f.priceAmount == null ? '' : _num(f.priceAmount!),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: vendorInput('Price', hint: '7500'),
                      validator: (v) => (v ?? '').isNotEmpty && double.tryParse(v!) == null
                          ? 'Enter a number.'
                          : null,
                      onChanged: (v) => _patch((p) => p.copyWith(priceAmount: () => double.tryParse(v))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: f.priceCurrency,
                      isExpanded: true,
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
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: priceBases.containsKey(f.priceBasis) ? f.priceBasis : 'per_person',
                decoration: vendorInput('Basis'),
                items: [
                  for (final e in priceBases.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => _patch((p) => p.copyWith(priceBasis: v)),
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
          VendorSection(
            icon: Icons.place_outlined,
            title: 'Meeting point',
            hint: 'Where travellers meet you.',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: f.usesVendorLocation,
                activeThumbColor: AppColors.brandGreen,
                title: const Text('My business address'),
                onChanged: (v) => _patch((p) => p.copyWith(
                      usesVendorLocation: v,
                      latitude: () => null,
                      longitude: () => null,
                    )),
              ),
              if (!f.usesVendorLocation) ...[
                const SizedBox(height: 8),
                PlacePicker(
                  api: widget.api,
                  latitude: f.latitude,
                  longitude: f.longitude,
                  onPick: (lat, lng, place) => _patch((p) => p.copyWith(
                        latitude: () => lat,
                        longitude: () => lng,
                        meetingPointAddress: place?.address ?? p.meetingPointAddress,
                      )),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey(f.meetingPointAddress.isEmpty ? 'empty' : 'set'),
                  initialValue: f.meetingPointAddress,
                  maxLength: 500,
                  decoration: vendorInput('Address travellers see', hint: 'Jetty 3, Nilaveli Beach'),
                  onChanged: (v) => _patch((p) => p.copyWith(meetingPointAddress: v)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
