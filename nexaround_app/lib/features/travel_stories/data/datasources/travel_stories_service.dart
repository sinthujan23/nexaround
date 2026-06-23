import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/api_constants.dart';
import '../models/travel_story.dart';

class TravelStoriesService {
  // Singleton instance
  static final TravelStoriesService _instance = TravelStoriesService._internal();
  factory TravelStoriesService() => _instance;
  TravelStoriesService._internal();

  final Dio _dio = ApiClient.instance;

  // Reference to the Hive Box we initialized in main.dart
  Box get _box => Hive.box('travel_stories_box');

  Future<List<TravelStory>> getStories() async {
    try {
      final response = await _dio.get(ApiConstants.travelStories);
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> data = response.data;
        final stories = data.map((json) => TravelStory.fromJson(json)).toList();
        
        // Cache to Hive
        await _box.clear();
        for (var s in stories) {
          await _box.add(s.toJson());
        }
        return stories;
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to fetch stories from backend ($e). Using Hive fallback.');
    }
    return _getStoriesFromHive(isJournal: false);
  }

  List<TravelStory> getCachedJournals() {
    return _getStoriesFromHive(isJournal: true);
  }

  Future<List<TravelStory>> getJournals() async {
    try {
      final response = await _dio.get('${ApiConstants.travelStories}/journal');
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> data = response.data;
        final journals = data.map((json) => TravelStory.fromJson(json)).toList();
        
        // Cache to Hive (append/update existing)
        for (var journal in journals) {
          await _updateOrAddToHive(journal);
        }
        return journals;
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to fetch journals from backend ($e). Using Hive fallback.');
    }
    return _getStoriesFromHive(isJournal: true);
  }

  Future<TravelStory?> addStory(TravelStory story) async {
    try {
      final response = await _dio.post(
        ApiConstants.travelStories,
        data: story.toJson(),
      );
      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final savedStory = TravelStory.fromJson(response.data);
        await _updateOrAddToHive(savedStory);
        return savedStory;
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to post story to backend ($e). Saving locally only.');
      await _box.add(story.toJson());
    }
    return story;
  }

  Future<void> toggleLike(String id) async {
    try {
      await _dio.post('${ApiConstants.travelStories}/$id/like');
      // Update local cache
      await _toggleLikeInHive(id);
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to toggle like on backend ($e). Toggling locally.');
      await _toggleLikeInHive(id);
    }
  }

  Future<void> addComment(String id, String commentText, int imageIndex) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.travelStories}/$id/comment',
        data: {
          'comment_text': commentText,
          'image_index': imageIndex,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Successfully added to backend, update Hive cache
        await _addCommentToHive(id, commentText, imageIndex, true);
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to post comment to backend ($e). Saving locally.');
      await _addCommentToHive(id, commentText, imageIndex, false);
    }
  }

  Future<TravelStory?> updateStory(String storyId, TravelStory updatedStory) async {
    try {
      final response = await _dio.put(
        '${ApiConstants.travelStories}/$storyId',
        data: updatedStory.toJson(),
      );
      if (response.statusCode == 200 && response.data != null) {
        final story = TravelStory.fromJson(response.data);
        await _updateOrAddToHive(story);
        return story;
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to update story on backend ($e). Updating locally.');
      await _updateOrAddToHive(updatedStory);
    }
    return updatedStory;
  }

  Future<void> deleteStory(String storyId) async {
    try {
      await _dio.delete('${ApiConstants.travelStories}/$storyId');
      await _deleteFromHive(storyId);
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to delete story from backend ($e). Deleting locally.');
      await _deleteFromHive(storyId);
    }
  }

  Future<List<String>?> uploadImages(List<String> filePaths) async {
    if (filePaths.isEmpty) return [];
    
    try {
      final formData = FormData();
      for (var path in filePaths) {
        final file = await MultipartFile.fromFile(
          path,
          filename: path.split('/').last.split('\\').last,
        );
        formData.files.add(MapEntry('files', file));
      }

      final response = await _dio.post(
        '${ApiConstants.travelStories}/upload',
        data: formData,
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        return List<String>.from(response.data['urls']);
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to upload images ($e). Fallback to local paths.');
    }
    return filePaths;
  }

  // --- Hive Helpers ---

  List<TravelStory> _getStoriesFromHive({required bool isJournal}) {
    final List<TravelStory> stories = [];
    for (var i = 0; i < _box.length; i++) {
      final Map<dynamic, dynamic>? raw = _box.getAt(i);
      if (raw != null) {
        final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
        final story = TravelStory.fromJson(jsonMap);
        if (story.isJournal == isJournal) {
          stories.add(story);
        }
      }
    }
    stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stories;
  }

  Future<void> _updateOrAddToHive(TravelStory story) async {
    bool found = false;
    for (var i = 0; i < _box.length; i++) {
      final Map<dynamic, dynamic>? raw = _box.getAt(i);
      if (raw != null) {
        final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
        if (jsonMap['id'] == story.id) {
          await _box.putAt(i, story.toJson());
          found = true;
          break;
        }
      }
    }
    if (!found) {
      await _box.add(story.toJson());
    }
  }

  Future<void> _toggleLikeInHive(String id) async {
    for (var i = 0; i < _box.length; i++) {
      final Map<dynamic, dynamic>? raw = _box.getAt(i);
      if (raw != null) {
        final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
        if (jsonMap['id'] == id) {
          final story = TravelStory.fromJson(jsonMap);
          if (story.isLiked) {
            story.isLiked = false;
            story.likesCount--;
          } else {
            story.isLiked = true;
            story.likesCount++;
          }
          await _box.putAt(i, story.toJson());
          break;
        }
      }
    }
  }

  Future<void> _addCommentToHive(String id, String commentText, int imageIndex, bool fromApi) async {
    for (var i = 0; i < _box.length; i++) {
      final Map<dynamic, dynamic>? raw = _box.getAt(i);
      if (raw != null) {
        final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
        if (jsonMap['id'] == id) {
          final story = TravelStory.fromJson(jsonMap);
          // Only add locally if the API didn't already return a fresh response,
          // though typically we'd reload the story. For simplicity we just append it.
          story.comments.add(
            TravelStoryComment(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              author: 'You',
              text: commentText,
              imageIndex: imageIndex,
            ),
          );
          await _box.putAt(i, story.toJson());
          break;
        }
      }
    }
  }

  Future<void> _deleteFromHive(String id) async {
    for (var i = 0; i < _box.length; i++) {
      final Map<dynamic, dynamic>? raw = _box.getAt(i);
      if (raw != null) {
        final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
        if (jsonMap['id'] == id) {
          await _box.deleteAt(i);
          break;
        }
      }
    }
  }
}

