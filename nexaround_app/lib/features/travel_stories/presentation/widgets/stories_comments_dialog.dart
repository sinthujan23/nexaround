import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/services/avatar_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/models/travel_story.dart';
import '../../data/datasources/travel_stories_service.dart';

class StoriesCommentsDialog extends StatefulWidget {
  final TravelStory story;
  final int imageIndex;
  final Function(String, int) onCommentAdded;

  const StoriesCommentsDialog({
    super.key,
    required this.story,
    required this.imageIndex,
    required this.onCommentAdded,
  });

  @override
  State<StoriesCommentsDialog> createState() => _StoriesCommentsDialogState();
}

class _StoriesCommentsDialogState extends State<StoriesCommentsDialog> {
  final TextEditingController _commentController = TextEditingController();
  late List<TravelStoryComment> _localComments;

  @override
  void initState() {
    super.initState();
    _localComments = List<TravelStoryComment>.from(widget.story.comments);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String _resolveCurrentAvatarUrl() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final user = authState.user;
      final hasSocialPhoto = user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty;
      if (CacheService.getUseSocialAvatar() && hasSocialPhoto) {
        return user.avatarUrl!;
      } else {
        final selectedId = CacheService.getSelectedAvatarId();
        return AvatarService.getPersonaById(selectedId).avatarUrl;
      }
    }
    return AvatarService.personas.first.avatarUrl;
  }

  void _submitComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final authState = context.read<AuthBloc>().state;
    String author = 'You';
    String? authorId;
    String authorAvatar = _resolveCurrentAvatarUrl();

    if (authState is AuthAuthenticated) {
      author = authState.user.displayName;
      authorId = authState.user.id;
    }

    final newComment = TravelStoryComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: author,
      authorId: authorId,
      authorAvatar: authorAvatar,
      text: text,
      imageIndex: widget.imageIndex,
      createdAt: DateTime.now(),
    );

    widget.onCommentAdded(text, widget.imageIndex);
    TravelStoriesService().addComment(
      widget.story.id,
      text,
      widget.imageIndex,
      author: author,
      authorId: authorId,
      authorAvatar: authorAvatar,
    );

    setState(() {
      _localComments.add(newComment);
      if (!widget.story.comments.any((c) => c.id == newComment.id)) {
        widget.story.comments.add(newComment);
      }
    });
    _commentController.clear();
  }

  void _deleteComment(TravelStoryComment comment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Comment',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'Are you sure you want to delete this comment? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _localComments.removeWhere((c) => c.id == comment.id);
                widget.story.comments.removeWhere((c) => c.id == comment.id);
              });
              TravelStoriesService().deleteComment(widget.story.id, comment.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _editComment(TravelStoryComment comment) {
    final editController = TextEditingController(text: comment.text);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[350],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Edit Comment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: editController,
                    autofocus: true,
                    maxLines: 4,
                    minLines: 2,
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(14),
                      border: InputBorder.none,
                      hintText: 'Edit your comment...',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final updatedText = editController.text.trim();
                      if (updatedText.isEmpty) return;
                      Navigator.pop(ctx);
                      setState(() {
                        final idx = _localComments.indexWhere((c) => c.id == comment.id);
                        if (idx != -1) {
                          _localComments[idx] = _localComments[idx].copyWith(text: updatedText);
                        }
                        final storyIdx = widget.story.comments.indexWhere((c) => c.id == comment.id);
                        if (storyIdx != -1) {
                          widget.story.comments[storyIdx] = widget.story.comments[storyIdx].copyWith(text: updatedText);
                        }
                      });
                      TravelStoriesService().editComment(widget.story.id, comment.id, updatedText);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final currentUser = authState is AuthAuthenticated ? authState.user : null;
    final currentUserId = currentUser?.id;
    final currentUserName = currentUser?.displayName;

    final bool isPostOwner = (currentUserId != null && widget.story.userId == currentUserId) ||
        (currentUserName != null &&
            widget.story.userName.trim().toLowerCase() == currentUserName.trim().toLowerCase());

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: 1,
          )
        ],
      ),
      child: Column(
        children: [
          // Drag indicator
          Container(
            width: 38,
            height: 4.5,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: Colors.grey[350],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Comments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.story.locationName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.black54, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Comment Feed
          Expanded(
            child: _localComments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 40,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No comments yet. Share your thoughts!',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    itemCount: _localComments.length,
                    itemBuilder: (context, index) {
                      final comment = _localComments[index];

                      final bool isCommentWriter = (currentUserId != null &&
                              comment.authorId == currentUserId) ||
                          (currentUserName != null &&
                              comment.author.trim().toLowerCase() ==
                                  currentUserName.trim().toLowerCase()) ||
                          comment.author == 'You';

                      final bool canDelete = isPostOwner || isCommentWriter;
                      final bool canEdit = isCommentWriter;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar
                            _buildCommentAvatar(comment, currentUser),
                            const SizedBox(width: 12),
                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        comment.author,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (comment.author == widget.story.userName) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Author',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    comment.text,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Action Menu (Edit / Delete)
                            if (canEdit || canDelete)
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: Colors.grey,
                                  size: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editComment(comment);
                                  } else if (value == 'delete') {
                                    _deleteComment(comment);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (canEdit)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 16, color: Colors.black87),
                                          SizedBox(width: 10),
                                          Text('Edit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  if (canDelete)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                          SizedBox(width: 10),
                                          Text(
                                            'Delete',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.error,
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
                    },
                  ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Add Comment Input Bar
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Row(
                children: [
                  // Current user avatar preview
                  UserAvatarView(
                    user: currentUser,
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Colors.black87, fontSize: 14),
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13.5),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _submitComment,
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentAvatar(TravelStoryComment comment, dynamic currentUser) {
    String? avatarUrl = comment.authorAvatar;
    final initials = _getInitials(comment.author);

    // 1. If author is current user (or 'You')
    final isMe = comment.author == 'You' ||
        (currentUser != null &&
            (comment.authorId == currentUser.id ||
                comment.author.trim().toLowerCase() ==
                    currentUser.displayName.trim().toLowerCase()));

    if (isMe && currentUser != null) {
      final hasSocialPhoto = currentUser.avatarUrl != null &&
          currentUser.avatarUrl.trim().isNotEmpty;
      if (CacheService.getUseSocialAvatar() && hasSocialPhoto) {
        avatarUrl = currentUser.avatarUrl;
      } else {
        final selectedId = CacheService.getSelectedAvatarId();
        avatarUrl = AvatarService.getPersonaById(selectedId).avatarUrl;
      }
    }

    // 2. If author is story creator
    if ((avatarUrl == null || avatarUrl.trim().isEmpty) &&
        comment.author.trim().toLowerCase() ==
            widget.story.userName.trim().toLowerCase() &&
        widget.story.userAvatar.trim().isNotEmpty) {
      avatarUrl = widget.story.userAvatar;
    }

    // 3. Fallback: generate high-res modern avatar seeded by author name
    if (avatarUrl == null || avatarUrl.trim().isEmpty) {
      final cleanName = comment.author.replaceAll('@', '').trim();
      final seed = Uri.encodeComponent(cleanName.isEmpty ? 'Traveler' : cleanName);
      avatarUrl = 'https://api.dicebear.com/7.x/lorelei/png?seed=$seed&backgroundColor=ffd5dc&radius=50&size=128';
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => _buildInitialsAvatar(initials),
          errorWidget: (_, __, ___) => _buildInitialsAvatar(initials),
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar(String initials) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _getInitials(String author) {
    final parts = author.replaceAll('@', '').trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].substring(0, min(2, parts[0].length)).toUpperCase();
    }
    return '??';
  }
}
