import 'forum_category.dart';
import 'forum_topic.dart';

class ForumHomeData {
  final List<ForumCategory> featuredDestinations;
  final List<ForumCategory> continentRegions;
  final List<ForumCategory> travelTopics;
  final List<ForumTopic> trendingTopics;
  final List<ForumTopic> recentTopics;
  final Map<String, dynamic> stats;

  const ForumHomeData({
    this.featuredDestinations = const [],
    this.continentRegions = const [],
    this.travelTopics = const [],
    this.trendingTopics = const [],
    this.recentTopics = const [],
    this.stats = const {},
  });

  factory ForumHomeData.fromJson(Map<String, dynamic> json) {
    List<ForumCategory> featured = [];
    if (json['featured_destinations'] is List) {
      featured = (json['featured_destinations'] as List)
          .map((e) => ForumCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<ForumCategory> regions = [];
    if (json['continent_regions'] is List) {
      regions = (json['continent_regions'] as List)
          .map((e) => ForumCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<ForumCategory> topics = [];
    if (json['travel_topics'] is List) {
      topics = (json['travel_topics'] as List)
          .map((e) => ForumCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<ForumTopic> trending = [];
    if (json['trending_topics'] is List) {
      trending = (json['trending_topics'] as List)
          .map((e) => ForumTopic.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<ForumTopic> recent = [];
    if (json['recent_topics'] is List) {
      recent = (json['recent_topics'] as List)
          .map((e) => ForumTopic.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return ForumHomeData(
      featuredDestinations: featured,
      continentRegions: regions,
      travelTopics: topics,
      trendingTopics: trending,
      recentTopics: recent,
      stats: json['stats'] is Map<String, dynamic> ? json['stats'] : {},
    );
  }
}
