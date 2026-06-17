class TravelStory {
  final String id;
  final String userName;
  final String userAvatar;
  final String locationName;
  final String category; // e.g. "Hidden Gem", "Offbeat Place", "Local Secret", "Scenic Viewpoint"
  final String description;
  final String imageUrl;
  int likesCount;
  final List<String> comments;
  final DateTime createdAt;
  bool isLiked;

  TravelStory({
    required this.id,
    required this.userName,
    required this.userAvatar,
    required this.locationName,
    required this.category,
    required this.description,
    required this.imageUrl,
    this.likesCount = 0,
    required this.comments,
    required this.createdAt,
    this.isLiked = false,
  });

  TravelStory copyWith({
    String? id,
    String? userName,
    String? userAvatar,
    String? locationName,
    String? category,
    String? description,
    String? imageUrl,
    int? likesCount,
    List<String>? comments,
    DateTime? createdAt,
    bool? isLiked,
  }) {
    return TravelStory(
      id: id ?? this.id,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      locationName: locationName ?? this.locationName,
      category: category ?? this.category,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      likesCount: likesCount ?? this.likesCount,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      isLiked: isLiked ?? this.isLiked,
    );
  }

  factory TravelStory.fromJson(Map<String, dynamic> json) {
    final commentsJson = json['comments'] as List<dynamic>? ?? [];
    final parsedComments = commentsJson.map((c) {
      final text = c['comment_text'] as String? ?? '';
      final author = c['user_display_name'] as String? ?? 'Anonymous';
      return '$author: $text';
    }).toList();

    return TravelStory(
      id: (json['id'] ?? '').toString(),
      userName: json['user_display_name'] as String? ?? 'Anonymous',
      userAvatar: json['user_avatar_url'] as String? ?? '',
      locationName: json['location_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      likesCount: json['likes_count'] as int? ?? 0,
      comments: parsedComments,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
      isLiked: json['is_liked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location_name': locationName,
      'category': category,
      'description': description,
      'image_url': imageUrl,
    };
  }
}
