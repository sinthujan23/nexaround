import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/country_dial_codes.dart';

/// Industry-standard phone input: a tappable country-code pill on the left
/// (flag + dial code) that opens a searchable bottom sheet, and a number
/// field on the right that accepts only digits.
///
/// The full international number ("+94 771234567") is assembled by
/// [fullNumber]; the validation logic checks both the code and the digit
/// count against the selected country's rules.
class PhoneNumberField extends StatelessWidget {
  final CountryDialCode selectedCountry;
  final TextEditingController controller;
  final ValueChanged<CountryDialCode> onCountryChanged;
  final String? errorText;

  const PhoneNumberField({
    super.key,
    required this.selectedCountry,
    required this.controller,
    required this.onCountryChanged,
    this.errorText,
  });

  /// Normalizes national digits, stripping local trunk zero prefix (e.g. 077 -> 77)
  /// when present so users can type naturally without error.
  static String normalizeDigits(String raw, CountryDialCode country) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0') && digits.length > country.minDigits) {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
    }
    return digits;
  }

  /// The full E.164-ish number sent to the server: "+{dialCode}{digits}".
  String get fullNumber {
    final digits = normalizeDigits(controller.text, selectedCountry);
    if (digits.isEmpty) return '';
    return '+${selectedCountry.dialCode}$digits';
  }

  /// Validate the national part against the country's expected digit range.
  /// Returns an error string, or null when valid.
  String? validate() {
    final digits = normalizeDigits(controller.text, selectedCountry);
    if (digits.isEmpty) return 'Please enter your phone number.';
    if (digits.length < selectedCountry.minDigits) {
      return 'Too short for ${selectedCountry.name}. '
          'Expected at least ${selectedCountry.minDigits} digits.';
    }
    if (digits.length > selectedCountry.maxDigits) {
      return 'Too long for ${selectedCountry.name}. '
          'Expected at most ${selectedCountry.maxDigits} digits.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: errorText != null ? AppColors.error : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              // Country code selector
              InkWell(
                onTap: () => _showCountryPicker(context),
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(11)),
                    border: Border(
                      right: BorderSide(
                        color: errorText != null
                            ? AppColors.error
                            : AppColors.border,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedCountry.flag,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        selectedCountry.formatted,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              // Phone number input
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]')),
                    LengthLimitingTextInputFormatter(
                        selectedCountry.maxDigits + 4),
                  ],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Phone number',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              errorText!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _showCountryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CountryPickerSheet(
        selected: selectedCountry,
        onPick: (country) {
          Navigator.pop(ctx);
          onCountryChanged(country);
        },
      ),
    );
  }
}

/// Searchable bottom sheet listing all countries with their flags and dial
/// codes. Matches the style of the experience destination picker.
class _CountryPickerSheet extends StatefulWidget {
  final CountryDialCode selected;
  final ValueChanged<CountryDialCode> onPick;

  const _CountryPickerSheet({required this.selected, required this.onPick});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<CountryDialCode> get _filtered {
    if (_query.isEmpty) return countryDialCodes;
    final q = _query.toLowerCase();
    return countryDialCodes.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.dialCode.contains(q) ||
          c.iso.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final filtered = _filtered;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: const [
                Icon(Icons.phone_rounded,
                    color: AppColors.brandGreen, size: 22),
                SizedBox(width: 10),
                Text(
                  'Select Country Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Search by country name or dial code.',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                autofocus: false,
                style:
                    const TextStyle(color: Colors.black87, fontSize: 14),
                onChanged: (val) => setState(() => _query = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search country or code...',
                  hintStyle: TextStyle(
                      color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Colors.grey, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: Colors.grey, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48,
                            color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'No countries found',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final country = filtered[i];
                      final isSelected =
                          country.iso == widget.selected.iso &&
                              country.dialCode ==
                                  widget.selected.dialCode;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.brandGreenLight
                                : AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(country.flag,
                              style: const TextStyle(fontSize: 20)),
                        ),
                        title: Text(
                          country.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 14.5,
                            color: isSelected
                                ? AppColors.brandGreen
                                : AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          country.formatted,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? AppColors.brandGreen
                                : AppColors.textSecondary,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: AppColors.brandGreen)
                            : null,
                        onTap: () => widget.onPick(country),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
