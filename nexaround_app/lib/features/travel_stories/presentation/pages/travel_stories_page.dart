import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../data/models/travel_story.dart';
import '../../data/datasources/travel_stories_service.dart';
import '../widgets/stories_comments_dialog.dart';

class TravelStoriesPage extends StatefulWidget {
  final List<TravelStory> stories;
  final int initialIndex;
  final Function(String storyId)? onStoryDeleted;

  const TravelStoriesPage({
    super.key,
    required this.stories,
    required this.initialIndex,
    this.onStoryDeleted,
  });

  @override
  State<TravelStoriesPage> createState() => _TravelStoriesPageState();
}

class _TravelStoriesPageState extends State<TravelStoriesPage> {
  late PageController _pageController;
  late int _currentIndex;
  final TextEditingController _commentController = TextEditingController();
  bool _isSendingComment = false;
  bool _isDeletingStory = false;
  final Set<String> _expandedStoryIds = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Color _getCategoryColor(String category) {
    if (category.contains('Hidden')) return Colors.purpleAccent;
    if (category.contains('Offbeat')) return Colors.orangeAccent;
    if (category.contains('Secret')) return AppColors.brandGreen;
    if (category.contains('Scenic')) return Colors.blueAccent;
    return Colors.tealAccent;
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImageProvider(url);
    } else if (url.startsWith('/static/')) {
      return CachedNetworkImageProvider('${ApiConstants.baseUrl}$url');
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return FileImage(file);
      }
      return CachedNetworkImageProvider(url.startsWith('/') ? '${ApiConstants.baseUrl}$url' : url);
    }
  }

  Widget _buildMainImage(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.white10,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        errorWidget: (_, __, ___) => Container(color: Colors.white10),
      );
    } else if (url.startsWith('/static/')) {
      final fullUrl = '${ApiConstants.baseUrl}$url';
      return CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.white10,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        errorWidget: (_, __, ___) => Container(color: Colors.white10),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: Colors.white10),
        );
      } else {
        final fullUrl = url.startsWith('/') ? '${ApiConstants.baseUrl}$url' : url;
        return CachedNetworkImage(
          imageUrl: fullUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Colors.white10,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
          errorWidget: (_, __, ___) => Container(color: Colors.white10),
        );
      }
    }
  }

  Future<void> _submitComment(TravelStory story) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSendingComment = true;
    });

    try {
      await TravelStoriesService().addComment(story.id, text);
      final authState = context.read<AuthBloc>().state;
      String author = 'You';
      if (authState is AuthAuthenticated) {
        author = authState.user.displayName;
      }
      setState(() {
        story.comments.add('$author: $text');
        _commentController.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingComment = false;
        });
      }
    }
  }

  void _showCommentsDialog(TravelStory story) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StoriesCommentsDialog(
          story: story,
          onCommentAdded: (commentText) {
            setState(() {
              story.comments.add(commentText);
            });
            TravelStoriesService().addComment(story.id, commentText);
          },
        );
      },
    );
  }

  Future<void> _deleteCurrentStory() async {
    final story = widget.stories[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Story', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to delete this story? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingStory = true);
    try {
      await TravelStoriesService().deleteStory(story.id);
      widget.onStoryDeleted?.call(story.id);
      if (!mounted) return;
      
      // Remove from local list
      widget.stories.removeAt(_currentIndex);
      
      if (widget.stories.isEmpty) {
        Navigator.pop(context);
        return;
      }
      
      // Adjust index if we deleted the last story
      if (_currentIndex >= widget.stories.length) {
        _currentIndex = widget.stories.length - 1;
      }
      setState(() => _isDeletingStory = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story deleted'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isDeletingStory = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete story: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No stories found', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final currentStory = widget.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient blurred background matching the active story's photo
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: ImageFiltered(
              key: ValueKey(currentStory.id),
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: _getImageProvider(currentStory.imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ),
          ),

          // 2. Safe Area layout for story view
          SafeArea(
            child: Column(
              children: [
                // Top Progress Bar & Close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      // Story Segment Indicators
                      Row(
                        children: List.generate(widget.stories.length, (index) {
                          final isWatched = index < _currentIndex;
                          final isActive = index == _currentIndex;
                          return Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              decoration: BoxDecoration(
                                color: isWatched
                                    ? Colors.white
                                    : isActive
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      // Top navigation row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.white24,
                                backgroundImage: currentStory.userAvatar.startsWith('http')
                                    ? CachedNetworkImageProvider(currentStory.userAvatar)
                                    : null,
                                child: !currentStory.userAvatar.startsWith('http')
                                    ? const Icon(Icons.person, size: 18, color: Colors.white70)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentStory.userName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Shared to ${currentStory.locationName}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // More options (delete)
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, authState) {
                                  final isOwner = authState is AuthAuthenticated &&
                                      currentStory.userId == authState.user.id;
                                  if (!isOwner) return const SizedBox.shrink();
                                  return IconButton(
                                    onPressed: _isDeletingStory ? null : _deleteCurrentStory,
                                    icon: _isDeletingStory
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 24),
                                  );
                                },
                              ),
                              // Close button
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. Main Swiping Page View
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemCount: widget.stories.length,
                    itemBuilder: (context, index) {
                      final story = widget.stories[index];
                      final isSelCatColor = _getCategoryColor(story.category);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Main image container
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.35),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _buildMainImage(story.imageUrl),
                                      // Left tap area to go to previous story
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: MediaQuery.of(context).size.width * 0.35,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (_currentIndex > 0) {
                                              _pageController.previousPage(
                                                duration: const Duration(milliseconds: 300),
                                                curve: Curves.easeInOut,
                                              );
                                            }
                                          },
                                          child: Container(color: Colors.transparent),
                                        ),
                                      ),
                                      // Right tap area to go to next story
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        left: MediaQuery.of(context).size.width * 0.35,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (_currentIndex < widget.stories.length - 1) {
                                              _pageController.nextPage(
                                                duration: const Duration(milliseconds: 300),
                                                curve: Curves.easeInOut,
                                              );
                                            }
                                          },
                                          child: Container(color: Colors.transparent),
                                        ),
                                      ),
                                      // Category Pill
                                      Positioned(
                                        top: 16,
                                        left: 16,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              color: Colors.black.withOpacity(0.4),
                                              child: Text(
                                                story.category,
                                                style: TextStyle(
                                                  color: isSelCatColor,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Location Pin overlay
                                      Positioned(
                                        bottom: 16,
                                        left: 16,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(30),
                                            border: Border.all(color: Colors.white24, width: 0.8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.location_on, size: 12, color: Colors.redAccent),
                                              const SizedBox(width: 4),
                                              Text(
                                                story.locationName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Description & Interaction section
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isExpanded = _expandedStoryIds.contains(story.id);
                                      final textSpan = TextSpan(
                                        text: story.description,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      );
                                      final tp = TextPainter(
                                        text: textSpan,
                                        maxLines: 4,
                                        textDirection: TextDirection.ltr,
                                      );
                                      tp.layout(maxWidth: constraints.maxWidth);
                                      final isLong = tp.didExceedMaxLines;

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          isExpanded
                                              ? ConstrainedBox(
                                                  constraints: const BoxConstraints(maxHeight: 150),
                                                  child: SingleChildScrollView(
                                                    physics: const BouncingScrollPhysics(),
                                                    child: Text(
                                                      story.description,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  story.description,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    height: 1.5,
                                                  ),
                                                  maxLines: 4,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                          if (isLong)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (isExpanded) {
                                                    _expandedStoryIds.remove(story.id);
                                                  } else {
                                                    _expandedStoryIds.add(story.id);
                                                  }
                                                });
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.only(top: 6),
                                                child: Text(
                                                  isExpanded ? 'See less' : 'See more',
                                                  style: const TextStyle(
                                                    color: AppColors.brandGreen,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Like story
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            if (story.isLiked) {
                                              story.isLiked = false;
                                              story.likesCount--;
                                            } else {
                                              story.isLiked = true;
                                              story.likesCount++;
                                            }
                                          });
                                          TravelStoriesService().toggleLike(story.id);
                                        },
                                        child: Row(
                                          children: [
                                            Icon(
                                              story.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                              color: story.isLiked ? Colors.redAccent : Colors.white70,
                                              size: 20,
                                            ).animate(target: story.isLiked ? 1.0 : 0.0).scale(
                                                  begin: const Offset(1.0, 1.0),
                                                  end: const Offset(1.3, 1.3),
                                                  curve: Curves.elasticOut,
                                                  duration: 350.ms,
                                                ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${story.likesCount}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Comment count / open list
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _showCommentsDialog(story),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 18),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${story.comments.length} Comments',
                                              style: const TextStyle(
                                                color: Colors.white70, 
                                                fontSize: 12, 
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // 4. Quick comment box at the very bottom
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: TextField(
                            controller: _commentController,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            decoration: InputDecoration(
                              hintText: 'Add a comment...',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13.5),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isSendingComment ? null : () => _submitComment(currentStory),
                        icon: _isSendingComment
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, color: AppColors.brandGreen),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
