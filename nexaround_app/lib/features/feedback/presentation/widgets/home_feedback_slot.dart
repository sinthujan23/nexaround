import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/feedback_page.dart';
import 'package:nexaround_app/features/feedback/presentation/widgets/survey_sheet.dart';

/// The card under the Forum banner on Home (client request, 2026-11-26).
///
/// Normally "Tell us what you want" (the "Your voice" card). While a quarterly
/// survey is open and this explorer hasn't answered, the same slot shows the
/// survey ticket instead, and the survey pops up by itself once after 20
/// seconds on Home (the server decides whether it may: "Later" hides it for 3
/// days, at most 3 times a round, never in an account's first day).
class HomeFeedbackSlot extends StatefulWidget {
  const HomeFeedbackSlot({super.key});

  @override
  State<HomeFeedbackSlot> createState() => _HomeFeedbackSlotState();
}

class _HomeFeedbackSlotState extends State<HomeFeedbackSlot> {
  static const _popUpAfter = Duration(seconds: 20);

  /// One pop-up per app run at most, whatever the server allows.
  static bool _poppedThisRun = false;

  final _service = FeedbackService();
  SurveyState? _survey;
  Timer? _timer;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
    FeedbackService.surveyRevision.addListener(_load);
  }

  @override
  void dispose() {
    _timer?.cancel();
    FeedbackService.surveyRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _service.currentSurvey();
      if (!mounted) return;
      setState(() => _survey = s);
      FeedbackService.surveyState.value = s;
      _timer?.cancel();
      if (s.showTicket && s.autoShow && !_poppedThisRun) _timer = Timer(_popUpAfter, _maybePopUp);
    } catch (_) {
      // Signed out or offline: the plain feedback card is shown.
    }
  }

  /// Pops the survey up only while Home is really what the traveller sees:
  /// the Home tab is selected (its TickerMode is on), nothing is open on top
  /// of it, and the app is in the foreground. Otherwise it waits a bit more.
  void _maybePopUp() {
    if (!mounted || _poppedThisRun) return;
    final round = _survey?.round;
    if (round == null || !(_survey?.autoShow ?? false)) return;
    final onScreen = TickerMode.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? false) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!onScreen) {
      _timer = Timer(_popUpAfter, _maybePopUp);
      return;
    }
    _poppedThisRun = true;
    _service.surveyShown(round.id).catchError((_) {});
    _openSurvey(round);
  }

  Future<void> _openSurvey(SurveyRound round) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showSurveySheet(context, round);
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _survey;
    final child = (s != null && s.showTicket)
        ? _SurveyTicket(onTap: () => _openSurvey(s.round!))
        : _YourVoiceCard(
            onOpen: ([type]) => openFeedbackPage(context, type: type, source: 'home'),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child),
    ).animate().fade(delay: 120.ms).slideY(begin: 0.1, end: 0);
  }
}

class _YourVoiceCard extends StatelessWidget {
  const _YourVoiceCard({required this.onOpen});
  final void Function([String? type]) onOpen;

