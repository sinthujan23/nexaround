class TravelStoryComment {
  final String id;
  final String author;
  final String? authorId;
  final String? authorAvatar;
  final String text;
  final int imageIndex;
  final DateTime? createdAt;

  TravelStoryComment({
    required this.id,
    required this.author,
    this.authorId,
    this.authorAvatar,
    required this.text,
    this.imageIndex = 0,
    this.createdAt,
  });

  TravelStoryComment copyWith({
    String? id,
    String? author,
    String? authorId,
    String? authorAvatar,
    String? text,
    int? imageIndex,
    DateTime? createdAt,
  }) {
    return TravelStoryComment(
      id: id ?? this.id,
      author: author ?? this.author,
      authorId: authorId ?? this.authorId,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      text: text ?? this.text,
      imageIndex: imageIndex ?? this.imageIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory TravelStoryComment.fromJson(Map<String, dynamic> json) {
    return TravelStoryComment(
      id: (json['id'] ?? '').toString(),
      author: json['user_display_name'] as String? ?? json['author'] as String? ?? json['userName'] as String? ?? json['user_name'] as String? ?? 'Anonymous',
      authorId: (json['user_id'] ?? json['userId'] ?? json['author_id'] ?? json['authorId'])?.toString(),
      authorAvatar: json['user_avatar'] as String? ?? json['userAvatar'] as String? ?? json['author_avatar'] as String?,
      text: json['comment_text'] as String? ?? json['text'] as String? ?? '',
      imageIndex: json['image_index'] as int? ?? 0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_display_name': author,
      'user_id': authorId,
      'user_avatar': authorAvatar,
      'comment_text': text,
      'image_index': imageIndex,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class TravelStory {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String locationName;
  final String category; // e.g. "Hidden Gem", "Offbeat Place", "Local Secret", "Scenic Viewpoint"
  final String description;
  final String imageUrl;
  final List<String> imageUrls;
  final double? latitude;
  final double? longitude;
  int likesCount;
  final List<TravelStoryComment> comments;
  final DateTime createdAt;
  bool isLiked;
  final bool isPublic;
  
  // Journal Features
  final bool isJournal;
  final DateTime? journalDate;
  final double totalSpend;
  final String spendCurrency;
  final String? cloudProvider;
  final String? cloudFolderUrl;

  // New Fields
  final String? country;
  final DateTime? travelDate;

  TravelStory({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.locationName,
    required this.category,
    required this.description,
    required this.imageUrl,
    this.imageUrls = const [],
    this.latitude,
    this.longitude,
    this.likesCount = 0,
    required this.comments,
    required this.createdAt,
    this.isLiked = false,
    this.isPublic = true,
    this.isJournal = false,
    this.journalDate,
    this.totalSpend = 0.0,
    this.spendCurrency = 'USD',
    this.cloudProvider,
    this.cloudFolderUrl,
    this.country,
    this.travelDate,
  });

  TravelStory copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    String? locationName,
    String? category,
    String? description,
    String? imageUrl,
    List<String>? imageUrls,
    double? latitude,
    double? longitude,
    int? likesCount,
    List<TravelStoryComment>? comments,
    DateTime? createdAt,
    bool? isLiked,
    bool? isPublic,
    bool? isJournal,
    DateTime? journalDate,
    double? totalSpend,
    String? spendCurrency,
    String? cloudProvider,
    String? cloudFolderUrl,
    String? country,
    DateTime? travelDate,
  }) {
    return TravelStory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      locationName: locationName ?? this.locationName,
      category: category ?? this.category,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      likesCount: likesCount ?? this.likesCount,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      isLiked: isLiked ?? this.isLiked,
      isPublic: isPublic ?? this.isPublic,
      isJournal: isJournal ?? this.isJournal,
      journalDate: journalDate ?? this.journalDate,
      totalSpend: totalSpend ?? this.totalSpend,
      spendCurrency: spendCurrency ?? this.spendCurrency,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      cloudFolderUrl: cloudFolderUrl ?? this.cloudFolderUrl,
      country: country ?? this.country,
      travelDate: travelDate ?? this.travelDate,
    );
  }

  factory TravelStory.fromJson(Map<String, dynamic> json) {
    final commentsJson = json['comments'] as List<dynamic>? ?? [];
    final parsedComments = commentsJson.map((c) {
      if (c is Map<String, dynamic>) {
        return TravelStoryComment.fromJson(c);
      }
      return TravelStoryComment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        author: 'User',
        text: c.toString()
      );
    }).toList();

    return TravelStory(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      userName: json['user_display_name'] as String? ?? json['userName'] as String? ?? json['user_name'] as String? ?? 'Anonymous',
      userAvatar: json['user_avatar_url'] as String? ?? json['userAvatar'] as String? ?? '',
      locationName: json['location_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      imageUrls: (json['image_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? 
                 ((json['image_url'] as String? ?? '').isNotEmpty ? [json['image_url'] as String] : []),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      likesCount: json['likes_count'] as int? ?? 0,
      comments: parsedComments,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
      isLiked: json['is_liked'] as bool? ?? false,
      isPublic: json['is_public'] as bool? ?? true,
      isJournal: json['is_journal'] as bool? ?? false,
      journalDate: json['journal_date'] != null 
          ? DateTime.parse(json['journal_date'] as String) 
          : null,
      totalSpend: (json['total_spend'] as num?)?.toDouble() ?? 0.0,
      spendCurrency: json['spend_currency'] as String? ?? 'USD',
      cloudProvider: json['cloud_provider'] as String?,
      cloudFolderUrl: json['cloud_folder_url'] as String?,
      country: json['country'] as String?,
      travelDate: json['travel_date'] != null 
          ? DateTime.parse(json['travel_date'] as String) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_display_name': userName,
      'user_avatar_url': userAvatar,
      'location_name': locationName,
      'category': category,
      'description': description,
      'image_url': imageUrl,
      'image_urls': imageUrls,
      'latitude': latitude,
      'longitude': longitude,
      'likes_count': likesCount,
      'is_liked': isLiked,
      'comments': comments.map((c) => c.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'is_public': isPublic,
      'is_journal': isJournal,
      'journal_date': journalDate?.toIso8601String(),
      'total_spend': totalSpend,
      'spend_currency': spendCurrency,
      'cloud_provider': cloudProvider,
      'cloud_folder_url': cloudFolderUrl,
      'country': country,
      'travel_date': travelDate?.toIso8601String(),
    };
  }
}
