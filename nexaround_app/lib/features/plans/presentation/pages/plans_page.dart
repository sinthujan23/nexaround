import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/plan_service.dart';
import 'package:nexaround_app/core/services/purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// One plan as the screen draws it. Limits come from the server's catalog;
/// these are the parts that never change: name, label, photo and colour.
class _PlanLook {
  final String key;
  final String name;
  final String tag;
  final String tagline;
  final String photo;
  final Color color;

  /// How far the photo is pulled up, as a share of the card's height, so its
  /// subject sits in the part above the white sheet instead of behind it.
  final double lift;

  const _PlanLook(this.key, this.name, this.tag, this.tagline, this.photo, this.color, this.lift);
}

const _plans = <_PlanLook>[
  _PlanLook('explorer', 'Explorer', 'FREE', 'For new and casual travellers',
      'assets/images/plan_explorer.jpg', Color(0xFF64748B), 0.67),
  _PlanLook('voyager', 'Voyager', 'PRO · MOST POPULAR', 'For someone planning a real trip soon',
      'assets/images/plan_voyager.jpg', Color(0xFF007A7C), 0.25),
  _PlanLook('globetrotter', 'Globetrotter', 'NEXT LEVEL', 'For frequent travellers, families and creators',
      'assets/images/plan_globetrotter.jpg', Color(0xFF0B3D91), 0.15),
];

