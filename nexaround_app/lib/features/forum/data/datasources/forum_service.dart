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

  // ── In-Memory Cache Store ──────────────────────────────────────────────────
  ForumHomeData? _cachedHomeData;
  final Map<String, ForumTopic> _cachedTopics = {};

  Future<ForumHomeData> getForumHome() async {
    try {
      final response = await _dio.get(ApiConstants.forumHome);
      if (response.statusCode == 200 && response.data != null) {
        _cachedHomeData = ForumHomeData.fromJson(response.data as Map<String, dynamic>);
        return _cachedHomeData!;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getForumHome failed ($e).');
    }

    if (_cachedHomeData != null) return _cachedHomeData!;
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
        return list;
      }
    } catch (e) {
      debugPrint('⚠️ ForumService.getTopics failed ($e).');
    }

    return [];
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
        _cachedTopics.remove(topicId);
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
