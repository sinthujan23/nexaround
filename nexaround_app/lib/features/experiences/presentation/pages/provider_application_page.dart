import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/country_dial_codes.dart';
import 'package:nexaround_app/core/widgets/phone_number_field.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';

/// "List your experience": a tour or activity business asks to join. The
/// details go to NexAround (Admin > Provider applications and the support
/// inbox); the team contacts them and adds the listing. Nothing is published.
Future<void> showProviderApplicationPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ProviderApplicationPage()),
  );
}

class ProviderApplicationPage extends StatefulWidget {
  const ProviderApplicationPage({super.key});

  @override
  State<ProviderApplicationPage> createState() => _ProviderApplicationPageState();
}

class _ProviderApplicationPageState extends State<ProviderApplicationPage> {
  final _businessController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _cityController = TextEditingController();
  final _offeringController = TextEditingController();
  final _linksController = TextEditingController();

  late CountryDialCode _phoneCountry;
  // Where the business is. Follows the phone's country until picked.
  CountryDialCode? _country;
  String? _phoneError;
  String? _error;
  bool _sending = false;
  bool _sent = false;

  // A to Z for the country menu; the phone field keeps its own order.
  late final List<CountryDialCode> _countries = [...countryDialCodes]
    ..sort((a, b) => a.name.compareTo(b.name));

  @override
  void initState() {
    super.initState();
    _phoneCountry = countryDialCodes.first;
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        _nameController.text = authState.user.displayName.trim();
        _emailController.text = authState.user.email.trim();
        final phone = authState.user.preferences['phone'] ??
            authState.user.preferences['phone_number'];
        final raw = phone?.toString().trim() ?? '';
        final detected = raw.isEmpty ? null : detectCountryFromPhone(raw);
        if (detected != null) {
          _phoneCountry = detected;
          var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.startsWith(detected.dialCode)) {
            digits = digits.substring(detected.dialCode.length);
          }
          _phoneController.text = digits;
        }
      }
    } catch (_) {
      // No AuthBloc above this page: the form simply starts empty.
    }
  }

  @override
  void dispose() {
    for (final c in [
      _businessController, _nameController, _phoneController, _emailController,
      _cityController, _offeringController, _linksController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  CountryDialCode get _businessCountry => _country ?? _phoneCountry;

  /// The first problem with the form, or null when it can be sent.
  String? _problem() {
    if (_businessController.text.trim().length < 2) return 'Please enter your business name.';
    if (_nameController.text.trim().length < 2) return 'Please enter your name.';
    final email = _emailController.text.trim();
    if (!email.contains('@') || !email.split('@').last.contains('.')) {
      return 'Please enter a valid email address.';
    }
    if (_offeringController.text.trim().length < 10) {
      return 'Tell us a little about what you offer.';
    }
    return null;
  }

  Future<void> _submit() async {
    final digits = PhoneNumberField.normalizeDigits(_phoneController.text, _phoneCountry);
    String? phoneErr;
    if (digits.isEmpty) {
      phoneErr = 'Please enter your phone number.';
    } else if (digits.length < _phoneCountry.minDigits || digits.length > _phoneCountry.maxDigits) {
      phoneErr = 'Check the number for ${_phoneCountry.name}.';
    }
    final problem = _problem();
    setState(() {
      _phoneError = phoneErr;
      _error = phoneErr == null ? problem : null;
    });
    if (phoneErr != null || problem != null) return;

    setState(() => _sending = true);
    final error = await ExperiencesService.submitProviderApplication(
      businessName: _businessController.text.trim(),
      contactName: _nameController.text.trim(),
      contactPhone: '+${_phoneCountry.dialCode}$digits',
      contactEmail: _emailController.text.trim(),
      countryCode: _businessCountry.iso,
      city: _cityController.text.trim(),
      offering: _offeringController.text.trim(),
      links: _linksController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      _sent = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('List your experience',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(child: _sent ? _buildSent() : _buildForm()),
    );
  }

  Widget _buildSent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, size: 64, color: AppColors.brandGreen),
          const SizedBox(height: 16),
          const Text('Thanks! We’ve got your details',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Our team will contact you soon to set up your listing.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brandGreenLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storefront_rounded, color: AppColors.brandGreen),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Run tours, boat trips or activities? Send us your details and our team '
                  'will contact you to list them on NexAround.',
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _field(_businessController, 'Business name', TextInputType.text),
        const SizedBox(height: 12),
        _field(_nameController, 'Your name', TextInputType.name),
        const SizedBox(height: 12),
        PhoneNumberField(
          selectedCountry: _phoneCountry,
          controller: _phoneController,
          onCountryChanged: (country) => setState(() {
            _phoneCountry = country;
            _phoneError = null;
          }),
          errorText: _phoneError,
        ),
        const SizedBox(height: 12),
        _field(_emailController, 'Email', TextInputType.emailAddress),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          // Rebuilt when the phone's country moves it, until one is picked.
          key: ValueKey(_businessCountry.iso),
          initialValue: _businessCountry.iso,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: InputDecoration(
            labelText: 'Country',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: [
            for (final c in _countries)
              DropdownMenuItem(value: c.iso, child: Text('${c.flag}  ${c.name}')),
          ],
          onChanged: (iso) => setState(() {
            _country = _countries.firstWhere((c) => c.iso == iso);
          }),
        ),
        const SizedBox(height: 12),
        _field(_cityController, 'City or town (optional)', TextInputType.text),
        const SizedBox(height: 12),
        TextField(
          controller: _offeringController,
          minLines: 4,
          maxLines: 8,
          maxLength: 3000,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'What do you offer?',
            hintText: 'Your experiences, prices, group sizes, season…',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _linksController,
          maxLength: 1000,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Links (optional)',
            hintText: 'Instagram, Google Maps, website',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Sending…' : 'Send my details',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'By sending, you agree that NexAround may contact you about listing your business.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
