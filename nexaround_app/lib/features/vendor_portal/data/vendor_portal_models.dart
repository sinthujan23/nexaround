/// What the vendor screens read and write: the partner API's shapes
/// (nexaround_backend/app/schemas/partner.py), as the web portal at
/// partner.nexaround.com uses them.
///
/// None of these carries a traveller's name or contact: the partner API never
/// sends one. A request reaches the vendor only as a feed line ("New request:
/// Desert Safari · Sun 25 Oct · 4 guests").
library;

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

double? _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

List<String> _strings(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A vendor the signed-in traveller has been given to manage.
class VendorAccess {
  final String vendorId;
  final String vendorName;
  final String? logoUrl;

  const VendorAccess({required this.vendorId, required this.vendorName, this.logoUrl});

  factory VendorAccess.fromJson(Map<String, dynamic> json) => VendorAccess(
        vendorId: json['vendor_id'].toString(),
        vendorName: (json['vendor_name'] ?? '').toString(),
        logoUrl: json['logo_url'] as String?,
      );
}

/// Who is signed in to the vendor screens, and for which business.
class VendorMe {
  final String loginId;
  final String? displayName;
  final String vendorId;
  final String vendorName;
  final bool vendorIsActive;

  const VendorMe({
    required this.loginId,
    this.displayName,
    required this.vendorId,
    required this.vendorName,
    required this.vendorIsActive,
  });

  factory VendorMe.fromJson(Map<String, dynamic> json) => VendorMe(
        loginId: json['login_id'].toString(),
        displayName: json['display_name'] as String?,
        vendorId: json['vendor_id'].toString(),
        vendorName: (json['vendor_name'] ?? '').toString(),
        vendorIsActive: json['vendor_is_active'] == true,
      );
}

/// Days travellers cannot book, inclusive at both ends.
class BlockedRange {
  final DateTime start;
  final DateTime end;

  const BlockedRange(this.start, this.end);

  factory BlockedRange.fromJson(Map<String, dynamic> json) => BlockedRange(
        DateTime.parse(json['start'].toString()),
        DateTime.parse(json['end'].toString()),
      );

  Map<String, dynamic> toJson() => {'start': _day(start), 'end': _day(end)};

  @override
  bool operator ==(Object other) =>
      other is BlockedRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class VendorPackage {
  final String? id;
  final String title;
  final String summary;
  final String description;
  final String category;
  final List<String> tags;
  final List<String> photoUrls;
  final List<BlockedRange> unavailableRanges;
  final double? priceAmount;
  final String priceCurrency;
  final String priceBasis;
  final int? durationMinutes;
  final int? maxParticipants;
  final int? bookingWindowDays;
  final List<String> inclusions;
  final List<String> languages;
  final bool usesVendorLocation;
  final String meetingPointAddress;
  final bool isActive;
  final double? latitude;
  final double? longitude;

  /// The server's word, not the form's: it also needs the whole listing to
  /// be live, which only NexAround can switch.
  final bool isPublished;

  const VendorPackage({
    this.id,
    this.title = '',
    this.summary = '',
    this.description = '',
    this.category = 'boat',
    this.tags = const [],
    this.photoUrls = const [],
    this.unavailableRanges = const [],
    this.priceAmount,
    this.priceCurrency = 'LKR',
    this.priceBasis = 'per_person',
    this.durationMinutes,
    this.maxParticipants,
    this.bookingWindowDays,
    this.inclusions = const [],
    this.languages = const [],
    this.usesVendorLocation = true,
    this.meetingPointAddress = '',
    this.isActive = true,
    this.latitude,
    this.longitude,
    this.isPublished = false,
  });

  factory VendorPackage.fromJson(Map<String, dynamic> json) => VendorPackage(
        id: json['id']?.toString(),
        title: (json['title'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        category: (json['category'] ?? 'other').toString(),
        tags: _strings(json['tags']),
        photoUrls: _strings(json['photo_urls']),
        unavailableRanges: ((json['unavailable_ranges'] as List?) ?? const [])
            .map((r) => BlockedRange.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        priceAmount: _double(json['price_amount']),
        priceCurrency: (json['price_currency'] ?? 'LKR').toString(),
        priceBasis: (json['price_basis'] ?? 'per_person').toString(),
        durationMinutes: _int(json['duration_minutes']),
        maxParticipants: _int(json['max_participants']),
        bookingWindowDays: _int(json['booking_window_days']),
        inclusions: _strings(json['inclusions']),
        languages: _strings(json['languages']),
        usesVendorLocation: json['uses_vendor_location'] != false,
        meetingPointAddress: (json['meeting_point_address'] ?? '').toString(),
        isActive: json['is_active'] != false,
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        isPublished: json['is_published'] == true,
      );

  /// The body of a create or update, which is a full replacement. A package
  /// that meets at the business has no point of its own; the server copies
  /// the vendor's.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'summary': summary.trim().isEmpty ? null : summary.trim(),
        'description': description.trim().isEmpty ? null : description,
        'category': category,
        'tags': tags,
        'photo_urls': photoUrls,
        'unavailable_ranges': unavailableRanges.map((r) => r.toJson()).toList(),
        'price_amount': priceAmount,
        'price_currency': priceCurrency,
        'price_basis': priceBasis,
        'duration_minutes': durationMinutes,
        'max_participants': maxParticipants,
        'booking_window_days': bookingWindowDays,
        'inclusions': inclusions,
        'languages': languages,
        'uses_vendor_location': usesVendorLocation,
        'meeting_point_address':
            meetingPointAddress.trim().isEmpty ? null : meetingPointAddress.trim(),
        'is_active': isActive,
        'latitude': usesVendorLocation ? null : latitude,
        'longitude': usesVendorLocation ? null : longitude,
      };

  VendorPackage copyWith({
    String? title,
    String? summary,
    String? description,
    String? category,
    List<String>? photoUrls,
    List<BlockedRange>? unavailableRanges,
    double? Function()? priceAmount,
    String? priceCurrency,
    String? priceBasis,
    int? Function()? durationMinutes,
    int? Function()? maxParticipants,
    int? Function()? bookingWindowDays,
    List<String>? inclusions,
    List<String>? languages,
    bool? usesVendorLocation,
    String? meetingPointAddress,
    bool? isActive,
    double? Function()? latitude,
    double? Function()? longitude,
  }) =>
      VendorPackage(
        id: id,
        title: title ?? this.title,
        summary: summary ?? this.summary,
        description: description ?? this.description,
        category: category ?? this.category,
        tags: tags,
        photoUrls: photoUrls ?? this.photoUrls,
        unavailableRanges: unavailableRanges ?? this.unavailableRanges,
        priceAmount: priceAmount != null ? priceAmount() : this.priceAmount,
        priceCurrency: priceCurrency ?? this.priceCurrency,
        priceBasis: priceBasis ?? this.priceBasis,
        durationMinutes: durationMinutes != null ? durationMinutes() : this.durationMinutes,
        maxParticipants: maxParticipants != null ? maxParticipants() : this.maxParticipants,
        bookingWindowDays:
            bookingWindowDays != null ? bookingWindowDays() : this.bookingWindowDays,
        inclusions: inclusions ?? this.inclusions,
        languages: languages ?? this.languages,
        usesVendorLocation: usesVendorLocation ?? this.usesVendorLocation,
        meetingPointAddress: meetingPointAddress ?? this.meetingPointAddress,
        isActive: isActive ?? this.isActive,
        latitude: latitude != null ? latitude() : this.latitude,
        longitude: longitude != null ? longitude() : this.longitude,
        isPublished: isPublished,
      );

  /// "Live", "Hidden" or "On, not visible", as the web portal says it.
  String get visibility {
    if (!isActive) return 'Hidden';
    return isPublished ? 'Live' : 'On, not visible';
  }
}

class VendorStats {
  final int packagesTotal;
  final int packagesPublished;

  const VendorStats({this.packagesTotal = 0, this.packagesPublished = 0});

  factory VendorStats.fromJson(Map<String, dynamic> json) => VendorStats(
        packagesTotal: _int(json['packages_total']) ?? 0,
        packagesPublished: _int(json['packages_published']) ?? 0,
      );
}

/// A traveller's rating, as any traveller sees it in the app: a display
/// name, no account id and no contact.
class VendorReview {
  final String id;
  final String? packageTitle;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime? createdAt;
  final String? vendorReply;
  final DateTime? vendorRepliedAt;

  const VendorReview({
    required this.id,
    this.packageTitle,
    required this.reviewerName,
    required this.rating,
    this.comment,
    this.createdAt,
    this.vendorReply,
    this.vendorRepliedAt,
  });

  factory VendorReview.fromJson(Map<String, dynamic> json) => VendorReview(
        id: json['id'].toString(),
        packageTitle: json['package_title'] as String?,
        reviewerName: (json['reviewer_name'] ?? 'Traveller').toString(),
        rating: _int(json['rating']) ?? 0,
        comment: json['comment'] as String?,
        createdAt: _date(json['created_at']),
        vendorReply: json['vendor_reply'] as String?,
        vendorRepliedAt: _date(json['vendor_replied_at']),
      );
}

class VendorReviewPage {
  final List<VendorReview> reviews;
  final int total;
  final double? average;
  final int reviewCount;
  final int unanswered;

  const VendorReviewPage({
    this.reviews = const [],
    this.total = 0,
    this.average,
    this.reviewCount = 0,
    this.unanswered = 0,
  });

  factory VendorReviewPage.fromJson(Map<String, dynamic> json) => VendorReviewPage(
        reviews: ((json['reviews'] as List?) ?? const [])
            .map((r) => VendorReview.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        total: _int(json['total']) ?? 0,
        average: _double(json['average']),
        reviewCount: _int(json['review_count']) ?? 0,
        unanswered: _int(json['unanswered']) ?? 0,
      );
}

/// The business profile. Phone, WhatsApp and the socials are shown but only
/// NexAround sets them: travellers reach the business through NexAround.
class VendorProfile {
  final String name;
  final String description;
  final double? latitude;
  final double? longitude;
  final String address;
  final String city;
  final String? countryCode;
  final String contactEmail;
  final String website;
  final String? logoUrl;
  final List<String> photoUrls;
  final String? contactPhone;
  final String? contactWhatsapp;
  final String? contactInstagram;
  final String? contactFacebook;
  final String? contactX;

  const VendorProfile({
    this.name = '',
    this.description = '',
    this.latitude,
    this.longitude,
    this.address = '',
    this.city = '',
    this.countryCode,
    this.contactEmail = '',
    this.website = '',
    this.logoUrl,
    this.photoUrls = const [],
    this.contactPhone,
    this.contactWhatsapp,
    this.contactInstagram,
    this.contactFacebook,
    this.contactX,
  });

  factory VendorProfile.fromJson(Map<String, dynamic> json) => VendorProfile(
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        address: (json['address'] ?? '').toString(),
        city: (json['city'] ?? '').toString(),
        countryCode: (json['country_code'] as String?)?.toUpperCase(),
        contactEmail: (json['contact_email'] ?? '').toString(),
        website: (json['website'] ?? '').toString(),
        logoUrl: json['logo_url'] as String?,
        photoUrls: _strings(json['photo_urls']),
        contactPhone: json['contact_phone'] as String?,
        contactWhatsapp: json['contact_whatsapp'] as String?,
        contactInstagram: json['contact_instagram'] as String?,
        contactFacebook: json['contact_facebook'] as String?,
        contactX: json['contact_x'] as String?,
      );

  /// Only the fields a vendor may change (PartnerVendorProfileUpdate); the
  /// contacts above are left out, and the server would drop them anyway.
  Map<String, dynamic> toJson() {
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    return {
      'name': name.trim(),
      'description': blank(description),
      'latitude': latitude,
      'longitude': longitude,
      'address': blank(address),
      'city': blank(city),
      'country_code': countryCode,
      'contact_email': blank(contactEmail),
      'website': blank(website),
      'logo_url': logoUrl,
      'photo_urls': photoUrls,
    };
  }

  VendorProfile copyWith({
    String? name,
    String? description,
    double? Function()? latitude,
    double? Function()? longitude,
    String? address,
    String? city,
    String? countryCode,
    String? contactEmail,
    String? website,
    List<String>? photoUrls,
  }) =>
      VendorProfile(
        name: name ?? this.name,
        description: description ?? this.description,
        latitude: latitude != null ? latitude() : this.latitude,
        longitude: longitude != null ? longitude() : this.longitude,
        address: address ?? this.address,
        city: city ?? this.city,
        countryCode: countryCode ?? this.countryCode,
        contactEmail: contactEmail ?? this.contactEmail,
        website: website ?? this.website,
        logoUrl: logoUrl,
        photoUrls: photoUrls ?? this.photoUrls,
        contactPhone: contactPhone,
        contactWhatsapp: contactWhatsapp,
        contactInstagram: contactInstagram,
        contactFacebook: contactFacebook,
        contactX: contactX,
      );
}

/// One line of the vendor's notifications, the same feed as the web bell.
class VendorActivityItem {
  final String id;
  final String kind;
  final String title;
  final String? body;
  final String actor;
  final String? actorName;
  final String? packageId;
  final DateTime createdAt;

  const VendorActivityItem({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    required this.actor,
    this.actorName,
    this.packageId,
    required this.createdAt,
  });

  factory VendorActivityItem.fromJson(Map<String, dynamic> json) => VendorActivityItem(
        id: json['id'].toString(),
        kind: (json['kind'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        body: json['body'] as String?,
        actor: (json['actor'] ?? '').toString(),
        actorName: json['actor_name'] as String?,
        packageId: json['package_id']?.toString(),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
      );
}

class VendorActivityPage {
  final List<VendorActivityItem> items;
  final bool hasMore;
  final int unread;
  final DateTime? seenAt;

  const VendorActivityPage({
    this.items = const [],
    this.hasMore = false,
    this.unread = 0,
    this.seenAt,
  });

  factory VendorActivityPage.fromJson(Map<String, dynamic> json) => VendorActivityPage(
        items: ((json['items'] as List?) ?? const [])
            .map((r) => VendorActivityItem.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
        hasMore: json['has_more'] == true,
        unread: _int(json['unread']) ?? 0,
        seenAt: _date(json['seen_at']),
      );
}

/// The Provider Agreement and whether this vendor still has to accept it.
class PartnerAgreement {
  final int version;
  final String title;
  final String body;
  final List<String> highlights;
  final int? acceptedVersion;

  /// True until this version is accepted: the screens stay behind it.
  final bool mustAccept;

  const PartnerAgreement({
    required this.version,
    required this.title,
    required this.body,
    this.highlights = const [],
    this.acceptedVersion,
    required this.mustAccept,
  });

  factory PartnerAgreement.fromJson(Map<String, dynamic> json) {
    final doc = Map<String, dynamic>.from(json['document'] as Map);
    return PartnerAgreement(
      version: _int(doc['version']) ?? 1,
      title: (doc['title'] ?? 'Provider Agreement').toString(),
      body: (doc['body'] ?? '').toString(),
      highlights: _strings(doc['highlights']),
      acceptedVersion: _int(json['accepted_version']),
      mustAccept: json['required'] == true,
    );
  }
}

/// A Google place found by the server's search, for placing a map pin.
class VendorPlace {
  final String? name;
  final String? address;
  final double latitude;
  final double longitude;
  final String? city;
  final String? countryCode;

  const VendorPlace({
    this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.city,
    this.countryCode,
  });

  factory VendorPlace.fromJson(Map<String, dynamic> json) => VendorPlace(
        name: json['name'] as String?,
        address: json['address'] as String?,
        latitude: _double(json['latitude']) ?? 0,
        longitude: _double(json['longitude']) ?? 0,
        city: json['city'] as String?,
        countryCode: (json['country_code'] as String?)?.toUpperCase(),
      );
}
