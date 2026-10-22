import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/core/widgets/premium_widgets.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_category.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

/// The pieces every vendor screen shares: the option lists the web portal
/// offers (nexaround_partner/src/format.js) and the app-styled widgets the
/// screens are built from, so they all line up on the same 16 px gutter.

/// The side margin of every vendor screen, as in Experiences.
const vendorGutter = 16.0;

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
  'per_hour': 'Per hour',
  'from': 'Starting from',
  'on_request': 'On request',
};

/// The bases a price option takes (no "On request": that is no option at all)
/// and how many a package may have: the server's OPTION_BASES and
/// MAX_PRICE_OPTIONS.
const optionBases = <String, String>{
  'per_person': 'Per person',
  'per_group': 'Per group',
  'per_hour': 'Per hour',
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

/// A package's main price as the card in the app reads it: "LKR 30,000 /
/// group", "From LKR 7,000" or "Price on request".
String packagePriceLine(VendorPackage pkg) {
  final first = pkg.priceOptions.isEmpty ? null : pkg.priceOptions.first;
  final amount = first?.amount ?? pkg.priceAmount;
  if (amount == null) return 'Price on request';
  final price = formatPrice(amount, pkg.priceCurrency);
  return switch (first?.basis ?? pkg.priceBasis) {
    'per_person' => '$price / person',
    'per_group' => '$price / group',
    'per_hour' => '$price / hour',
    'from' => 'From $price',
    _ => price,
  };
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

/// The round, outlined button the Experiences screens use for Back.
class VendorCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;
  final Widget? badge;

  const VendorCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.textPrimary,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: icon == Icons.arrow_back_ios_new_rounded ? 16 : 20, color: color),
      ),
    );
    if (badge == null) return button;
    return Stack(clipBehavior: Clip.none, children: [
      button,
      Positioned(top: -2, right: -2, child: badge!),
    ]);
  }
}

/// The app bar of a vendor page: the round Back button and a centred title,
/// like Experiences.
PreferredSizeWidget vendorAppBar(BuildContext context, String title, {List<Widget> actions = const []}) {
  return AppBar(
    backgroundColor: AppColors.background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    automaticallyImplyLeading: false,
    leadingWidth: 56 + vendorGutter - 8,
    leading: Navigator.of(context).canPop()
        ? Padding(
            padding: const EdgeInsets.only(left: vendorGutter),
            child: Center(
              child: VendorCircleButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
          )
        : null,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
      ),
    ),
    actions: [
      for (final a in actions) Center(child: a),
      const SizedBox(width: vendorGutter),
    ],
  );
}

/// The white card every vendor list and form is made of: the app's
/// GlassCard, tappable when [onTap] is given.
class VendorCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const VendorCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: padding,
      margin: margin,
      borderRadius: AppRadii.brLg,
      // Fields inside need a Material for their ink.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
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
    return VendorCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, color: AppColors.brandGreen, size: 36, iconSize: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint!,
                          style: const TextStyle(
                              fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// The input decoration every vendor form field uses: the app's field style
/// (theme), with the label kept at the top of tall fields and no character
/// counter (the limit still holds).
InputDecoration vendorInput(String label, {String? hint, String? helper, Widget? suffix, Widget? prefix}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      suffixIcon: suffix,
      prefixIcon: prefix,
      alignLabelWithHint: true,
      counterText: '',
    );

/// What a dropdown in a vendor form needs on top of [vendorInput]: an arrow
/// that shows on the light field (the theme's default is white) and the
/// field's own text size rather than a heading's. The style replaces the
/// theme's outright, so it starts from the theme's to keep the app font.
const vendorDropdownIcon = Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary);
TextStyle? vendorDropdownText(BuildContext context) => Theme.of(context)
    .textTheme
    .titleMedium
    ?.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary);

/// A label and a switch on one line, the switch in the app's colours.
class VendorSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const VendorSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
        title: Text(title,
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
      ),
    );
  }
}

/// Where the vendor's own edits stand, over a form: waiting for NexAround,
/// sent back with NexAround's note, or (nothing waiting) how review works.
/// [firstTime] for a package not approved yet; [what] names the record.
class VendorReviewBanner extends StatelessWidget {
  final VendorReviewState review;
  final bool firstTime;
  final String what;

