import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/feedback_page.dart';
import 'package:nexaround_app/features/feedback/presentation/widgets/feedback_ui.dart';

/// The explorer's own messages and the team's replies. A reply's push and
/// bell line open this page (NotificationRouter, type `feedback_reply`).
class MyFeedbackPage extends StatefulWidget {
  const MyFeedbackPage({super.key});

  @override
  State<MyFeedbackPage> createState() => _MyFeedbackPageState();
}

class _MyFeedbackPageState extends State<MyFeedbackPage> {
  final _service = FeedbackService();
  List<MyFeedbackItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.mine();
      if (mounted) setState(() { _items = items; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = FeedbackService.errorText(e, 'Could not load your feedback.'));
    }
  }

  Future<void> _newMessage() async {
    await openFeedbackPage(context, source: 'my_feedback');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedbackUi.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(children: [
                FeedbackCircleButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: 'Back',
                  background: Colors.white,
                  onTap: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Center(
                    child: Text('My feedback',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
                  ),
                ),
                const SizedBox(width: 38),
              ]),
            ),
            Expanded(
              child: RefreshIndicator(color: FeedbackVocab.teal, onRefresh: _load, child: _body()),
            ),
          ],
        ),
      ),
      floatingActionButton: _items == null ? null : _NewMessageButton(onTap: _newMessage),
    );
  }

  Widget _body() {
    if (_error != null && _items == null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 90),
          const Icon(Icons.cloud_off_rounded, size: 40, color: FeedbackUi.mute),
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, color: FeedbackUi.sub)),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _load,
              child: const Text('Try again',
                  style: TextStyle(fontWeight: FontWeight.w700, color: FeedbackVocab.teal)),
            ),
          ),
        ],
      );
    }
    if (_items == null) return const Center(child: CircularProgressIndicator(color: FeedbackVocab.teal));
    if (_items!.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 70),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(color: FeedbackVocab.tint, shape: BoxShape.circle),
              child: const Icon(Icons.forum_rounded, size: 40, color: FeedbackVocab.teal),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Nothing sent yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: FeedbackUi.ink)),
          const SizedBox(height: 6),
          const Text("Your messages and the team's replies show here.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: FeedbackUi.sub, height: 1.4)),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      itemCount: _items!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _FeedbackCard(item: _items![i]),
    );
  }
}

String _when(DateTime? d) {
  if (d == null) return '';
  final local = d.toLocal();
  return DateFormat(local.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy').format(local);
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item});
  final MyFeedbackItem item;

  static (String, Color, Color) _status(String s) => switch (s) {
        'planned' => ('Planned', const Color(0xFFE8F0FF), const Color(0xFF2563EB)),
        'done' => ('Done', FeedbackVocab.tint, FeedbackVocab.teal),
        'replied' => ('Replied', FeedbackVocab.tint, FeedbackVocab.teal),
        'closed' => ('Closed', const Color(0xFFEEF1F2), FeedbackUi.sub),
        _ => ('Received', const Color(0xFFEEF1F2), FeedbackUi.sub),
      };

  @override
  Widget build(BuildContext context) {
    final kind = FeedbackVocab.type(item.type);
    final (label, bg, fg) = _status(item.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6ECEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _TypeChip(kind: kind),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_when(item.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: FeedbackUi.mute)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
              child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(item.text, style: const TextStyle(fontSize: 14.5, height: 1.45, color: FeedbackUi.ink)),
          for (final r in item.replies) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 11, 12, 11),
              decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: FeedbackUi.gradient),
                    child: const Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(
                            child: Text('NexAround team',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: FeedbackVocab.tealDark)),
                          ),
                          Text(_when(r.at), style: const TextStyle(fontSize: 12, color: FeedbackUi.mute)),
                        ]),
                        const SizedBox(height: 3),
                        Text(r.text, style: const TextStyle(fontSize: 13.8, height: 1.42, color: FeedbackUi.ink)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The message type as a small coloured pill.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.kind});
  final FeedbackKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: kind.color, shape: BoxShape.circle),
          child: Icon(kind.icon, size: 13, color: Colors.white),
        ),
        const SizedBox(width: 5),
        Text(kind.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color.lerp(kind.color, Colors.black, 0.35),
            )),
      ]),
    );
  }
}

class _NewMessageButton extends StatelessWidget {
  const _NewMessageButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: FeedbackUi.gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x4D005E60), blurRadius: 22, offset: Offset(0, 10))],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit_rounded, size: 19, color: Colors.white),
            SizedBox(width: 7),
            Text('New message', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}
