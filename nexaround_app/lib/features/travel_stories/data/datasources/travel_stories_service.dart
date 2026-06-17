import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/api_constants.dart';
import '../models/travel_story.dart';

class TravelStoriesService {
  // Singleton instance
  static final TravelStoriesService _instance = TravelStoriesService._internal();
  factory TravelStoriesService() => _instance;
  TravelStoriesService._internal();

  final Dio _dio = ApiClient.instance;

  // In-memory fallback list in case backend is offline
  final List<TravelStory> _fallbackStories = [];

  Future<List<TravelStory>> getStories() async {
    try {
      final response = await _dio.get(ApiConstants.travelStories);
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> data = response.data;
        return data.map((json) => TravelStory.fromJson(json)).toList();
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to fetch stories from backend ($e). Using fallback mock data.');
    }
    return List.from(_fallbackStories);
  }

  Future<TravelStory?> addStory(TravelStory story) async {
    try {
      final response = await _dio.post(
        ApiConstants.travelStories,
        data: story.toJson(),
      );
      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        return TravelStory.fromJson(response.data);
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to post story to backend ($e). Saving locally in fallback list.');
      // Append to fallback stories locally
      _fallbackStories.insert(0, story);
    }
    return story;
  }

  Future<void> toggleLike(String id) async {
    try {
      await _dio.post('${ApiConstants.travelStories}/$id/like');
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to toggle like on backend ($e). Toggling locally.');
      // Toggle locally on fallback list
      final index = _fallbackStories.indexWhere((s) => s.id == id);
      if (index != -1) {
        final story = _fallbackStories[index];
        if (story.isLiked) {
          story.isLiked = false;
          story.likesCount--;
        } else {
          story.isLiked = true;
          story.likesCount++;
        }
      }
    }
  }

  Future<void> addComment(String id, String commentText) async {
    try {
      await _dio.post(
        '${ApiConstants.travelStories}/$id/comment',
        data: {'comment_text': commentText},
      );
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to post comment to backend ($e). Saving locally in fallback.');
      final index = _fallbackStories.indexWhere((s) => s.id == id);
      if (index != -1) {
        _fallbackStories[index].comments.add('You @explorer_me: $commentText');
      }
    }
  }

  Future<String?> uploadImage(String filePath) async {
    try {
      final file = await MultipartFile.fromFile(
        filePath,
        filename: filePath.split('/').last.split('\\').last,
      );
      final formData = FormData.fromMap({
        'file': file,
      });

      final response = await _dio.post(
        '${ApiConstants.travelStories}/upload',
        data: formData,
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        return response.data['url'] as String;
      }
    } catch (e) {
      print('⚠️ TravelStoriesService: Failed to upload image ($e).');
    }
    return null;
  }

  // Pre-defined template images for mocked upload
  static List<Map<String, String>> getPresetPhotos() {
    return [
      {
        'title': 'Ella Train',
        'url': 'https://images.unsplash.com/photo-1546708973-b339540b5162?w=600&auto=format&fit=crop',
      },
      {
        'title': 'Pidurangala Sunrise',
        'url': 'https://images.unsplash.com/photo-1588598126702-8611846b036c?w=600&auto=format&fit=crop',
      },
      {
        'title': 'Tropical Cove',
        'url': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&auto=format&fit=crop',
      },
      {
        'title': 'Tea Plantation',
        'url': 'https://images.unsplash.com/photo-1555899434-94d1368aa7af?w=600&auto=format&fit=crop',
      },
      {
        'title': 'Safari Gathering',
        'url': 'https://images.unsplash.com/photo-1516426122078-c23e76319801?w=600&auto=format&fit=crop',
      },
      {
        'title': 'Ancient Temple',
        'url': 'https://images.unsplash.com/photo-1568790308560-f4ca6469cfbe?w=600&auto=format&fit=crop',
      },
    ];
  }
}
