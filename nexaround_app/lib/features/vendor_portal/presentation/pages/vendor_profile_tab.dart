import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/countries.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import '../widgets/photo_editor.dart';
import '../widgets/place_picker.dart';

/// The business profile travellers see: details, location and contact.
/// Phone, WhatsApp and the socials are shown read-only: NexAround sets them,
/// so travellers reach the business through NexAround.
class VendorProfileTab extends StatefulWidget {
  final VendorPortalApi api;
  final ValueChanged<String> onRenamed;

  const VendorProfileTab({super.key, required this.api, required this.onRenamed});

  @override
  State<VendorProfileTab> createState() => _VendorProfileTabState();
}

class _VendorProfileTabState extends State<VendorProfileTab> {
  final _formKey = GlobalKey<FormState>();
  VendorProfile? _form;
  String _base = '';
  Object? _error;
  bool _saving = false;
  bool _photosBusy = false;
  // Rebuilds the text fields when a saved profile comes back changed.
  int _revision = 0;

  static const _managed = 'Managed by NexAround';

  bool get _dirty => _form != null && jsonEncode(_form!.toJson()) != _base;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.api.profile();
      if (mounted) _set(profile);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _set(VendorProfile profile) => setState(() {
        _form = profile;
        _base = jsonEncode(profile.toJson());
        _error = null;
        _revision++;
      });

  void _patch(VendorProfile Function(VendorProfile p) change) => setState(() => _form = change(_form!));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photosBusy) {
      showVendorSnack(context, 'Photos are still uploading. Wait for them to finish, then save.',
          error: true);
      return;
    }
    if ((_form!.countryCode ?? '').isEmpty) {
      showVendorSnack(context, 'Choose your country first.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.api.saveProfile(_form!);
      if (!mounted) return;
      _set(saved);
      widget.onRenamed(saved.name);
      showVendorSnack(context, 'Saved. Travellers see this straight away.');
    } catch (e) {
      if (mounted) showVendorSnack(context, userMessageFor(e, action: 'save your profile'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _countryName(String? code) {
    if (code == null) return null;
    for (final e in countryCodes.entries) {
      if (e.value == code) return e.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _form == null) {
      return ListView(children: [
        VendorEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load your profile',
          message: userMessageFor(_error),
          action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ),
      ]);
    }
    final f = _form;
    if (f == null) return const Center(child: CircularProgressIndicator());
    final country = _countryName(f.countryCode);

    return Form(
      key: _formKey,
      child: ListView(
        key: ValueKey(_revision),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          VendorSection(
            icon: Icons.storefront_outlined,
            title: 'Details',
            children: [
              TextFormField(
                initialValue: f.name,
                maxLength: 255,
                decoration: vendorInput('Business name *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the business name.' : null,
                onChanged: (v) => _patch((p) => p.copyWith(name: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: f.description,
                minLines: 4,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: vendorInput('Description', hint: 'What makes your business special'),
                onChanged: (v) => _patch((p) => p.copyWith(description: v)),
              ),
              const SizedBox(height: 14),
              const Text('Photos', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              PhotoEditor(
                api: widget.api,
                value: f.photoUrls,
                onBusy: (busy) => setState(() => _photosBusy = busy),
                onChanged: (urls) => _patch((p) => p.copyWith(photoUrls: urls)),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.place_outlined,
            title: 'Location',
            hint: 'Where your business is. Packages that meet at your business use this.',
            children: [
              PlacePicker(
                api: widget.api,
                latitude: f.latitude,
                longitude: f.longitude,
                onPick: (lat, lng, place) {
                  _patch((p) => p.copyWith(
                        latitude: () => lat,
                        longitude: () => lng,
                        address: place?.address,
                        city: place?.city,
                        countryCode: place?.countryCode,
                      ));
                  if (place != null) setState(() => _revision++);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: f.address,
                maxLength: 500,
                decoration: vendorInput('Address'),
                onChanged: (v) => _patch((p) => p.copyWith(address: v)),
              ),
              const SizedBox(height: 4),
              TextFormField(
                initialValue: f.city,
                maxLength: 120,
                decoration: vendorInput('City'),
                onChanged: (v) => _patch((p) => p.copyWith(city: v)),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: country,
                isExpanded: true,
                decoration: vendorInput('Country *'),
                items: [
                  for (final name in countriesList)
                    if (countryCodes[name] != null)
                      DropdownMenuItem(value: name, child: Text(name)),
                ],
                validator: (v) => v == null ? 'Choose your country.' : null,
                onChanged: (v) => _patch((p) => p.copyWith(countryCode: countryCodes[v])),
              ),
            ],
          ),
          VendorSection(
            icon: Icons.contact_mail_outlined,
            title: 'Contact',
            hint: 'Phone, WhatsApp and social accounts are set by NexAround.',
            children: [
              _readOnly('Phone', f.contactPhone),
              _readOnly('WhatsApp', f.contactWhatsapp),
              TextFormField(
                initialValue: f.contactEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: vendorInput('Email', hint: 'bookings@business.com'),
                onChanged: (v) => _patch((p) => p.copyWith(contactEmail: v)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: f.website,
                keyboardType: TextInputType.url,
                decoration: vendorInput('Website', hint: 'https://business.com'),
                onChanged: (v) => _patch((p) => p.copyWith(website: v)),
              ),
              const SizedBox(height: 12),
              _readOnly('Instagram', f.contactInstagram),
              _readOnly('Facebook', f.contactFacebook),
              _readOnly('X', f.contactX),
            ],
          ),
          FilledButton(
            onPressed: _saving || !_dirty ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(_saving ? 'Saving…' : (_dirty ? 'Save changes' : 'No changes')),
          ),
        ],
      ),
    );
  }

  Widget _readOnly(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: value ?? '',
          enabled: false,
          decoration: vendorInput(label, hint: _managed, helper: value == null ? null : _managed),
        ),
      );
}
