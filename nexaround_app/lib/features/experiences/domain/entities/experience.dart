/// Days a package cannot be booked, both ends included. A single blocked day
/// has the same start and end. Dates only: the time of day is always midnight.
class ExperienceDateRange {
  final DateTime start;
  final DateTime end;

  const ExperienceDateRange({required this.start, required this.end});

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

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

  /// The admin's free-text region, e.g. "Kerala State · Munnar region". Shown
  /// with a pin icon, never as a map location. On cards and detail.
  final String? regionLabel;

  /// Average of travellers' published reviews (one decimal), null with none.
  final double? ratingAvg;
  final int ratingCount;

  // Detail-only. Empty on a card.
  final String? description;

  /// The description with its formatting (headings, bold, lists) as light
  /// Markdown. Null from a server that predates it; then [description] is shown.
  final String? descriptionMd;
  final List<String> photoUrls;

  /// Uploaded clips, as API paths (like photos). Detail-only.
  final List<String> videoUrls;

  /// Days the package cannot be booked; every other day is available.
  /// Detail-only, and empty on a card.
  final List<ExperienceDateRange> unavailableRanges;
  final int? maxParticipants;

  /// How many days ahead a date may be requested; null on a card, where the
  /// enquiry sheet falls back to a year (the server's default).
  final int? bookingWindowDays;
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
    this.regionLabel,
    this.ratingAvg,
    this.ratingCount = 0,
    this.description,
    this.descriptionMd,
    this.photoUrls = const [],
    this.videoUrls = const [],
    this.unavailableRanges = const [],
    this.maxParticipants,
    this.bookingWindowDays,
    this.inclusions = const [],
    this.languages = const [],
    this.meetingPointAddress,
    this.vendor,
  });

  bool get hasRating => ratingAvg != null && ratingCount > 0;
  bool get hasRegion => (regionLabel ?? '').trim().isNotEmpty;
  bool get hasVendorWhatsapp => (vendorWhatsapp ?? '').trim().isNotEmpty;
  bool get hasVendorInstagram => (vendorInstagram ?? '').trim().isNotEmpty;
  bool get hasVendorFacebook => (vendorFacebook ?? '').trim().isNotEmpty;
  bool get hasVendorX => (vendorX ?? '').trim().isNotEmpty;
  bool get hasSocials =>
      hasVendorWhatsapp || hasVendorInstagram || hasVendorFacebook || hasVendorX;

  /// Human-friendly duration label for cards and detail views, e.g. "1 Hour Duration", "2 Hours Duration", "45 Mins Duration".
  String get formattedDuration {
    if (durationMinutes != null && durationMinutes! > 0) {
      final mins = durationMinutes!;
      final h = mins ~/ 60;
      final m = mins % 60;
      if (h > 0 && m > 0) {
        return '$h hr $m mins duration';
      } else if (h > 0) {
        return h == 1 ? '1 Hour Duration' : '$h Hours Duration';
      } else {
        return '$m Mins Duration';
      }
    }
    if (durationLabel.isNotEmpty) {
      final clean = durationLabel.trim().toLowerCase();
      if (clean == '1h') return '1 Hour Duration';
      if (clean.endsWith('h')) {
        final hours = clean.substring(0, clean.length - 1);
        return '$hours Hours Duration';
      }
      if (clean.endsWith('m')) {
        final minutes = clean.substring(0, clean.length - 1);
        return '$minutes Mins Duration';
      }
      return '$durationLabel Duration';
    }
    return '';
  }

  bool isUnavailableOn(DateTime day) =>
      unavailableRanges.any((range) => range.contains(day));

  /// The first bookable day from [from] to [to] (both included), or null when
  /// every day in between is blocked.
  DateTime? firstAvailableFrom(DateTime from, DateTime to) {
    var day = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    while (!day.isAfter(last)) {
      if (!isUnavailableOn(day)) return day;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }

  /// Every image for the gallery, falling back to the cover when the detail
  /// payload has not been loaded yet.
  List<String> get galleryUrls {
    if (photoUrls.isNotEmpty) return photoUrls;
    final cover = coverPhotoUrl;
    return cover == null ? const [] : [cover];
  }
}