  @override
  Widget build(BuildContext context) {
    Widget typeButton(String key) {
      final t = FeedbackVocab.type(key);
      return GestureDetector(
        onTap: () => onOpen(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(t.icon, size: 16, color: t.color),
            const SizedBox(width: 5),
            Text(t.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black)),
          ]),
        ),
      );
    }

    return GestureDetector(
      key: const ValueKey('your-voice'),
      onTap: () => onOpen(),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF1FBF9), Color(0xFFE3F5F2), Color(0xFFFFF7EA)],
            stops: [0, 0.55, 1],
          ),
          border: Border.all(color: const Color(0xFFCDEBE6)),
          boxShadow: [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.12), blurRadius: 26, offset: const Offset(0, 10))],
        ),
        child: Stack(children: [
          // A soft mint glow behind the bubbles.
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 170,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [FeedbackVocab.mint.withValues(alpha: 0.45), FeedbackVocab.mint.withValues(alpha: 0)]),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 14,
            child: SizedBox(
              width: 86,
              height: 70,
              child: Stack(children: [
                Positioned(
                  right: 0,
                  top: 0,
                  child: Transform.rotate(
                    angle: 0.14,
                    child: Container(
                      width: 58,
                      height: 44,
                      decoration: BoxDecoration(
                        color: FeedbackVocab.teal,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16), topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4),
                        ),
                        boxShadow: [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
                      ),
                      child: const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 26,
                  child: Transform.rotate(
                    angle: -0.17,
                    child: Container(
                      width: 48,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDBA4D),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14), topRight: Radius.circular(14),
                          bottomRight: Radius.circular(4), bottomLeft: Radius.circular(14),
                        ),
                        boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
                      ),
                      child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 19),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.campaign_rounded, size: 13, color: FeedbackVocab.teal),
                    SizedBox(width: 5),
                    Text('YOUR VOICE',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: FeedbackVocab.teal)),
                  ]),
                ),
                const SizedBox(height: 9),
                const Padding(
                  padding: EdgeInsets.only(right: 96),
                  child: Text('Tell us what you want',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2, color: Colors.black)),
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(right: 90),
                  child: Text('Suggestions, problems or wishes. The team reads every one.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF4B5A5A), height: 1.4)),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        typeButton('suggestion'),
                        const SizedBox(width: 7),
                        typeButton('improvement'),
                        const SizedBox(width: 7),
                        typeButton('problem'),
                        const SizedBox(width: 7),
                        typeButton('love'),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: FeedbackVocab.teal, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The survey as a ticket: a tear line at 72% with notches top and bottom,
/// echoing Trip Split's boarding passes.
class _SurveyTicket extends StatelessWidget {
  const _SurveyTicket({required this.onTap});
  final VoidCallback onTap;

  static const _tear = 0.72;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('survey-ticket'),
      onTap: onTap,
      child: SizedBox(
        height: 150,
        child: PhysicalShape(
          clipper: const _TicketClipper(_tear),
          color: FeedbackVocab.teal,
          elevation: 10,
          shadowColor: const Color(0x66005052),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF004547), FeedbackVocab.teal]),
            ),
            child: LayoutBuilder(builder: (context, box) {
              final tearX = box.maxWidth * _tear;
              return Stack(children: [
                Positioned(
                  left: -30,
                  top: -60,
                  child: Container(
                    width: 180,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [FeedbackVocab.mint.withValues(alpha: 0.35), FeedbackVocab.mint.withValues(alpha: 0)]),
                    ),
                  ),
                ),
                Positioned(left: tearX - 1, top: 18, bottom: 18, child: const CustomPaint(size: Size(2, double.infinity), painter: _DashPainter())),
                Positioned(
                  left: 18,
                  top: 16,
                  width: tearX - 30,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.how_to_vote_rounded, size: 14, color: FeedbackVocab.mint),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text('QUICK SURVEY',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: FeedbackVocab.mint)),
                        ),
                      ]),
                      const SizedBox(height: 7),
                      const Text('Help shape the next NexAround update',
                          maxLines: 2,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.2, color: Colors.white)),
                      const SizedBox(height: 12),
                      Row(children: [
                        for (var i = 0; i < 5; i++) ...[
                          Container(
                            width: 16,
                            height: 5,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(9)),
                          ),
                          const SizedBox(width: 4),
                        ],
                        const SizedBox(width: 2),
                        Text('5 questions', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
                      ]),
                    ],
                  ),
                ),
                Positioned(
                  left: tearX,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
                        ),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('1', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                          Text('MIN', style: TextStyle(fontSize: 9, color: Colors.white70, height: 1.2)),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                        child: const Text('Start',
                            style: TextStyle(color: FeedbackVocab.tealDark, fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                    ],
                  ),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper(this.tear);
  final double tear;

  @override
  Path getClip(Size size) {
    const r = 13.0;
    final x = size.width * tear;
    final card = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, 0), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(x, size.height), radius: r));
    return Path.combine(PathOperation.difference, card, notches);
  }

  @override
  bool shouldReclip(covariant _TicketClipper oldClipper) => oldClipper.tear != tear;
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    for (double y = 0; y < size.height; y += 9) {
      final end = y + 5 > size.height ? size.height : y + 5;
      canvas.drawLine(Offset(0, y), Offset(0, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
