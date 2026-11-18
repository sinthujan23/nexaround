class CategoryEntity {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final int sortOrder;

  const CategoryEntity({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    required this.sortOrder,
  });
}

class AttractionEntity {
  final String id;
  final String name;
  final String? description;
  final String? history;
  final double latitude;
  final double longitude;
  final String? categoryId;
  final String? categoryName;
  final String? address;
  final Map<String, dynamic> openingHours;
  final double entryFee;
  final String currency;
  final double rating;
  final int reviewCount;
  final List<String> photoUrls;
  final List<String> tags;
  final int geofenceRadiusM;
  final double? distanceM;
  final bool isActive;
  final DateTime createdAt;
  final bool excludedByKeyword;
  // Free map data (free users): our 0..100 score instead of a Google rating,
  // an optional chip ("Famous" / "Popular with travellers") and 'open' as the
  // source. Google places leave these at their defaults.
  final int popularity;
  final String? popularityLabel;
  final String? dataSource;
  // Our travellers' own ratings (server: services/place_reviews). The server
  // decides which stars a card shows: 'google', 'nexaround' (no Google rating
  // and at least 3 of ours) or 'none'. Null means an answer from before the
  // server sent it (an old cached list): the old rules apply.
  final double? ourRating;
  final int ourReviewCount;
  final String? ratingSource;

  String? get category => categoryName;

  /// True for free-map-data places: no stars, show [popularityLabel] instead.
  bool get isFreeData => dataSource == 'open';

  const AttractionEntity({
    required this.id,
    required this.name,
    this.description,
    this.history,
    required this.latitude,
    required this.longitude,
    this.categoryId,
    this.categoryName,
    this.address,
    this.openingHours = const {},
    this.entryFee = 0.0,
    this.currency = 'USD',
    this.rating = 0.0,
    this.reviewCount = 0,
    this.photoUrls = const [],
    this.tags = const [],
    this.geofenceRadiusM = 100,
    this.distanceM,
    this.isActive = true,
    required this.createdAt,
    this.excludedByKeyword = false,
    this.popularity = 0,
    this.popularityLabel,
    this.dataSource,
    this.ourRating,
    this.ourReviewCount = 0,
    this.ratingSource,
  });
}
