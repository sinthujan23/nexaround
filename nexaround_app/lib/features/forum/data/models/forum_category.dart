class ForumCategory {
  final String id;
  final String name;
  final String slug;
  final String categoryType; // 'destination', 'region', 'topic'
  final String? parentId;
  final String? description;
  final String? imageUrl;
  final String? icon;
  final String? countryCode;
  final String? cityName;
  final bool isFeatured;
  final int topicsCount;
  final int postsCount;
  final List<ForumCategory> subcategories;

  const ForumCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.categoryType = 'destination',
    this.parentId,
    this.description,
    this.imageUrl,
    this.icon,
    this.countryCode,
    this.cityName,
    this.isFeatured = false,
    this.topicsCount = 0,
    this.postsCount = 0,
    this.subcategories = const [],
  });

  factory ForumCategory.fromJson(Map<String, dynamic> json) {
    var rawSub = json['subcategories'];
    List<ForumCategory> subList = [];
    if (rawSub is List) {
      subList = rawSub.map((e) => ForumCategory.fromJson(e as Map<String, dynamic>)).toList();
    }

    return ForumCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      categoryType: json['category_type']?.toString() ?? 'destination',
      parentId: json['parent_id']?.toString(),
      description: json['description']?.toString(),
      imageUrl: json['image_url']?.toString(),
      icon: json['icon']?.toString(),
      countryCode: json['country_code']?.toString(),
      cityName: json['city_name']?.toString(),
      isFeatured: json['is_featured'] == true,
      topicsCount: (json['topics_count'] as num?)?.toInt() ?? 0,
      postsCount: (json['posts_count'] as num?)?.toInt() ?? 0,
      subcategories: subList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'category_type': categoryType,
      'parent_id': parentId,
      'description': description,
      'image_url': imageUrl,
      'icon': icon,
      'country_code': countryCode,
      'city_name': cityName,
      'is_featured': isFeatured,
      'topics_count': topicsCount,
      'posts_count': postsCount,
      'subcategories': subcategories.map((e) => e.toJson()).toList(),
    };
  }
}
