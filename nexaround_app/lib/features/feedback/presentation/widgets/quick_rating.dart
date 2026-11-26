import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/feedback_page.dart';
import 'package:nexaround_app/features/feedback/presentation/widgets/feedback_ui.dart';

/// One tap after finishing something: "Good" or "Not great". "Not great"
/// then offers quick reasons and "Tell us more" (the feedback page with the
/// context filled in). Each plan / trip / challenge is asked once per device;
/// the server keeps one rating per explorer per thing.
///
/// [feature] is odyssey | city_guides | walking_challenge.
class QuickRatingCard extends StatefulWidget {
  const QuickRatingCard({
    super.key,
    required this.feature,
    required this.refId,
    required this.refLabel,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    this.dark = false,
  });

  final String feature;
  final String refId;
  final String refLabel;
  final String title;
  final String subtitle;
  final IconData icon;

  /// For dark screens (the Walking Challenge finish): a dark glass card.
  final bool dark;

  @override
  State<QuickRatingCard> createState() => _QuickRatingCardState();
}

class _QuickRatingCardState extends State<QuickRatingCard> {
  final _service = FeedbackService();
  bool? _asked; // null while checking
  bool? _good; // the answer given here
  final Set<String> _reasons = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    FeedbackService.alreadyAsked(widget.feature, widget.refId).then((v) {
      if (mounted) setState(() => _asked = v);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _answer(bool good) async {
    setState(() => _good = good);
    await FeedbackService.markAsked(widget.feature, widget.refId);
    try {
      await _service.rate(feature: widget.feature, refId: widget.refId, refLabel: widget.refLabel, good: good);
    } catch (_) {
      // A lost rating is not worth bothering the traveller about.
    }
  }

  void _toggleReason(String key) {
    setState(() => _reasons.contains(key) ? _reasons.remove(key) : _reasons.add(key));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _service
          .rate(feature: widget.feature, refId: widget.refId, refLabel: widget.refLabel, good: false, reasons: _reasons.toList())
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Already asked on an earlier visit, and nothing answered this time.
    if (_asked == null || (_asked == true && _good == null)) return const SizedBox.shrink();
    final dark = widget.dark;

    Widget body;
    if (_good == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: widget.icon,
            title: widget.title,
            subtitle: widget.subtitle,
            dark: dark,
            iconBox: dark
                ? BoxDecoration(color: FeedbackVocab.mint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(13))
                : BoxDecoration(gradient: FeedbackUi.gradient, borderRadius: BorderRadius.circular(13)),
            iconColor: dark ? FeedbackVocab.mint : Colors.white,
          ),
          const SizedBox(height: 14),
          ThumbButtons(onGood: () => _answer(true), onBad: () => _answer(false), dark: dark),
        ],
      );
    } else if (_good == true) {
      body = Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dark ? const Color(0xFF10B981).withValues(alpha: 0.18) : const Color(0xFFECFDF5),
          ),
          child: Icon(Icons.favorite_rounded, size: 19, color: dark ? const Color(0xFF6EE7B7) : const Color(0xFF10B981)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text('Thanks! Glad you liked it.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: dark ? Colors.white : FeedbackUi.ink)),
        ),
      ]);
    } else {
      body = BadReasons(
        feature: widget.feature,
        selected: _reasons,
        onToggle: _toggleReason,
        dark: dark,
        onMore: () => openFeedbackPage(
          context,
          type: 'problem',
          source: widget.feature,
          feature: widget.feature,
          refId: widget.refId,
          refLabel: widget.refLabel,
        ),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
          border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.12)) : null,
          boxShadow: dark ? null : const [BoxShadow(color: Color(0x1A003C3C), blurRadius: 26, offset: Offset(0, 10))],
        ),
        child: body,
      ),
    );
  }
}

/// Icon square, title and one-line subtitle at the top of a rating card.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.dark,
    required this.iconBox,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool dark;
  final BoxDecoration iconBox;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 40, height: 40, decoration: iconBox, child: Icon(icon, size: 22, color: iconColor)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: dark ? Colors.white : FeedbackUi.ink)),
          const SizedBox(height: 1),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: dark ? Colors.white.withValues(alpha: 0.65) : FeedbackUi.sub)),
        ]),
      ),
    ]);
  }
}

/// "Good" / "Not great" side by side, the same width. [big] puts the icon
/// over the label (the City Guide sheet).
class ThumbButtons extends StatelessWidget {
  const ThumbButtons({super.key, required this.onGood, required this.onBad, this.big = false, this.dark = false});
  final VoidCallback onGood;
  final VoidCallback onBad;
  final bool big;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required String label,
      required IconData icon,
      required Color fg,
      required Color bg,
      required Color border,
      required VoidCallback onTap,
    }) {
      final content = big
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: fg, size: 30),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: fg)),
            ])
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg)),
              ),
            ]);
      return Expanded(
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(big ? 18 : 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(big ? 18 : 14),
            onTap: onTap,
            child: Container(
              height: big ? 96 : 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(big ? 18 : 14),
                border: Border.all(color: border, width: 1.5),
              ),
              child: content,
            ),
          ),
        ),
      );
    }

    return Row(children: [
      button(
        label: 'Good',
        icon: Icons.thumb_up_rounded,
        fg: dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
        bg: dark ? const Color(0xFF10B981).withValues(alpha: 0.16) : const Color(0xFFECFDF5),
        border: dark ? const Color(0xFF34D399).withValues(alpha: 0.45) : const Color(0xFFA7F3D0),
        onTap: onGood,
      ),
      const SizedBox(width: 10),
      button(
        label: 'Not great',
        icon: Icons.thumb_down_rounded,
        fg: dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
        bg: dark ? const Color(0xFFEF4444).withValues(alpha: 0.14) : const Color(0xFFFEF2F2),
        border: dark ? const Color(0xFFF87171).withValues(alpha: 0.45) : const Color(0xFFFECACA),
        onTap: onBad,
      ),
    ]);
  }
}