  const VendorReviewBanner({
    super.key,
    required this.review,
    this.firstTime = false,
    this.what = 'package',
  });

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String title, String body) = review.changesRequested
        ? (
            AppColors.error,
            Icons.edit_note_rounded,
            'NexAround asked for changes',
            'Make the changes and save to send it for review again.',
          )
        : review.isPending
            ? (
                const Color(0xFFB7791F),
                Icons.hourglass_top_rounded,
                'Waiting for NexAround’s review',
                firstTime
                    ? 'Travellers can see it once it is approved. You will get a notification when it is checked.'
                    : 'Travellers see the current $what until your changes are approved. '
                        'You will get a notification when they are checked.',
              )
            : (
                AppColors.brandGreen,
                Icons.verified_outlined,
                firstTime ? 'Checked before it goes live' : 'Changes are checked first',
                firstTime
                    ? 'NexAround checks new packages before travellers can see them.'
                    : 'NexAround checks changes to the details, photos${what == 'package' ? ' and prices' : ''} '
                        'before travellers see them.'
                        '${what == 'package' ? ' Availability and Show in the app apply at once.' : ''}',
              );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: AppRadii.brMd,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                if (review.changesRequested && (review.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadii.brSm,
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Text(review.note!,
                        style: const TextStyle(
                            fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                ],
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "In review", "Edit in review" or "Changes needed"; nothing when no edit
/// waits.
class ReviewPill extends StatelessWidget {
  final VendorReviewState review;
  final bool approved;

  const ReviewPill(this.review, {super.key, this.approved = true});

  @override
  Widget build(BuildContext context) {
    if (!review.isPending && !review.changesRequested) return const SizedBox.shrink();
    final color = review.changesRequested ? AppColors.error : const Color(0xFFB7791F);
    final label = review.changesRequested ? 'Changes needed' : (approved ? 'Edit in review' : 'In review');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// "Live" (green), "On, not visible" (amber), "Hidden" or "Not live yet"
/// (grey).
class VisibilityPill extends StatelessWidget {
  final String label;

  const VisibilityPill(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Live' => AppColors.success,
      'Hidden' || 'Not live yet' => AppColors.textTertiary,
      _ => const Color(0xFFB7791F),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
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
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.brandGreenLight, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.brandGreen),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Over a list shown from what the device kept, when the server could not
/// be reached: the same line My requests shows.
class VendorSavedNote extends StatelessWidget {
  final String message;

  const VendorSavedNote({super.key, this.message = 'Showing saved data. Pull down to refresh.'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
          ),
        ],
      ),
    );
  }
}

/// The teal call to action of a vendor screen (the Experiences screens'
/// "Request booking" colour), full width unless [compact].
class VendorPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;

  const VendorPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppColors.brandGreen,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.surfaceElevated,
      disabledForegroundColor: AppColors.textTertiary,
      minimumSize: compact ? const Size(0, 40) : const Size.fromHeight(52),
      padding: compact ? const EdgeInsets.symmetric(horizontal: 16) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? AppRadii.pill : AppRadii.md)),
      // From the theme's, which carries the app font: this one replaces it.
      textStyle: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(fontSize: compact ? 13.5 : 15, fontWeight: FontWeight.w700),
    );
    return icon == null
        ? ElevatedButton(onPressed: onPressed, style: style, child: Text(label))
        : ElevatedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: compact ? 18 : 20),
            label: Text(label),
          );
  }
}

/// The bar pinned under a form with its Save button, so it is in reach
/// however long the form is.
class VendorActionBar extends StatelessWidget {
  final Widget child;

  const VendorActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(vendorGutter, 10, vendorGutter, 12),
        child: child,
      ),
    );
  }
}

/// A tile with a square photo (or a placeholder), for package lists.
class PackageThumb extends StatelessWidget {
  final List<String> photoUrls;
  final double size;

  const PackageThumb(this.photoUrls, {super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surface,
      child: const Icon(Icons.kayaking_rounded, color: AppColors.textMuted),
    );
    return ClipRRect(
      borderRadius: AppRadii.brSm,
      child: SizedBox(
        width: size,
        height: size,
        child: photoUrls.isEmpty
            ? placeholder
            : Image.network(
                mediaUrl(photoUrls.first),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}
