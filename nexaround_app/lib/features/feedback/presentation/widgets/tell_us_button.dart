import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/feedback_page.dart';
import 'package:nexaround_app/features/feedback/presentation/widgets/survey_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The round "Tell us" button on Home, bottom right above the menu bar
/// (client, 2026-11-26: the "Your voice" card sits too low on Home for most
/// explorers to reach it).
///
/// Tapping it opens a quick menu: the quarterly survey while one is waiting
/// for this explorer, then Suggestion / Improvement / Problem / Love it, each
/// opening the Feedback page with that choice picked. A one-time tip
/// introduces it, and an amber "1" shows while a survey is waiting.
class TellUsButton extends StatefulWidget {
  const TellUsButton({super.key});

  /// Where Home places it: just above the floating menu bar, which is 72 high
  /// and sits 20 from the bottom of the screen.
  static const double right = 14;
  static const double bottom = 100;

  /// The circle, and the circle with its "Tell us" label under it.
  static const double _circle = 60;
  static const double _width = 72;
  static const double _height = 74;

  @override
  State<TellUsButton> createState() => _TellUsButtonState();
}

class _TellUsButtonState extends State<TellUsButton> with SingleTickerProviderStateMixin {
  static const _tipSeenKey = 'tell_us_tip_seen_v1';

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _tipTimer;
  bool _tip = false;

