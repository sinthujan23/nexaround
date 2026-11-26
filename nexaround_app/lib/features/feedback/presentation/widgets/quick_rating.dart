import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/feedback_page.dart';

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

  /// For dark screens (the Walking Challenge finish).
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
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final sub = dark ? Colors.white70 : AppColors.textSecondary;

    Widget body;
    if (_good == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: FeedbackVocab.teal, borderRadius: BorderRadius.circular(14)),
              child: Icon(widget.icon, color: Colors.white, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(height: 2),
                Text(widget.subtitle, style: TextStyle(fontSize: 13, color: sub)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          ThumbButtons(onGood: () => _answer(true), onBad: () => _answer(false), dark: dark),
        ],
      );
    } else if (_good == true) {
      body = Row(children: [
        const Icon(Icons.favorite_rounded, color: Color(0xFF10B981), size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text('Thanks! Glad you liked it.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg))),
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
          borderRadius: BorderRadius.circular(22),
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : (_good == false ? const Color(0xFFFEF2F2) : null),
          gradient: dark || _good == false
              ? null
              : const LinearGradient(colors: [Color(0xFFF1FBF9), Color(0xFFFFF7EA)]),
          border: Border.all(
            color: dark ? Colors.white24 : (_good == false ? const Color(0xFFFDE2E2) : const Color(0xFFD9EEEA)),
          ),
        ),
        child: body,
      ),
    );
  }
}

/// "Good" / "Not great" side by side.
class ThumbButtons extends StatelessWidget {
  const ThumbButtons({super.key, required this.onGood, required this.onBad, this.big = false, this.dark = false});
  final VoidCallback onGood;
  final VoidCallback onBad;
  final bool big;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, IconData icon, Color color, Color bg, Color border, VoidCallback onTap) {
      return Expanded(
        child: Material(
          color: dark ? Colors.white.withValues(alpha: 0.1) : bg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              height: big ? 60 : 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dark ? Colors.white24 : border, width: 1.5),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: dark ? Colors.white : color)),
              ]),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      button('Good', Icons.thumb_up_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5), const Color(0xFFA7F3D0), onGood),
      const SizedBox(width: 10),
      button('Not great', Icons.thumb_down_rounded, const Color(0xFFEF4444), const Color(0xFFFEF2F2), const Color(0xFFFECACA), onBad),
    ]);
  }
}

/// After "Not great": quick reasons and "Tell us more".
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

  @override
  Widget build(BuildContext context) {
    final reasons = FeedbackVocab.quickReasons[feature] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.thumb_down_rounded, color: Color(0xFFEF4444), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Sorry about that. What went wrong?',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: dark ? Colors.white : AppColors.textPrimary)),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final r in reasons)
              GestureDetector(
                onTap: () => onToggle(r.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected.contains(r.key)
                        ? const Color(0xFFEF4444)
                        : (dark ? Colors.white.withValues(alpha: 0.1) : Colors.white),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: selected.contains(r.key) ? const Color(0xFFEF4444) : const Color(0xFFF1D5D5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(r.icon, size: 17, color: selected.contains(r.key) ? Colors.white : const Color(0xFFEF4444)),
                    const SizedBox(width: 6),
                    Text(r.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: selected.contains(r.key) ? Colors.white : (dark ? Colors.white : AppColors.textPrimary),
                        )),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onMore,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Tell us more',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: dark ? FeedbackVocab.mint : FeedbackVocab.teal)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, size: 18, color: dark ? FeedbackVocab.mint : FeedbackVocab.teal),
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
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
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
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(9))),
            const SizedBox(height: 18),
            if (!_bad) ...[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(colors: [Color(0xFFFDBA4D), Color(0xFFF59E0B)]),
                  boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
                ),
                child: const Icon(Icons.flag_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 14),
              Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(widget.question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, color: AppColors.textSecondary)),
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
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip', style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600, fontSize: 15)),
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
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    if (_reasons.isNotEmpty) _rate(false, reasons: _reasons.toList());
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: FeedbackVocab.teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
