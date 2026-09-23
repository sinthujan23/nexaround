import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';

/// Hand-written JSON parsing, matching the convention in
/// `features/attractions/data/models/attraction_model.dart`. There is no
/// freezed/json_serializable codegen in this area of the app.
///
/// Every read uses `as X?` with a default, which means a backend field rename
/// is silent here — it becomes a default rather than an error. The contract
/// test `test_the_package_card_still_carries_every_field_the_app_parses` in
/// `nexaround_backend/tests/test_experiences.py` pins these key names for
/// exactly that reason; update both together.
class ExperienceVendorModel extends ExperienceVendorEntity {
  const ExperienceVendorModel({
    required super.id,
    required super.name,
    super.description,
    super.address,
    required super.latitude,
    required super.longitude,
    super.contactPhone,
    super.contactWhatsapp,
    super.contactInstagram,
    super.contactFacebook,
    super.contactX,
    super.website,
    super.logoUrl,
    super.photoUrls,
    super.rating,
    super.reviewCount,
  });

  factory ExperienceVendorModel.fromJson(Map<String, dynamic> json) {
    return ExperienceVendorModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      contactPhone: json['contact_phone'] as String?,
      contactWhatsapp: json['contact_whatsapp'] as String?,
      contactInstagram: json['contact_instagram'] as String?,
      contactFacebook: json['contact_facebook'] as String?,
      contactX: json['contact_x'] as String?,
      website: json['website'] as String?,
      logoUrl: json['logo_url'] as String?,
      photoUrls: _stringList(json['photo_urls']),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ExperiencePackageModel extends ExperiencePackageEntity {
  const ExperiencePackageModel({
    required super.id,
    required super.title,
    super.summary,
    super.category,
    required super.vendorId,
    required super.vendorName,
    super.vendorWhatsapp,
    super.vendorInstagram,
    super.vendorFacebook,
    super.vendorX,
    super.coverPhotoUrl,
    super.photoCount,
    super.priceAmount,
    super.priceCurrency,
    super.priceBasis,
    super.priceLabel,
    super.durationMinutes,
    super.durationLabel,
    required super.latitude,
    required super.longitude,
    super.distanceM,
    super.tags,
    super.description,
    super.photoUrls,
    super.maxParticipants,
    super.inclusions,
    super.languages,
    super.meetingPointAddress,
    super.vendor,
  });

  factory ExperiencePackageModel.fromJson(Map<String, dynamic> json) {
    final vendorJson = json['vendor'];
    return ExperiencePackageModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String?,
      category: json['category'] as String?,
      vendorId: json['vendor_id']?.toString() ?? '',
      vendorName: json['vendor_name'] as String? ?? '',
      vendorWhatsapp: json['vendor_whatsapp'] as String?,
      vendorInstagram: json['vendor_instagram'] as String?,
      vendorFacebook: json['vendor_facebook'] as String?,
      vendorX: json['vendor_x'] as String?,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      priceAmount: (json['price_amount'] as num?)?.toDouble(),
      priceCurrency: json['price_currency'] as String? ?? 'USD',
      priceBasis: json['price_basis'] as String? ?? 'per_person',
      priceLabel: json['price_label'] as String? ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      durationLabel: json['duration_label'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      tags: _stringList(json['tags']),
      description: json['description'] as String?,
      photoUrls: _stringList(json['photo_urls']),
      maxParticipants: (json['max_participants'] as num?)?.toInt(),
      inclusions: _stringList(json['inclusions']),
      languages: _stringList(json['languages']),
      meetingPointAddress: json['meeting_point_address'] as String?,
      vendor: vendorJson is Map<String, dynamic>
          ? ExperienceVendorModel.fromJson(vendorJson)
          : null,
    );
  }
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return const [];
}
