class ForumPost {
  final String id;
  final String topicId;
  final String userId;
  final String userDisplayName;
  final String? userAvatarUrl;
  final String? parentPostId;
  final String content;
  final List<String> imageUrls;
  final int likesCount;
  final bool isBestAnswer;
  final bool isAiGenerated;
  final bool isLiked;
  final DateTime createdAt;
  final List<ForumPost> replies;

  const ForumPost({
    required this.id,
    required this.topicId,
    required this.userId,
    required this.userDisplayName,
    this.userAvatarUrl,
    this.parentPostId,
    required this.content,
    this.imageUrls = const [],
    this.likesCount = 0,
    this.isBestAnswer = false,
    this.isAiGenerated = false,
    this.isLiked = false,
    required this.createdAt,
    this.replies = const [],
  });

  factory ForumPost.fromJson(Map<String, dynamic> json) {
    var rawReplies = json['replies'];
    List<ForumPost> replyList = [];
    if (rawReplies is List) {
      replyList = rawReplies.map((e) => ForumPost.fromJson(e as Map<String, dynamic>)).toList();
    }

    var rawImages = json['image_urls'];
    List<String> images = [];
    if (rawImages is List) {
      images = rawImages.map((e) => e.toString()).toList();
    }

    DateTime parsedDate;
    try {
      parsedDate = json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return ForumPost(
      id: json['id']?.toString() ?? '',
      topicId: json['topic_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userDisplayName: json['user_display_name']?.toString() ?? 'Traveler',
      userAvatarUrl: json['user_avatar_url']?.toString(),
      parentPostId: json['parent_post_id']?.toString(),
      content: json['content']?.toString() ?? '',
      imageUrls: images,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      isBestAnswer: json['is_best_answer'] == true,
      isAiGenerated: json['is_ai_generated'] == true,
      isLiked: json['is_liked'] == true,
      createdAt: parsedDate,
      replies: replyList,
    );
  }

  ForumPost copyWith({
    bool? isLiked,
    int? likesCount,
    bool? isBestAnswer,
  }) {
    return ForumPost(
      id: id,
      topicId: topicId,
      userId: userId,
      userDisplayName: userDisplayName,
      userAvatarUrl: userAvatarUrl,
      parentPostId: parentPostId,
      content: content,
      imageUrls: imageUrls,
      likesCount: likesCount ?? this.likesCount,
      isBestAnswer: isBestAnswer ?? this.isBestAnswer,
      isAiGenerated: isAiGenerated,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt,
      replies: replies,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topic_id': topicId,
      'user_id': userId,
      'user_display_name': userDisplayName,
      'user_avatar_url': userAvatarUrl,
      'parent_post_id': parentPostId,
      'content': content,
      'image_urls': imageUrls,
      'likes_count': likesCount,
      'is_best_answer': isBestAnswer,
      'is_ai_generated': isAiGenerated,
      'is_liked': isLiked,
      'created_at': createdAt.toIso8601String(),
      'replies': replies.map((r) => r.toJson()).toList(),
    };
  }
}
