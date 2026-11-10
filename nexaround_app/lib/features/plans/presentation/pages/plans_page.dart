import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/plan_service.dart';
import 'package:nexaround_app/core/services/purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Explorer / Voyager / Globetrotter, as in the packages document
/// (Nexaround_Subscription_Packages.docx, 2026-11-10).
///
/// Limits are read from the server's catalog, so a limit the TL changes in the
/// admin panel shows here without a release; prices come from the store, in
/// the user's own currency, with the USD list price as a fallback.
class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlansPage()),
    );
  }

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  static const _termsUrl = 'https://app.nexaround.com/terms';
  static const _privacyUrl = 'https://app.nexaround.com/privacy';

  // USD list prices (shown only if the store's own price cannot be loaded).
  static const _fallbackPrices = {
    'voyager_monthly': r'$4.59',
    'voyager_yearly': r'$45.99',
    'globetrotter_monthly': r'$6.89',
    'globetrotter_yearly': r'$68.99',
  };

  bool _yearly = false;
  bool _busy = false;
  Map<String, Package> _packages = const {};

  @override
  void initState() {
    super.initState();
    PlanService.refresh();
    PurchaseService.packages().then((p) {
      if (mounted) setState(() => _packages = p);
    });
  }

  String _priceFor(String plan) {
    final key = '${plan}_${_yearly ? 'yearly' : 'monthly'}';
    return _packages[key]?.storeProduct.priceString ?? _fallbackPrices[key] ?? '';
  }

  String? _perMonthFor(String plan) {
    if (!_yearly) return null;
    final p = _packages['${plan}_yearly']?.storeProduct;
    if (p != null) return '≈ ${p.currencyCode} ${(p.price / 12).toStringAsFixed(2)} a month';
    return plan == 'voyager' ? r'≈ $3.83 a month' : r'≈ $5.75 a month';
  }

  Future<void> _buy(String plan) async {
    final key = '${plan}_${_yearly ? 'yearly' : 'monthly'}';
    final package = _packages[key];
    if (package == null) {
      _snack("The store isn't available right now. Please try again in a moment.");
      PurchaseService.packages().then((p) {
        if (mounted) setState(() => _packages = p);
      });
      return;
    }
    setState(() => _busy = true);
    final outcome = await PurchaseService.buy(package);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseOutcome.purchased:
        _snack('Welcome to ${plan == 'voyager' ? 'Voyager' : 'Globetrotter'}!');
        break;
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.failed:
      case PurchaseOutcome.unavailable:
        _snack("The purchase didn't go through. You have not been charged.");
        break;
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final ok = await PurchaseService.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    final plan = PlanService.status.value;
    _snack(!ok
        ? "Couldn't reach the store. Please try again."
        : (plan != null && plan.isPaid)
            ? 'Restored: you are on ${plan.planName}.'
            : 'No subscription was found for this account.');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Map<String, dynamic> _limitsFor(PlanStatus? s, String plan) {
    for (final c in s?.catalog ?? const <Map<String, dynamic>>[]) {
      if (c['plan'] == plan && c['limits'] is Map) {
        return Map<String, dynamic>.from(c['limits'] as Map);
      }
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text('Choose your plan',
            style: text.titleLarge?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: ValueListenableBuilder<PlanStatus?>(
        valueListenable: PlanService.status,
        builder: (context, status, _) {
          final current = status?.plan ?? 'explorer';
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  _periodSwitch(text),
                  const SizedBox(height: 18),
                  _PlanCard(
                    name: 'Explorer',
                    tier: 'Free',
                    price: 'Free',
                    rows: _rows('explorer', _limitsFor(status, 'explorer')),
                    isCurrent: current == 'explorer',
                    accent: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 14),
                  _PlanCard(
                    name: 'Voyager',
                    tier: 'Pro',
                    price: _priceFor('voyager'),
                    period: _yearly ? 'a year' : 'a month',
                    perMonth: _perMonthFor('voyager'),
                    rows: _rows('voyager', _limitsFor(status, 'voyager')),
                    isCurrent: current == 'voyager',
                    accent: AppColors.brandGreen,
                    onChoose: _busy || current == 'voyager' ? null : () => _buy('voyager'),
                  ),
                  const SizedBox(height: 14),
                  _PlanCard(
                    name: 'Globetrotter',
                    tier: 'Next level',
                    price: _priceFor('globetrotter'),
                    period: _yearly ? 'a year' : 'a month',
                    perMonth: _perMonthFor('globetrotter'),
                    rows: _rows('globetrotter', _limitsFor(status, 'globetrotter')),
                    isCurrent: current == 'globetrotter',
                    accent: const Color(0xFF0B3D91),
                    onChoose: _busy || current == 'globetrotter' ? null : () => _buy('globetrotter'),
                  ),
                  const SizedBox(height: 22),
                  _footer(text, status),
                ],
              ),
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x33000000),
                    child: Center(child: CircularProgressIndicator(color: AppColors.brandGreen)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _periodSwitch(TextTheme text) {
    Widget option(String label, bool yearly) {
      final selected = _yearly == yearly;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _yearly = yearly),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.charcoal : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: text.labelLarge?.copyWith(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [option('Monthly', false), option('Yearly · save ~17%', true)]),
    );
  }

  int _n(Map<String, dynamic> l, String k, int d) => (l[k] is num) ? (l[k] as num).toInt() : d;

  /// The rows of the packages document, in its order and wording.
  List<(String, String)> _rows(String plan, Map<String, dynamic> l) {
    final explorer = plan == 'explorer';
    final odyssey = _n(l, 'odyssey_per_period', explorer ? 1 : (plan == 'voyager' ? 8 : 15));
    final days = _n(l, 'odyssey_max_days', explorer ? 5 : (plan == 'voyager' ? 10 : 14));
    final neva = _n(l, 'neva_per_day', explorer ? 20 : (plan == 'voyager' ? 100 : 300));
    final arKm = (_n(l, 'ar_radius_m', explorer ? 2000 : 10000) / 1000).round();
    final lite = l['odyssey_lite'] ?? explorer;
    return [
      ('Odyssey plans per month',
          explorer ? '$odyssey Lite plan${odyssey == 1 ? '' : 's'}' : '$odyssey full plans'),
      ('Longest trip', '$days days'),
      ('Ratings and opening hours checked', lite == true ? 'Hidden' : 'Shown'),
      ('Booking plan with partner links', 'Yes'),
      ('Neva messages per day', plan == 'globetrotter' ? '$neva (fair use)' : '$neva'),
      ('AR view range', explorer ? '$arKm km' : 'Up to $arKm km'),
      ('Around You / Discover distance',
          explorer ? 'Nearest 2 bands (up to 25 km)\nMedical / Hospital: full range' : 'All 3 bands (up to 50 km)'),
      ('Live map data', explorer ? 'Daily limit' : (plan == 'voyager' ? 'Higher limit' : 'Highest limit')),
      ('Journal, stories, forum, Experiences', 'Yes'),
      ('Plan queue (Odyssey)', l['priority_queue'] == true ? 'Priority' : 'Standard'),
    ];
  }

  Widget _footer(TextTheme text, PlanStatus? status) {
    final store = (!Platform.isIOS) ? 'Google Play' : 'App Store';
    final account = (!Platform.isIOS) ? 'Google account' : 'Apple ID';
    final small = text.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.4);
    final link = text.bodySmall?.copyWith(
        color: AppColors.brandGreen, fontWeight: FontWeight.w700, decoration: TextDecoration.underline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _busy ? null : _restore,
              child: Text('Restore purchases', style: link),
            ),
            if (status != null && status.isPaid && status.store != 'admin')
              TextButton(
                onPressed: PurchaseService.manage,
                child: Text('Manage subscription', style: link),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Payment is charged to your $account when you confirm. Subscriptions renew '
          'automatically at the same price for the same period unless cancelled at least '
          '24 hours before the period ends. You can cancel or change your plan any time in '
          'your $store subscription settings.',
          style: small,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => launchUrl(Uri.parse(_termsUrl), mode: LaunchMode.externalApplication),
              child: Text('Terms of Use', style: link),
            ),
            Text('·', style: small),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
              child: Text('Privacy Policy', style: link),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String tier;
  final String price;
  final String? period;
  final String? perMonth;
  final List<(String, String)> rows;
  final bool isCurrent;
  final Color accent;
  final VoidCallback? onChoose;

  const _PlanCard({
    required this.name,
    required this.tier,
    required this.price,
    required this.rows,
    required this.isCurrent,
    required this.accent,
    this.period,
    this.perMonth,
    this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isCurrent ? accent : AppColors.border, width: isCurrent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name,
                  style: text.titleLarge?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tier,
                    style: text.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (isCurrent)
                Text('Your plan',
                    style: text.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price,
                  style: text.headlineSmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              if (period != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(period!, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
          if (perMonth != null)
            Text(perMonth!, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(label, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: Text(value,
                        style: text.bodySmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          if (onChoose != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onChoose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Choose $name',
                    style: text.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