/// After "Not great": "Sorry about that", the reasons in a 2 × 2 grid, and
/// "Tell us more".
class BadReasons extends StatelessWidget {
  const BadReasons({
    super.key,
    required this.feature,
    required this.selected,
    required this.onToggle,
    required this.onMore,
    this.dark = false,
  });
  final String feature;
  final Set<String> selected;
  final void Function(String key) onToggle;
  final VoidCallback onMore;
  final bool dark;

  static const _red = Color(0xFFEF4444);

  Widget _tile(FeedbackKind r) {
    final on = selected.contains(r.key);
    final onFg = dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => onToggle(r.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on
                ? (dark ? _red.withValues(alpha: 0.18) : const Color(0xFFFEF2F2))
                : (dark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: on ? _red : (dark ? Colors.white.withValues(alpha: 0.18) : FeedbackUi.line),
              width: 1.5,
            ),
          ),
          child: Row(children: [
            Icon(r.icon, size: 18, color: on ? onFg : _red),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(r.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      color: on ? onFg : (dark ? Colors.white : FeedbackUi.ink),
                    )),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reasons = FeedbackVocab.quickReasons[feature] ?? const <FeedbackKind>[];
    final accent = dark ? FeedbackVocab.mint : FeedbackVocab.teal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHeader(
          icon: Icons.sentiment_dissatisfied_rounded,
          title: 'Sorry about that',
          subtitle: 'What went wrong? Pick any.',
          dark: dark,
          iconBox: BoxDecoration(
            color: dark ? _red.withValues(alpha: 0.16) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(13),
          ),
          iconColor: dark ? const Color(0xFFFCA5A5) : _red,
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < reasons.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: _tile(reasons[i])),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < reasons.length ? _tile(reasons[i + 1]) : const SizedBox.shrink()),
            ]),
          ),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEEF2F1))),
          ),
          child: Row(children: [
            Expanded(
              child: Text(selected.isEmpty ? 'Thanks for telling us.' : 'Saved. Thank you!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.8, color: dark ? Colors.white.withValues(alpha: 0.6) : FeedbackUi.mute)),
            ),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onMore,
                behavior: HitTestBehavior.opaque,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Tell us more', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: accent)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
                ]),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

/// The City Guide version: a sheet when a trip is finished. Asked once per
/// trip; nothing happens if this device already asked.
Future<void> showQuickRatingSheet(
  BuildContext context, {
  required String feature,
  required String refId,
  required String refLabel,
  required String title,
  required String question,
}) async {
  if (await FeedbackService.alreadyAsked(feature, refId)) return;
  await FeedbackService.markAsked(feature, refId);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _QuickRatingSheet(feature: feature, refId: refId, refLabel: refLabel, title: title, question: question),
  );
}

class _QuickRatingSheet extends StatefulWidget {
  const _QuickRatingSheet({
    required this.feature,
    required this.refId,
    required this.refLabel,
    required this.title,
    required this.question,
  });
  final String feature;
  final String refId;
  final String refLabel;
  final String title;
  final String question;

  @override
  State<_QuickRatingSheet> createState() => _QuickRatingSheetState();
}

class _QuickRatingSheetState extends State<_QuickRatingSheet> {
  final _service = FeedbackService();
  bool _bad = false;
  final Set<String> _reasons = {};

  Future<void> _rate(bool good, {List<String> reasons = const []}) async {
    try {
      await _service.rate(feature: widget.feature, refId: widget.refId, refLabel: widget.refLabel, good: good, reasons: reasons);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: const Color(0xFFD5DDDC), borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 18),
            if (!_bad) ...[
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [FeedbackUi.teal2, FeedbackVocab.tealDark]),
                  boxShadow: [BoxShadow(color: Color(0x4D005E60), blurRadius: 24, offset: Offset(0, 12))],
                ),
                child: const Icon(Icons.flag_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 14),
              Text(widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
              const SizedBox(height: 5),
              Text(widget.question,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, color: FeedbackUi.sub)),
              const SizedBox(height: 20),
              ThumbButtons(
                big: true,
                onGood: () {
                  _rate(true);
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(const SnackBar(content: Text('Thanks for telling us!')));
                },
                onBad: () {
                  _rate(false);
                  setState(() => _bad = true);
                },
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip',
                    style: TextStyle(color: FeedbackUi.sub, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ] else ...[
              BadReasons(
                feature: widget.feature,
                selected: _reasons,
                onToggle: (k) => setState(() => _reasons.contains(k) ? _reasons.remove(k) : _reasons.add(k)),
                onMore: () {
                  if (_reasons.isNotEmpty) _rate(false, reasons: _reasons.toList());
                  // This sheet is gone after pop, so push from the page under it.
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(
                    builder: (_) => FeedbackPage(
                      initialType: 'problem',
                      source: widget.feature,
                      feature: widget.feature,
                      refId: widget.refId,
                      refLabel: widget.refLabel,
                    ),
                  ));
                },
              ),
              const SizedBox(height: 18),
              FeedbackPrimaryButton(
                label: 'Done',
                onTap: () {
                  if (_reasons.isNotEmpty) _rate(false, reasons: _reasons.toList());
                  Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
