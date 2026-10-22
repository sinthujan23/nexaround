import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_category.dart';

/// The pieces every vendor screen shares: the option lists the web portal
/// offers (nexaround_partner/src/format.js) and a few app-styled widgets.

/// The package categories the server takes: the app's, without the "All"
/// filter chip, plus "Other", which the app shows with the generic style.
final List<ExperienceCategory> vendorCategories = [
  ...experienceCategories.where((c) => c.value != null),
  const ExperienceCategory(
    'other',
    '🧭',
    Icons.grid_view_rounded,
    'Other',
    'Other',
    [Color(0xFF00A3A6), Color(0xFF005E60)],
    Color(0xFF007A7C),
  ),
];

String categoryLabel(String? value) =>
    vendorCategories.firstWhere((c) => c.value == value,
        orElse: () => vendorCategories.last).label;

const priceBases = <String, String>{
  'per_person': 'Per person',
  'per_group': 'Per group',
  'from': 'Starting from',
  'on_request': 'On request',
};

/// The bases a price option takes (no "On request": that is no option at all)
/// and how many a package may have: the server's PRICE_BASES and
/// MAX_PRICE_OPTIONS.
const optionBases = <String, String>{
  'per_person': 'Per person',
  'per_group': 'Per group',
  'from': 'Starting from',
};
const maxPriceOptions = 6;

/// How far ahead travellers may pick a date; null is the platform default
/// (a year).
const bookingWindows = <int?, String>{
  null: 'Up to a year (default)',
  7: '1 week ahead',
  14: '2 weeks ahead',
  30: '1 month ahead',
  60: '2 months ahead',
  90: '3 months ahead',
  180: '6 months ahead',
};

/// The currencies a package may be priced in: the Profile list, less the two
/// the server refuses (no exchange rate exists for them).
final List<Map<String, String>> packageCurrencies = CurrencyService.supportedCurrencies
    .where((c) => c['code'] != 'KPW' && c['code'] != 'SVC')
    .toList();

/// "LKR 7,500" or "On request".
String formatPrice(double? amount, String currency) {
  if (amount == null) return 'On request';
  final whole = amount == amount.roundToDouble();
  final text = whole ? amount.toInt().toString() : amount.toStringAsFixed(2);
  final grouped = text.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return '$currency $grouped';
}

/// Photo URLs the server returns are paths ("/static/uploads/...").
String mediaUrl(String url) =>
    url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url';

void showVendorSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.error : AppColors.charcoal,
    ));
}

/// A titled card that groups a few fields, like the web portal's sections.
class VendorSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? trailing;
  final List<Widget> children;

  const VendorSection({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: AppColors.brandGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!,
                style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// The input decoration every vendor form field uses.
InputDecoration vendorInput(String label, {String? hint, String? helper, Widget? suffix}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.brandGreen, width: 1.6),
      ),
    );

/// "Live" (green), "On, not visible" (amber) or "Hidden" (grey).
class VisibilityPill extends StatelessWidget {
  final String label;

  const VisibilityPill(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Live' => AppColors.success,
      'Hidden' => AppColors.textTertiary,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class VendorEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const VendorEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A tile with a square photo (or a placeholder), for package lists.
class PackageThumb extends StatelessWidget {
  final List<String> photoUrls;
  final double size;

  const PackageThumb(this.photoUrls, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: photoUrls.isEmpty
            ? Container(
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.confirmation_number_outlined,
                    color: AppColors.textTertiary),
              )
            : Image.network(
                mediaUrl(photoUrls.first),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceVariant),
              ),
      ),
    );
  }
}
