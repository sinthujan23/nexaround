import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/models/forum_topic.dart';
import '../pages/forum_thread_page.dart';

class ForumTopicCard extends StatelessWidget {
  final ForumTopic topic;
  final VoidCallback? onTopicUpdated;

  const ForumTopicCard({
    super.key,
    required this.topic,
    this.onTopicUpdated,
  });

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
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ForumThreadPage(topicId: topic.id, initialTopic: topic),
          ),
        );
        if (result == true) {
          onTopicUpdated?.call();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
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
            // Top Row: Category tag, Pin badge, Best answer badge, Time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        topic.categoryType == 'topic'
                            ? Icons.tag_rounded
                            : Icons.location_on_rounded,
                        size: 12,
                        color: AppColors.brandGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        topic.categoryName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandGreen,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (topic.isPinned) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFFD97706)),
                        SizedBox(width: 2),
                        Text(
                          'PINNED',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (topic.bestAnswerId != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF16A34A)),
                        SizedBox(width: 2),
                        Text(
                          'ANSWERED',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  _formatTimeAgo(topic.createdAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Question Title
            Text(
              topic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),

            // Question Excerpt
            Text(
              topic.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),

            // Tags (if any)
            if (topic.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: topic.tags.take(3).map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$tag',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // Bottom Row: Author avatar & name + Stats (replies & likes)
            Row(
              children: [
                // Author avatar
                CircleAvatar(
                  radius: 12,
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
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    topic.userDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),

                // Stats: Helpful Upvotes
                Row(
                  children: [
                    Icon(
                      topic.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 14,
                      color: topic.isLiked ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${topic.likesCount}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: topic.isLiked ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Stats: Replies
                Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${topic.repliesCount}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
