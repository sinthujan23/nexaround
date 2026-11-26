import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/feedback/data/feedback_service.dart';
import 'package:nexaround_app/features/feedback/feedback_constants.dart';
import 'package:nexaround_app/features/feedback/presentation/pages/feedback_page.dart';

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

  static String _when(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d.toLocal());

  static (String, Color, Color) _status(String s) => switch (s) {
        'planned' => ('Planned', const Color(0xFFE8F0FF), const Color(0xFF2563EB)),
        'done' => ('Done', FeedbackVocab.tint, FeedbackVocab.teal),
        'replied' => ('Replied', FeedbackVocab.tint, FeedbackVocab.teal),
        'closed' => ('Closed', const Color(0xFFF1F2F4), const Color(0xFF6B7280)),
        _ => ('Received', const Color(0xFFF1F2F4), const Color(0xFF6B7280)),
      };

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
        title: const Text('My feedback',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: FeedbackVocab.teal,
        foregroundColor: Colors.white,
        onPressed: () async {
          await openFeedbackPage(context, source: 'my_feedback');
          _load();
        },
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New message', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        color: FeedbackVocab.teal,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_error != null && _items == null) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
      ]);
    }
    if (_items == null) return const Center(child: CircularProgressIndicator(color: FeedbackVocab.teal));
    if (_items!.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.forum_rounded, size: 54, color: AppColors.textMuted),
          SizedBox(height: 14),
          Text('Nothing sent yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Your messages and the team\'s replies show here.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _items!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final f = _items![i];
        final t = FeedbackVocab.type(f.type);
        final (label, bg, fg) = _status(f.status);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFECECEC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(t.icon, size: 18, color: t.color),
                const SizedBox(width: 6),
                Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(width: 8),
                Text(_when(f.createdAt), style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                  child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
                ),
              ]),
              const SizedBox(height: 10),
              Text(f.text, style: const TextStyle(fontSize: 15, height: 1.45)),
              for (final r in f.replies) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: FeedbackVocab.tint, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.verified_rounded, size: 16, color: FeedbackVocab.teal),
                        const SizedBox(width: 6),
                        const Text('NexAround team',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: FeedbackVocab.tealDark)),
                        const SizedBox(width: 6),
                        Text(_when(r.at), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      ]),
                      const SizedBox(height: 6),
                      Text(r.text, style: const TextStyle(fontSize: 14.5, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
