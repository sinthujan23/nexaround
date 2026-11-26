import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/my_feedback_page.dart';

/// Opens "Tell us what you want". [source] says where it was opened from
/// (home, profile, odyssey, city_guides, walking_challenge); [feature],
/// [refId] and [refLabel] are set when it follows a "Not great" rating.
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

  final _service = FeedbackService();
  final _text = TextEditingController();
  final _focus = FocusNode();
  late String _type = widget.initialType ?? 'idea';
  final List<_Shot> _shots = [];
  bool _canReply = true;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _uploading => _shots.any((s) => s.name == null && !s.failed);
  bool get _canSend => _text.text.trim().length >= 2 && !_sending && !_uploading;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_sent ? '' : 'Feedback',
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          if (!_sent)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyFeedbackPage())),
              icon: const Icon(Icons.forum_rounded, size: 18, color: FeedbackVocab.teal),
              label: const Text('My feedback', style: TextStyle(color: FeedbackVocab.teal, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: SafeArea(child: _sent ? _thanks() : _form()),
    );
  }

  Widget _form() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
            children: [
              const Text('Tell us what you want',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.15)),
              const SizedBox(height: 6),
              const Text('We read every message. The best ideas end up in the app.',
                  style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4)),
              if (widget.refLabel != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.link_rounded, size: 18, color: FeedbackVocab.teal),
                    const SizedBox(width: 8),
                    Expanded(child: Text('About: ${widget.refLabel}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: FeedbackVocab.tealDark))),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              const Text("What's it about?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final t in FeedbackVocab.types) _typeChip(t)],
              ),
              const SizedBox(height: 20),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _focus.hasFocus ? FeedbackVocab.teal : const Color(0xFFE4E4E4), width: 1.5),
                  boxShadow: _focus.hasFocus
                      ? [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.08), spreadRadius: 4)]
                      : null,
                ),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 6,
                      maxLines: 12,
                      maxLength: 5000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        hintText: _hint,
                        hintStyle: const TextStyle(color: AppColors.textTertiary, height: 1.45),
                      ),
                      style: const TextStyle(fontSize: 15.5, height: 1.45),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text('${_text.text.length} / 5000',
                            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _shotsRow(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    const Icon(Icons.mark_email_read_rounded, color: FeedbackVocab.teal, size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You can reply to me', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('By email and in-app notification',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
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
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _canSend ? _send : null,
              style: FilledButton.styleFrom(
                backgroundColor: FeedbackVocab.teal,
                disabledBackgroundColor: FeedbackVocab.teal.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 20),
              label: Text(_sending ? 'Sending…' : _uploading ? 'Adding picture…' : 'Send',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }

  String get _hint => switch (_type) {
        'idea' => 'What would make NexAround better for you?',
        'problem' => 'What went wrong? Where in the app did it happen?',
        'love' => 'What do you enjoy most?',
        _ => 'Tell us anything…',
      };

  Widget _typeChip(FeedbackKind t) {
    final on = _type == t.key;
    return GestureDetector(
      onTap: () => setState(() => _type = t.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: on ? FeedbackVocab.teal : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? FeedbackVocab.teal : const Color(0xFFEDEDED)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, size: 18, color: on ? Colors.white : t.color),
            const SizedBox(width: 6),
            Text(t.label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _shotsRow() {
    return Row(
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
                        child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
                      ),
                    if (s.failed)
                      Container(color: Colors.black45, child: const Icon(Icons.error_outline_rounded, color: Colors.white)),
                  ]),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _shots.remove(s)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],
        if (_shots.length < _maxShots)
          GestureDetector(
            onTap: _addShot,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCFCFCF), width: 1.5),
                color: AppColors.surface,
              ),
              child: const Icon(Icons.add_photo_alternate_rounded, color: AppColors.textSecondary),
            ),
          ),
        if (_shots.isEmpty) ...[
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Add up to 3 screenshots\n(optional)',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary, height: 1.35)),
          ),
        ],
      ],
    );
  }

  Widget _thanks() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF00A3A5), FeedbackVocab.tealDark]),
              boxShadow: [BoxShadow(color: FeedbackVocab.teal.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))],
            ),
            child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 58),
          ),
          const SizedBox(height: 26),
          const Text('Thank you!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            _canReply
                ? 'Your message went straight to the NexAround team. We\'ll let you know when we reply.'
                : 'Your message went straight to the NexAround team.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.5),
          ),
          const Spacer(flex: 2),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: FeedbackVocab.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('Done', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
