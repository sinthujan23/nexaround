import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/currency_service.dart';

/// The currencies a traveller may see experience prices in: the app's list,
/// less the two the server has no rate for (services/currencies.py).
List<Map<String, String>> get experienceCurrencies => CurrencyService.supportedCurrencies
    .where((c) => c['code'] != 'KPW' && c['code'] != 'SVC')
    .toList();

// Offered first: the ones travellers on the app use most.
const _popular = ['USD', 'EUR', 'GBP', 'LKR', 'INR', 'QAR', 'AED', 'SAR'];

/// The chip in the Experiences app bar: "Original" (each provider's own price,
/// the default) or the currency every price is also shown in, marked "≈".
/// Display only: a request is always for the provider's price.
class ExperienceCurrencyChip extends StatelessWidget {
  const ExperienceCurrencyChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: CacheService.experienceCurrencyNotifier,
      builder: (context, value, _) {
        final code = value ?? CacheService.getExperienceCurrency();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Material(
            color: AppColors.surface,
            shape: StadiumBorder(
              side: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => showExperienceCurrencyPicker(context, code),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.currency_exchange_rounded,
                        size: 15, color: AppColors.brandGreen),
                    const SizedBox(width: 5),
                    Text(
                      code ?? 'Original',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pick a currency; "Original prices" goes back to each provider's own.
Future<void> showExperienceCurrencyPicker(BuildContext context, String? current) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _CurrencySheet(current: current),
  );
}

class _CurrencySheet extends StatefulWidget {
  final String? current;

  const _CurrencySheet({required this.current});

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String _query = '';

  Future<void> _pick(String? code) async {
    Navigator.pop(context);
    if (code != widget.current) await CacheService.setExperienceCurrency(code);
  }

  @override
  Widget build(BuildContext context) {
    final all = experienceCurrencies;
    final q = _query.trim().toLowerCase();
    final matches = all.where((c) =>
        q.isEmpty ||
        c['code']!.toLowerCase().contains(q) ||
        c['name']!.toLowerCase().contains(q));
    // Popular first, in that order, then the rest A to Z.
    final ordered = [
      for (final code in _popular) ...matches.where((c) => c['code'] == code),
      ...matches.where((c) => !_popular.contains(c['code'])),
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Show prices in',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Converted with today’s rate, marked ≈. You always book at the '
                'provider’s own price.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search currency',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (q.isEmpty)
                    _row(
                      leading: const Icon(Icons.storefront_rounded,
                          size: 20, color: AppColors.brandGreen),
                      title: 'Original prices',
                      subtitle: 'Each provider’s own currency, with dollars',
                      selected: widget.current == null,
                      onTap: () => _pick(null),
                    ),
                  for (final c in ordered)
                    _row(
                      leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 20)),
                      title: c['code']!,
                      subtitle: c['name']!,
                      selected: widget.current == c['code'],
                      onTap: () => _pick(c['code']),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required Widget leading,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: SizedBox(width: 30, child: Center(child: leading)),
      title: Text(title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? AppColors.brandGreen : AppColors.textPrimary,
          )),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen)
          : null,
      onTap: onTap,
    );
  }
}
