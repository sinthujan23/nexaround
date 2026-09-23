/// A vendor agency selling experiences: boat rides, guided tours, water sports.
///
/// Note there is no email field. The backend deliberately never serialises the
/// vendor's address to the app — it is the destination for enquiry
/// notifications, and phone/WhatsApp are the public channels.
class ExperienceVendorEntity {
  final String id;
  final String name;
  final String? description;
  final String? address;
  final double latitude;
  final double longitude;
  final String? contactPhone;
  final String? contactWhatsapp;
  final String? contactInstagram;
  final String? contactFacebook;
  final String? contactX;
  final String? website;
  final String? logoUrl;
  final List<String> photoUrls;
  final double? rating;
  final int reviewCount;

  const ExperienceVendorEntity({
    required this.id,
    required this.name,
    this.description,
    this.address,
    required this.latitude,
    required this.longitude,
    this.contactPhone,
    this.contactWhatsapp,
    this.contactInstagram,
    this.contactFacebook,
    this.contactX,
    this.website,
    this.logoUrl,
    this.photoUrls = const [],
    this.rating,
    this.reviewCount = 0,
  });

  bool get hasPhone => (contactPhone ?? '').trim().isNotEmpty;
  bool get hasWhatsapp => (contactWhatsapp ?? '').trim().isNotEmpty;
  bool get hasInstagram => (contactInstagram ?? '').trim().isNotEmpty;
  bool get hasFacebook => (contactFacebook ?? '').trim().isNotEmpty;
  bool get hasX => (contactX ?? '').trim().isNotEmpty;
  bool get hasSocials => hasWhatsapp || hasInstagram || hasFacebook || hasX;
  bool get hasWebsite => (website ?? '').trim().isNotEmpty;
}

/// One sellable package. This — not the vendor — is the Discovery card unit,
/// so a vendor with three boat tours produces three cards.
class ExperiencePackageEntity {
  final String id;
  final String title;
  final String? summary;
  final String? category;
  final String vendorId;
  final String vendorName;
  final String? vendorWhatsapp;
  final String? vendorInstagram;
  final String? vendorFacebook;
  final String? vendorX;
  final String? coverPhotoUrl;
  final int photoCount;
  final double? priceAmount;
  final String priceCurrency;
  final String priceBasis;

  /// Rendered server-side, so the app, the admin panel and any future surface
  /// cannot disagree about how a price reads.
  final String priceLabel;
  final int? durationMinutes;
  final String durationLabel;
  final double latitude;
  final double longitude;
  final double? distanceM;
  final List<String> tags;

  // Detail-only. Empty on a card.
  final String? description;
  final List<String> photoUrls;
  final int? maxParticipants;
  final List<String> inclusions;
  final List<String> languages;
  final String? meetingPointAddress;
  final ExperienceVendorEntity? vendor;

  const ExperiencePackageEntity({
    required this.id,
    required this.title,
    this.summary,
    this.category,
    required this.vendorId,
    required this.vendorName,
    this.vendorWhatsapp,
    this.vendorInstagram,
    this.vendorFacebook,
    this.vendorX,
    this.coverPhotoUrl,
    this.photoCount = 0,
    this.priceAmount,
    this.priceCurrency = 'USD',
    this.priceBasis = 'per_person',
    this.priceLabel = '',
    this.durationMinutes,
    this.durationLabel = '',
    required this.latitude,
    required this.longitude,
    this.distanceM,
    this.tags = const [],
    this.description,
    this.photoUrls = const [],
    this.maxParticipants,
    this.inclusions = const [],
    this.languages = const [],
    this.meetingPointAddress,
    this.vendor,
  });

  bool get hasVendorWhatsapp => (vendorWhatsapp ?? '').trim().isNotEmpty;
  bool get hasVendorInstagram => (vendorInstagram ?? '').trim().isNotEmpty;
  bool get hasVendorFacebook => (vendorFacebook ?? '').trim().isNotEmpty;
  bool get hasVendorX => (vendorX ?? '').trim().isNotEmpty;
  bool get hasSocials =>
      hasVendorWhatsapp || hasVendorInstagram || hasVendorFacebook || hasVendorX;

  /// Every image for the gallery, falling back to the cover when the detail
  /// payload has not been loaded yet.
  List<String> get galleryUrls {
    if (photoUrls.isNotEmpty) return photoUrls;
    final cover = coverPhotoUrl;
    return cover == null ? const [] : [cover];
  }
}
