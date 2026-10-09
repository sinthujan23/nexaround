import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/cache_service.dart';
import '../models/forum_category.dart';
import '../models/forum_topic.dart';
import '../models/forum_post.dart';
import '../models/forum_home_data.dart';

class ForumService {
  static final ForumService _instance = ForumService._internal();
  factory ForumService() => _instance;
  ForumService._internal();

  final Dio _dio = ApiClient.instance;

  // ── Multi-Tier Cache Store (Memory + SharedPreferences) ───────────────────
  ForumHomeData? _cachedHomeData;
  final Map<String, ForumTopic> _cachedTopics = {};
  final Map<String, List<ForumTopic>> _cachedCategoryTopics = {};

  /// Fast synchronous lookup for Forum Home (zero-latency instant render)
  ForumHomeData? getCachedForumHome() {
    if (_cachedHomeData != null) return _cachedHomeData;
    final diskJson = CacheService.getCachedForumHome();
    if (diskJson != null) {
      try {
        final data = ForumHomeData.fromJson(diskJson);
        _cachedHomeData = data;
        for (final t in data.trendingTopics) {
          _cachedTopics[t.id] = t;
        }
        for (final t in data.recentTopics) {
          _cachedTopics[t.id] = t;
        }
        return data;
      } catch (_) {}
    }
    return null;
  }

  Future<ForumHomeData> getForumHome() async {
    try {
      final response = await _dio.get(ApiConstants.forumHome);
      if (response.statusCode == 200 && response.data != null) {
        final rawMap = response.data as Map<String, dynamic>;
        _cachedHomeData = ForumHomeData.fromJson(rawMap);
        CacheService.cacheForumHome(rawMap);
        for (final t in _cachedHomeData!.trendingTopics) {
          _cachedTopics[t.id] = t;
        }
        for (final t in _cachedHomeData!.recentTopics) {
          _cachedTopics[t.id] = t;
        }
        return _cachedHomeData!;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getForumHome failed ($e).');
    }

    final cached = getCachedForumHome();
    if (cached != null) return cached;
    return const ForumHomeData(
      featuredDestinations: [],
      continentRegions: [],
      travelTopics: [],
      trendingTopics: [],
      recentTopics: [],
      stats: {'total_topics': 0, 'total_posts': 0},
    );
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

  /// Fast synchronous lookup for Category Topics (zero-latency instant render)
  List<ForumTopic>? getCachedTopics({String? categorySlug}) {
    if (categorySlug != null) {
      if (_cachedCategoryTopics.containsKey(categorySlug)) {
        return _cachedCategoryTopics[categorySlug];
      }
      final rawList = CacheService.getCachedForumCategoryTopics(categorySlug);
      if (rawList != null && rawList.isNotEmpty) {
        try {
          final list = rawList.map((e) => ForumTopic.fromJson(e)).toList();
          _cachedCategoryTopics[categorySlug] = list;
          for (final t in list) {
            _cachedTopics[t.id] = t;
          }
          return list;
        } catch (_) {}
      }
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
        final rawList = (response.data as List).cast<Map<String, dynamic>>();
        final list = rawList.map((e) => ForumTopic.fromJson(e)).toList();
        for (final t in list) {
          _cachedTopics[t.id] = t;
        }
        if (categorySlug != null && (query == null || query.isEmpty) && tag == null && skip == 0) {
          _cachedCategoryTopics[categorySlug] = list;
          CacheService.cacheForumCategoryTopics(categorySlug, rawList);
        }
        return list;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getTopics failed ($e).');
    }

    if (categorySlug != null) {
      final fallback = getCachedTopics(categorySlug: categorySlug);
      if (fallback != null) return fallback;
    }
    return [];
  }

  /// Fast synchronous lookup for Question Thread & Replies
  ForumTopic? getCachedTopicDetail(String topicId) {
    if (_cachedTopics.containsKey(topicId)) {
      final t = _cachedTopics[topicId]!;
      if (t.posts.isNotEmpty) return t;
    }
    final diskJson = CacheService.getCachedForumTopicDetail(topicId);
    if (diskJson != null) {
      try {
        final t = ForumTopic.fromJson(diskJson);
        _cachedTopics[topicId] = t;
        return t;
      } catch (_) {}
    }
    return _cachedTopics[topicId];
  }

  Future<ForumTopic?> getTopicDetail(String topicId) async {
    try {
      final response = await _dio.get(ApiConstants.forumTopicDetail(topicId));
      if (response.statusCode == 200 && response.data != null) {
        final rawMap = response.data as Map<String, dynamic>;
        final topic = ForumTopic.fromJson(rawMap);
        _cachedTopics[topic.id] = topic;
        CacheService.cacheForumTopicDetail(topic.id, rawMap);
        return topic;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getTopicDetail failed ($e).');
    }

    return getCachedTopicDetail(topicId);
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
        final rawMap = response.data as Map<String, dynamic>;
        final topic = ForumTopic.fromJson(rawMap);
        _cachedTopics[topic.id] = topic;
        CacheService.cacheForumTopicDetail(topic.id, rawMap);

        // Optimistically update home cache
        if (_cachedHomeData != null) {
          _cachedHomeData = ForumHomeData(
            featuredDestinations: _cachedHomeData!.featuredDestinations,
            continentRegions: _cachedHomeData!.continentRegions,
            travelTopics: _cachedHomeData!.travelTopics,
            trendingTopics: [topic, ..._cachedHomeData!.trendingTopics],
            recentTopics: [topic, ..._cachedHomeData!.recentTopics],
            stats: _cachedHomeData!.stats,
          );
          CacheService.cacheForumHome(_cachedHomeData!.toJson());
        }

        // Optimistically update category topics cache
        if (topic.categorySlug.isNotEmpty && _cachedCategoryTopics.containsKey(topic.categorySlug)) {
          _cachedCategoryTopics[topic.categorySlug] = [
            topic,
            ..._cachedCategoryTopics[topic.categorySlug]!.where((t) => t.id != topic.id)
          ];
          CacheService.cacheForumCategoryTopics(
            topic.categorySlug,
            _cachedCategoryTopics[topic.categorySlug]!.map((e) => e.toJson()).toList(),
          );
        }

        return topic;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.createTopic error ($e).');
      rethrow;
    }
    throw Exception('Failed to create topic');
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

        // Optimistically update cached topic with the new reply
        final existingTopic = _cachedTopics[topicId];
        if (existingTopic != null) {
          final updatedTopic = existingTopic.copyWith(
            posts: [...existingTopic.posts, post],
            repliesCount: existingTopic.repliesCount + 1,
          );
          _cachedTopics[topicId] = updatedTopic;
          CacheService.cacheForumTopicDetail(topicId, updatedTopic.toJson());
        }

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

  Future<bool> deleteTopic(String topicId) async {
    try {
      final response = await _dio.delete(ApiConstants.forumTopicDelete(topicId));
      if (response.statusCode == 200 || response.statusCode == 204) {
        final removed = _cachedTopics.remove(topicId);
        if (removed != null && removed.categorySlug.isNotEmpty) {
          _cachedCategoryTopics[removed.categorySlug]?.removeWhere((t) => t.id == topicId);
        }
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.deleteTopic error ($e).');
    }
    return false;
  }

  Future<bool> deletePost(String postId) async {
    try {
      final response = await _dio.delete(ApiConstants.forumPostDelete(postId));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('⚠️ ForumService.deletePost error ($e).');
    }
    return false;
  }
}
