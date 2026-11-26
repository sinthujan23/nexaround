import 'package:flutter/material.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/widgets/feedback_ui.dart';

/// The quarterly survey: an intro, five questions (one per screen) and a
/// thank-you. Closing it unanswered in any way ("Remind me later", Later, ✕,
/// dragging it down, tapping outside, Back) hides the pop-up for 3 days; the
/// Tell us button keeps offering it until it is answered or the team closes it.
Future<void> showSurveySheet(BuildContext context, SurveyRound round) async {
  var answered = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _SurveySheet(round: round, onAnswered: () => answered = true),
  );
  if (!answered) {
    try {
      await FeedbackService().surveyLater(round.id);
    } catch (_) {}
  }
}

class _SurveySheet extends StatefulWidget {
  const _SurveySheet({required this.round, required this.onAnswered});
  final SurveyRound round;
  final VoidCallback onAnswered;

  @override
  State<_SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<_SurveySheet> {
  static const _questions = 5;
  final _service = FeedbackService();
  final _a = SurveyAnswer();
  final _other = TextEditingController();
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();

  /// 0 = intro, 1..5 = questions, 6 = thanks.
  int _step = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _commentFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _other.dispose();
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  /// showSurveySheet snoozes the survey when it closes unanswered.
  void _later() => Navigator.pop(context);

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
      widget.onAnswered();
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

  /// The start and thank-you screens are only as tall as their content; the
  /// questions get a tall sheet with their content starting at the top.
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final question = _step >= 1 && _step <= _questions;
    final handle = Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(color: const Color(0xFFC9D3D2), borderRadius: BorderRadius.circular(3)),
    );
    final Widget body = question
        ? SizedBox(
            height: mq.size.height * 0.86,
            child: Column(
              children: [
                handle,
                const SizedBox(height: 14),
                _header(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
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
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(height: 18),
              Flexible(child: SingleChildScrollView(child: _step == 0 ? _intro() : _thanks())),
              _footer(),
            ],
          );
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 14), child: body),
        ),
      ),
    );
  }

  /// Back (or close on the first question), the 5-step progress bar, Later.
  Widget _header() {
    final first = _step == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          FeedbackCircleButton(
            icon: first ? Icons.close_rounded : Icons.arrow_back_rounded,
            label: first ? 'Later' : 'Back',
            onTap: first ? _later : () => setState(() => _step--),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                for (var i = 0; i < _questions; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < _step ? FeedbackVocab.teal : const Color(0xFFE3EAE9),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: _later,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Later', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: FeedbackUi.mute)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text('QUESTION $_step OF $_questions',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: FeedbackVocab.teal)),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _footer() {
    if (_step == 0) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        FeedbackPrimaryButton(
          label: 'Start survey',
          icon: Icons.arrow_forward_rounded,
          iconAfter: true,
          onTap: () => setState(() => _step = 1),
        ),
        TextButton(
          onPressed: _later,
          child: const Text('Remind me later',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FeedbackUi.sub)),
        ),
      ]);
    }
    if (_step > _questions) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FeedbackPrimaryButton(label: 'Done', onTap: () => Navigator.pop(context)),
      );
    }
    final last = _step == _questions;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: FeedbackPrimaryButton(
        label: _sending ? 'Sending…' : last ? 'Send answers' : 'Next',
        icon: last ? Icons.send_rounded : Icons.arrow_forward_rounded,
        iconAfter: !last,
        busy: _sending,
        onTap: _canGoOn ? _next : null,
      ),
    );
  }

  Widget _question(String text, [String? hint]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, height: 1.22, letterSpacing: -0.3, color: FeedbackUi.ink)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint, style: const TextStyle(fontSize: 13.5, color: FeedbackUi.mute)),
          ],
          const SizedBox(height: 16),
        ],
      );

  /// One question's screen (steps 1–5).
  Widget _content() => switch (_step) {
        1 => _nps(),
        2 => _features(),
        3 => _buildNext(),
        4 => _pay(),
        _ => _commentStep(),
      };

  /// A selectable tile used for features and "why not": a round icon and a
  /// one-line label that shrinks rather than wrapping.
  Widget _pickTile({required IconData icon, required String label, required bool on, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? FeedbackVocab.tint : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? FeedbackVocab.teal : FeedbackUi.line, width: 1.5),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 30,
              height: 30,
              decoration: BoxDecoration(shape: BoxShape.circle, color: on ? FeedbackVocab.teal : FeedbackUi.bg),
              child: Icon(icon, size: 17, color: on ? Colors.white : FeedbackVocab.teal),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      color: on ? FeedbackVocab.tealDark : FeedbackUi.ink,
                    )),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Two tiles per row.
  List<Widget> _pairs(List<Widget> tiles) => [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
            ]),
          ),
      ];

  // ── Intro ───────────────────────────────────────────────────────────────
  // The earlier design (the TL preferred it): the tilted vote card with a
  // bulb and a star, a centred title and three short promises.

  Widget _intro() {
    Widget bullet(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: const Color(0xFFEEF7F6), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: FeedbackVocab.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
            ),
          ]),
        );
    return Column(
      children: [
        SizedBox(
          width: 150,
          height: 128,
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
        const SizedBox(height: 12),
        const Text('Help shape the next\nNexAround update',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.3, color: FeedbackUi.ink)),
        const SizedBox(height: 8),
        const Text('Tell us how you use the app and\nwhat we should build next.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, color: FeedbackUi.sub, height: 1.45)),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(children: [
            bullet(Icons.timer_rounded, 'About 1 minute · 5 questions'),
            bullet(Icons.lock_rounded, 'Only our team sees answers'),
            bullet(Icons.event_repeat_rounded, 'We ask once every 3 months'),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ── Q1: recommend 0–10 ──────────────────────────────────────────────────

  Widget _nps() {
    final n = _a.nps;
    final reply = n == null
        ? null
        : n >= 9
            ? (Icons.celebration_rounded, '$n · Great! That means a lot to us.')
            : n >= 7
                ? (Icons.lightbulb_rounded, '$n · Thanks! What would make it a 10? Tell us in a moment.')
                : (Icons.handshake_rounded, '$n · Thanks for being honest. We\'ll keep improving.');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question('How likely are you to recommend NexAround to a friend?'),
          const SizedBox(height: 6),
          // 0–5 on the first row, 6–10 on the second, all the same size.
          LayoutBuilder(builder: (_, box) {
            // Rounded down so six always fit on the first row.
            final cell = ((box.maxWidth - 5 * 8) / 6).floorToDouble();
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i <= 10; i++)
                  Semantics(
                    button: true,
                    selected: n == i,
                    child: GestureDetector(
                      onTap: () => setState(() => _a.nps = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: cell,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: n == i ? null : FeedbackUi.bg,
                          gradient: n == i ? FeedbackUi.gradient : null,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: n == i
                              ? const [BoxShadow(color: Color(0x47005E60), blurRadius: 16, offset: Offset(0, 8))]
                              : null,
                        ),
                        child: Text('$i',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700, color: n == i ? Colors.white : FeedbackUi.ink)),
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 14),
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: const LinearGradient(
                colors: [Color(0xFFF87171), Color(0xFFFBBF24), Color(0xFF34D399)],
                stops: [0, 0.6, 1],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Row(children: [
            Text('Not likely', style: TextStyle(fontSize: 12.5, color: FeedbackUi.mute)),
            Spacer(),
            Text('Very likely', style: TextStyle(fontSize: 12.5, color: FeedbackUi.mute)),
          ]),
          if (reply != null) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(reply.$1, color: FeedbackVocab.teal, size: 26),
                const SizedBox(width: 11),
                Expanded(
                    child: Text(reply.$2, style: const TextStyle(fontSize: 14.5, height: 1.4, color: FeedbackUi.ink))),
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
          ..._pairs([
            for (final f in FeedbackVocab.features)
              _pickTile(
                icon: f.icon,
                label: f.label,
                on: _a.features.contains(f.key),
                onTap: () => setState(() => _a.features.contains(f.key) ? _a.features.remove(f.key) : _a.features.add(f.key)),
              ),
          ]),
        ],
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
          for (final o in widget.round.options) _optionRow(o, picks.indexOf(o.key)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FeedbackUi.line, width: 1.5),
            ),
            child: Row(children: [
              const Icon(Icons.edit_outlined, size: 20, color: FeedbackVocab.teal),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _other,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: FeedbackUi.plainInput('Something else? Tell us…'),
                  style: const TextStyle(fontSize: 14.5, color: FeedbackUi.ink),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(SurveyOption o, int rank) {
    final on = rank >= 0;
    final full = _a.buildNext.length >= 3;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: on ? FeedbackVocab.tint : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? FeedbackVocab.teal : FeedbackUi.line, width: 1.5),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 32,
                height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: on ? FeedbackVocab.teal : FeedbackUi.bg),
                child: Icon(FeedbackVocab.optionIcon(o.icon), size: 18, color: on ? Colors.white : FeedbackVocab.teal),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(o.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: FeedbackUi.ink)),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? FeedbackVocab.teal : Colors.transparent,
                  border: on ? null : Border.all(color: const Color(0xFFD3DCDB), width: 2),
                ),
                child: on
                    ? Text('${rank + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))
                    : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Q4: would you pay? ──────────────────────────────────────────────────

  Widget _pay() {
    Widget payTile(String key, IconData icon, String label, Color color) {
      final on = _a.wouldPay == key;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            onTap: () => setState(() {
              _a.wouldPay = key;
              if (key == 'no') _a.priceRange = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(
                color: on ? color.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? color : FeedbackUi.line, width: on ? 2 : 1.5),
              ),
              child: Column(children: [
                Icon(icon, size: 26, color: color),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
              ]),
            ),
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
          const SizedBox(height: 20),
          if (pays) ..._priceList(),
          if (_a.wouldPay == 'no') ..._whyNot(),
        ],
      ),
    );
  }

  List<Widget> _priceList() {
    return [
      const Text('How much a month feels fair?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
      const SizedBox(height: 2),
      const Text('In US dollars', style: TextStyle(fontSize: 12.5, color: FeedbackUi.mute)),
      const SizedBox(height: 10),
      for (final (key, label) in FeedbackVocab.priceRanges)
        Semantics(
          button: true,
          selected: _a.priceRange == key,
          child: GestureDetector(
            onTap: () => setState(() => _a.priceRange = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _a.priceRange == key ? FeedbackVocab.tint : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _a.priceRange == key ? FeedbackVocab.teal : FeedbackUi.line, width: 1.5),
              ),
              child: Row(children: [
                Icon(_a.priceRange == key ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    size: 22, color: _a.priceRange == key ? FeedbackVocab.teal : const Color(0xFFC9D3D2)),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _a.priceRange == key ? FontWeight.w700 : FontWeight.w600,
                        color: _a.priceRange == key ? FeedbackVocab.tealDark : FeedbackUi.ink,
                      )),
                ),
                const Text('a month', style: TextStyle(fontSize: 12, color: FeedbackUi.mute)),
              ]),
            ),
          ),
        ),
    ];
  }

  List<Widget> _whyNot() {
    return [
      const Text.rich(TextSpan(children: [
        TextSpan(text: 'What holds you back? ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
        TextSpan(text: '(optional)', style: TextStyle(fontSize: 14, color: FeedbackUi.mute)),
      ])),
      const SizedBox(height: 10),
      ..._pairs([
        for (final w in FeedbackVocab.whyNot)
          _pickTile(
            icon: w.icon,
            label: w.label,
            on: _a.whyNot.contains(w.key),
            onTap: () => setState(() => _a.whyNot.contains(w.key) ? _a.whyNot.remove(w.key) : _a.whyNot.add(w.key)),
          ),
      ]),
    ];
  }

  // ── Q5: anything else ───────────────────────────────────────────────────

  Widget _commentStep() {
    final focused = _commentFocus.hasFocus;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _question("Anything else you'd like to tell us?", 'Optional · write in any language'),
          GestureDetector(
            onTap: _commentFocus.requestFocus,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: const BoxConstraints(minHeight: 150),
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: focused ? FeedbackVocab.teal : FeedbackUi.line, width: 1.5),
                boxShadow: focused ? [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.10), spreadRadius: 4)] : null,
              ),
              child: TextField(
                controller: _comment,
                focusNode: _commentFocus,
                minLines: 6,
                maxLines: 10,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: FeedbackUi.plainInput('Your thoughts…'),
                style: const TextStyle(fontSize: 15, height: 1.5, color: FeedbackUi.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Thanks ──────────────────────────────────────────────────────────────

  Widget _thanks() {
    return Column(children: [
        const SizedBox(height: 8),
        const FeedbackSuccessBadge(),
        const SizedBox(height: 16),
        const Text('Thank you!',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: FeedbackUi.ink)),
        const SizedBox(height: 8),
        const Text('Your answers help decide what we build next.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: FeedbackUi.sub, height: 1.45)),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: FeedbackUi.bg, borderRadius: BorderRadius.circular(99)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_repeat_rounded, size: 18, color: FeedbackVocab.teal),
            SizedBox(width: 8),
            Text('Next survey in about 3 months', style: TextStyle(fontSize: 13.5, color: FeedbackUi.sub)),
          ]),
        ),
      ]);
  }
}
