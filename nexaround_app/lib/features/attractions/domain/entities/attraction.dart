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
  });
}
