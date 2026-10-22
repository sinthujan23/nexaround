import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/constants/countries.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';
import '../widgets/photo_editor.dart';

/// The business profile travellers see: details, location and contact.
/// Phone, WhatsApp and the socials are shown read-only: NexAround sets them,
/// so travellers reach the business through NexAround.
class VendorProfileTab extends StatefulWidget {
  final VendorPortalApi api;
  final ValueChanged<String> onRenamed;

  /// True while there are changes not saved yet.
  final ValueChanged<bool>? onDirtyChanged;

  const VendorProfileTab({super.key, required this.api, required this.onRenamed, this.onDirtyChanged});

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
  bool _reportedDirty = false;
  // Whether the form holds the server's copy. A save replaces the whole
  // profile, so it waits for it: the kept copy may be an older one.
  bool _fresh = false;
  // Rebuilds the text fields when a saved profile comes back changed.
  int _revision = 0;

  bool get _dirty => _form != null && jsonEncode(_form!.toJson()) != _base;

  @override
  void initState() {
    super.initState();
    final kept = widget.api.cachedProfile();
    if (kept != null) _set(kept);
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.api.profile();
      if (!mounted) return;
      _form == null ? _set(profile) : _refresh(profile);
      setState(() {
        _fresh = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The server's copy, come while the kept one showed: taken as it is, or
  /// with the changes already typed moved onto it.
  void _refresh(VendorProfile fresh) {
    final freshJson = fresh.toJson();
    if (jsonEncode(freshJson) == _base) {
      // Only what NexAround sets can differ: no field to rebuild.
      setState(() => _form = fresh.withManagedFrom(_form!.toJson()));
      return;
    }
    if (!_dirty) {
      _set(fresh);
      return;
    }
    final mine = rebaseEdits(jsonDecode(_base) as Map<String, dynamic>, _form!.toJson(), freshJson);
    setState(() {
      _form = fresh.withManagedFrom(mine);
      _base = jsonEncode(freshJson);
      _revision++;
    });
    _reportDirty();
  }

  void _set(VendorProfile profile) {
    setState(() {
      _form = profile;
      _base = jsonEncode(profile.toJson());
      _error = null;
      _revision++;
    });
    _reportDirty();
  }

  void _patch(VendorProfile Function(VendorProfile p) change) {
    setState(() => _form = change(_form!));
    _reportDirty();
  }

  void _reportDirty() {
    final dirty = _dirty;
    if (dirty == _reportedDirty) return;
    _reportedDirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  /// Puts back what was last saved.
  void _discard() => _set(_form!.withManagedFrom(jsonDecode(_base) as Map<String, dynamic>));

  Future<void> _save() async {
    if (!_fresh) {
      showVendorSnack(
          context,
          _error == null
              ? 'Still loading your latest profile. Try again in a moment.'
              : 'Can’t reach NexAround to check for changes. Connect, then save again.',
          error: true);
      if (_error != null) _load();
      return;
    }
    if (!_formKey.currentState!.validate()) {
      showVendorSnack(context, 'Check the fields marked in red.', error: true);
      return;
    }
    if (_photosBusy) {
      showVendorSnack(context, 'Photos are still uploading. Wait for them to finish, then save.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.api.saveProfile(_form!);
      if (!mounted) return;
      _set(saved);
      // The header keeps the live name until NexAround approves a new one.
      if (saved.review.status == 'approved') widget.onRenamed(saved.name);
      showVendorSnack(
          context,
          saved.review.isPending
              ? 'Sent for review. Travellers see your current profile until NexAround approves it.'
              : 'Saved.');
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
    final dirty = _dirty;

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: ValueKey(_revision),
                padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_error != null) const VendorSavedNote(),
                  const Text('Business profile',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  const Text('What travellers see about your business',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  VendorReviewBanner(review: f.review, what: 'profile'),
                  VendorSection(
                    icon: Icons.storefront_outlined,
                    title: 'Details',
                    children: [
                      TextFormField(
                        initialValue: f.name,
                        maxLength: 255,
                        textCapitalization: TextCapitalization.words,
                        decoration: vendorInput('Business name *'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the business name.' : null,
                        onChanged: (v) => _patch((p) => p.copyWith(name: v)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: f.description,
                        minLines: 4,
                        maxLines: 10,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: vendorInput('Description', hint: 'What makes your business special'),
                        onChanged: (v) => _patch((p) => p.copyWith(description: v)),
                      ),
                    ],
                  ),
                  VendorSection(
                    icon: Icons.photo_library_outlined,
                    title: 'Photos',
                    hint: 'The first photo is the cover of your business page.',
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
                    icon: Icons.alternate_email_rounded,
                    title: 'Email',
                    hint: 'Not shown in the app.',
                    children: [
                      TextFormField(
                        initialValue: f.contactEmail,
                        keyboardType: TextInputType.emailAddress,
                        decoration: vendorInput('Email', hint: 'bookings@business.com'),
                        onChanged: (v) => _patch((p) => p.copyWith(contactEmail: v)),
                      ),
                    ],
                  ),
                  VendorSection(
                    icon: Icons.lock_outline_rounded,
                    title: 'Set by NexAround',
                    hint: 'Travellers find and book you through NexAround, so where you are and '
                        'how to reach you are kept by our team. Ask NexAround to change them.',
                    children: [
                      _managed(Icons.place_outlined, 'Address', f.address),
                      _managed(Icons.location_city_outlined, 'City', f.city),
                      _managed(Icons.flag_outlined, 'Country', country),
                      _managed(Icons.language_rounded, 'Website', f.website),
                      _managed(Icons.call_outlined, 'Phone', f.contactPhone),
                      _managed(Icons.chat_outlined, 'WhatsApp', f.contactWhatsapp),
                      _managed(Icons.camera_alt_outlined, 'Instagram', f.contactInstagram),
                      _managed(Icons.facebook_outlined, 'Facebook', f.contactFacebook),
                      _managed(Icons.alternate_email_rounded, 'X', f.contactX, last: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Only while there is something to save, so it is never missed at
        // the foot of the long form.
        AnimatedSize(
          duration: AppDurations.normal,
          curve: AppCurves.standard,
          child: dirty || _saving
              ? VendorActionBar(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _discard,
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          child: const Text('Discard'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: VendorPrimaryButton(
                          label: _saving ? 'Saving…' : 'Save changes',
                          onPressed: _saving ? null : _save,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// One contact NexAround keeps: shown, not editable.
  Widget _managed(IconData icon, String label, String? value, {bool last = false}) {
    final set = (value ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              set ? value!.trim() : 'Not set',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: set ? FontWeight.w600 : FontWeight.w400,
                color: set ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
