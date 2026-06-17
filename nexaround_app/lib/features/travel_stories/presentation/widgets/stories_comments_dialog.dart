import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/travel_story.dart';

class StoriesCommentsDialog extends StatefulWidget {
  final TravelStory story;
  final Function(String) onCommentAdded;

  const StoriesCommentsDialog({
    super.key,
    required this.story,
    required this.onCommentAdded,
  });

  @override
  State<StoriesCommentsDialog> createState() => _StoriesCommentsDialogState();
}

class _StoriesCommentsDialogState extends State<StoriesCommentsDialog> {
  final TextEditingController _commentController = TextEditingController();
  late List<String> _localComments;

  @override
  void initState() {
    super.initState();
    _localComments = List.from(widget.story.comments);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    widget.onCommentAdded(text);
    setState(() {
      _localComments.add(text);
    });
    _commentController.clear();
    // Scroll list down to see comment
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1018).withOpacity(0.95), // Premium dark theme matching app
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            children: [
              // Drag indicator
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.story.locationName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),

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
                              color: Colors.white.withOpacity(0.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No comments yet. Share your thoughts!',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        itemCount: _localComments.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.white12,
                                  child: Text(
                                    _getInitials(index),
                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getAuthorName(index),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _localComments[index].contains(': ')
                                            ? _localComments[index].substring(_localComments[index].indexOf(': ') + 2)
                                            : _localComments[index],
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.3,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
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

              const Divider(height: 1, color: Colors.white12),

              // Add Comment Input Bar
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                          ),
                          child: TextField(
                            controller: _commentController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: 'Add a comment...',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13.5),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _submitComment,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: Color(0xFF0A1018),
                            size: 16,
                          ),
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
    );
  }

  String _getInitials(int index) {
    final rawComment = _localComments[index];
    if (rawComment.contains(': ')) {
      final author = rawComment.split(': ').first;
      final parts = author.replaceAll('@', '').split(' ');
      if (parts.length >= 2) {
        return (parts[0][0] + parts[1][0]).toUpperCase();
      }
      return author.substring(0, min(2, author.length)).toUpperCase();
    }
    if (index == _localComments.length - 1 && _commentController.text.isEmpty) {
      return 'ME';
    }
    final initials = ['JD', 'EM', 'SL', 'AK', 'MB'];
    return initials[index % initials.length];
  }

  String _getAuthorName(int index) {
    final rawComment = _localComments[index];
    if (rawComment.contains(': ')) {
      return rawComment.split(': ').first;
    }
    if (index == _localComments.length - 1 && _commentController.text.isEmpty) {
      return 'You @explorer_me';
    }
    final names = ['Jane Doe @jane_d', 'Ethan Miller @ethan_m', 'Sithmi Lokuge @sithmi', 'Arun Kumar @arunk', 'Maya Brown @mayab'];
    return names[index % names.length];
  }
}
