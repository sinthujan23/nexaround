import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../data/models/travel_story.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/core/widgets/full_screen_image_viewer.dart';
import 'package:nexaround_app/core/services/cloud_storage_service.dart';
import 'package:nexaround_app/features/travel_stories/data/datasources/travel_stories_service.dart';

class TravelStoryCard extends StatefulWidget {
  final TravelStory story;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback? onLocationTap;
  final VoidCallback? onTap;

  const TravelStoryCard({
    super.key,
    required this.story,
    required this.onLikeTap,
    required this.onCommentTap,
    this.onLocationTap,
    this.onTap,
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

  Widget _buildImage(String url, int index, List<String> allUrls) {
    return GestureDetector(
      onTap: () => _openFullScreenViewer(index, allUrls),
      child: _buildImageContent(url),
    );
  }

  Widget _buildImageContent(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppColors.surface,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.brandGreen,
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
      );
    } else if (url.startsWith('/static/')) {
      final fullUrl = '${ApiConstants.baseUrl}$url';
      return CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppColors.surface,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.brandGreen,
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: AppColors.surfaceVariant),
        );
      } else {
        final fullUrl = url.startsWith('/')
            ? '${ApiConstants.baseUrl}$url'
            : url;
        return CachedNetworkImage(
          imageUrl: fullUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: AppColors.surface,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.brandGreen,
                ),
              ),
            ),
          ),
          errorWidget: (_, __, ___) =>
              Container(color: AppColors.surfaceVariant),
        );
      }
    }
  }

  void _openFullScreenViewer(int initialIndex, List<String> allUrls) {
    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final isAuthor = currentUserId == widget.story.userId;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(
          imageUrls: allUrls,
          initialIndex: initialIndex,
          showDeleteOption: isAuthor,
          onDelete: () async {
            if (widget.story.cloudFolderUrl != null && widget.story.cloudProvider != null) {
              final provider = widget.story.cloudProvider == 'google_drive' 
                  ? CloudProvider.googleDrive 
                  : CloudProvider.dropbox;
              try {
                await CloudStorageService().deleteFromCloud(provider, widget.story.cloudFolderUrl!);
              } catch (e) {
                print("Failed to delete from cloud: $e");
                // We still proceed to delete the post from the app
              }
            }
            await TravelStoriesService().deleteStory(widget.story.id);
          },
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();

    final images = urls.take(3).toList();
    final isSingle = images.length == 1;
    final isDouble = images.length == 2;

    if (isSingle) {
      return _buildImage(images[0], 0, urls);
    }

    if (isDouble) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildImage(images[0], 0, urls)),
          const SizedBox(width: 2),
          Expanded(child: _buildImage(images[1], 1, urls)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 2, child: _buildImage(images[0], 0, urls)),
        const SizedBox(width: 2),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildImage(images[1], 1, urls)),
              const SizedBox(height: 2),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImage(images[2], 2, urls),
                    if (urls.length > 3)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        alignment: Alignment.center,
                        child: Text(
                          '+${urls.length - 3}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _getCategoryColor(widget.story.category);
    final allUrls = widget.story.imageUrls.isNotEmpty
        ? widget.story.imageUrls
        : (widget.story.imageUrl.isNotEmpty
              ? [widget.story.imageUrl]
              : <String>[]);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 18, bottom: 8, top: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.border.withOpacity(0.8),
            width: 1.0,
          ),
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
                      backgroundImage:
                          widget.story.userAvatar.startsWith('http')
                          ? CachedNetworkImageProvider(widget.story.userAvatar)
                          : null,
                      child: !widget.story.userAvatar.startsWith('http')
                          ? const Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BlocBuilder<AuthBloc, AuthState>(
                            builder: (context, authState) {
                              String display = widget.story.userName;
                              if (display.trim().isEmpty || display.trim().toLowerCase() == 'anonymous') {
                                if (authState is AuthAuthenticated) {
                                  display = authState.user.displayName.isNotEmpty && authState.user.displayName.toLowerCase() != 'anonymous' 
                                      ? authState.user.displayName 
                                      : (authState.user.email.isNotEmpty ? authState.user.email.split('@')[0] : 'Explorer');
                                } else {
                                  display = 'Explorer';
                                }
                              }
                              return Text(
                                display,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
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
                    // Category Tag and Spend
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: catColor.withOpacity(0.3),
                              width: 0.8,
                            ),
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
                        if (widget.story.isJournal && widget.story.totalSpend > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              '${widget.story.spendCurrency} ${widget.story.totalSpend.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Post image
              SizedBox(
                height: 240,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImageGrid(allUrls),
                    // Location Overlay Tag
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: widget.onLocationTap,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: Colors.black.withOpacity(0.6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 10,
                                  color: Colors.white,
                                ),
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
                    if (widget.story.imageUrls.length > 1)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.layers_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Story description
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: widget.story.description.length > 95
                            ? '${widget.story.description.substring(0, 92)}...'
                            : widget.story.description,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (widget.story.description.length > 95)
                        const TextSpan(
                          text: ' see more',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brandGreen,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const Spacer(),
              const Divider(height: 1, color: AppColors.border),

              // Social actions footer
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                                _localLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 16,
                                color: _localLiked
                                    ? Colors.red
                                    : AppColors.textTertiary,
                              )
                              .animate(target: _localLiked ? 1.0 : 0.0)
                              .scale(
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
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    final days = difference.inDays;

    if (days >= 365) {
      final years = (days / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    } else if (days >= 60) {
      final months = (days / 30).floor();
      return '$months months ago';
    } else if (days >= 30) {
      return '1 month ago';
    } else if (days >= 7) {
      final weeks = (days / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (days >= 1) {
      return days == 1 ? '1 day ago' : '$days days ago';
    } else if (difference.inHours >= 1) {
      return difference.inHours == 1 ? '1 hour ago' : '${difference.inHours} hours ago';
    } else if (difference.inMinutes >= 1) {
      return difference.inMinutes == 1 ? '1 min ago' : '${difference.inMinutes} mins ago';
    } else {
      return 'just now';
    }
  }
}
