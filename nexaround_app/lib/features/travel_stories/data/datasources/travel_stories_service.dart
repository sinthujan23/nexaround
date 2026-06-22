import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/travel_story.dart';

class TravelStoriesService {
  // Singleton instance
  static final TravelStoriesService _instance = TravelStoriesService._internal();
  factory TravelStoriesService() => _instance;
  TravelStoriesService._internal();

  // Reference to the Hive Box we initialized in main.dart
  Box get _box => Hive.box('travel_stories_box');

  Future<List<TravelStory>> getStories() async {
    try {
      final List<TravelStory> stories = [];

      // MIGRATION: If we have old stories in SharedPreferences, import them to Hive
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_travel_stories');
      if (cachedData != null) {
        final List<dynamic> oldData = jsonDecode(cachedData);
        for (var json in oldData) {
          final s = TravelStory.fromJson(json);
          // Only add if not already in Hive
          bool exists = false;
          for (var i = 0; i < _box.length; i++) {
            final raw = _box.getAt(i);
            if (raw != null) {
              final mapped = Map<String, dynamic>.from(raw);
              if (mapped['id'] == s.id) exists = true;
            }
          }
          if (!exists) {
            await _box.add(s.toJson());
          }
        }
        // Delete old cache so we don't migrate again
        await prefs.remove('cached_travel_stories');
      }

      // Read all saved stories from Hive
      for (var i = 0; i < _box.length; i++) {
        final Map<dynamic, dynamic>? raw = _box.getAt(i);
        if (raw != null) {
          // Convert Hive Map to standard Map<String, dynamic>
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
          stories.add(TravelStory.fromJson(jsonMap));
        }
      }
      // Sort by descending date
      stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return stories;
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to fetch stories from Hive ($e).');
      return [];
    }
  }

  Future<TravelStory?> addStory(TravelStory story) async {
    try {
      // Save directly into the Hive box
      await _box.add(story.toJson());
      return story;
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to post story to Hive ($e).');
      return null;
    }
  }

  Future<void> toggleLike(String id) async {
    try {
      for (var i = 0; i < _box.length; i++) {
        final Map<dynamic, dynamic>? raw = _box.getAt(i);
        if (raw != null) {
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
          if (jsonMap['id'] == id) {
            final story = TravelStory.fromJson(jsonMap);
            // Toggle like state
            if (story.isLiked) {
              story.isLiked = false;
              story.likesCount--;
            } else {
              story.isLiked = true;
              story.likesCount++;
            }
            // Overwrite the specific index in Hive
            await _box.putAt(i, story.toJson());
            break;
          }
        }
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to toggle like in Hive ($e).');
    }
  }

  Future<void> addComment(String id, String commentText, int imageIndex) async {
    try {
      for (var i = 0; i < _box.length; i++) {
        final Map<dynamic, dynamic>? raw = _box.getAt(i);
        if (raw != null) {
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
          if (jsonMap['id'] == id) {
            final story = TravelStory.fromJson(jsonMap);
            // Add comment
            story.comments.add(
              TravelStoryComment(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                author: 'You',
                text: commentText,
                imageIndex: imageIndex,
              ),
            );
            // Overwrite the specific index in Hive
            await _box.putAt(i, story.toJson());
            break;
          }
        }
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to post comment to Hive ($e).');
    }
  }

  Future<TravelStory?> updateStory(String storyId, TravelStory updatedStory) async {
    try {
      for (var i = 0; i < _box.length; i++) {
        final Map<dynamic, dynamic>? raw = _box.getAt(i);
        if (raw != null) {
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
          if (jsonMap['id'] == storyId) {
            await _box.putAt(i, updatedStory.toJson());
            return updatedStory;
          }
        }
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to update story in Hive ($e).');
    }
    return null;
  }

  Future<void> deleteStory(String storyId) async {
    try {
      for (var i = 0; i < _box.length; i++) {
        final Map<dynamic, dynamic>? raw = _box.getAt(i);
        if (raw != null) {
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(raw);
          if (jsonMap['id'] == storyId) {
            await _box.deleteAt(i);
            break;
          }
        }
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to delete story from Hive ($e).');
      rethrow;
    }
  }

  Future<List<String>?> uploadImages(List<String> filePaths) async {
    // The images are actually stored locally and uploaded to Google Drive.
    // This is just a passthrough that returns the local paths so the TravelStory uses the local cache URI
    // for displaying the image in the feed.
    return filePaths;
  }
}