/// Explorer / Voyager / Globetrotter as swipe cards ("A2", picked 2026-11-11):
/// each plan's photo fills its card, a white sheet at the bottom holds the
/// price, four highlights and the button, and the screen behind takes on the
/// photo of the plan in view.
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

  late final PageController _pager;
  int _index = 1; // Voyager first: the most popular plan
  bool _yearly = false;
  bool _busy = false;
  Map<String, Package> _packages = const {};

  @override
  void initState() {
    super.initState();
    if (PlanService.status.value?.plan == 'globetrotter') _index = 2;
    _pager = PageController(viewportFraction: 0.8, initialPage: _index);
    PlanService.refresh();
    PurchaseService.packages().then((p) {
      if (mounted) setState(() => _packages = p);
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  // ── Prices ───────────────────────────────────────────────────────────────

  String _priceFor(String plan) {
    final key = '${plan}_${_yearly ? 'yearly' : 'monthly'}';
    return _packages[key]?.storeProduct.priceString ?? _fallbackPrices[key] ?? '';
  }

  String? _perMonthFor(String plan) {
    if (!_yearly || plan == 'explorer') return null;
    final p = _packages['${plan}_yearly']?.storeProduct;
    if (p != null) return '≈ ${p.currencyCode} ${(p.price / 12).toStringAsFixed(2)} a month';
    return plan == 'voyager' ? r'≈ $3.83 a month' : r'≈ $5.75 a month';
  }

  // ── Actions ──────────────────────────────────────────────────────────────

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

  // ── Limits → words ───────────────────────────────────────────────────────

  Map<String, dynamic> _limitsFor(PlanStatus? s, String plan) {
    for (final c in s?.catalog ?? const <Map<String, dynamic>>[]) {
      if (c['plan'] == plan && c['limits'] is Map) {
        return Map<String, dynamic>.from(c['limits'] as Map);
      }
    }
    return const {};
  }

  int _n(Map<String, dynamic> l, String k, int d) => (l[k] is num) ? (l[k] as num).toInt() : d;

  /// The four highlights on a card.
  List<(IconData, String)> _highlights(String plan, Map<String, dynamic> l) {
    final explorer = plan == 'explorer';
    final odyssey = _n(l, 'odyssey_per_period', explorer ? 1 : (plan == 'voyager' ? 8 : 15));
    final days = _n(l, 'odyssey_max_days', explorer ? 5 : (plan == 'voyager' ? 10 : 14));
    final neva = _n(l, 'neva_per_day', explorer ? 20 : (plan == 'voyager' ? 100 : 300));
    final arKm = (_n(l, 'ar_radius_m', explorer ? 2000 : 10000) / 1000).round();
    return [
      (Icons.map_outlined, explorer ? '$odyssey Lite plan' : '$odyssey Odyssey plans'),
      (Icons.calendar_today_outlined, 'Trips to $days days'),
      (Icons.chat_bubble_outline_rounded, '$neva Neva / day'),
      if (plan == 'globetrotter' && l['priority_queue'] != false)
        (Icons.bolt_rounded, 'Priority queue')
      else
        (Icons.view_in_ar_outlined, explorer ? 'AR $arKm km' : 'AR up to $arKm km'),
    ];
  }

  /// Every row of the packages document, in its order and wording.
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

  // ── Screen ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1B1C),
        body: ValueListenableBuilder<PlanStatus?>(
          valueListenable: PlanService.status,
          builder: (context, status, _) {
            final current = status?.plan ?? 'explorer';
            return Stack(
              children: [
                // The screen takes on the plan in view: its photo, blurred.
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    child: _Backdrop(key: ValueKey(_index), photo: _plans[_index].photo),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      _header(text),
                      _periodSwitch(text),
                      Expanded(
                        child: PageView.builder(
                          controller: _pager,
                          itemCount: _plans.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (context, i) => AnimatedScale(
                            scale: i == _index ? 1 : 0.92,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              child: _card(text, _plans[i], _limitsFor(status, _plans[i].key),
                                  current: current == _plans[i].key, userPlan: current),
                            ),
                          ),
                        ),
                      ),
                      _dots(),
                      _footer(text, status),
                    ],
                  ),
                ),
                if (_busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18, semanticLabel: 'Back'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose your plan',
                    style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                Text('Swipe to compare',
                    style: text.bodySmall?.copyWith(color: const Color(0xFFD3E4E4))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodSwitch(TextTheme text) {
    Widget option(String label, bool yearly) {
      final selected = _yearly == yearly;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _yearly = yearly),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              label,
              style: text.labelLarge?.copyWith(
                color: selected ? AppColors.charcoal : const Color(0xFFD3E4E4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(children: [option('Monthly', false), const SizedBox(width: 4), option('Yearly · save 17%', true)]),
    );
  }

  Widget _card(TextTheme text, _PlanLook p, Map<String, dynamic> limits,
      {required bool current, required String userPlan}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 20))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: LayoutBuilder(
          builder: (context, box) {
            // Small phones: the sheet drops its secondary lines so the photo
            // still shows above it.
            final compact = box.maxHeight < 470;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Taller than the card and anchored to its bottom: the top of
                // the photo is cropped so its subject shows above the sheet.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: -box.maxHeight * p.lift,
                  child: Image.asset(p.photo, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: Text(current ? 'YOUR PLAN' : p.tag,
                        style: text.labelSmall?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: _sheet(text, p, limits, current: current, userPlan: userPlan, compact: compact),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sheet(TextTheme text, _PlanLook p, Map<String, dynamic> limits,
      {required bool current, required String userPlan, required bool compact}) {
    final explorer = p.key == 'explorer';
    final perMonth = _perMonthFor(p.key);
    final highlights = _highlights(p.key, limits);

    String label;
    VoidCallback? onPressed;
    if (current) {
      label = 'Your plan';
    } else if (explorer) {
      label = 'Included with every plan';
    } else {
      label = 'Choose ${p.name}';
      onPressed = _busy ? null : () => _buy(p.key);
    }

    Widget chip((IconData, String) h) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(color: const Color(0xFFF1F7F7), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(h.$1, size: 16, color: p.color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(h.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(p.name,
                    style: text.headlineSmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              ),
              Text(explorer ? 'Free' : _priceFor(p.key),
                  style: text.titleLarge?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              if (!explorer)
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 3),
                  child: Text(_yearly ? '/ yr' : '/ mo',
                      style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ),
            ],
          ),
          if (perMonth != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(perMonth, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
            ),
          if (!compact) ...[
            const SizedBox(height: 2),
            Text(p.tagline, style: text.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Row(children: [chip(highlights[0]), const SizedBox(width: 8), chip(highlights[1])]),
          const SizedBox(height: 8),
          Row(children: [chip(highlights[2]), const SizedBox(width: 8), chip(highlights[3])]),
          InkWell(
            onTap: () => _showEverything(text, p, limits),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See everything included',
                      style: text.labelLarge?.copyWith(color: p.color, fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.color),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: p.color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE9ECEF),
                disabledForegroundColor: AppColors.textSecondary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(label,
                  style: text.labelLarge?.copyWith(
                      color: onPressed == null ? AppColors.textSecondary : Colors.white,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  void _showEverything(TextTheme text, _PlanLook p, Map<String, dynamic> limits) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Everything in ${p.name}',
                  style: text.titleMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final (label, value) in _rows(p.key, limits))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                            style: text.bodySmall
                                ?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _plans.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _index ? Colors.white : Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(TextTheme text, PlanStatus? status) {
    final store = Platform.isIOS ? 'App Store' : 'Google Play';
    final small = text.bodySmall?.copyWith(color: const Color(0xFFD3E4E4), fontSize: 11, height: 1.35);
    final link = text.bodySmall?.copyWith(
        color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.underline,
        decorationColor: Colors.white);
    Widget linkButton(String label, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: link),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          Text(
            'Renews automatically at the same price until cancelled at least 24 hours before '
            'the period ends. Cancel any time in your $store subscription settings.',
            style: small,
            textAlign: TextAlign.center,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              linkButton('Restore purchases', _busy ? () {} : _restore),
              if (status != null && status.isPaid && status.store != 'admin')
                linkButton('Manage subscription', PurchaseService.manage),
              linkButton('Terms', () => launchUrl(Uri.parse(_termsUrl), mode: LaunchMode.externalApplication)),
              linkButton('Privacy', () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The blurred, darkened photo behind the cards.
class _Backdrop extends StatelessWidget {
  final String photo;

  const _Backdrop({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Image.asset(photo, fit: BoxFit.cover, cacheWidth: 400),
        ),
        const ColoredBox(color: Color(0x990A1618)),
      ],
    );
  }
}
