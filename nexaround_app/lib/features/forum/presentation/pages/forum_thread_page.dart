import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/forum_service.dart';
import '../../data/models/forum_topic.dart';
import '../../data/models/forum_post.dart';

class ForumThreadPage extends StatefulWidget {
  final String topicId;
  final ForumTopic? initialTopic;

  const ForumThreadPage({
    super.key,
    required this.topicId,
    this.initialTopic,
  });

  @override
  State<ForumThreadPage> createState() => _ForumThreadPageState();
}

class _ForumThreadPageState extends State<ForumThreadPage> {
  final ForumService _service = ForumService();
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  ForumTopic? _topic;
  bool _isLoading = true;
  bool _isSendingReply = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
    _loadTopic();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTopic() async {
    try {
      final detailed = await _service.getTopicDetail(widget.topicId);
      if (mounted) {
        setState(() {
          _topic = detailed ?? _topic;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleTopicLike() async {
    if (_topic == null) return;
    final currentLiked = _topic!.isLiked;
    final currentCount = _topic!.likesCount;

    setState(() {
      _topic = _topic!.copyWith(
        isLiked: !currentLiked,
        likesCount: currentLiked ? (currentCount - 1).clamp(0, 99999) : currentCount + 1,
      );
    });

    try {
      final res = await _service.toggleTopicLike(_topic!.id);
      if (mounted) {
        setState(() {
          _topic = _topic!.copyWith(
            isLiked: res['is_liked'] == true,
            likesCount: (res['likes_count'] as num?)?.toInt() ?? _topic!.likesCount,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    if (_topic == null) return;
    final currentBm = _topic!.isBookmarked;

    setState(() {
      _topic = _topic!.copyWith(isBookmarked: !currentBm);
    });

    try {
      final res = await _service.toggleBookmark(_topic!.id);
      if (mounted) {
        setState(() {
          _topic = _topic!.copyWith(isBookmarked: res['is_bookmarked'] == true);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _topic!.isBookmarked ? 'Saved to bookmarks' : 'Removed from bookmarks',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _togglePostLike(ForumPost post) async {
    final currentLiked = post.isLiked;
    final currentCount = post.likesCount;

    final updatedPosts = _topic?.posts.map((p) {
      if (p.id == post.id) {
        return p.copyWith(
          isLiked: !currentLiked,
          likesCount: currentLiked ? (currentCount - 1).clamp(0, 99999) : currentCount + 1,
        );
      }
      return p;
    }).toList();

    setState(() {
      _topic = _topic?.copyWith(posts: updatedPosts);
    });

    try {
      final res = await _service.togglePostLike(post.id);
      if (mounted) {
        final serverPosts = _topic?.posts.map((p) {
          if (p.id == post.id) {
            return p.copyWith(
              isLiked: res['is_liked'] == true,
              likesCount: (res['likes_count'] as num?)?.toInt() ?? p.likesCount,
            );
          }
          return p;
        }).toList();
        setState(() {
          _topic = _topic?.copyWith(posts: serverPosts);
        });
      }
    } catch (_) {}
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _topic == null) return;

    setState(() => _isSendingReply = true);
    FocusScope.of(context).unfocus();

    try {
      final newPost = await _service.createReply(
        topicId: _topic!.id,
        content: text,
      );

      _replyController.clear();

      if (mounted) {
        final currentPosts = List<ForumPost>.from(_topic!.posts);
        currentPosts.add(newPost);
        setState(() {
          _topic = _topic!.copyWith(
            posts: currentPosts,
            repliesCount: _topic!.repliesCount + 1,
          );
        });

        // Scroll to the new reply
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post reply: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingReply = false);
      }
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes.clamp(1, 59)}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 30) {
      return '${diff.inDays}d ago';
    } else {
      return '${(diff.inDays / 30).floor()}mo ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final topic = _topic;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(
          topic?.categoryName.isNotEmpty == true
              ? '${topic!.categoryName} Forum'
              : 'Travel Forum',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              topic?.isBookmarked == true
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: topic?.isBookmarked == true
                  ? AppColors.brandGreen
                  : const Color(0xFF64748B),
            ),
            onPressed: _toggleBookmark,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF64748B)),
            onPressed: () {
              if (topic != null) {
                SharePlus.instance.share(ShareParams(
                  text: '${topic.title}\n\nJoin the discussion on NexAround!',
                  subject: topic.title,
                ));
              }
            },
          ),
        ],
      ),
      body: (_isLoading && topic == null)
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandGreen))
          : topic == null
              ? Center(
                  child: Text(
                    _errorMessage ?? 'Topic not found',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadTopic,
                        color: AppColors.brandGreen,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            // ── Original Post (OP) Card ─────────────────────
                            _buildOpCard(topic),
                            const SizedBox(height: 16),


                            // ── Replies Section Header ──────────────────────
                            Row(
                              children: [
                                Text(
                                  'Community Replies (${topic.posts.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const Spacer(),
                                const Text(
                                  'Oldest first',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // ── Replies Stream ──────────────────────────────
                            if (topic.posts.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.brandGreen.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 28,
                                        color: AppColors.brandGreen,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No replies yet',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Be the first to share your firsthand experience!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ...topic.posts.map((post) => _buildReplyCard(post, topic)),
                          ],
                        ),
                      ),
                    ),

                    // ── Sticky Reply Input Bar ───────────────────────────────
                    _buildReplyBar(),
                  ],
                ),
    );
  }

  Widget _buildOpCard(ForumTopic topic) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Row
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage: (topic.userAvatarUrl != null && topic.userAvatarUrl!.isNotEmpty)
                    ? CachedNetworkImageProvider(topic.userAvatarUrl!)
                    : null,
                child: (topic.userAvatarUrl == null || topic.userAvatarUrl!.isEmpty)
                    ? Text(
                        topic.userDisplayName.isNotEmpty
                            ? topic.userDisplayName[0].toUpperCase()
                            : 'T',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.userDisplayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _formatTimeAgo(topic.createdAt),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${topic.viewsCount} views',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Category Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  topic.categoryName,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            topic.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),

          // Content
          Text(
            topic.content,
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF334155),
              height: 1.5,
            ),
          ),

          // Tags
          if (topic.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: topic.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Interaction Bar: Helpful like & replies
          Row(
            children: [
              GestureDetector(
                onTap: _toggleTopicLike,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: topic.isLiked
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: topic.isLiked
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        topic.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 16,
                        color: topic.isLiked ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Helpful (${topic.likesCount})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: topic.isLiked ? const Color(0xFFEF4444) : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(
                    '${topic.repliesCount} answers',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildReplyCard(ForumPost post, ForumTopic topic) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: post.isBestAnswer
              ? const Color(0xFF22C55E)
              : const Color(0xFFE2E8F0),
          width: post.isBestAnswer ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Best answer banner
          if (post.isBestAnswer) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 13, color: Color(0xFF16A34A)),
                  SizedBox(width: 4),
                  Text(
                    'BEST ANSWER VERIFIED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16A34A),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Author Row
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage: (post.userAvatarUrl != null && post.userAvatarUrl!.isNotEmpty)
                    ? CachedNetworkImageProvider(post.userAvatarUrl!)
                    : null,
                child: (post.userAvatarUrl == null || post.userAvatarUrl!.isEmpty)
                    ? Text(
                        post.userDisplayName.isNotEmpty
                            ? post.userDisplayName[0].toUpperCase()
                            : 'T',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.userDisplayName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      _formatTimeAgo(post.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Content
          Text(
            post.content,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF334155),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),

          // Footer: Helpful Like
          Row(
            children: [
              GestureDetector(
                onTap: () => _togglePostLike(post),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Icon(
                      post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 14,
                      color: post.isLiked ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      post.likesCount > 0 ? '${post.likesCount} Helpful' : 'Helpful',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: post.isLiked ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _replyController,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                decoration: const InputDecoration(
                  hintText: 'Share your advice or answer...',
                  hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isSendingReply ? null : _sendReply,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _isSendingReply
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
