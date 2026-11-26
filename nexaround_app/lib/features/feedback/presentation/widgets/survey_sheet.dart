import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';

/// The quarterly survey: an intro, five questions (one per screen) and a
/// thank-you. "Later" (or closing it) hides the pop-up for 3 days; the Home
/// card stays until the survey is answered or closed by the team.
Future<void> showSurveySheet(BuildContext context, SurveyRound round) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (_) => _SurveySheet(round: round),
  );
}

class _SurveySheet extends StatefulWidget {
  const _SurveySheet({required this.round});
  final SurveyRound round;

  @override
  State<_SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<_SurveySheet> {
  static const _questions = 5;
  final _service = FeedbackService();
  final _a = SurveyAnswer();
  final _other = TextEditingController();
  final _comment = TextEditingController();

  /// 0 = intro, 1..5 = questions, 6 = thanks.
  int _step = 0;
  bool _sending = false;

  @override
  void dispose() {
    _other.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _later() async {
    Navigator.pop(context);
    try {
      await _service.surveyLater(widget.round.id);
    } catch (_) {}
  }

  bool get _canGoOn => switch (_step) {
        1 => _a.nps != null,
        4 => _a.wouldPay != null && (_a.wouldPay == 'no' || _a.priceRange != null),
        _ => true,
      };

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step < _questions) {
      setState(() => _step++);
      return;
    }
    _a.buildNextOther = _other.text;
    _a.comment = _comment.text;
    setState(() => _sending = true);
    try {
      await _service.answerSurvey(widget.round.id, _a);
      if (mounted) setState(() => _step = _questions + 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FeedbackService.errorText(e, 'Your answers could not be sent. Please try again.'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: mq.size.height * 0.88,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
            child: Column(
              children: [
                Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(9))),
                const SizedBox(height: 14),
                if (_step >= 1 && _step <= _questions) _header(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(_step), child: _content()),
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Row(children: [
          Text('QUESTION $_step OF $_questions',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: FeedbackVocab.teal, letterSpacing: 0.3)),
          const Spacer(),
          GestureDetector(
            onTap: _later,
            child: const Row(children: [
              Text('Later', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
              SizedBox(width: 4),
              Icon(Icons.schedule_rounded, size: 17, color: AppColors.textMuted),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < _questions; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 5,
                decoration: BoxDecoration(
                  color: i < _step ? FeedbackVocab.teal : const Color(0xFFE9EDED),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _footer() {
    if (_step == 0) {
      return Column(children: [
        _primary('Start survey', Icons.arrow_forward_rounded, () => setState(() => _step = 1)),
        TextButton(
          onPressed: _later,
          child: const Text('Remind me later', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
        ),
      ]);
    }
    if (_step > _questions) return _primary('Done', null, () => Navigator.pop(context));
    final last = _step == _questions;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        if (_step > 1) ...[
          SizedBox(
            width: 56,
            height: 56,
            child: Material(
              color: const Color(0xFFF2F3F3),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => _step--),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: _primary(
            _sending ? 'Sending…' : last ? 'Send answers' : 'Next',
            last ? Icons.send_rounded : Icons.arrow_forward_rounded,
            _canGoOn && !_sending ? _next : null,
          ),
        ),
      ]),
    );
  }

  Widget _primary(String label, IconData? icon, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: FeedbackVocab.teal,
          disabledBackgroundColor: FeedbackVocab.teal.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20)],
        ]),
      ),
    );
  }

  Widget _question(String text, [String? hint]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, height: 1.22, letterSpacing: -0.3)),
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(hint, style: const TextStyle(fontSize: 14, color: AppColors.textTertiary)),
          ],
          const SizedBox(height: 16),
        ],
      );

  Widget _content() => switch (_step) {
        0 => _intro(),
        1 => _nps(),
        2 => _features(),
        3 => _buildNext(),
        4 => _pay(),
        5 => _commentStep(),
        _ => _thanks(),
      };

  // ── Intro ───────────────────────────────────────────────────────────────

  Widget _intro() {
    Widget bullet(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: const Color(0xFFEEF7F6), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: FeedbackVocab.teal),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, color: Color(0xFF333333)))),
          ]),
        );
    return SingleChildScrollView(
      child: Column(children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(onPressed: _later, icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary)),
        ),
        SizedBox(
          width: 150,
          height: 130,
          child: Stack(children: [
            Positioned(
              left: 25,
              top: 10,
              child: Transform.rotate(
                angle: -0.1,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(colors: [FeedbackVocab.teal, Color(0xFF004547)]),
                    boxShadow: [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 16))],
                  ),
                  child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 52),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Transform.rotate(
                angle: 0.2,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFFDBA4D), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 6,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 14, offset: Offset(0, 6))],
                ),
                child: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 22),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        const Text('Help shape the next\nNexAround update',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2)),
        const SizedBox(height: 10),
        const Text('Tell us how you use the app and what we should build next.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 22),
        bullet(Icons.timer_rounded, 'About 1 minute, 5 questions'),
        bullet(Icons.lock_rounded, 'Answers go only to the NexAround team'),
        bullet(Icons.event_repeat_rounded, 'We ask once every 3 months'),
      ]),
    );
  }

  // ── Q1: recommend 0–10 ──────────────────────────────────────────────────

  Widget _nps() {
    Color edge(int i) => i <= 6 ? const Color(0xFFF87171) : (i <= 8 ? const Color(0xFFFBBF24) : const Color(0xFF34D399));
    final n = _a.nps;
    final reply = n == null
        ? null
        : n >= 9
            ? (Icons.celebration_rounded, '$n · Great! Thanks, that means a lot to us.')
            : n >= 7
                ? (Icons.lightbulb_rounded, '$n · Thanks! What would make it a 10? Tell us in a moment.')
                : (Icons.handshake_rounded, '$n · Thanks for being honest. We\'ll keep improving.');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question('How likely are you to recommend NexAround to a friend?'),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.sentiment_dissatisfied_rounded, size: 20, color: Color(0xFFF87171)),
            SizedBox(width: 4),
            Text('Not likely', style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
            Spacer(),
            Text('Very likely', style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
            SizedBox(width: 4),
            Icon(Icons.sentiment_very_satisfied_rounded, size: 20, color: Color(0xFF34D399)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i <= 10; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _a.nps = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: n == i ? 56 : 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: n == i ? FeedbackVocab.teal : const Color(0xFFF3F5F5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border(bottom: BorderSide(color: edge(i), width: 4)),
                          boxShadow: n == i
                              ? [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))]
                              : null,
                        ),
                        child: Text('$i',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: n == i ? Colors.white : const Color(0xFF333333))),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (reply != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFEEF8F6), borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Icon(reply.$1, color: FeedbackVocab.teal, size: 26),
                const SizedBox(width: 12),
                Expanded(child: Text(reply.$2, style: const TextStyle(fontSize: 14.5, height: 1.4))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── Q2: features used ───────────────────────────────────────────────────

  Widget _features() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question('Which features do you use most?',
              'Pick as many as you like${_a.features.isEmpty ? '' : ' · ${_a.features.length} picked'}'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 0.98,
            children: [
              for (final f in FeedbackVocab.features)
                _tile(
                  icon: f.icon,
                  label: f.label,
                  on: _a.features.contains(f.key),
                  onTap: () => setState(() => _a.features.contains(f.key) ? _a.features.remove(f.key) : _a.features.add(f.key)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile({required IconData icon, required String label, required bool on, required VoidCallback onTap, Color? color}) {
    final c = color ?? FeedbackVocab.teal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        decoration: BoxDecoration(
          color: on ? FeedbackVocab.tint : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? FeedbackVocab.teal : const Color(0xFFECECEC), width: 1.5),
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: on ? c : const Color(0xFFF3F5F5), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 23, color: on ? Colors.white : const Color(0xFF4A5555)),
              ),
              const SizedBox(height: 7),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.15)),
            ]),
          ),
          if (on) const Positioned(top: 0, right: 0, child: Icon(Icons.check_circle_rounded, size: 18, color: FeedbackVocab.teal)),
        ]),
      ),
    );
  }

  // ── Q3: build next, ranked ──────────────────────────────────────────────

  Widget _buildNext() {
    final picks = _a.buildNext;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question('What should we build next?', 'Pick up to 3, in order${picks.isEmpty ? '' : ' · ${picks.length} picked'}'),
          for (final (i, o) in widget.round.options.indexed) _optionRow(o, i, picks.indexOf(o.key)),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD4D4D4), width: 1.5),
            ),
            child: Row(children: [
              const Icon(Icons.edit_rounded, size: 20, color: AppColors.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _other,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    hintText: 'Something else? Tell us…',
                    hintStyle: TextStyle(color: AppColors.textTertiary),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(SurveyOption o, int index, int rank) {
    final on = rank >= 0;
    final full = _a.buildNext.length >= 3;
    final color = FeedbackVocab.optionColor(index);
    return GestureDetector(
      onTap: () => setState(() {
        if (on) {
          _a.buildNext.remove(o.key);
        } else if (!full) {
          _a.buildNext.add(o.key);
        }
      }),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: !on && full ? 0.5 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: on ? FeedbackVocab.tint : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? FeedbackVocab.teal : const Color(0xFFECECEC), width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(FeedbackVocab.optionIcon(o.icon), size: 21, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(o.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? FeedbackVocab.teal : Colors.transparent,
                border: on ? null : Border.all(color: const Color(0xFFD4D4D4), width: 2),
              ),
              child: on ? Text('${rank + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)) : null,
            ),
          ]),
        ),
      ),
    );
  }

  // ── Q4: would you pay? ──────────────────────────────────────────────────

  Widget _pay() {
    Widget payTile(String key, IconData icon, String label, Color color) {
      final on = _a.wouldPay == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _a.wouldPay = key;
            if (key == 'no') _a.priceRange = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: on ? FeedbackVocab.tint : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: on ? FeedbackVocab.teal : const Color(0xFFECECEC), width: 1.5),
            ),
            child: Column(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: on ? color : color.withValues(alpha: 0.12)),
                child: Icon(icon, size: 23, color: on ? Colors.white : color),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
    }

    final pays = _a.wouldPay == 'yes' || _a.wouldPay == 'maybe';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question('Would you pay for NexAround?'),
          Row(children: [
            payTile('yes', Icons.thumb_up_rounded, 'Yes', const Color(0xFF10B981)),
            const SizedBox(width: 9),
            payTile('maybe', Icons.help_rounded, 'Maybe', const Color(0xFFF59E0B)),
            const SizedBox(width: 9),
            payTile('no', Icons.thumb_down_rounded, 'No', const Color(0xFFEF4444)),
          ]),
          const SizedBox(height: 22),
          if (pays) ..._priceLadder(),
          if (_a.wouldPay == 'no') ..._whyNot(),
        ],
      ),
    );
  }

  List<Widget> _priceLadder() {
    return [
      const Row(children: [
        Icon(Icons.calendar_month_rounded, size: 19, color: FeedbackVocab.teal),
        SizedBox(width: 6),
        Text('How much a month feels fair?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 2),
      const Text('In US dollars', style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
      const SizedBox(height: 14),
      SizedBox(
        height: 196,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, (key, label)) in FeedbackVocab.priceRanges.indexed) ...[
              if (i > 0) const SizedBox(width: 7),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _a.priceRange = key),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_a.priceRange == key)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(99)),
                          child: const Text('Fair', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: FeedbackVocab.teal)),
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 58.0 + i * 26,
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 9),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(14), bottom: Radius.circular(8)),
                          color: _a.priceRange == key ? null : const Color(0xFFEEF1F1),
                          gradient: _a.priceRange == key
                              ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF00A3A5), FeedbackVocab.teal])
                              : null,
                        ),
                        child: Icon(Icons.payments_rounded, size: 18, color: _a.priceRange == key ? Colors.white : const Color(0xFFB9C2C2)),
                      ),
                      const SizedBox(height: 7),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _a.priceRange == key ? FontWeight.w700 : FontWeight.w600,
                            color: _a.priceRange == key ? FeedbackVocab.teal : const Color(0xFF555555),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _whyNot() {
    return [
      const Text.rich(TextSpan(children: [
        TextSpan(text: 'What holds you back? ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        TextSpan(text: '(optional)', style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
      ])),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final w in FeedbackVocab.whyNot)
            GestureDetector(
              onTap: () => setState(() => _a.whyNot.contains(w.key) ? _a.whyNot.remove(w.key) : _a.whyNot.add(w.key)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: _a.whyNot.contains(w.key) ? FeedbackVocab.tint : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _a.whyNot.contains(w.key) ? FeedbackVocab.teal : const Color(0xFFECECEC), width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(w.icon, size: 19, color: _a.whyNot.contains(w.key) ? FeedbackVocab.teal : const Color(0xFF7A8585)),
                  const SizedBox(width: 7),
                  Text(w.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ],
      ),
    ];
  }

  // ── Q5: anything else ───────────────────────────────────────────────────

  Widget _commentStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question("Anything else you'd like to tell us?", 'Optional · write in any language'),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: FeedbackVocab.teal, width: 1.5),
              boxShadow: [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.08), spreadRadius: 4)],
            ),
            child: TextField(
              controller: _comment,
              minLines: 6,
              maxLines: 10,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Your thoughts…',
                hintStyle: TextStyle(color: AppColors.textTertiary),
              ),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Thanks ──────────────────────────────────────────────────────────────

  Widget _thanks() {
    const dots = [
      (40.0, 30.0, 10.0, Color(0xFFFDBA4D)), (190.0, 10.0, 8.0, FeedbackVocab.mint), (230.0, 70.0, 12.0, Color(0xFFF472B6)),
      (20.0, 110.0, 8.0, Color(0xFF60A5FA)), (210.0, 140.0, 9.0, Color(0xFF34D399)), (70.0, 150.0, 7.0, Color(0xFFFDBA4D)),
      (130.0, 0.0, 9.0, Color(0xFFA78BFA)),
    ];
    return SingleChildScrollView(
      child: Column(children: [
        const SizedBox(height: 40),
        SizedBox(
          width: 250,
          height: 180,
          child: Stack(children: [
            for (final d in dots)
              Positioned(
                left: d.$1,
                top: d.$2,
                child: Container(width: d.$3, height: d.$3, decoration: BoxDecoration(color: d.$4, borderRadius: BorderRadius.circular(3))),
              ),
            Positioned(
              left: 65,
              top: 30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF00A3A5), FeedbackVocab.tealDark]),
                  boxShadow: [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.35), blurRadius: 36, offset: const Offset(0, 18))],
                ),
                child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 62),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        const Text('Thank you!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Your answers help decide what we build next.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: const Color(0xFFF3F6F6), borderRadius: BorderRadius.circular(99)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_repeat_rounded, size: 18, color: FeedbackVocab.teal),
            SizedBox(width: 8),
            Text('Next survey in about 3 months', style: TextStyle(fontSize: 13.5, color: Color(0xFF4B5A5A))),
          ]),
        ),
      ]),
    );
  }
}
