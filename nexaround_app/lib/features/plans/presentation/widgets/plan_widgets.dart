import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/plan_service.dart';
import 'package:nexaround_app/features/plans/presentation/pages/plans_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sits above every screen (MaterialApp.builder) and opens the plans sheet
/// whenever the app runs into a plan limit, wherever that happened.
class PlanLimitListener extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const PlanLimitListener({super.key, required this.navigatorKey, required this.child});

  @override
  State<PlanLimitListener> createState() => _PlanLimitListenerState();
}

class _PlanLimitListenerState extends State<PlanLimitListener> {
  StreamSubscription<PlanLimitEvent>? _sub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _sub = PlanService.limitEvents.listen(_onLimit);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onLimit(PlanLimitEvent event) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || _showing) return;
    _showing = true;
    try {
      await showModalBottomSheet<void>(
        context: ctx,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetContext) => _PlanLimitSheet(
          event: event,
          onSeePlans: () {
            Navigator.of(sheetContext).pop();
            final nav = widget.navigatorKey.currentState;
            nav?.push(MaterialPageRoute(builder: (_) => const PlansPage()));
          },
        ),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PlanLimitSheet extends StatelessWidget {
  final PlanLimitEvent event;
  final VoidCallback onSeePlans;

  const _PlanLimitSheet({required this.event, required this.onSeePlans});

  String get _title {
    switch (event.feature) {
      case 'odyssey':
        return "You've used this month's Odyssey plans";
      case 'odyssey_days':
        return 'Longer trips need a bigger plan';
      case 'neva':
        return "You've used today's Neva messages";
      case 'ar_range':
        return 'See further in AR';
      case 'bands':
        return 'See places further away';
      case 'live_map':
        return "Today's live map updates are used up";
      default:
        return 'Upgrade your plan';
    }
  }

  String get _body {
    final when = event.resetsAt?.toLocal();
    switch (event.feature) {
      case 'odyssey':
        return 'Your plan includes ${event.limit ?? 'a set number of'} Odyssey '
            'plan${event.limit == 1 ? '' : 's'} a month'
            '${when != null ? ' and renews on ${_date(when)}' : ''}. '
            'Voyager gives you 8 full plans and Globetrotter 15.';
      case 'odyssey_days':
        return 'Explorer plans trips of up to 5 days. Voyager goes to 10 days and Globetrotter to 14.';
      case 'neva':
        return 'Neva is back at midnight (UTC). Voyager includes 100 messages a day and Globetrotter 300.';
      case 'ar_range':
        return 'Explorer shows places within 2 km in AR. Voyager and Globetrotter reach 10 km.';
      case 'bands':
        return 'Explorer shows the nearest two distance bands. Voyager and Globetrotter show all three.';
      case 'live_map':
        return "You're seeing places we've already saved. Voyager and Globetrotter include far more live updates.";
      default:
        return event.message;
    }
  }

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            const Icon(Icons.workspace_premium_rounded, color: AppColors.brandGreen, size: 34),
            const SizedBox(height: 10),
            Text(_title,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_body,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onSeePlans,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('See plans',
                  style: text.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Not now', style: text.labelLarge?.copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "My plan" on the profile page: the plan, what is left, and the way in to
/// the plans screen.
class MyPlanCard extends StatefulWidget {
  const MyPlanCard({super.key});

  @override
  State<MyPlanCard> createState() => _MyPlanCardState();
}

class _MyPlanCardState extends State<MyPlanCard> {
  @override
  void initState() {
    super.initState();
    PlanService.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<PlanStatus?>(
      valueListenable: PlanService.status,
      builder: (context, s, _) {
        final name = s?.planName ?? 'Explorer';
        final paid = s?.isPaid ?? false;
        String detail;
        if (s == null) {
          detail = 'See what each plan includes';
        } else if (!s.enforced) {
          detail = paid ? 'Thank you for subscribing' : 'Free plan';
        } else {
          detail = '${s.odysseyLeft} of ${s.odysseyPerPeriod} Odyssey plan'
              '${s.odysseyPerPeriod == 1 ? '' : 's'} left · '
              '${s.nevaLeft} Neva messages today';
        }
        if (s?.status == 'billing_issue') {
          detail = 'Payment problem: please update your payment method in the store';
        }
        return GestureDetector(
          onTap: () => PlansPage.open(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: paid ? AppColors.charcoal : AppColors.brandGreenLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: paid ? AppColors.charcoal : AppColors.brandGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_rounded,
                    color: paid ? Colors.white : AppColors.brandGreen, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$name plan',
                          style: text.titleMedium?.copyWith(
                              color: paid ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(detail,
                          style: text.bodySmall?.copyWith(
                              color: paid ? Colors.white70 : AppColors.textSecondary)),
                    ],
                  ),
                ),
                Text(paid ? 'Manage' : 'Upgrade',
                    style: text.labelLarge?.copyWith(
                        color: paid ? Colors.white : AppColors.brandGreen, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: paid ? Colors.white : AppColors.brandGreen),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Under an Around You section on Explorer: the farthest band, shown locked.
class LockedBandRow extends StatelessWidget {
  final Color themeColor;
  final double fromKm;
  final double toKm;

  const LockedBandRow({super.key, required this.themeColor, required this.fromKm, required this.toKm});

  String _km(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => PlansPage.open(context),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: themeColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: themeColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_rounded, size: 14, color: themeColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Places ${_km(fromKm)}–${_km(toKm)} km away · Voyager',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: themeColor, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: themeColor),
          ],
        ),
      ),
    );
  }
}

/// Shown instead of the app when this build is older than the server's
/// `min_app_version`: plans need the plans screen that newer builds have.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

  static const _androidUrl = 'https://play.google.com/store/apps/details?id=com.nexaround.app';
  static const _iosUrl = 'https://apps.apple.com/app/nexaround/id6806252363';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.system_update_rounded, size: 56, color: AppColors.brandGreen),
              const SizedBox(height: 18),
              Text('Please update nexARound',
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'This version is no longer supported. Update to the latest version to keep exploring.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => launchUrl(
                  Uri.parse(Platform.isIOS ? _iosUrl : _androidUrl),
                  mode: LaunchMode.externalApplication,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Update now',
                    style: text.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
