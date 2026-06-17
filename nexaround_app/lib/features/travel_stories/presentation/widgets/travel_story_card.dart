import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/models/travel_story.dart';

class TravelStoryCard extends StatefulWidget {
  final TravelStory story;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback? onLocationTap;

  const TravelStoryCard({
    super.key,
    required this.story,
    required this.onLikeTap,
    required this.onCommentTap,
    this.onLocationTap,
  });

  @override
  State<TravelStoryCard> createState() => _TravelStoryCardState();
}

class _TravelStoryCardState extends State<TravelStoryCard> {
  bool _localLiked = false;
  int _localLikesCount = 0;

  @override
  void initState() {
    super.initState();
    _localLiked = widget.story.isLiked;
    _localLikesCount = widget.story.likesCount;
  }

  @override
  void didUpdateWidget(covariant TravelStoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.story.isLiked != widget.story.isLiked ||
        oldWidget.story.likesCount != widget.story.likesCount) {
      setState(() {
        _localLiked = widget.story.isLiked;
        _localLikesCount = widget.story.likesCount;
      });
    }
  }

  Color _getCategoryColor(String category) {
    if (category.contains('Hidden')) return Colors.purple;
    if (category.contains('Offbeat')) return Colors.orange;
    if (category.contains('Secret')) return AppColors.brandGreen;
    if (category.contains('Scenic')) return Colors.blue;
    return Colors.teal;
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _getCategoryColor(widget.story.category);

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 18, bottom: 8, top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withOpacity(0.8), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: widget.story.userAvatar.startsWith('http')
                        ? CachedNetworkImageProvider(widget.story.userAvatar)
                        : null,
                    child: !widget.story.userAvatar.startsWith('http')
                        ? const Icon(Icons.person, size: 16, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.story.userName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _timeAgo(widget.story.createdAt),
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Category Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: catColor.withOpacity(0.3), width: 0.8),
                    ),
                    child: Text(
                      widget.story.category,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: catColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Post image
            SizedBox(
              height: 115,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.story.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppColors.surface,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandGreen),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                  ),
                  // Location Overlay Tag
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: GestureDetector(
                      onTap: widget.onLocationTap,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Colors.black.withOpacity(0.6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on, size: 10, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                widget.story.locationName,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Story description
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                widget.story.description,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const Spacer(),
            const Divider(height: 1, color: AppColors.border),

            // Social actions footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Like button
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        if (_localLiked) {
                          _localLiked = false;
                          _localLikesCount--;
                        } else {
                          _localLiked = true;
                          _localLikesCount++;
                        }
                      });
                      widget.onLikeTap();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _localLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: _localLiked ? Colors.red : AppColors.textTertiary,
                        ).animate(
                          target: _localLiked ? 1.0 : 0.0,
                        ).scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.3, 1.3),
                          curve: Curves.elasticOut,
                          duration: 350.ms,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_localLikesCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Comment button
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onCommentTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.story.comments.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}
