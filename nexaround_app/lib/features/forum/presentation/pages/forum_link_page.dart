import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/forum/data/datasources/forum_service.dart';
import 'package:nexaround_app/features/forum/data/models/forum_topic.dart';
import 'package:nexaround_app/features/forum/presentation/pages/forum_home_page.dart';
import 'package:nexaround_app/features/forum/presentation/pages/forum_thread_page.dart';

/// What a shared link (`https://nexaround.com/f/<topic id>`) opens.
///
/// A link carries only the id, and the thread page needs a topic to draw,
/// so this fetches it first and then presents the thread page in place.
///
/// Opened at /home/f/:id (lib/app/routes.dart), over Home, so Back returns
/// there. A signed-out user is sent to sign in first and lands here after.
/// The standalone /f/:id route is a fallback the redirect never lets through;
/// there [standalone] makes Back go through the splash screen.
class ForumLinkPage extends StatefulWidget {
  final String topicId;
  final bool standalone;

  const ForumLinkPage({
    super.key,
    required this.topicId,
    this.standalone = false,
  });

  @override
  State<ForumLinkPage> createState() => _ForumLinkPageState();
}

class _ForumLinkPageState extends State<ForumLinkPage> {
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  ForumTopic? _topic;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final topic = _uuid.hasMatch(widget.topicId)
        ? await ForumService().getTopicDetail(widget.topicId)
        : null;
    if (!mounted) return;
    setState(() {
      _topic = topic;
      _loading = false;
    });
  }

  void _leave() {
    if (widget.standalone) {
      context.go('/');
    } else if (!Navigator.of(context).canPop()) {
      context.go('/home');
    } else {
      Navigator.of(context).pop();
    }
  }

  void _explore() {
    if (widget.standalone || !Navigator.of(context).canPop()) {
      _leave();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ForumHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget page;
    if (_loading) {
      page = const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.brandGreen)),
      );
    } else if (_topic != null) {
      page = ForumThreadPage(topicId: widget.topicId, initialTopic: _topic);
    } else {
      page = _buildUnavailable();
    }

    if (!widget.standalone) return page;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: page,
    );
  }

  Widget _buildUnavailable() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _leave,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandGreen.withValues(alpha: 0.1),
                ),
                child: const Icon(Icons.forum_outlined,
                    size: 32, color: AppColors.brandGreen),
              ),
              const SizedBox(height: 16),
              const Text(
                'This discussion is no longer available',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'It may have been removed or deleted by the author. There are plenty more discussions to explore in the forum.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _explore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Explore travel forums',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
