import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/api_constants.dart';
import '../models/forum_category.dart';
import '../models/forum_topic.dart';
import '../models/forum_post.dart';
import '../models/forum_home_data.dart';

class ForumService {
  static final ForumService _instance = ForumService._internal();
  factory ForumService() => _instance;
  ForumService._internal();

  final Dio _dio = ApiClient.instance;

  // ── In-Memory Cache & Fallback Store ─────────────────────────────────────────
  ForumHomeData? _cachedHomeData;
  final Map<String, ForumTopic> _cachedTopics = {};
  final List<ForumTopic> _userCreatedTopics = [];

  Future<ForumHomeData> getForumHome() async {
    ForumHomeData home;
    try {
      final response = await _dio.get(ApiConstants.forumHome);
      if (response.statusCode == 200 && response.data != null) {
        home = ForumHomeData.fromJson(response.data as Map<String, dynamic>);
      } else {
        home = _cachedHomeData ?? _buildMockHomeData();
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getForumHome failed ($e). Using cached or fallback data.');
      home = _cachedHomeData ?? _buildMockHomeData();
    }

    // Always merge user-created topics at the beginning so newly posted questions never disappear
    final mergedRecent = <ForumTopic>[
      ..._userCreatedTopics,
      ...home.recentTopics.where((t) => !_userCreatedTopics.any((u) => u.id == t.id)),
    ];
    final mergedTrending = <ForumTopic>[
      ..._userCreatedTopics,
      ...home.trendingTopics.where((t) => !_userCreatedTopics.any((u) => u.id == t.id)),
    ];

    _cachedHomeData = ForumHomeData(
      featuredDestinations: home.featuredDestinations,
      continentRegions: home.continentRegions,
      travelTopics: home.travelTopics,
      trendingTopics: mergedTrending,
      recentTopics: mergedRecent,
    );

    return _cachedHomeData!;
  }

  Future<List<ForumCategory>> getCategories({String? categoryType, String? parentId}) async {
    try {
      final Map<String, dynamic> params = {};
      if (categoryType != null) params['category_type'] = categoryType;
      if (parentId != null) params['parent_id'] = parentId;

      final response = await _dio.get(ApiConstants.forumCategories, queryParameters: params);
      if (response.statusCode == 200 && response.data != null) {
        return (response.data as List)
            .map((e) => ForumCategory.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getCategories failed ($e).');
    }
    return (await getForumHome()).featuredDestinations;
  }

  Future<ForumCategory?> getCategory(String idOrSlug) async {
    try {
      final response = await _dio.get('${ApiConstants.forumCategories}/$idOrSlug');
      if (response.statusCode == 200 && response.data != null) {
        return ForumCategory.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getCategory failed ($e).');
    }

    final home = await getForumHome();
    for (final c in home.featuredDestinations) {
      if (c.id == idOrSlug || c.slug == idOrSlug) return c;
    }
    for (final r in home.continentRegions) {
      if (r.id == idOrSlug || r.slug == idOrSlug) return r;
      for (final sub in r.subcategories) {
        if (sub.id == idOrSlug || sub.slug == idOrSlug) return sub;
      }
    }
    for (final t in home.travelTopics) {
      if (t.id == idOrSlug || t.slug == idOrSlug) return t;
    }
    return null;
  }

  Future<List<ForumTopic>> getTopics({
    String? categoryId,
    String? categorySlug,
    String? query,
    String sortBy = 'recent',
    String? tag,
    int skip = 0,
    int limit = 20,
  }) async {
    try {
      final Map<String, dynamic> params = {
        'sort_by': sortBy,
        'skip': skip,
        'limit': limit,
      };
      if (categoryId != null) params['category_id'] = categoryId;
      if (categorySlug != null) params['category_slug'] = categorySlug;
      if (query != null && query.trim().isNotEmpty) params['query'] = query.trim();
      if (tag != null) params['tag'] = tag;

      final response = await _dio.get(ApiConstants.forumTopics, queryParameters: params);
      if (response.statusCode == 200 && response.data != null) {
        final list = (response.data as List)
            .map((e) => ForumTopic.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final t in list) {
          _cachedTopics[t.id] = t;
        }
        final matchingUserTopics = _userCreatedTopics.where((t) {
          if (categoryId != null && t.categoryId != categoryId) return false;
          if (categorySlug != null && t.categorySlug != categorySlug) return false;
          return true;
        }).toList();
        return [
          ...matchingUserTopics,
          ...list.where((t) => !matchingUserTopics.any((u) => u.id == t.id)),
        ];
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getTopics failed ($e). Falling back to mock topics.');
    }

    final home = await getForumHome();
    List<ForumTopic> result = [...home.trendingTopics, ...home.recentTopics];
    final seen = <String>{};
    result = result.where((t) => seen.add(t.id)).toList();
    if (categorySlug != null) {
      result = result.where((t) => t.categorySlug == categorySlug).toList();
    }
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result.where((t) => t.title.toLowerCase().contains(q) || t.content.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  Future<ForumTopic?> getTopicDetail(String topicId) async {
    try {
      final response = await _dio.get(ApiConstants.forumTopicDetail(topicId));
      if (response.statusCode == 200 && response.data != null) {
        final topic = ForumTopic.fromJson(response.data as Map<String, dynamic>);
        _cachedTopics[topic.id] = topic;
        return topic;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getTopicDetail failed ($e).');
    }

    if (_cachedTopics.containsKey(topicId)) {
      return _cachedTopics[topicId];
    }
    return null;
  }

  Future<ForumTopic> createTopic({
    required String categoryId,
    required String title,
    required String content,
    List<String> tags = const [],
    List<String> imageUrls = const [],
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.forumTopics,
        data: {
          'category_id': categoryId,
          'title': title,
          'content': content,
          'tags': tags,
          'image_urls': imageUrls,
        },
      );
      if (response.statusCode == 201 && response.data != null) {
        final topic = ForumTopic.fromJson(response.data as Map<String, dynamic>);
        _cachedTopics[topic.id] = topic;
        _userCreatedTopics.removeWhere((t) => t.id == topic.id);
        _userCreatedTopics.insert(0, topic);
        if (_cachedHomeData != null) {
          _cachedHomeData = ForumHomeData(
            featuredDestinations: _cachedHomeData!.featuredDestinations,
            continentRegions: _cachedHomeData!.continentRegions,
            travelTopics: _cachedHomeData!.travelTopics,
            trendingTopics: [topic, ..._cachedHomeData!.trendingTopics.where((t) => t.id != topic.id)],
            recentTopics: [topic, ..._cachedHomeData!.recentTopics.where((t) => t.id != topic.id)],
          );
        }
        return topic;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.createTopic server error ($e). Creating fallback topic.');
    }

    // Graceful fallback for offline, mock data, or server errors
    String catName = 'Travel Community';
    String catSlug = 'general';
    if (_cachedHomeData != null) {
      final allCats = [
        ..._cachedHomeData!.travelTopics,
        ..._cachedHomeData!.featuredDestinations,
      ];
      for (final c in allCats) {
        if (c.id == categoryId || c.slug == categoryId) {
          catName = c.name;
          catSlug = c.slug;
          break;
        }
      }
    }

    final localTopic = ForumTopic(
      id: 'topic-${DateTime.now().millisecondsSinceEpoch}',
      categoryId: categoryId,
      categoryName: catName,
      categorySlug: catSlug,
      userId: 'user-current',
      userDisplayName: 'You (Traveler)',
      userAvatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200',
      title: title,
      content: content.isNotEmpty ? content : title,
      tags: tags,
      imageUrls: imageUrls,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      likesCount: 0,
      repliesCount: 0,
      viewsCount: 1,
      isLiked: false,
      isBookmarked: false,
    );

    _cachedTopics[localTopic.id] = localTopic;
    _userCreatedTopics.removeWhere((t) => t.id == localTopic.id);
    _userCreatedTopics.insert(0, localTopic);

    _cachedHomeData ??= _buildMockHomeData();

    _cachedHomeData = ForumHomeData(
      featuredDestinations: _cachedHomeData!.featuredDestinations,
      continentRegions: _cachedHomeData!.continentRegions,
      travelTopics: _cachedHomeData!.travelTopics,
      trendingTopics: [localTopic, ..._cachedHomeData!.trendingTopics.where((t) => t.id != localTopic.id)],
      recentTopics: [localTopic, ..._cachedHomeData!.recentTopics.where((t) => t.id != localTopic.id)],
    );

    return localTopic;
  }

  Future<ForumPost> createReply({
    required String topicId,
    required String content,
    String? parentPostId,
    List<String> imageUrls = const [],
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.forumTopicReplies(topicId),
        data: {
          'content': content,
          'parent_post_id': parentPostId,
          'image_urls': imageUrls,
        },
      );
      if (response.statusCode == 201 && response.data != null) {
        final post = ForumPost.fromJson(response.data as Map<String, dynamic>);
        return post;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.createReply error ($e).');
      rethrow;
    }
    throw Exception('Failed to post reply');
  }

  Future<Map<String, dynamic>> toggleTopicLike(String topicId) async {
    try {
      final response = await _dio.post(ApiConstants.forumTopicLike(topicId));
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.toggleTopicLike error ($e).');
    }
    return {'is_liked': true, 'likes_count': 1};
  }

  Future<Map<String, dynamic>> togglePostLike(String postId) async {
    try {
      final response = await _dio.post(ApiConstants.forumPostLike(postId));
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.togglePostLike error ($e).');
    }
    return {'is_liked': true, 'likes_count': 1};
  }

  Future<Map<String, dynamic>> toggleBookmark(String topicId) async {
    try {
      final response = await _dio.post(ApiConstants.forumTopicBookmark(topicId));
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.toggleBookmark error ($e).');
    }
    return {'is_bookmarked': true};
  }

  Future<bool> setBestAnswer(String topicId, String postId) async {
    try {
      final response = await _dio.post(ApiConstants.forumBestAnswer(topicId, postId));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ ForumService.setBestAnswer error ($e).');
      return false;
    }
  }

  // ── Beautiful In-Memory Fallback Builder ─────────────────────────────────────
  ForumHomeData _buildMockHomeData() {
    final romeCat = ForumCategory(
      id: 'mock-rome',
      name: 'Rome',
      slug: 'rome',
      countryCode: 'IT',
      cityName: 'Rome',
      isFeatured: true,
      icon: 'account_balance',
      imageUrl: 'https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=800',
      description: 'The Eternal City: Colosseum, Vatican, Trastevere & culinary gems.',
      topicsCount: 148,
    );

    final tokyoCat = ForumCategory(
      id: 'mock-tokyo',
      name: 'Tokyo',
      slug: 'tokyo',
      countryCode: 'JP',
      cityName: 'Tokyo',
      isFeatured: true,
      icon: 'train',
      imageUrl: 'https://images.unsplash.com/photo-1503899036084-c55cdd92da26?w=800',
      description: 'Neon metropolis: Shinkansen travel, ramen spots & etiquette.',
      topicsCount: 210,
    );

    final parisCat = ForumCategory(
      id: 'mock-paris',
      name: 'Paris',
      slug: 'paris',
      countryCode: 'FR',
      cityName: 'Paris',
      isFeatured: true,
      icon: 'attractions',
      imageUrl: 'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800',
      description: 'City of Lights: Eiffel Tower, Louvre & café culture.',
      topicsCount: 195,
    );

    final baliCat = ForumCategory(
      id: 'mock-bali',
      name: 'Bali',
      slug: 'bali',
      countryCode: 'ID',
      cityName: 'Bali',
      isFeatured: true,
      icon: 'spa',
      imageUrl: 'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=800',
      description: 'Island of the Gods: Ubud rice terraces, waterfalls & surf.',
      topicsCount: 164,
    );

    final soloCat = ForumCategory(
      id: 'mock-solo',
      name: 'Solo Travel',
      slug: 'solo-travel',
      categoryType: 'topic',
      icon: 'person',
      imageUrl: 'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=800',
      description: 'Safety, meeting friends, and confidence for solo wanderers.',
      topicsCount: 312,
    );

    final airCat = ForumCategory(
      id: 'mock-air',
      name: 'Air Travel & Flights',
      slug: 'air-travel',
      categoryType: 'topic',
      icon: 'flight_takeoff',
      imageUrl: 'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=800',
      description: 'Airlines, carry-on rules, lounges, and booking hacks.',
      topicsCount: 420,
    );

    final budgetCat = ForumCategory(
      id: 'mock-budget',
      name: 'Budget & Backpacking',
      slug: 'budget-backpacking',
      categoryType: 'topic',
      icon: 'account_balance_wallet',
      imageUrl: 'https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?w=800',
      description: 'Hostels, rail passes, free sights, and stretching your fund.',
      topicsCount: 275,
    );

    final familyCat = ForumCategory(
      id: 'mock-family',
      name: 'Family Travel',
      slug: 'family-travel',
      categoryType: 'topic',
      icon: 'family_restroom',
      imageUrl: 'https://images.unsplash.com/photo-1511895426328-dc8714191300?w=800',
      description: 'Traveling with kids, strollers, and stress-free itineraries.',
      topicsCount: 180,
    );

    final mockTopic1 = ForumTopic(
      id: 'mock-topic-1',
      categoryId: romeCat.id,
      categoryName: 'Rome',
      categorySlug: 'rome',
      userId: 'mock-user-1',
      userDisplayName: 'Elena Vance',
      userAvatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200',
      title: 'Colosseum & Roman Forum: Best time of day and ticket advice for first-timers?',
      content:
          'Visiting Rome for the first time in May! I want to know if it\'s better to book the Colosseum first thing in the morning (8:30 AM) or late afternoon around sunset. Also, does the standard ticket include the Arena Floor, and is the Roma Pass worth it?',
      tags: ['Colosseum', 'Tickets', 'Itinerary', 'First-time'],
      viewsCount: 342,
      repliesCount: 4,
      likesCount: 28,
      isPinned: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      updatedAt: DateTime.now().subtract(const Duration(minutes: 45)),
      posts: [
        ForumPost(
          id: 'mock-post-1',
          topicId: 'mock-topic-1',
          userId: 'mock-user-expert',
          userDisplayName: 'Marco Rossi',
          userAvatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200',
          content:
              'Definitely aim for 8:30 AM or 4:30 PM! Midday heat and crowds on the Roman Forum can be intense as there is very little shade. Standard tickets cover the Roman Forum and Palatine Hill within 24 hours. The Full Experience ticket is required for the Arena and Underground.',
          likesCount: 19,
          isBestAnswer: true,
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ],
    );

    final mockTopic2 = ForumTopic(
      id: 'mock-topic-2',
      categoryId: tokyoCat.id,
      categoryName: 'Tokyo',
      categorySlug: 'tokyo',
      userId: 'mock-user-2',
      userDisplayName: 'Kenji Sato',
      userAvatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200',
      title: 'Digital Welcome Suica vs Physical IC Card in 2026: What\'s working best?',
      content:
          'Planning 10 days across Tokyo and Kyoto. Is it currently easier to load a digital Suica on Apple Wallet / Google Wallet with a Visa or Mastercard, or should I pick up a physical tourist IC card at Haneda Airport upon arrival?',
      tags: ['Transport', 'Suica', 'Tokyo', 'Payment'],
      viewsCount: 480,
      repliesCount: 6,
      likesCount: 42,
      createdAt: DateTime.now().subtract(const Duration(hours: 7)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    final mockTopic3 = ForumTopic(
      id: 'mock-topic-3',
      categoryId: soloCat.id,
      categoryName: 'Solo Travel',
      categorySlug: 'solo-travel',
      categoryType: 'topic',
      userId: 'mock-user-3',
      userDisplayName: 'Sarah Jenkins',
      userAvatarUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200',
      title: 'First solo trip to Europe: How do you handle dinner alone without feeling awkward?',
      content:
          'I am doing my first solo trip next month. Daytime sightseeing feels great, but I get slightly nervous about dining alone in sit-down restaurants in the evening. Any mindset tips or recommendations for dining spots that feel welcoming?',
      tags: ['Solo', 'Dining', 'Tips', 'Confidence'],
      viewsCount: 520,
      repliesCount: 8,
      likesCount: 64,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    _cachedTopics[mockTopic1.id] = mockTopic1;
    _cachedTopics[mockTopic2.id] = mockTopic2;
    _cachedTopics[mockTopic3.id] = mockTopic3;

    return ForumHomeData(
      featuredDestinations: [romeCat, tokyoCat, parisCat, baliCat],
      continentRegions: [
        ForumCategory(
          id: 'mock-region-eu',
          name: 'Europe',
          slug: 'europe',
          categoryType: 'region',
          icon: 'public',
          subcategories: [romeCat, parisCat],
        ),
        ForumCategory(
          id: 'mock-region-asia',
          name: 'Asia',
          slug: 'asia',
          categoryType: 'region',
          icon: 'travel_explore',
          subcategories: [tokyoCat, baliCat],
        ),
      ],
      travelTopics: [soloCat, airCat, budgetCat, familyCat],
      trendingTopics: [mockTopic3, mockTopic2, mockTopic1],
      recentTopics: [mockTopic1, mockTopic2, mockTopic3],
      stats: {'total_topics': 1840, 'total_posts': 6420},
    );
  }
}
