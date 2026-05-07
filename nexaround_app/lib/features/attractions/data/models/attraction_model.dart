import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

class CategoryModel extends CategoryEntity {
  const CategoryModel({
    required super.id,
    required super.name,
    super.icon,
    super.color,
    required super.sortOrder,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
    };
  }
}

class AttractionModel extends AttractionEntity {
  const AttractionModel({
    required super.id,
    required super.name,
    super.description,
    super.history,
    required super.latitude,
    required super.longitude,
    super.categoryId,
    super.categoryName,
    super.address,
    super.openingHours,
    super.entryFee,
    super.currency,
    super.rating,
    super.reviewCount,
    super.photoUrls,
    super.tags,
    super.geofenceRadiusM,
    super.distanceM,
    super.isActive,
    required super.createdAt,
  });

  factory AttractionModel.fromJson(Map<String, dynamic> json) {
    return AttractionModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      history: json['history'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      address: json['address'] as String?,
      openingHours: json['opening_hours'] as Map<String, dynamic>? ?? {},
      entryFee: (json['entry_fee'] as num? ?? 0.0).toDouble(),
      currency: json['currency'] as String? ?? 'USD',
      rating: (json['rating'] as num? ?? 0.0).toDouble(),
      reviewCount: json['review_count'] as int? ?? 0,
      photoUrls: (json['photo_urls'] as List<dynamic>?)?.cast<String>() ?? [],
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      geofenceRadiusM: json['geofence_radius_m'] as int? ?? 100,
      distanceM: json['distance_m'] != null ? (json['distance_m'] as num).toDouble() : null,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'history': history,
      'latitude': latitude,
      'longitude': longitude,
      'category_id': categoryId,
      'category_name': categoryName,
      'address': address,
      'opening_hours': openingHours,
      'entry_fee': entryFee,
      'currency': currency,
      'rating': rating,
      'review_count': reviewCount,
      'photo_urls': photoUrls,
      'tags': tags,
      'geofence_radius_m': geofenceRadiusM,
      'distance_m': distanceM,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
