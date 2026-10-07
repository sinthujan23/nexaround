import 'forum_post.dart';

class ForumTopic {
  final String id;
  final String categoryId;
  final String categoryName;
  final String categorySlug;
  final String categoryType;
  final String userId;
  final String userDisplayName;
  final String? userAvatarUrl;
  final String title;
  final String content;
  final List<String> tags;
  final List<String> imageUrls;
  final int viewsCount;
  final int repliesCount;
  final int likesCount;
  final bool isPinned;
  final bool isLocked;
  final String? bestAnswerId;
  final String? aiSummary;
  final bool isLiked;
  final bool isBookmarked;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ForumPost> posts;

  const ForumTopic({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categorySlug,
    this.categoryType = 'destination',
    required this.userId,
    required this.userDisplayName,
    this.userAvatarUrl,
    required this.title,
    required this.content,
    this.tags = const [],
    this.imageUrls = const [],
    this.viewsCount = 0,
    this.repliesCount = 0,
    this.likesCount = 0,
    this.isPinned = false,
    this.isLocked = false,
    this.bestAnswerId,
    this.aiSummary,
    this.isLiked = false,
    this.isBookmarked = false,
    required this.createdAt,
    required this.updatedAt,
    this.posts = const [],
  });

  factory ForumTopic.fromJson(Map<String, dynamic> json) {
    var rawTags = json['tags'];
    List<String> tagList = [];
    if (rawTags is List) {
      tagList = rawTags.map((e) => e.toString()).toList();
    }

    var rawImages = json['image_urls'];
    List<String> imageList = [];
    if (rawImages is List) {
      imageList = rawImages.map((e) => e.toString()).toList();
    }

    var rawPosts = json['posts'];
    List<ForumPost> postList = [];
    if (rawPosts is List) {
      postList = rawPosts.map((e) => ForumPost.fromJson(e as Map<String, dynamic>)).toList();
    }

    DateTime parsedCreated;
    try {
      parsedCreated = json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now();
    } catch (_) {
      parsedCreated = DateTime.now();
    }

    DateTime parsedUpdated;
    try {
      parsedUpdated = json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : parsedCreated;
    } catch (_) {
      parsedUpdated = parsedCreated;
    }

    return ForumTopic(
      id: json['id']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
      categorySlug: json['category_slug']?.toString() ?? '',
      categoryType: json['category_type']?.toString() ?? 'destination',
      userId: json['user_id']?.toString() ?? '',
      userDisplayName: json['user_display_name']?.toString() ?? 'Traveler',
      userAvatarUrl: json['user_avatar_url']?.toString(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      tags: tagList,
      imageUrls: imageList,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      repliesCount: (json['replies_count'] as num?)?.toInt() ?? 0,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      isPinned: json['is_pinned'] == true,
      isLocked: json['is_locked'] == true,
      bestAnswerId: json['best_answer_id']?.toString(),
      aiSummary: json['ai_summary']?.toString(),
      isLiked: json['is_liked'] == true,
      isBookmarked: json['is_bookmarked'] == true,
      createdAt: parsedCreated,
      updatedAt: parsedUpdated,
      posts: postList,
    );
  }

  ForumTopic copyWith({
    bool? isLiked,
    int? likesCount,
    bool? isBookmarked,
    int? repliesCount,
    List<ForumPost>? posts,
    String? bestAnswerId,
  }) {
    return ForumTopic(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      categorySlug: categorySlug,
      categoryType: categoryType,
      userId: userId,
      userDisplayName: userDisplayName,
      userAvatarUrl: userAvatarUrl,
      title: title,
      content: content,
      tags: tags,
      imageUrls: imageUrls,
      viewsCount: viewsCount,
      repliesCount: repliesCount ?? this.repliesCount,
      likesCount: likesCount ?? this.likesCount,
      isPinned: isPinned,
      isLocked: isLocked,
      bestAnswerId: bestAnswerId ?? this.bestAnswerId,
      aiSummary: aiSummary,
      isLiked: isLiked ?? this.isLiked,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      createdAt: createdAt,
      updatedAt: updatedAt,
      posts: posts ?? this.posts,
    );
  }
}
