import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/my_feedback_page.dart';
import 'package:nexaround_app/features/feedback/presentation/widgets/feedback_ui.dart';

/// Opens "Tell us what you want". [source] says where it was opened from
/// (tell_us, profile, my_feedback, odyssey, city_guides, walking_challenge);
/// [feature], [refId] and [refLabel] are set when it follows a "Not great"
/// rating. Without a [type] the type list opens first.
Future<void> openFeedbackPage(
  BuildContext context, {
  String? type,
  required String source,
  String? feature,
  String? refId,
  String? refLabel,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => FeedbackPage(
      initialType: type,
      source: source,
      feature: feature,
      refId: refId,
      refLabel: refLabel,
    ),
  ));
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({
    super.key,
    this.initialType,
    required this.source,
    this.feature,
    this.refId,
    this.refLabel,
  });

  final String? initialType;
  final String source;
  final String? feature;
  final String? refId;
  final String? refLabel;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _Shot {
  _Shot(this.path);
  final String path;
  String? name; // set once uploaded
  bool failed = false;
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const _maxShots = 3;
  static const _maxLength = 5000;

  final _service = FeedbackService();
  final _text = TextEditingController();
  final _focus = FocusNode();
  late String _type = widget.initialType ?? 'suggestion';
  final List<_Shot> _shots = [];
  bool _canReply = true;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
    // No type picked yet (Profile, My feedback): ask what it's about first,
    // once the page has slid in.
    if (widget.initialType == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && !_sent) _pickType();
        });
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _uploading => _shots.any((s) => s.name == null && !s.failed);
  bool get _canSend => _text.text.trim().length >= 2 && !_sending && !_uploading;

  Future<void> _pickType() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TypeSheet(selected: _type),
    );
    if (picked != null && mounted) setState(() => _type = picked);
  }

  Future<void> _addShot() async {
    if (_shots.length >= _maxShots) return;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, maxHeight: 1800, imageQuality: 85);
    } catch (_) {
      _say('Could not open your photos.');
      return;
    }
    if (picked == null || !mounted) return;
    final shot = _Shot(picked.path);
    setState(() => _shots.add(shot));
    try {
      shot.name = await _service.uploadScreenshot(picked.path);
    } catch (e) {
      shot.failed = true;
      _say(FeedbackService.errorText(e, 'That picture could not be added.'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    try {
      await _service.send(
        type: _type,
        text: _text.text.trim(),
        screenshots: [for (final s in _shots) if (s.name != null) s.name!],
        canReply: _canReply,
        sourceScreen: widget.source,
        feature: widget.feature,
        refId: widget.refId,
        refLabel: widget.refLabel,
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _sent = true);
    } catch (e) {
      _say(FeedbackService.errorText(e, 'Your message could not be sent. Please try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openMine() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyFeedbackPage()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _sent ? _thanks() : _form()),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(children: [
        FeedbackCircleButton(
          icon: Icons.arrow_back_ios_new_rounded,
          label: 'Back',
          onTap: () => Navigator.pop(context),
        ),
        const Spacer(),
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: _openMine,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(99)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.forum_rounded, size: 17, color: FeedbackVocab.tealDark),
                SizedBox(width: 6),
                Text('My feedback',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: FeedbackVocab.tealDark)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _form() {
    final kind = FeedbackVocab.type(_type);
    return Column(
      children: [
        _topBar(),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            children: [
              const Text('Tell us what you want',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.15, color: FeedbackUi.ink)),
              const SizedBox(height: 5),
              const Text('Every message goes straight to our team.',
                  style: TextStyle(fontSize: 14, color: FeedbackUi.sub, height: 1.4)),
              if (widget.refLabel != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.link_rounded, size: 18, color: FeedbackVocab.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('About: ${widget.refLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: FeedbackVocab.tealDark)),
                    ),
                  ]),
                ),
              ],
              const FeedbackSectionLabel("It's about"),
              _typeCard(kind),
              FeedbackSectionLabel('Your message', trailing: '${_text.text.length} / $_maxLength'),
              _textBox(),
              const FeedbackSectionLabel('Screenshots', trailing: 'optional · up to 3'),
              _shotsRow(),
              const SizedBox(height: 16),
              _replyCard(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FeedbackPrimaryButton(
            label: _sending ? 'Sending…' : _uploading ? 'Adding picture…' : 'Send',
            icon: Icons.send_rounded,
            busy: _sending,
            onTap: _canSend ? _send : null,
          ),
        ),
      ],
    );
  }

  /// The chosen type on one line, with "Change" to pick another.
  Widget _typeCard(FeedbackKind kind) {
    return Semantics(
      button: true,
      label: 'About: ${kind.label}. Change',
      child: GestureDetector(
        onTap: _pickType,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: FeedbackUi.line, width: 1.5),
          ),
          child: Row(children: [
            FeedbackTypeIcon(kind: kind),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
                const SizedBox(height: 1),
                Text(kind.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: FeedbackUi.sub)),
              ]),
            ),
            const SizedBox(width: 8),
            const Text('Change', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: FeedbackVocab.teal)),
            const Icon(Icons.expand_more_rounded, size: 18, color: FeedbackVocab.teal),
          ]),
        ),
      ),
    );
  }

  String get _hint => switch (_type) {
        'suggestion' => 'What would you like to see in NexAround?',
        'improvement' => 'What could work better? Where in the app?',
        'problem' => 'What went wrong? Where in the app did it happen?',
        'love' => 'What do you enjoy most?',
        _ => 'Tell us anything…',
      };

  /// One white box: the field inside has no fill or border of its own.
  Widget _textBox() {
    final focused = _focus.hasFocus;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 140),
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: focused ? FeedbackVocab.teal : FeedbackUi.line, width: 1.5),
          boxShadow: focused ? [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.10), spreadRadius: 4)] : null,
        ),
        child: TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 5,
          maxLines: 10,
          maxLength: _maxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: FeedbackUi.plainInput(_hint),
          style: const TextStyle(fontSize: 15, height: 1.45, color: FeedbackUi.ink),
        ),
      ),
    );
  }

  Widget _shotsRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          for (final s in _shots) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.file(File(s.path), fit: BoxFit.cover),
                      if (s.name == null && !s.failed)
                        Container(
                          color: Colors.black38,
                          child: const Center(
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          ),
                        ),
                      if (s.failed)
                        Container(color: Colors.black45, child: const Icon(Icons.error_outline_rounded, color: Colors.white)),
                    ]),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: Semantics(
                    button: true,
                    label: 'Remove picture',
                    child: GestureDetector(
                      onTap: () => setState(() => _shots.remove(s)),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: FeedbackUi.ink,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
          ],
          if (_shots.length < _maxShots)
            Semantics(
              button: true,
              label: 'Add a screenshot',
              child: GestureDetector(
                onTap: _addShot,
                child: CustomPaint(
                  painter: const _DashedBox(color: Color(0xFFBFCBCA), radius: 14),
                  child: const SizedBox(
                    width: 64,
                    height: 64,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded, size: 22, color: FeedbackVocab.teal),
                        SizedBox(height: 2),
                        Text('Add', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: FeedbackVocab.teal)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _replyCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: FeedbackUi.bg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          const Icon(Icons.mark_email_read_rounded, color: FeedbackVocab.teal, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You can reply to me',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
                SizedBox(height: 1),
                Text('By email and app notification',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.3, color: FeedbackUi.sub)),
              ],
            ),
          ),
          Switch.adaptive(
            value: _canReply,
            activeTrackColor: FeedbackVocab.teal,
            onChanged: (v) => setState(() => _canReply = v),
          ),
        ],
      ),
    );
  }

  Widget _thanks() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        children: [
          const Spacer(),
          const FeedbackSuccessBadge(),
          const SizedBox(height: 16),
          const Text('Thank you!',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: FeedbackUi.ink)),
          const SizedBox(height: 8),
          const Text('Your message went straight to the NexAround team.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: FeedbackUi.sub, height: 1.45)),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(_canReply ? Icons.notifications_active_rounded : Icons.forum_rounded,
                    size: 20, color: FeedbackVocab.teal),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  _canReply
                      ? "When we reply, you'll get a notification. Replies are kept in My feedback."
                      : 'You can find your messages in My feedback.',
                  style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF2F3F3E)),
                ),
              ),
            ]),
          ),
          const Spacer(flex: 2),
          FeedbackPrimaryButton(label: 'Done', onTap: () => Navigator.pop(context)),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MyFeedbackPage())),
            child: const Text('See my feedback',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FeedbackUi.sub)),
          ),
        ],
      ),
    );
  }
}

/// "What's it about?": the five message types as clear rows.
class _TypeSheet extends StatelessWidget {
  const _TypeSheet({required this.selected});
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: const Color(0xFFD5DDDC), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 14),
          const Text("What's it about?",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
          const SizedBox(height: 12),
          for (final (i, t) in FeedbackVocab.types.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _TypeRow(kind: t, on: t.key == selected, onTap: () => Navigator.pop(context, t.key)),
          ],
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.kind, required this.on, required this.onTap});
  final FeedbackKind kind;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: on ? FeedbackVocab.tint : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? FeedbackVocab.teal : FeedbackUi.line, width: 1.5),
          ),
          child: Row(children: [
            FeedbackTypeIcon(kind: kind),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
                const SizedBox(height: 1),
                Text(kind.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: FeedbackUi.sub)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 24, color: on ? FeedbackVocab.teal : const Color(0xFFC9D3D2)),
          ]),
        ),
      ),
    );
  }
}

/// A dashed rounded border (the "Add" screenshot tile).
class _DashedBox extends CustomPainter {
  const _DashedBox({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.75));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBox oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
