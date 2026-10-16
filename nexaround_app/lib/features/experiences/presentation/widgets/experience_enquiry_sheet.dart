import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/utils/contact_launcher.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/enquiry_validation.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_terms.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_terms_page.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/my_experience_requests_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_date_picker.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_good_to_know.dart';

Future<void> showExperienceEnquirySheet(
  BuildContext context,
  ExperiencePackageEntity package,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (_) => _EnquirySheet(package: package),
  );
}

class _EnquirySheet extends StatefulWidget {
  final ExperiencePackageEntity package;

  const _EnquirySheet({required this.package});

  @override
  State<_EnquirySheet> createState() => _EnquirySheetState();
}

class _EnquirySheetState extends State<_EnquirySheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  final _pickupController = TextEditingController();

  // Google place suggestions for the pickup box. The traveller may pick one
  // or keep their own text; either is sent as typed in the box.
  List<Map<String, dynamic>> _pickupSuggestions = [];
  Timer? _pickupDebounce;
  int _pickupQuery = 0;

  DateTime? _preferredDate;
  int _partySize = 2;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  // The Experience Booking Terms. The saved copy shows at once and the
  // current version replaces it; a request is sent with the version shown.
  ExperienceTerms? _terms = ExperiencesService.cachedTerms();
  bool _termsFailed = false;
  bool _termsTicked = false;
  // Send was tapped without ticking: outline the box and say why.
  bool _termsNudge = false;
  late final TapGestureRecognizer _termsLink = TapGestureRecognizer()
    ..onTap = () => showExperienceTerms(context);

  @override
  void initState() {
    super.initState();
    _loadTerms();
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        if (authState.user.displayName.trim().isNotEmpty) {
          _nameController.text = authState.user.displayName.trim();
        }
        if (authState.user.email.trim().isNotEmpty) {
          _emailController.text = authState.user.email.trim();
        }
        final phone = authState.user.preferences['phone'] ??
            authState.user.preferences['phone_number'];
        if (phone != null && phone.toString().trim().isNotEmpty) {
          _phoneController.text = phone.toString().trim();
        }
      }
    } catch (_) {
      // In case AuthBloc is unavailable in context
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    _pickupController.dispose();
    _pickupDebounce?.cancel();
    _termsLink.dispose();
    super.dispose();
  }

  Future<void> _loadTerms() async {
    final fresh = await ExperiencesService.fetchTerms();
    if (!mounted) return;
    setState(() {
      if (fresh != null) {
        // A new version has to be ticked afresh.
        if (fresh.version != _terms?.version) _termsTicked = false;
        _terms = fresh;
      }
      _termsFailed = _terms == null;
    });
  }

  void _setTicked(bool value) => setState(() {
        _termsTicked = value;
        _termsNudge = false;
      });

  void _onPickupChanged(String text) {
    _pickupDebounce?.cancel();
    if (text.trim().length < 2) {
      _pickupQuery++; // drop any search still in flight
      if (_pickupSuggestions.isNotEmpty) setState(() => _pickupSuggestions = []);
      return;
    }
    _pickupDebounce = Timer(const Duration(milliseconds: 300), () async {
      final query = ++_pickupQuery;
      // Lean the results toward the package; a package listed by country
      // only has no point (0, 0), so search unbiased then.
      final lat = widget.package.latitude;
      final lng = widget.package.longitude;
      final hasPoint = !(lat == 0 && lng == 0);
      List<Map<String, dynamic>> results = [];
      try {
        results = await GooglePlacesService.getAutocompleteSuggestions(
          input: text,
          latitude: hasPoint ? lat : null,
          longitude: hasPoint ? lng : null,
        );
      } catch (_) {
        // No suggestions; whatever they typed is still sent.
      }
      if (!mounted || query != _pickupQuery) return;
      setState(() => _pickupSuggestions = results.take(5).toList());
    });
  }

  void _pickPickupSuggestion(Map<String, dynamic> suggestion) {
    _pickupQuery++;
    final text = (suggestion['description'] as String?)?.trim() ?? '';
    setState(() {
      if (text.isNotEmpty) {
        _pickupController.text = text;
        _pickupController.selection =
            TextSelection.collapsed(offset: text.length);
      }
      _pickupSuggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _submit() async {
    final error = validateEnquiry(
      name: _nameController.text,
      phone: _phoneController.text,
      email: _emailController.text,
      partySize: _partySize,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final terms = _terms;
    if (terms == null) {
      setState(() => _error =
          "Couldn't load the booking terms. Please try again.");
      return;
    }
    if (!terms.accepted && !_termsTicked) {
      setState(() => _termsNudge = true);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await ExperiencesService.submitEnquiry(
      packageId: widget.package.id,
      contactName: _nameController.text.trim(),
      contactPhone: _phoneController.text.trim(),
      acceptedTermsVersion: terms.version,
      contactEmail: _emailController.text.trim(),
      preferredDate: _preferredDate,
      partySize: _partySize,
      pickupLocation: _pickupController.text.trim(),
      message: _messageController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = result.error;
      _sent = result.sent;
      if (result.termsChanged) {
        // Published since this sheet loaded them: drop the old version so it
        // cannot be sent again, and show the new one to accept.
        _terms = null;
        _termsTicked = false;
      }
    });
    if (result.termsChanged) await _loadTerms();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lift the sheet above the keyboard, or the phone field sits under it.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: SingleChildScrollView(
          child: _sent ? _buildConfirmation() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    final vendor = widget.package.vendor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.brandGreenLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              size: 32, color: AppColors.brandGreen),
        ),
        const SizedBox(height: 16),
        const Text(
          'Request sent',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          "We've sent your request to ${widget.package.vendorName}. "
          'They usually reply within a day.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        if ((_terms?.highlights ?? const []).isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Good to know',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ExperienceHighlights(lines: _terms!.highlights),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (vendor != null && vendor.hasWhatsapp)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => ContactLauncher.whatsApp(
                vendor.contactWhatsapp,
                message: 'Hi, I just sent an enquiry about '
                    '"${widget.package.title}" on NexAround.',
              ),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Message on WhatsApp'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Done'),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            showMyExperienceRequests(navigator.context);
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.brandGreen),
          child: const Text('Follow or cancel it in My requests'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text('Request this experience',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${widget.package.title} · ${widget.package.vendorName}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        _field(_nameController, 'Your name', TextInputType.name),
        const SizedBox(height: 12),
        _field(_phoneController, 'Phone number', TextInputType.phone),
        const SizedBox(height: 12),
        _field(_emailController, 'Email (optional)', TextInputType.emailAddress),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How many people?',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _stepper(
                        Icons.remove_rounded,
                        () => setState(() {
                          if (_partySize > 1) _partySize--;
                        }),
                        enabled: _partySize > 1,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          '$_partySize',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _stepper(
                        Icons.add_rounded,
                        () => setState(() {
                          if (_partySize < 100) _partySize++;
                        }),
                        enabled: _partySize < 100,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preferred date',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 14, color: AppColors.textTertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _preferredDate == null
                                  ? 'Any'
                                  : '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _pickupController,
          maxLength: 500,
          textInputAction: TextInputAction.search,
          onChanged: _onPickupChanged,
          decoration: InputDecoration(
            labelText: 'Pickup hotel or location (optional)',
            hintText: 'Search your hotel or a place',
            prefixIcon: const Icon(Icons.location_on_rounded,
                size: 20, color: AppColors.brandGreen),
            counterText: '',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_pickupSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (final suggestion in _pickupSuggestions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined,
                        size: 18, color: AppColors.textTertiary),
                    title: Text(
                      suggestion['description'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                    ),
                    onTap: () => _pickPickupSuggestion(suggestion),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        TextField(
          controller: _messageController,
          maxLines: 3,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: 'Special requests (optional)',
            helperText: 'Special requests may incur extra charges.',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(fontSize: 13, color: Colors.redAccent)),
        ],

        const SizedBox(height: 12),
        _buildTerms(),
        const SizedBox(height: 12),
        const Text(
          'This is a booking request, not a confirmed booking. The vendor '
          'will contact you to confirm the date, price and pickup.',
          style: TextStyle(
              fontSize: 12, height: 1.4, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _sending ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send request',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  /// The clickwrap: the key rules, then a checkbox the first time this
  /// account meets this version of the terms, or a one-line reminder after.
  Widget _buildTerms() {
    final terms = _terms;
    const small = TextStyle(
        fontSize: 12.5, height: 1.45, color: AppColors.textSecondary);
    if (terms == null) {
      return Row(
        children: _termsFailed
            ? [
                const Expanded(
                  child: Text("Couldn't load the booking terms.", style: small),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _termsFailed = false);
                    _loadTerms();
                  },
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandGreen),
                  child: const Text('Try again'),
                ),
              ]
            : const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Loading booking terms…', style: small),
              ],
      );
    }

    final link = TextSpan(
      text: terms.title,
      style: const TextStyle(
        color: AppColors.brandGreen,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.brandGreen,
      ),
      recognizer: _termsLink,
    );
    final nudged = _termsNudge && !_termsTicked;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: nudged ? AppColors.error : AppColors.border,
          width: nudged ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Before you send',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ExperienceHighlights(lines: terms.highlights),
          if (terms.accepted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(TextSpan(style: small, children: [
                const TextSpan(text: 'By sending this request you agree to the '),
                link,
                const TextSpan(text: '.'),
              ])),
            )
          else
            InkWell(
              onTap: () => _setTicked(!_termsTicked),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _termsTicked,
                    onChanged: (value) => _setTicked(value ?? false),
                    activeColor: AppColors.brandGreen,
                    side: BorderSide(
                      color: nudged ? AppColors.error : AppColors.textTertiary,
                      width: 1.5,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 9, bottom: 6),
                      child: Text.rich(TextSpan(style: small, children: [
                        const TextSpan(text: 'I have read and agree to the '),
                        link,
                        const TextSpan(text: '.'),
                      ])),
                    ),
                  ),
                ],
              ),
            ),
          if (nudged)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Tick the box to agree to the terms before sending.',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
      TextEditingController controller, String label, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _stepper(IconData icon, VoidCallback? onTap, {bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? Colors.transparent : Colors.grey.withOpacity(0.08),
          border: Border.all(
            color: enabled ? AppColors.border : AppColors.border.withOpacity(0.5),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // The vendor's window; the server refuses anything past it.
    final windowDays = widget.package.bookingWindowDays ?? 365;
    final lastDate = now.add(Duration(days: windowDays));
    final tomorrow = now.add(const Duration(days: 1));
    final package = widget.package;

    // Open on the first day the vendor has not blocked, so OK never returns a
    // blocked day.
    final wanted = _preferredDate ?? (tomorrow.isAfter(lastDate) ? now : tomorrow);
    final initial = package.firstAvailableFrom(wanted, lastDate) ??
        package.firstAvailableFrom(now, lastDate);
    if (initial == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No dates are available for this experience right now.'),
      ));
      return;
    }

    final picked = await showExperienceDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: lastDate,
      // Days the vendor has blocked show in red and cannot be picked.
      isUnavailable: package.isUnavailableOn,
      helpText: windowDays == 1
          ? 'Book up to 1 day ahead'
          : 'Book up to $windowDays days ahead',
    );
    if (picked != null) setState(() => _preferredDate = picked);
  }
}