  @override
  void initState() {
    super.initState();
    _tipTimer = Timer(const Duration(seconds: 2), _maybeShowTip);
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// The tip shows once ever, while Home is really on screen: the Home tab is
  /// selected (its TickerMode is on) and nothing is open on top of it.
  Future<void> _maybeShowTip() async {
    if (!mounted) return;
    final onScreen = TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? false);
    if (!onScreen) {
      _tipTimer = Timer(const Duration(seconds: 3), _maybeShowTip);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_tipSeenKey) ?? false) return;
    await prefs.setBool(_tipSeenKey, true);
    if (!mounted) return;
    setState(() => _tip = true);
    _tipTimer = Timer(const Duration(seconds: 9), _hideTip);
    // A soft ring pulses three times, then stops for good.
    for (var i = 0; i < 3 && mounted && _tip; i++) {
      try {
        await _pulse.forward(from: 0).orCancel;
      } catch (_) {
        return; // disposed mid-pulse
      }
    }
  }

  void _hideTip() {
    _tipTimer?.cancel();
    if (mounted && _tip) setState(() => _tip = false);
  }

  Future<void> _openMenu() async {
    _hideTip();
    final state = FeedbackService.surveyState.value;
    final round = state != null && state.showTicket ? state.round : null;
    final pick = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => _TellUsMenu(withSurvey: round != null),
      transitionBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );
    if (!mounted || pick == null) return;
    if (pick == 'survey' && round != null) {
      await showSurveySheet(context, round);
    } else {
      await openFeedbackPage(context, type: pick, source: 'tell_us');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, alignment: Alignment.centerRight, child: child),
          ),
          child: _tip
              ? Padding(
                  key: const ValueKey('tip'),
                  padding: const EdgeInsets.only(right: 10, bottom: 18),
                  child: _Tip(onClose: _hideTip),
                )
              : const SizedBox.shrink(key: ValueKey('no-tip')),
        ),
        Semantics(
          button: true,
          label: 'Tell us. Send a suggestion, a problem or anything else.',
          child: GestureDetector(
            onTap: _openMenu,
            child: SizedBox(
              width: TellUsButton._width,
              height: TellUsButton._height,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // The first-visit pulse.
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) {
                      final v = _pulse.value;
                      if (v == 0 || v == 1) return const SizedBox.shrink();
                      return Transform.scale(
                        scale: 1 + v * 0.5,
                        child: Opacity(
                          opacity: (1 - v) * 0.7,
                          child: Container(
                            width: TellUsButton._circle,
                            height: TellUsButton._circle,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: FeedbackVocab.mint.withValues(alpha: 0.35),
                              border: Border.all(color: FeedbackVocab.teal.withValues(alpha: 0.4), width: 1.5),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const _Circle(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: const Color(0xFFD7EEEA)),
                          boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        child: const Text('Tell us',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: FeedbackVocab.tealDark)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ).animate().fade(duration: 300.ms, delay: 400.ms).scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1));
  }
}

/// The teal circle: a chat bubble with a small amber sparkle, and an amber
/// "1" while a survey is waiting for this explorer.
class _Circle extends StatelessWidget {
  const _Circle();

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x2E000000), blurRadius: 3, offset: Offset(0, 2))];
    return Container(
      width: TellUsButton._circle,
      height: TellUsButton._circle,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA59A), FeedbackVocab.teal, Color(0xFF004F52)],
          stops: [0, 0.5, 1],
        ),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x73005457), blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // A soft shine at the top left.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.45, -0.7),
                  radius: 0.9,
                  colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
          const SizedBox(
            width: 30,
            height: 30,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 0, top: 3, child: Icon(Icons.sms_rounded, size: 27, color: Colors.white, shadows: shadow)),
              Positioned(
                right: -7,
                top: -6,
                child: Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFFFDBA4D), shadows: shadow),
              ),
            ]),
          ),
          ValueListenableBuilder<SurveyState?>(
            valueListenable: FeedbackService.surveyState,
            builder: (_, s, __) {
              if (s == null || !s.showTicket) return const SizedBox.shrink();
              return Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: const Text('1',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "NEW · Tell us what you want", shown once beside the button.
class _Tip extends StatelessWidget {
  const _Tip({required this.onClose});
  final VoidCallback onClose;

  static const _dark = Color(0xFF0B2A2A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 214,
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F3A3A), Color(0xFF0A2626)],
              ),
              boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 30, offset: Offset(0, 14))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: FeedbackVocab.mint, borderRadius: BorderRadius.circular(99)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFF063B3B)),
                    SizedBox(width: 4),
                    Text('NEW',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFF063B3B))),
                  ]),
                ),
                const SizedBox(height: 7),
                const Text('Tell us what you want',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.2, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Suggestions, problems or wishes. The team reads every one.',
                    style: TextStyle(fontSize: 12.8, height: 1.35, color: Colors.white.withValues(alpha: 0.78))),
                const SizedBox(height: 10),
                const Text('Got it', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: FeedbackVocab.mint)),
              ],
            ),
          ),
          // The pointer towards the button.
          Positioned(
            right: -6,
            bottom: 22,
            child: Transform.rotate(
              angle: 0.785,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: _dark, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The quick menu over a dimmed, blurred Home. Pops with the picked type
/// ('survey' for the survey), or nothing when closed.
class _TellUsMenu extends StatelessWidget {
  const _TellUsMenu({required this.withSurvey});
  final bool withSurvey;

  static const _types = ['suggestion', 'improvement', 'problem', 'love'];

  @override
  Widget build(BuildContext context) {
    // The close button sits exactly on the Tell us circle.
    const side = (TellUsButton._width - TellUsButton._circle) / 2;
    const closeBottom = TellUsButton.bottom + TellUsButton._height - TellUsButton._circle;
    final items = <Widget>[
      if (withSurvey)
        _MenuPill(
          icon: Icons.how_to_vote_rounded,
          color: Colors.white.withValues(alpha: 0.18),
          label: 'Quick survey',
          sub: '1 min · 5 questions',
          survey: true,
          onTap: () => Navigator.pop(context, 'survey'),
        ),
      for (final k in _types)
        _MenuPill(
          icon: FeedbackVocab.type(k).icon,
          color: FeedbackVocab.type(k).color,
          label: FeedbackVocab.type(k).label,
          onTap: () => Navigator.pop(context, k),
        ),
    ];
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: const ColoredBox(color: Color(0x8A041414)),
              ),
            ),
          ),
          Positioned(
            right: TellUsButton.right + side,
            bottom: closeBottom + TellUsButton._circle + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Tell us',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Colors.white)),
                    Text("What's it about?", style: TextStyle(fontSize: 13.5, color: Colors.white70)),
                  ]),
                ).animate().fadeIn(duration: 200.ms),
                const SizedBox(height: 14),
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  items[i]
                      .animate()
                      .fadeIn(duration: 180.ms, delay: (40 * (items.length - 1 - i)).ms)
                      .slideY(begin: 0.35, end: 0, duration: 220.ms, delay: (40 * (items.length - 1 - i)).ms, curve: Curves.easeOutCubic),
                ],
              ],
            ),
          ),
          Positioned(
            right: TellUsButton.right + side,
            bottom: closeBottom,
            child: Semantics(
              button: true,
              label: 'Close',
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: TellUsButton._circle,
                  height: TellUsButton._circle,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 22, offset: Offset(0, 10))],
                  ),
                  child: const Icon(Icons.close_rounded, size: 30, color: Color(0xFF14201F)),
                ),
              ),
            ).animate().rotate(begin: -0.125, end: 0, duration: 220.ms, curve: Curves.easeOutCubic),
          ),
        ],
      ),
    );
  }
}

/// One choice in the quick menu: a white pill with a coloured round icon, or
/// the teal survey pill with its "1 min" line.
class _MenuPill extends StatelessWidget {
  const _MenuPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.sub,
    this.survey = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String? sub;
  final bool survey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = survey ? Colors.white : const Color(0xFF14201F);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
          decoration: BoxDecoration(
            color: survey ? null : Colors.white,
            gradient: survey
                ? const LinearGradient(colors: [Color(0xFF00555A), FeedbackVocab.teal, Color(0xFF0E9A8F)])
                : null,
            borderRadius: BorderRadius.circular(99),
            boxShadow: const [BoxShadow(color: Color(0x3D000000), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                child: Icon(icon, size: 21, color: Colors.white),
              ),
              const SizedBox(width: 10),
              if (sub == null)
                Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg))
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.15, color: fg)),
                    Text(sub!,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.78))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
